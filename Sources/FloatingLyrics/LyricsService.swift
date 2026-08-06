import Foundation

enum LyricsService {
    static func lines(for track: Track) async -> [LyricLine] {
        if let response = await fetchGet(track) {
            return response.lines
        }

        if let response = await fetchSearch(track) {
            return response.lines
        }

        return []
    }

    private static func fetchGet(_ track: Track) async -> LRCLibLyrics? {
        guard let url = request(path: "/api/get", track: track) else { return nil }
        do {
            let data = try await requestData(from: url)
            return try decodeLyrics(from: data)
        } catch {
            logError("lyrics get failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func fetchSearch(_ track: Track) async -> LRCLibLyrics? {
        guard let url = request(path: "/api/search", track: track) else { return nil }
        do {
            let data = try await requestData(from: url)
            return try decodeSearchResults(from: data)
        } catch {
            logError("lyrics search failed: \(error.localizedDescription)")
            return nil
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
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FloatingLyrics/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            logError("lyrics http=\(http.statusCode) url=\(url.absoluteString)")
            throw URLError(.badServerResponse)
        }
        return data
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
