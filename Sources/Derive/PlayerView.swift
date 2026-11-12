import AppKit
import SwiftUI

/// The player window's content: the player, and the Artists panel on its right when open.
/// The cover's tint is behind both.
struct PlayerWindowContent: View {
    @ObservedObject private var player = Player.shared
    @ObservedObject private var panel = ArtistsPanel.shared

    var body: some View {
        HStack(spacing: 0) {
            PlayerView(style: .window)
                .frame(maxWidth: .infinity)
            if panel.isOpen {
                ArtistsView()
                    .frame(width: ArtistsPanel.width)
                    .background(.black.opacity(0.22))
                    // Sized first: in a tall window, the square cover must not push the panel out.
                    .layoutPriority(1)
            }
        }
        .background {
            // The cover's tint, with a darker bottom for depth. Fades with the cover.
            ZStack {
                Color(nsColor: player.tint)
                LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
            }
            .animation(.easeInOut(duration: 1), value: player.coverID)
            .ignoresSafeArea()
        }
        // The tint is always dark, so the window always uses light text.
        .environment(\.colorScheme, .dark)
    }
}

/// Whether the Artists panel is open in the player window. Saved, like the window's frame.
@MainActor
final class ArtistsPanel: ObservableObject {
    static let shared = ArtistsPanel()
    static let width: CGFloat = 440
    private static let key = "artistsPanelOpen"

    @Published var isOpen = UserDefaults.standard.bool(forKey: ArtistsPanel.key) {
        didSet { UserDefaults.standard.set(isOpen, forKey: Self.key) }
    }
}

/// The player, shown in the menu bar window and in the player window.
struct PlayerView: View {
    enum Style { case menu, window }

    let style: Style
    @ObservedObject private var player = Player.shared
    @AppStorage(PlayerWindow.keepOnTopKey) private var keepOnTop = false
    @ObservedObject private var panel = ArtistsPanel.shared

    var body: some View {
        VStack(spacing: 10) {
            cover
            controls
            status
            Divider()
            footer
        }
        .padding(14)
        .frame(width: style == .menu ? 220 : nil)
        .frame(minWidth: style == .window ? PlayerWindow.minPlayerWidth : nil,
               minHeight: style == .window ? 320 : nil)
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let cover = player.cover {
                // A new id per cover: the old image fades out while the new one fades in.
                Image(nsImage: cover).resizable().scaledToFill()
                    .id(player.coverID)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1), value: player.coverID)
        .aspectRatio(1, contentMode: .fit)
        // Menu: fixed-size slot, the menu bar window does not reliably resize with its content.
        // Window: the cover grows with the window.
        .frame(width: style == .menu ? 192 : nil, height: style == .menu ? 192 : nil)
        .frame(maxWidth: style == .window ? .infinity : nil, maxHeight: style == .window ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            if style == .menu {
                Button { PlayerWindow.show() } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Open the player in its own window")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: style == .menu ? 16 : 22) {
            Button { player.radio.toggle() } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15))
                    .foregroundStyle(player.radio ? Color.accentColor : Color.secondary)
            }
            .help(player.radio
                  ? "Radio is on: a new random album after each track"
                  : "Radio is off: the album plays to the end")

            Button { player.nextAlbum() } label: {
                Image(systemName: "shuffle").font(.system(size: 18))
            }
            .help("Random album")

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }

            Button { player.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.system(size: 18))
            }
            .help(player.radio ? "Next random track" : "Next track")
            .disabled(player.nowPlaying == nil)

            Button { player.dislikeCurrent() } label: {
                Image(systemName: "hand.thumbsdown").font(.system(size: 15))
            }
            .help("Thumbs down: skip this track and never play it again")
            .disabled(player.nowPlaying == nil)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .disabled(player.isLoading)
    }

    private var status: some View {
        // Reserves room for a two-line title plus the artist, so the controls don't jump,
        // while the artist stays right under the title when the title fits on one line.
        ZStack(alignment: .top) {
            names(title: Text("A\nA"), artist: " ").hidden()
            names(title: titleText, artist: player.isLoading ? " " : player.artist ?? " ")
        }
    }

    private var titleText: Text {
        if player.isLoading { return Text("Loading…") }
        if let error = player.errorMessage { return Text(error).foregroundColor(.red) }
        return Text(player.nowPlaying ?? " ")
    }

    private func names(title: Text, artist: String) -> some View {
        VStack(spacing: 4) {
            title
                // The menu bar window is small; the player window has room for readable names.
                .font(style == .menu ? .caption : .title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(artist)
                .font(style == .menu ? .caption.weight(.semibold) : .title2.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Bandcamp") {
                if let url = player.pageURL { NSWorkspace.shared.open(url) }
            }
            .disabled(player.pageURL == nil)
            .help("Open the current album on Bandcamp")
            Spacer()
            switch style {
            case .menu:
                Button("Artists…") { PlayerWindow.showArtists() }
                    .help("Open the player window with the artist list")
            case .window:
                Button(panel.isOpen ? "Hide artists" : "Artists…") { PlayerWindow.toggleArtists() }
            }
            Spacer()
            switch style {
            case .menu:
                AppMenu()
            case .window:
                Toggle("On top", isOn: $keepOnTop)
                    .toggleStyle(.checkbox)
                    .help("Keep this window above other apps")
            }
        }
        .buttonStyle(.plain).font(.caption)
    }
}

