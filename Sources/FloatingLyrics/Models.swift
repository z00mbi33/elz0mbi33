import Foundation

struct Track: Equatable {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval?

    var identity: String {
        [title, artist].joined(separator: "|")
    }
}

struct PlaybackSnapshot: Equatable {
    static let empty = PlaybackSnapshot(track: nil, position: 0, isPlaying: false)

    let track: Track?
    let position: TimeInterval
    let isPlaying: Bool
}

struct LyricLine: Equatable {
    let timestamp: TimeInterval
    let text: String
}

enum LyricTimeline {
    static func currentLine(in lines: [LyricLine], at position: TimeInterval) -> LyricLine? {
        lines.last { $0.timestamp <= position } ?? lines.first
    }
}
