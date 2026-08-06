import Foundation

enum LyricsService {
    private static let rateLimiter = LRCLIBRateLimiter()

    static func lines(for track: Track) async -> [LyricLine] {
        do {
            if let response = try await fetchGet(track) {
                return response.lines
            }
        } catch {
            if isCancellation(error) { return [] }
            return []
        }

        if Task.isCancelled {
            return []
        }

        do {
            if let response = try await fetchSearch(track) {
                return response.lines
            }
        } catch {
            if isCancellation(error) { return [] }
            return []
        }

        return []
    }

    private static func fetchGet(_ track: Track) async throws -> LRCLibLyrics? {
        guard let url = request(path: "/api/get", track: track) else { return nil }
        do {
            let data = try await requestData(from: url)
            return try decodeLyrics(from: data)
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }

            if case LyricsServiceError.httpStatus(404) = error {
                return nil
            }

            logError("lyrics get failed: \(error.localizedDescription)")
            throw error
        }
    }

    private static func fetchSearch(_ track: Track) async throws -> LRCLibLyrics? {
        guard let url = request(path: "/api/search", track: track) else { return nil }
        do {
            let data = try await requestData(from: url)
            return try decodeSearchResults(from: data)
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }

            if case LyricsServiceError.httpStatus(404) = error {
                return nil
            }

            logError("lyrics search failed: \(error.localizedDescription)")
            throw error
        }
    }

    private static func request(path: String, track: Track) -> URL? {
        var components = URLComponents(string: "https://lrclib.net")
        components?.path = path
        components?.queryItems = [
            URLQueryItem(
                name: "track_name",
                value: track.title.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(
                name: "artist_name",
                value: track.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        return components?.url
    }

    private static func requestData(from url: URL) async throws -> Data {
        await rateLimiter.acquire()
        if Task.isCancelled {
            await rateLimiter.release()
            throw CancellationError()
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FloatingLyrics/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5
        var released = false
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    let retryAfter = RetryAfterParser.delay(from: http.value(forHTTPHeaderField: "Retry-After"))
                    await rateLimiter.release(retryAfter: retryAfter)
                    released = true
                    let retryAfterText = retryAfter.map { String(format: "%.3f", $0) } ?? "nil"
                    logError("lyrics http=429 retryAfter=\(retryAfterText) url=\(url.absoluteString)")
                    throw LyricsServiceError.httpStatus(429)
                }

                if !(200...299).contains(http.statusCode) {
                    await rateLimiter.release()
                    released = true
                    logError("lyrics http=\(http.statusCode) url=\(url.absoluteString)")
                    throw LyricsServiceError.httpStatus(http.statusCode)
                }
            }

            await rateLimiter.release()
            released = true
            return data
        } catch {
            if isCancellation(error) {
                if !released {
                    await rateLimiter.release()
                }
                throw CancellationError()
            }

            if !released {
                await rateLimiter.release()
            }

            logError("lyrics request failed: \(error.localizedDescription) url=\(url.absoluteString)")
            throw error
        }
    }

    private static func decodeLyrics(from data: Data) throws -> LRCLibLyrics {
        let response = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
        return LRCLibLyrics(response: response)
    }

    private static func decodeSearchResults(from data: Data) throws -> LRCLibLyrics? {
        if let response = try? JSONDecoder().decode(LRCLIBResponse.self, from: data) {
            return LRCLibLyrics(response: response)
        }

        let responses = try JSONDecoder().decode([LRCLIBResponse].self, from: data)
        let best = responses.first {
            ($0.syncedLyrics?.isEmpty == false) || ($0.plainLyrics?.isEmpty == false)
        }
        return best.map(LRCLibLyrics.init(response:))
    }

    private static func logError(_ message: String) {
        guard let root = projectRoot else { return }
        let logs = root.appendingPathComponent(".logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let url = logs.appendingPathComponent("floating-lyrics.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }

    private static var projectRoot: URL? {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct LRCLIBResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?
}

private struct LRCLibLyrics {
    let lines: [LyricLine]

    init(response: LRCLIBResponse) {
        let timed = response.syncedLyrics.map(LRCParser.parse) ?? []
        let plain = response.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)

        if !timed.isEmpty {
            lines = timed
        } else if let plain, !plain.isEmpty {
            lines = [LyricLine(timestamp: 0, text: plain)]
        } else {
            lines = []
        }
    }

    init(syncedLyrics: String?, plainLyrics: String?) {
        self.init(response: LRCLIBResponse(syncedLyrics: syncedLyrics, plainLyrics: plainLyrics))
    }
}

actor LRCLIBRateLimiter {
    private let minimumSpacing: TimeInterval = 0.3
    private var blockedUntil = Date.distantPast
    private var nextTicket = 0
    private var servingTicket = 0
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func acquire() async {
        let ticket = nextTicket
        nextTicket += 1

        if ticket != servingTicket {
            await withCheckedContinuation { continuation in
                waiters[ticket] = continuation
            }
        }

        let wait = max(0, blockedUntil.timeIntervalSinceNow)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    func release(retryAfter: TimeInterval? = nil) {
        let delay = max(minimumSpacing, retryAfter ?? 0)
        blockedUntil = max(blockedUntil, Date().addingTimeInterval(delay))
        servingTicket += 1

        if let continuation = waiters.removeValue(forKey: servingTicket) {
            continuation.resume()
        }
    }
}

enum RetryAfterParser {
    static func delay(from header: String?) -> TimeInterval? {
        guard let header else { return nil }
        return Double(header.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum LyricsServiceError: Error {
    case httpStatus(Int)
}

private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

enum LRCParser {
    static func parse(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            guard let closing = line.firstIndex(of: "]"), line.hasPrefix("[") else { continue }
            let timeTag = String(line[line.index(after: line.startIndex)..<closing])
            let text = String(line[line.index(after: closing)...]).trimmingCharacters(
                in: .whitespaces)
            guard let timestamp: TimeInterval = parseTimestamp(timeTag), !text.isEmpty else {
                continue
            }
            lines.append(LyricLine(timestamp: timestamp, text: text))
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    private static func parseTimestamp(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let minutes = Double(parts[0]),
            let seconds = Double(parts[1])
        else { return nil }
        return minutes * 60 + seconds
    }
}
