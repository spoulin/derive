import SwiftUI

/// Handles derive:// URLs (e.g. from a Stream Deck) and reopens the player window at launch.
/// sonnov:// still works, from when the app was called Sonnov.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NowPlaying.setUp()
            PlayerWindow.restore()
            // Picks up artists followed or unfollowed on Bandcamp since the last launch.
            await ArtistStore.shared.refresh()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Windows close while quitting; the player window must still reopen at next launch.
        MainActor.assumeIsolated { PlayerWindow.isQuitting = true }
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "derive" || url.scheme == "sonnov" {
            Task { @MainActor in
                let player = Player.shared
                switch url.host {
                case "play": player.play()
                case "pause": player.pause()
                case "toggle": player.toggle()
                case "next": player.nextTrack()
                case "shuffle": player.nextAlbum()
                case "window": PlayerWindow.show()
                case "artists":
                    PlayerWindow.show()
                    PlayerWindow.toggleArtists()
                case "radio": player.radio = true
                case "album": player.radio = false
                case "dislike": player.dislikeCurrent()
                case "like": player.likeCurrent()
                case "signin": BandcampSession.shared.signIn()
                case "artist":
                    // derive://artist?url=name.bandcamp.com plays that artist, listed or not.
                    let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "url" }?.value ?? ""
                    guard let site = ArtistStore.siteURL(from: value) else { break }
                    let artist = ArtistStore.shared.artists.first { $0.url.host == site.host }
                        ?? Artist(url: site, name: site.host ?? value)
                    player.playArtist(artist)
                default: break
                }
            }
        }
    }
}

@main
struct DeriveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var player = Player.shared

    init() {
        SettingsMigration.run()
    }

    var body: some Scene {
        MenuBarExtra {
            PlayerView(style: .menu)
        } label: {
            Image(systemName: player.isPlaying ? "waveform" : "play.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

/// The app was called Sonnov, with bundle ID com.stephanepoulin.sonnov. On first launch under the
/// new ID, copies its settings (artists, player window) so nothing is lost. The old file is left as is.
enum SettingsMigration {
    private static let oldDomain = "com.stephanepoulin.sonnov"
    private static let doneKey = "migratedFromSonnov"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        // Nothing to copy, or settings already exist under the new ID.
        guard defaults.object(forKey: "artists") == nil,
              let old = defaults.persistentDomain(forName: oldDomain) else { return }
        for (key, value) in old where !key.hasPrefix("NSStatusItem") {
            defaults.set(value, forKey: key)
        }
    }
}
