import AppKit
import MediaPlayer

/// Makes Dérive the "Now Playing" app of macOS: the media keys (play/pause, next) reach it, and
/// Control Center shows the track, the artist and the cover.
@MainActor
enum NowPlaying {
    static func setUp() {
        let center = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            command.addTarget { _ in
                DispatchQueue.main.async { action() }
                return .success
            }
        }
        handle(center.playCommand) { Player.shared.play() }
        handle(center.pauseCommand) { Player.shared.pause() }
        handle(center.togglePlayPauseCommand) { Player.shared.toggle() }
        handle(center.nextTrackCommand) { Player.shared.nextTrack() }
        // There is no previous track in a random player: the previous key starts the track again.
        handle(center.previousTrackCommand) { Player.shared.restartTrack() }
        // A media key held down: on Apple keyboards, a press a bit long on ⏭ or ⏮ is a seek, not
        // a next or previous track. Moves fast in the track while the key is held.
        func scan(_ command: MPRemoteCommand, _ direction: Double) {
            command.isEnabled = true
            command.addTarget { event in
                let begins = (event as? MPSeekCommandEvent)?.type == .beginSeeking
                DispatchQueue.main.async {
                    if begins { Player.shared.startScanning(direction) } else { Player.shared.stopScanning() }
                }
                return .success
            }
        }
        scan(center.seekForwardCommand, 1)
        scan(center.seekBackwardCommand, -1)
        // Moving in the track from Control Center's bar.
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            DispatchQueue.main.async { Player.shared.seek(to: position) }
            return .success
        }
    }

    struct Info {
        let title: String
        let album: String
        let artist: String
        let duration: Double
        let elapsed: Double
        let isPlaying: Bool
        let cover: NSImage?
    }

    static func update(_ info: Info?) {
        let center = MPNowPlayingInfoCenter.default()
        guard let info else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyAlbumTitle: info.album,
            MPMediaItemPropertyArtist: info.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if info.duration > 0 { values[MPMediaItemPropertyPlaybackDuration] = info.duration }
        if let cover = info.cover {
            values[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }
        center.nowPlayingInfo = values
        // On macOS, the media keys follow this state.
        center.playbackState = info.isPlaying ? .playing : .paused
    }
}
