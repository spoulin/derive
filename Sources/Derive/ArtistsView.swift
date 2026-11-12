import AppKit
import SwiftUI

/// Panel of the player window, with three tabs: the artists to pick from, the tracks given a
/// thumbs down, and the merch of the artist playing.
struct ArtistsView: View {
    enum Tab: String { case artists, dislikes, merch }

    @ObservedObject var store = ArtistStore.shared
    @ObservedObject var dislikes = DislikeStore.shared
    @ObservedObject var playability = PlayabilityStore.shared
    @ObservedObject var player = Player.shared
    @State private var input = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirmUnlink = false
    @State private var showAdd = false
    @AppStorage("panelTab") private var tab = Tab.artists

    private var followedCount: Int { store.artists.filter(\.isFollowed).count }
    private var manualCount: Int { store.artists.count - followedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Show", selection: $tab) {
                    Text("Artists (\(store.artists.count))").tag(Tab.artists)
                    Text("Thumbs down (\(dislikes.tracks.count))").tag(Tab.dislikes)
                    Text("Merch").tag(Tab.merch)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            switch tab {
            case .artists: artistsTab
            case .dislikes: dislikesTab
            case .merch: MerchView()
            }
        }
        .padding(16)
        .frame(minHeight: 420)
    }

    @ViewBuilder private var artistsTab: some View {
        List {
            if store.artists.isEmpty && store.profile == nil {
                HStack(alignment: .top) {
                    Text("No artists yet. Click + to add an artist, or your Bandcamp profile to play the artists you follow.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    artistsToolbar
                }
            }
            if manualCount > 0 {
                Section {
                    ForEach($store.artists) { $artist in
                        if !artist.isFollowed {
                            row($artist, removable: true)
                        }
                    }
                } header: {
                    // The buttons sit on the first section's header, which stays pinned on scroll.
                    HStack {
                        Text("Added by hand")
                        Spacer()
                        artistsToolbar
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
                    HStack {
                        followingHeader(profile)
                        Spacer()
                        if manualCount == 0 { artistsToolbar }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
        .frame(minHeight: 160)
        .confirmationDialog("Unlink bandcamp.com/\(store.profile ?? "")?", isPresented: $confirmUnlink) {
            Button("Unlink and remove \(followedCount) artists", role: .destructive) { store.unlink() }
        } message: {
            Text("Artists added by hand stay. You can link the profile again later, but on and off choices are lost.")
        }

    }

    private func followingHeader(_ profile: String) -> some View {
        Text("Following on Bandcamp (\(followedCount))")
            .help("Artists and labels followed by bandcamp.com/\(profile). They update at each launch.")
    }

    /// Top right of the Artists tab: progress, add, and the other actions.
    @ViewBuilder private var artistsToolbar: some View {
        if let progress = player.checkProgress {
            Text("Checking \(progress.done)/\(progress.total)…").font(.caption).foregroundStyle(.secondary)
        }
        if store.isSyncing || player.checkProgress != nil {
            ProgressView().controlSize(.mini)
        }
        Button { showAdd = true } label: {
            Image(systemName: "plus.circle")
        }
        .buttonStyle(.borderless)
        .help("Add an artist, or link your Bandcamp profile")
        .popover(isPresented: $showAdd, arrowEdge: .bottom) { addForm }
        Menu {
            if let profile = store.profile {
                Button("Refresh from bandcamp.com/\(profile)") { Task { await store.refresh() } }
                Divider()
                Button("Turn all followed on") { store.setFollowedEnabled(true) }
                Button("Turn all followed off") { store.setFollowedEnabled(false) }
                Divider()
            }
            Button("Check which artists can play") {
                Task { await player.checkPlayability(of: store.artists) }
            }
            .disabled(player.checkProgress != nil || store.artists.isEmpty)
            if store.profile != nil {
                Divider()
                Button("Unlink…") { confirmUnlink = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// One field for both: an artist's site, or a Bandcamp profile to link.
    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add an artist or a label, or link your Bandcamp profile to play the artists you follow.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .padding(14)
        .frame(width: 360)
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
            .scrollIndicators(.never)
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
            let reason = playability.reason(for: artist.wrappedValue.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.wrappedValue.name)
                if let reason {
                    Text(reason.label).font(.caption).foregroundStyle(.orange)
                } else {
                    Text(artist.wrappedValue.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            .help(reason?.detail ?? "")
            // Turned-off and unplayable artists are dimmed, so the list reads at a glance.
            .opacity(artist.wrappedValue.enabled && reason == nil ? 1 : 0.45)
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
                        error = "Already linked to bandcamp.com/\(linked). Unlink it first, from the … menu at the top."
                    } else {
                        try await store.link(input)
                        input = ""
                        showAdd = false
                    }
                } else {
                    try await store.add(input)
                    input = ""
                    showAdd = false
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
