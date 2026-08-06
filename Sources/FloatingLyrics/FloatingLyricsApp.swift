import AppKit
import SwiftUI

@main
@MainActor
struct elz0mbi33App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PlaybackStore()
    private let launchAtLogin = LaunchAtLoginManager()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var poller: Timer?
    private let spotify = SpotifyClient()
    private var statusTitle = StatusTitle()
    private var lyricsTask: Task<Void, Never>?
    private var introTask: Task<Void, Never>?
    private var lastTrackIdentity: String?
    private var lastLyricsFetchAt: Date?
    private let lyricsRetryDelay: TimeInterval = 2
    private var debugLogURL: URL? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let logs = root.appendingPathComponent(".logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("floating-lyrics.log")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        poll()
        poller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 240)
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(store: store, launchAtLogin: launchAtLogin))
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 520)
        item.button?.title = statusTitle.text
        item.button?.lineBreakMode = .byTruncatingTail
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func poll() {
        let snapshot = spotify.snapshot()
        store.update(snapshot: snapshot)
        updateStatusTitle()
        guard let track = snapshot.track else {
            lastTrackIdentity = nil
            lastLyricsFetchAt = nil
            lyricsTask?.cancel()
            introTask?.cancel()
            store.clearLyrics()
            return
        }

        if track.identity != lastTrackIdentity {
            lastTrackIdentity = track.identity
            lastLyricsFetchAt = Date()
            store.clearLyrics()
            store.beginLyricsLoad()
            store.beginTrackIntro(for: track)
            introTask?.cancel()
            introTask = Task { [weak store] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    store?.endTrackIntro(for: track.identity)
                }
            }
            lyricsTask?.cancel()
            lyricsTask = Task { [weak store] in
                let lines = await LyricsService.lines(for: track)
                await MainActor.run {
                    guard store?.snapshot.track?.identity == track.identity else { return }
                    store?.updateLyrics(lines)
                }
            }
            return
        }

        guard snapshot.isPlaying else { return }
        guard !store.hasLyrics, !store.isLoadingLyrics else { return }
        guard let fetchedAt = lastLyricsFetchAt, Date().timeIntervalSince(fetchedAt) >= lyricsRetryDelay else { return }
        lastLyricsFetchAt = Date()
        store.beginLyricsLoad()
        lyricsTask?.cancel()
        lyricsTask = Task { [weak store] in
            let lines = await LyricsService.lines(for: track)
            await MainActor.run {
                guard store?.snapshot.track?.identity == track.identity else { return }
                store?.updateLyrics(lines)
            }
        }
    }

    private func updateStatusTitle() {
        let title = statusTitle.render(text: store.statusText)
        if statusItem?.button?.title != title {
            statusItem?.button?.title = title
        }
        statusItem?.button?.toolTip = store.snapshot.track.map { "\($0.title) — \($0.artist)" }
    }
}

@MainActor
final class PlaybackStore: ObservableObject {
    @Published var snapshot = PlaybackSnapshot.empty
    @Published var lyrics: [LyricLine] = []
    @Published var currentLine: LyricLine?
    @Published var isLoadingLyrics = false
    @Published var hasLyrics = false
    @Published var trackIntroText: String?

    func update(snapshot: PlaybackSnapshot) {
        self.snapshot = snapshot
        guard !lyrics.isEmpty, snapshot.track != nil else {
            currentLine = nil
            return
        }
        currentLine = LyricTimeline.currentLine(in: lyrics, at: snapshot.position)
    }

    func updateLyrics(_ lyrics: [LyricLine]) {
        self.lyrics = lyrics
        isLoadingLyrics = false
        hasLyrics = !lyrics.isEmpty
        guard snapshot.isPlaying else { return }
        currentLine = LyricTimeline.currentLine(in: lyrics, at: snapshot.position)
    }

    func beginLyricsLoad() {
        isLoadingLyrics = true
        hasLyrics = false
    }

    func beginTrackIntro(for track: Track) {
        trackIntroText = "\(track.title) — \(track.artist)"
    }

    func endTrackIntro(for identity: String) {
        guard snapshot.track?.identity == identity else { return }
        trackIntroText = nil
    }

    func clearLyrics() {
        lyrics = []
        currentLine = nil
        isLoadingLyrics = false
        hasLyrics = false
        trackIntroText = nil
    }

    var statusText: String {
        if !snapshot.isPlaying, let trackText {
            return "\(trackText) (paused)"
        }

        if let trackLabel = trackIntroText {
            return trackLabel
        }

        if let current = currentLine?.text {
            return current
        }

        return fallbackText
    }

    private var fallbackText: String {
        if isLoadingLyrics { return "Loading lyrics…" }
        if snapshot.track != nil, !hasLyrics { return "Lyrics unavailable" }
        return snapshot.track?.title ?? "No track"
    }

    private var trackText: String? {
        snapshot.track.map { "\($0.artist) — \($0.title)" }
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var store: PlaybackStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("elz0mbi33")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("lyric")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.snapshot.track?.title ?? "No track playing")
                    .font(.headline)
                Text(store.snapshot.track?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(store.statusText)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(launchAtLogin.isEnabled ? "Launch at Login: On" : "Launch at Login: Off") {
                    launchAtLogin.toggle()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .frame(width: 360, height: 240)
    }

    private var stateText: String {
        guard store.snapshot.track != nil else { return "" }
        return store.snapshot.isPlaying ? "Playing" : "Paused"
    }
}

private struct StatusTitle {
    let prefix = "♫  "
    let maxCharacters = 80

    var text: String { prefix.trimmingCharacters(in: .whitespaces) }

    func render(text: String) -> String {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.isEmpty { return prefix.trimmingCharacters(in: .whitespaces) }
        if compact.count <= maxCharacters { return prefix + compact }
        return prefix + compact.prefix(maxCharacters - 1) + "…"
    }
}
