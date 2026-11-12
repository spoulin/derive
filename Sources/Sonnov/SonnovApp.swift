import SwiftUI

/// Handles sonnov:// URLs (e.g. from a Stream Deck) and reopens the player window at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in PlayerWindow.restore() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Windows close while quitting; the player window must still reopen at next launch.
        MainActor.assumeIsolated { PlayerWindow.isQuitting = true }
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "sonnov" {
            Task { @MainActor in
                let player = Player.shared
                switch url.host {
                case "play": player.play()
                case "pause": player.pause()
                case "toggle": player.toggle()
                case "next": player.nextTrack()
                case "shuffle": player.nextAlbum()
                case "window": PlayerWindow.show()
                default: break
                }
            }
        }
    }
}

@main
struct SonnovApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var player = Player.shared

    var body: some Scene {
        MenuBarExtra {
            PlayerView(style: .menu)
        } label: {
            Image(systemName: player.isPlaying ? "waveform" : "play.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
