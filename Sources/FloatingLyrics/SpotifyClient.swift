import AppKit
import Foundation

final class SpotifyClient {
    func snapshot() -> PlaybackSnapshot {
        let script = """
        tell application "Spotify"
            if it is running then
                return {name of current track, artist of current track, album of current track, duration of current track, player position, player state is playing}
            end if
            return {"", "", "", 0, 0, false}
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return .empty }
        var error: NSDictionary?
        let output = appleScript.executeAndReturnError(&error)
        guard error == nil, output.numberOfItems == 6 else { return .empty }

        let title = output.atIndex(1)?.stringValue ?? ""
        let artist = output.atIndex(2)?.stringValue ?? ""
        let album = output.atIndex(3)?.stringValue
        let duration = output.atIndex(4).map { $0.doubleValue / 1000 }
        let position = output.atIndex(5)?.doubleValue ?? 0
        let isPlaying = output.atIndex(6)?.booleanValue ?? false

        let track = title.isEmpty ? nil : Track(title: title, artist: artist, album: album, duration: duration)
        return PlaybackSnapshot(track: track, position: position, isPlaying: isPlaying)
    }
}
