import SwiftUI

/// Handles sonnov://play, pause, toggle, next and shuffle (e.g. from a Stream Deck).
final class AppDelegate: NSObject, NSApplicationDelegate {
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
            VStack(spacing: 10) {
                // Fixed-size slot: the menu bar window does not reliably resize with its content.
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    if let url = player.artURL {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .frame(width: 192, height: 192)
                .clipShape(RoundedRectangle(cornerRadius: 6))

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

                Divider()
                HStack {
                    Button("Bandcamp") {
                        if let url = player.pageURL { NSWorkspace.shared.open(url) }
                    }
                    .disabled(player.pageURL == nil)
                    .help("Open the current album on Bandcamp")
                    Spacer()
                    Button("Artists…") { ArtistsWindow.show() }
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
                .buttonStyle(.plain).font(.caption)
            }
            .padding(14)
            .frame(width: 220)
        } label: {
            Image(systemName: player.isPlaying ? "waveform" : "play.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
