import AppKit
import SwiftUI

/// The player, shown in the menu bar window and in the separate player window.
struct PlayerView: View {
    enum Style { case menu, window }

    let style: Style
    @ObservedObject private var player = Player.shared
    @AppStorage(PlayerWindow.keepOnTopKey) private var keepOnTop = false
    @Environment(\.colorScheme) private var colorScheme

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
        .frame(minWidth: style == .window ? 240 : nil, minHeight: style == .window ? 320 : nil)
        .background {
            if style == .window {
                // The cover's tint, with a darker bottom for depth. Fades with the cover.
                ZStack {
                    Color(nsColor: player.tint)
                    LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .animation(.easeInOut(duration: 1), value: player.coverID)
                .ignoresSafeArea()
            }
        }
        // The tint is always dark, so the window always uses light text.
        .environment(\.colorScheme, style == .window ? .dark : colorScheme)
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
        HStack(spacing: 22) {
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
            .help("Next track")
            .disabled(player.nowPlaying == nil)
        }
        .buttonStyle(.plain)
        .disabled(player.isLoading)
    }

    private var status: some View {
        VStack(spacing: 4) {
            Group {
                if player.isLoading {
                    Text("Loading…")
                } else if let error = player.errorMessage {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text(player.nowPlaying ?? " ")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2, reservesSpace: true)

            Text(player.isLoading ? " " : player.artist ?? " ")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack {
            Button("Bandcamp") {
                if let url = player.pageURL { NSWorkspace.shared.open(url) }
            }
            .disabled(player.pageURL == nil)
            .help("Open the current album on Bandcamp")
            Spacer()
            Button("Artists…") { ArtistsWindow.show() }
            Spacer()
            switch style {
            case .menu:
                Button("Quit") { NSApplication.shared.terminate(nil) }
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
    private static let openKey = "playerWindowOpen"
    private static var window: NSWindow?
    private static let delegate = Delegate()
    /// Applies "On top" as soon as the setting changes, from the checkbox or from outside.
    private static var keepOnTopObserver: NSKeyValueObservation?
    static var isQuitting = false

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: PlayerView(style: .window))
            host.sizingOptions = [.minSize]
            let created = NSWindow(contentViewController: host)
            created.title = "Sonnov"
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