/// The player in its own window, which stays open when clicking elsewhere.
/// Its frame is saved by AppKit; whether it was open is saved so it comes back at launch.
@MainActor
enum PlayerWindow {
    static let keepOnTopKey = "playerWindowKeepOnTop"
    /// Leaves room for the five buttons with some space on each side.
    static let minPlayerWidth: CGFloat = 300
    private static let openKey = "playerWindowOpen"
    private static var window: NSWindow?
    private static let delegate = Delegate()
    /// Applies "On top" as soon as the setting changes, from the checkbox or from outside.
    private static var keepOnTopObserver: NSKeyValueObservation?
    static var isQuitting = false

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: PlayerWindowContent())
            host.sizingOptions = [.minSize]
            let created = NSWindow(contentViewController: host)
            created.title = "Dérive"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            created.isMovableByWindowBackground = true
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.fullScreenNone]
            created.delegate = delegate
            created.setContentSize(NSSize(width: 340, height: 470))
            created.center()
            created.setFrameAutosaveName("PlayerWindow")
            // A frame saved by an older version may be narrower than the player now allows.
            let minWidth = minPlayerWidth + (ArtistsPanel.shared.isOpen ? ArtistsPanel.width : 0)
            if created.frame.width < minWidth {
                var frame = created.frame
                frame.size.width = minWidth
                created.setFrame(frame, display: false)
            }
            window = created
            keepOnTopObserver = UserDefaults.standard.observe(\.playerWindowKeepOnTop) { _, _ in
                Task { @MainActor in PlayerWindow.applyLevel() }
            }
        }
        applyLevel()
        UserDefaults.standard.set(true, forKey: openKey)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Reopens the window at launch when it was open when the app quit.
    static func restore() {
        if UserDefaults.standard.bool(forKey: openKey) { show() }
    }

    /// Opens the player window with the Artists panel.
    static func showArtists() {
        show()
        setArtists(true)
    }

    static func toggleArtists() {
        setArtists(!ArtistsPanel.shared.isOpen)
    }

    /// A window at least this wide keeps its width when the panel opens: the player gets
    /// narrower instead (it keeps 400 points or more). A narrower window grows to the right.
    static let wideWindow: CGFloat = 400 + ArtistsPanel.width
    /// Whether opening the panel made the window wider, so closing it gives that width back.
    private static let grewKey = "artistsPanelGrewWindow"

    private static func setArtists(_ open: Bool) {
        let panel = ArtistsPanel.shared
        guard let window, panel.isOpen != open else { return }
        var frame = window.frame
        let screen = window.screen?.visibleFrame
        if open {
            let height = max(frame.height, 560)
            frame.origin.y = frame.maxY - height // Keep the top edge in place.
            frame.size.height = height
            let grows = frame.width < wideWindow
            if grows {
                frame.size.width += ArtistsPanel.width
                if let screen {
                    // Stay on the screen: move left first, then shrink the player if still too wide.
                    frame.size.width = min(frame.width, screen.width)
                    if frame.maxX > screen.maxX { frame.origin.x = max(screen.minX, screen.maxX - frame.width) }
                }
            }
            UserDefaults.standard.set(grows, forKey: grewKey)
            // Resize first, then show the panel, so the player never gets squeezed.
            window.setFrame(frame, display: true)
            panel.isOpen = true
        } else {
            panel.isOpen = false
            if UserDefaults.standard.bool(forKey: grewKey) {
                // Never narrower than the player's minimum, even if the window was made smaller.
                frame.size.width = max(frame.width - ArtistsPanel.width, PlayerWindow.minPlayerWidth)
                window.setFrame(frame, display: true)
            }
        }
    }

    static func applyLevel() {
        window?.level = UserDefaults.standard.bool(forKey: keepOnTopKey) ? .floating : .normal
    }

    private final class Delegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                // Quitting also closes the window: only a close by the user forgets it.
                if !PlayerWindow.isQuitting {
                    UserDefaults.standard.set(false, forKey: PlayerWindow.openKey)
                }
            }
        }
    }
}

private extension UserDefaults {
    /// Same name as PlayerWindow.keepOnTopKey, so the setting can be observed with KVO.
    @objc dynamic var playerWindowKeepOnTop: Bool { bool(forKey: "playerWindowKeepOnTop") }
}
