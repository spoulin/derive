import AppKit
import SwiftUI

/// Panel of the player window, with two groups of tabs. On the left, the artist playing (photo,
/// bio, shows, fan comments), their community page and their merch. On the right, your library:
/// the artists to pick from, the tracks given a thumbs up or down, and the history.
struct ArtistsView: View {
    enum Tab: String { case artists, fans, likes, dislikes, history, artist, merch, community }

    @ObservedObject var store = ArtistStore.shared
    @ObservedObject var dislikes = DislikeStore.shared
    @ObservedObject var playability = PlayabilityStore.shared
    @ObservedObject var player = Player.shared
    @ObservedObject var merch = MerchStore.shared
    @ObservedObject var info = ArtistInfoStore.shared
    @ObservedObject var community = CommunityStore.shared
    @ObservedObject var session = BandcampSession.shared
    @ObservedObject var history = HistoryStore.shared
    @ObservedObject var likes = LikeStore.shared
    @ObservedObject var fans = FollowedFanStore.shared
    @State private var input = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirmUnlink = false
    @State private var showAdd = false
    @AppStorage("panelTab") private var tab = Tab.artists
    /// The tab cycle of a new track, while it runs.
    @State private var tabCycle: Task<Void, Never>?

    private var followedCount: Int { store.artists.filter(\.isFollowed).count }
    private var manualCount: Int { store.artists.count - followedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Two groups: on the left what follows the album playing, on the right your library
            // (the artists to pick from and the thumbs down). Icons and counts keep the bar
            // short; the names are in the tooltips. A segmented Picker drops an icon mixed with
            // text, so each group is a row of buttons styled like one.
            // With big numbers, the bar would run past the panel: the first form that fits wins.
            ViewThatFits(in: .horizontal) {
                tabBar(.full)
                tabBar(.tight)
                tabBar(.short)
                tabBar(.openTabOnly)
            }

            // A ZStack, so a tab changed by the cycle fades into the next one.
            ZStack {
                // A column, as each tab's views go one under the other (a ZStack alone would
                // lay them over each other).
                VStack(alignment: .leading, spacing: 12) { tabContent }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(tab)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(minHeight: 420)
        // Loads the merch of the artist playing while the panel is open, so the Merch tab
        // shows its count without being opened.
        .task(id: player.currentArtist?.url) {
            guard let site = player.currentArtist?.url else { return }
            async let merchLoaded: Void = merch.load(site)
            async let communityLoaded: Void = community.load(site)
            _ = await (merchLoaded, communityLoaded)
        }
        .task(id: player.pageURL) {
            if let page = player.pageURL { await info.load(page) }
        }
        .onChange(of: player.nowPlaying) { _ in startTabCycle() }
    }

    /// How the tabs show their numbers: in full, in full but closer together, short (1.2K) and
    /// close together, or only on the tab open.
    enum CountStyle { case full, tight, short, openTabOnly }

    private func tabBar(_ style: CountStyle) -> some View {
        HStack {
            tabGroup {
                tabButton(.artist, symbol: "info.circle", counts: style, count: showCount,
                          name: showCount.map { "Artist playing · \($0) upcoming shows" } ?? "Artist playing")
                tabButton(.community, symbol: "bubble.left.and.bubble.right", counts: style, count: communityPosts,
                          name: communityPosts.map { "Community of the artist playing · \($0) posts" }
                              ?? "Community of the artist playing")
                tabButton(.merch, symbol: "cart", counts: style, count: merchCount, name: "Merch of the artist playing")
            }
            Spacer()
            tabGroup {
                tabButton(.artists, symbol: "person.2", counts: style, count: store.artists.count,
                          name: "Your artists")
                tabButton(.fans, symbol: "person.crop.circle", counts: style, count: fans.fans.count,
                          name: "Fans you follow")
                tabButton(.likes, symbol: "hand.thumbsup", counts: style, count: likes.tracks.count,
                          name: "Your thumbs up")
                tabButton(.dislikes, symbol: "hand.thumbsdown", counts: style, count: dislikes.tracks.count,
                          name: "Your thumbs down")
                tabButton(.history, symbol: "clock.arrow.circlepath", counts: style, count: history.playedToday,
                          name: "History · \(history.playedToday) tracks played today")
            }
        }
    }

    /// Upcoming shows of the artist playing, when there are any.
    private var showCount: Int? {
        guard let page = player.pageURL, case .loaded(let artist) = info.state(for: page),
              !artist.shows.isEmpty else { return nil }
        return artist.shows.count
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .artists: artistsTab
        case .dislikes: dislikesTab
        case .history: HistoryView()
        case .likes: LikedView()
        case .fans: FansView()
        case .artist: ArtistInfoView()
        case .merch: MerchView()
        case .community: CommunityView()
        }
    }

