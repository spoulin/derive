import SwiftUI

/// Handles randamp:// URLs (e.g. from a Stream Deck) and reopens the player window at launch.
/// derive:// and sonnov:// still work, from when the app was called Dérive, then Sonnov.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NowPlaying.setUp()
            PlayerWindow.restore()
            // Picks up artists followed or unfollowed on Bandcamp since the last launch.
            await ArtistStore.shared.refresh()
            await FollowedFanStore.shared.refresh()
        }
    }

    /// A click on the Dock icon brings the player window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PlayerWindow.show()
        return true
    }

    /// Right-click on the Dock icon: the main controls.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        do {
            let player = Player.shared
            let menu = NSMenu()
            func add(_ title: String, checked: Bool = false, enabled: Bool = true, _ action: @escaping @MainActor () -> Void) {
                let item = DockMenuItem(title: title, action: action)
                item.state = checked ? .on : .off
                item.isEnabled = enabled
                menu.addItem(item)
            }
            let playing = player.nowPlaying != nil
            add(player.isPlaying ? "Pause" : "Play") { player.toggle() }
            add("Next Track", enabled: playing) { player.nextTrack() }
            add("New Random Album") { player.nextAlbum() }
            menu.addItem(.separator())
            add("Thumbs Up", enabled: playing) { player.likeCurrent() }
            add("Thumbs Down", enabled: playing) { player.dislikeCurrent() }
            menu.addItem(.separator())
            add("Radio", checked: player.radio) { player.radio.toggle() }
            add("Favorites", checked: player.favoritesOnly) { player.favoritesOnly.toggle() }
            add("Fans Mix", checked: player.fansMix) { player.fansMix.toggle() }
            add("New Releases", checked: player.newReleases) { player.setNewReleases(!player.newReleases) }
            return menu
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Windows close while quitting; the player window must still reopen at next launch.
        MainActor.assumeIsolated { PlayerWindow.isQuitting = true }
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where ["randamp", "derive", "sonnov"].contains(url.scheme) {
            Task { @MainActor in
                let player = Player.shared
                switch url.host {
                case "play": player.play()
                case "pause": player.pause()
                case "toggle": player.toggle()
                case "next": player.nextTrack()
                case "shuffle": player.nextAlbum()
                case "window": PlayerWindow.show()
                case "artists", "panel":
                    PlayerWindow.show()
                    PlayerWindow.toggleArtists()
                case "radio": player.radio = true
                case "album": player.radio = false
                case "dislike": player.dislikeCurrent()
                case "like": player.likeCurrent()
                case "favorites": player.favoritesOnly.toggle()
                case "fansmix": player.fansMix.toggle()
                case "randomfan": player.shuffleRandomFan()
                case "newreleases": player.setNewReleases(!player.newReleases)
                case "signin": BandcampSession.shared.signIn()
                case "collection":
                    // randamp://collection?user=name shuffles in that fan's collection;
                    // randamp://collection alone goes back to your own artists.
                    let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "user" }?.value
                    if let user = value.flatMap(Following.username(from:)) {
                        player.shuffleCollection(of: user)
                    } else {
                        player.leaveCollection()
                    }
                case "artist":
                    // randamp://artist?url=name.bandcamp.com plays that artist, listed or not.
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
struct RandAmpApp: App {
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
        // The menus at the top of the screen, while the player window is open.
        .commands { RandAmpCommands() }
    }
}

/// The app was called Dérive (com.stephanepoulin.derive), and Sonnov (com.stephanepoulin.sonnov)
/// before that. On first launch under the new ID, copies the settings of the most recent one
/// (artists, likes, history, player window) and Dérive's Bandcamp session, so nothing is lost and
/// no new sign-in is needed. The old files are left as they are.
enum SettingsMigration {
    private static let oldIDs = ["com.stephanepoulin.derive", "com.stephanepoulin.sonnov"]
    private static let doneKey = "migratedToRandAmp"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        // Settings already exist under the new ID: nothing to copy.
        guard defaults.object(forKey: "artists") == nil,
              let oldID = oldIDs.first(where: { defaults.persistentDomain(forName: $0) != nil }),
              let old = defaults.persistentDomain(forName: oldID) else { return }
        for (key, value) in old where !key.hasPrefix("NSStatusItem") {
            defaults.set(value, forKey: key)
        }
        copyWebsiteData(from: oldID)
    }

    /// The sign-in window keeps Bandcamp's cookies in WebKit's folders, named after the bundle ID.
    /// Runs before any web view exists, so WebKit opens the copies.
    private static func copyWebsiteData(from oldID: String) {
        guard let newID = Bundle.main.bundleIdentifier else { return }
        let files = FileManager.default
        let library = files.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        for (folder, suffix) in [("WebKit", ""), ("HTTPStorages", ""), ("HTTPStorages", ".binarycookies")] {
            let old = library.appendingPathComponent(folder).appendingPathComponent(oldID + suffix)
            let new = library.appendingPathComponent(folder).appendingPathComponent(newID + suffix)
            guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { continue }
            try? files.copyItem(at: old, to: new)
        }
    }
}

/// A Dock menu item that runs a closure.
private final class DockMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, action: @escaping @MainActor () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("Not used") }

    @objc private func fire() { MainActor.assumeIsolated { run() } }
}

/// The app's menus, shown while it's in the Dock: Check for Updates in the RandAmp menu, and a
/// Playback menu with the player's controls.
struct RandAmpCommands: Commands {
    @ObservedObject private var player = Player.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { NSWorkspace.shared.open(AppInfo.releasesPage) }
        }
        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Next Track") { player.nextTrack() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.nowPlaying == nil)
            Button("New Random Album") { player.nextAlbum() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            Button("Thumbs Up") { player.likeCurrent() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(player.nowPlaying == nil)
            Button("Thumbs Down") { player.dislikeCurrent() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(player.nowPlaying == nil)
            Divider()
            Toggle("Radio", isOn: $player.radio)
            Toggle("Favorites", isOn: $player.favoritesOnly)
            Toggle("Fans Mix", isOn: $player.fansMix)
            Toggle("New Releases", isOn: Binding(get: { player.newReleases }, set: { player.setNewReleases($0) }))
            Divider()
            Button("Show or Hide Side Panel") { PlayerWindow.toggleArtists() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}
