import AppKit
import SwiftUI

/// Window where the user adds, removes and turns artists on or off.
struct ArtistsView: View {
    @ObservedObject var store = ArtistStore.shared
    @State private var input = ""
    @State private var isAdding = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach($store.artists) { $artist in
                    HStack {
                        Toggle(isOn: $artist.enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                Text(artist.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            store.remove(artist)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(artist.name)")
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                TextField("artist.bandcamp.com", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .disabled(isAdding)
                if isAdding {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Add", action: add).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Each artist that is turned on has the same chance. Then one of their albums is picked at random.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 320)
    }

    private func add() {
        guard !isAdding else { return }
        isAdding = true
        error = nil
        Task {
            do {
                try await store.add(input)
                input = ""
            } catch let failure as ArtistStore.AddError {
                error = failure.errorDescription
            } catch {
                self.error = "No albums found at that address."
            }
            isAdding = false
        }
    }
}

/// Opens the Artists window, or brings it to the front. The app has no Dock icon,
/// so it must activate itself for the window to come forward.
@MainActor
enum ArtistsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: ArtistsView()))
            created.title = "Artists"
            created.styleMask = [.titled, .closable, .resizable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