    /// At each new track, while a tab of the album playing is open: the (i) tab, then Community,
    /// then Merch, 30 seconds apart. A tab with nothing to show is skipped: no posts, or no merch
    /// still available. Opening a tab yourself stops it. Your library tabs (artists, thumbs
    /// down) are never left this way.
    private func startTabCycle() {
        tabCycle?.cancel()
        tabCycle = nil
        guard player.nowPlaying != nil, [.artist, .community, .merch].contains(tab) else { return }
        if tab != .artist { withAnimation(.easeInOut(duration: 0.8)) { tab = .artist } }
        tabCycle = Task { @MainActor in
            var remaining: [Tab] = [.community, .merch]
            while !remaining.isEmpty {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                var next: Tab?
                while next == nil, !remaining.isEmpty {
                    let candidate = remaining.removeFirst()
                    if await hasContent(candidate) { next = candidate }
                    guard !Task.isCancelled else { return }
                }
                guard let next else { return }
                withAnimation(.easeInOut(duration: 0.8)) { tab = next }
            }
        }
    }

    /// Whether a tab of the album playing has something to show, waiting up to 10 seconds for it
    /// to load.
    private func hasContent(_ tab: Tab) async -> Bool {
        for _ in 0..<20 {
            guard !Task.isCancelled, let site = player.currentArtist?.url else { return false }
            switch tab {
            case .community:
                if let empty = isCommunityEmpty(site) { return !empty }
            case .merch:
                if isMerchEmpty(site) != nil { return (merchCount ?? 0) > 0 }
            default:
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// nil while loading.
    private func isMerchEmpty(_ site: URL) -> Bool? {
        switch merch.state(for: site) {
        case .loaded(let items): items.isEmpty
        case .failed: true
        case nil, .loading: nil
        }
    }

    /// nil while loading. Empty: no community page, or a page without posts or supporters.
    private func isCommunityEmpty(_ site: URL) -> Bool? {
        switch community.state(for: site) {
        case .loaded(let page): page.map { $0.stories.isEmpty && $0.supporters.isEmpty } ?? true
        case .failed: true
        case nil, .loading: nil
        }
    }

    /// Posts listed in the Community tab for the artist playing (messages only followers can
    /// read included), when there are any.
    private var communityPosts: Int? {
        guard let site = player.currentArtist?.url, case .loaded(let page?) = community.state(for: site),
              !page.stories.isEmpty else { return nil }
        return page.stories.count
    }

    /// Items the artist playing still sells (sold out left out); none while loading, or when
    /// nothing plays.
    private var merchCount: Int? {
        guard let site = player.currentArtist?.url,
              case .loaded(let items) = merch.state(for: site) else { return nil }
        return items.filter { !$0.soldOut }.count
    }

    private func tabGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .padding(2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private func tabButton(_ value: Tab, symbol: String, counts style: CountStyle, count: Int?,
                           name: String) -> some View {
        let selected = tab == value
        let shown: String? = count.flatMap { count in
            switch style {
            case .full, .tight: count.formatted()
            case .short: count.formatted(.number.notation(.compactName))
            case .openTabOnly: selected ? count.formatted(.number.notation(.compactName)) : nil
            }
        }
        return Button {
            // Choosing a tab yourself stops the cycle of the track playing.
            tabCycle?.cancel()
            tabCycle = nil
            tab = value
        } label: {
            HStack(spacing: style == .full ? 4 : 3) {
                Image(systemName: symbol)
                if let shown { Text(shown).monospacedDigit() }
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            // One line, whatever the room: with seven tabs, a count must never wrap.
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, style == .full ? 8 : 5)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A number the tab doesn't show in full is in its tooltip (some names already say it).
        .help(style == .full || name.contains("·") ? name : count.map { "\(name) · \($0.formatted())" } ?? name)
        .accessibilityLabel(count.map { "\(name), \($0)" } ?? name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var artistsTab: some View {
        List {
            if store.artists.isEmpty && store.profile == nil {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No artists yet. Sign in to Bandcamp to play the artists you follow, or click + to add an artist or your profile.")
                            .foregroundStyle(.secondary)
                        if !session.isSignedIn {
                            Button("Sign In to Bandcamp…") { session.signIn() }
                        }
                    }
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
        if store.isSyncing {
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
            BandcampSessionButton()
            if store.profile != nil {
                Button("Unlink…") { confirmUnlink = true }
            }
            Divider()
            AboutMenuItems()
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
            if store.profile == nil && !session.isSignedIn {
                Button("Sign In to Bandcamp…") {
                    showAdd = false
                    session.signIn()
                }
                .help("Opens Bandcamp's sign-in page. Signed in, RandAmp links your profile by itself.")
                Text("Signed in, RandAmp plays the artists you follow, and shows their messages in Community. Or, without signing in:")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Text("These tracks are never played at random. Click play to listen to one, or the undo arrow to let it play again.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(dislikes.tracks) { track in
                HStack {
                    CoverThumbnail(url: track.artURL)
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
