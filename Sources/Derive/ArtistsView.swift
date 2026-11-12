import AppKit
import SwiftUI

/// Panel of the player window, with two tabs: the artists to pick from, and the tracks
/// given a thumbs down.
struct ArtistsView: View {
    enum Tab: String { case artists, dislikes }

    @ObservedObject var store = ArtistStore.shared
    @ObservedObject var dislikes = DislikeStore.shared
    @State private var input = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirmUnlink = false
    @AppStorage("panelTab") private var tab = Tab.artists

    private var followedCount: Int { store.artists.filter(\.isFollowed).count }
    private var manualCount: Int { store.artists.count - followedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $tab) {
                Text("Artists (\(store.artists.count))").tag(Tab.artists)
                Text("Thumbs down (\(dislikes.tracks.count))").tag(Tab.dislikes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .artists: artistsTab
            case .dislikes: dislikesTab
            }
        }
        .padding(16)
        .frame(minHeight: 420)
    }

    @ViewBuilder private var artistsTab: some View {
        List {
            if store.artists.isEmpty && store.profile == nil {
                Text("No artists yet. Paste an artist's address, or your Bandcamp profile to play the artists you follow.")
                    .foregroundStyle(.secondary)
            }
            if manualCount > 0 {
                Section("Added by hand") {
                    ForEach($store.artists) { $artist in
                        if !artist.isFollowed {
                            row($artist, removable: true)
                        }
                    }
                }
            }
            if let profile = store.profile {
                Section {
                    if let syncError = store.syncError {
                        Text(syncError).font(.caption).foregroundStyle(.red)
                    }
                    ForEach($store.artists) { $artist in
                        if artist.isFollowed {
                            row($artist, removable: false)
                        }
                    }
                } header: {
                    followingHeader(profile)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .frame(minHeight: 160)
        .confirmationDialog("Unlink bandcamp.com/\(store.profile ?? "")?", isPresented: $confirmUnlink) {
            Button("Unlink and remove \(followedCount) artists", role: .destructive) { store.unlink() }
        } message: {
            Text("Artists added by hand stay. You can link the profile again later, but on and off choices are lost.")
        }

        // One field for both: an artist's site, or a Bandcamp profile to link.
        HStack {
            TextField("name.bandcamp.com or bandcamp.com/yourprofile", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
                .disabled(isWorking)
            if isWorking {
                ProgressView().controlSize(.small)
            } else {
                Button("Add", action: add).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func followingHeader(_ profile: String) -> some View {
        HStack {
            Text("Following on Bandcamp (\(followedCount))")
                .help("Artists and labels followed by bandcamp.com/\(profile). They update at each launch.")
            Spacer()
            if store.isSyncing {
                ProgressView().controlSize(.mini)
            }
            Menu {
                Button("Refresh from bandcamp.com/\(profile)") { Task { await store.refresh() } }
                Divider()
                Button("Turn all on") { store.setFollowedEnabled(true) }
                Button("Turn all off") { store.setFollowedEnabled(false) }
                Divider()
                Button("Unlink…") { confirmUnlink = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }


    @ViewBuilder private var dislikesTab: some View {
        if dislikes.tracks.isEmpty {
            Text("No thumbs down yet. Tracks you give a thumbs down are listed here and never played again.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(dislikes.tracks) { track in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                        Text("\(track.artist) — \(track.album)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                    Button { Player.shared.playDisliked(track) } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Listen to this track")
                    Button { NSWorkspace.shared.open(track.albumURL) } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open the album on Bandcamp")
                    Button { dislikes.remove(track) } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove the thumbs down: this track can play again")
                }
            }
            .scrollContentBackground(.hidden)
            Text("These tracks are never played at random. Click play to listen to one, or the undo arrow to let it play again.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ artist: Binding<Artist>, removable: Bool) -> some View {
        HStack {
            Button {
                Player.shared.playArtist(artist.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Play a random album by \(artist.wrappedValue.name) (turns radio off)")
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.wrappedValue.name)
                Text(artist.wrappedValue.url.host ?? "").font(.caption).foregroundStyle(.secondary)
            }
            // Turned-off artists are dimmed, so the list reads at a glance.
            .opacity(artist.wrappedValue.enabled ? 1 : 0.45)
            Spacer()
            if removable {
                Button {
                    store.remove(artist.wrappedValue)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove \(artist.wrappedValue.name)")
            }
            Toggle("Play \(artist.wrappedValue.name) at random", isOn: artist.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }


    /// A profile (bandcamp.com/name) links it; anything else is added as an artist site.
    private func add() {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            do {
                if Following.username(from: input) != nil {
                    if let linked = store.profile {
                        error = "Already linked to bandcamp.com/\(linked). Unlink it first, from the … menu."
                    } else {
                        try await store.link(input)
                        input = ""
                    }
                } else {
                    try await store.add(input)
                    input = ""
                }
            } catch let failure as ArtistStore.AddError {
                error = failure.errorDescription
            } catch let failure as FollowingError {
                error = failure.errorDescription
            } catch {
                self.error = "No albums found at that address."
            }
            isWorking = false
        }
    }
}
