import AppKit
import SwiftUI

/// Community tab: the latest posts on the Bandcamp community page of the artist playing, and the
/// fans who bought something lately. New releases play in Dérive; messages only signed-in
/// followers can read are gathered in one line that opens the page on Bandcamp.
struct CommunityView: View {
    @ObservedObject private var player = Player.shared
    @ObservedObject private var store = CommunityStore.shared
    @ObservedObject private var session = BandcampSession.shared

    var body: some View {
        if let artist = player.currentArtist {
            content(for: artist)
                .task(id: artist.url) { await store.load(artist.url) }
        } else {
            message("Play something to see the artist's community.")
        }
    }

    @ViewBuilder private func content(for artist: Artist) -> some View {
        switch store.state(for: artist.url) {
        case nil, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            message(reason)
        case .loaded(nil):
            message("\(artist.name) has no community page on Bandcamp.")
        case .loaded(let community?):
            loaded(community, artist: artist)
        }
    }

    private func loaded(_ community: Community, artist: Artist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("\(artist.name) on Bandcamp").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { NSWorkspace.shared.open(community.pageURL) } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open the community page on Bandcamp")
                }
                if !community.supporters.isEmpty { supporters(community.supporters) }
                // A thin line between posts, with room on both sides.
                VStack(alignment: .leading, spacing: 14) {
                    sectionTitle("Latest posts")
                    // Messages only followers can read are gathered in one line, which still
                    // tells when the artist posted something new.
                    let locked = community.stories.filter { $0.kind == .message(text: nil) }
                    let shown = community.stories.filter { $0.kind != .message(text: nil) }
                    if !locked.isEmpty { lockedMessages(locked, artist: artist, page: community.pageURL) }
                    if community.stories.isEmpty {
                        Text("No posts yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, story in
                        if index > 0 || !locked.isEmpty { Divider().opacity(0.6) }
                        row(story, artist: artist, page: community.pageURL)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
    }

    private func supporters(_ fans: [Community.Supporter]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recent supporters")
            // Top-aligned: a fan without a place has one line less, and must not sit lower.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .top)], spacing: 14) {
                ForEach(fans) { fan in
                    Button { shuffleCollection(fan.profileURL, avatar: fan.avatarURL) } label: {
                        VStack(spacing: 6) {
                            SupporterAvatar(url: fan.avatarURL)
                            Text(fan.name).font(.caption).lineLimit(1)
                            if let location = fan.location {
                                Text(location).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("Shuffle in \(fan.name)'s collection. Right-click to open their Bandcamp page.")
                    .contextMenu { fanMenu(fan.profileURL, avatar: fan.avatarURL) }
                }
            }
        }
    }

    /// One line for the messages only followers can read: how many, and when the latest came.
    /// Marked New when the latest is less than two weeks old.
    private func lockedMessages(_ messages: [Community.Story], artist: Artist, page: URL) -> some View {
        let latest = messages.compactMap(\.date).max()
        let isNew = latest.map { Date().timeIntervalSince($0) < 14 * 24 * 3600 } ?? false
        // Not a button as a whole: the sign-in link inside it must take its own clicks.
        return HStack(spacing: 10) {
                thumbnail(nil, symbol: "lock", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(messages.count == 1 ? "1 message from the artist"
                                                 : "\(messages.count) messages from the artist")
                            .font(.callout.weight(.semibold))
                        if isNew {
                            Text("NEW").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.blue, in: Capsule())
                        }
                    }
                    Text([latest.map { "Latest \($0.formatted(.relative(presentation: .named)))" },
                          session.isSignedIn ? "follow \(artist.name) on Bandcamp to read them"
                                             : "for followers signed in on Bandcamp"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if !session.isSignedIn {
                        Button("Sign in to Bandcamp to read them") { session.signIn() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .help("Opens Bandcamp's sign-in page in a window. Dérive keeps the session, never the password.")
                    }
                }
                Spacer(minLength: 0)
                Button { NSWorkspace.shared.open(page) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .help("Read them on Bandcamp")
        }
    }

    @ViewBuilder private func row(_ story: Community.Story, artist: Artist, page: URL) -> some View {
        switch story.kind {
        case let .release(title, by, art, url, featured, preorder):
            postRow(story, label: preorder ? "Pre-order" : "New release", color: .orange) {
                Button { if let url { Player.shared.playAlbum(at: url, by: artist) } } label: {
                    thumbnail(art, symbol: "music.note", size: 96)
                        .overlay {
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                                .shadow(radius: 3)
                        }
                }
                .buttonStyle(.plain)
                .disabled(url == nil)
                .help("Play it")
            } content: {
                Text(title).font(.callout.weight(.semibold))
                if let by, by != artist.name {
                    Text(by).font(.caption).foregroundStyle(.secondary)
                }
                if let featured, !featured.isEmpty {
                    Text("Featured track: \(featured)").font(.caption).foregroundStyle(.secondary)
                }
            } open: { url ?? page }

        case let .listeningParty(title, text, start, art, url):
            postRow(story, label: "Listening party", color: .purple) {
                thumbnail(art, symbol: "dot.radiowaves.left.and.right")
            } content: {
                Text(title).font(.callout.weight(.semibold))
                if let start {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !text.isEmpty { Text(text).font(.callout).lineSpacing(4) }
            } open: { url ?? page }

        case let .message(text):
            postRow(story, label: "Message from the artist", color: .blue) {
                thumbnail(nil, symbol: "text.bubble")
            } content: {
                if let text {
                    Text(text).font(.callout).lineSpacing(4).lineLimit(8).textSelection(.enabled)
                } else {
                    Text("Only followers signed in on Bandcamp can read it.")
                        .font(.callout).italic().foregroundStyle(.secondary)
                }
            } open: { page }
        }
    }

    /// One post: a picture on the left, then a colored label, the content and a line with the
    /// date, likes and comments. The arrow opens the post's page on Bandcamp.
    private func postRow<Picture: View, Content: View>(
        _ story: Community.Story, label: String, color: Color,
        @ViewBuilder picture: () -> Picture, @ViewBuilder content: () -> Content,
        open: () -> URL
    ) -> some View {
        let url = open()
        return HStack(alignment: .top, spacing: 12) {
            picture()
            VStack(alignment: .leading, spacing: 5) {
                Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(color)
                content()
                HStack(spacing: 10) {
                    if let date = story.date {
                        Text(date.formatted(.relative(presentation: .named)))
                    }
                    if story.likes > 0 { Label("\(story.likes)", systemImage: "heart") }
                    if story.comments > 0 { Label("\(story.comments)", systemImage: "bubble.left") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless)
                .help("Open on Bandcamp")
        }
    }

    private func thumbnail(_ url: URL?, symbol: String, size: CGFloat = 48) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                } else {
                    Image(systemName: symbol).foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Clicking a fan shuffles in their collection; their Bandcamp page is in the right-click menu.
@MainActor
func shuffleCollection(_ profileURL: URL?, avatar: URL? = nil) {
    guard let user = profileURL.flatMap({ Following.username(from: $0.absoluteString) }) else { return }
    Player.shared.shuffleCollection(of: user, avatar: avatar)
}

@MainActor @ViewBuilder
func fanMenu(_ profileURL: URL?, avatar: URL? = nil) -> some View {
    Button("Shuffle Their Collection") { shuffleCollection(profileURL, avatar: avatar) }
    Button("Open on Bandcamp") { if let url = profileURL { NSWorkspace.shared.open(url) } }
}

/// A recent supporter's picture. On hover, a play glyph says that a click plays their collection.
private struct SupporterAvatar: View {
    let url: URL?
    @State private var hovering = false

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: 64, height: 64)
        .overlay {
            if hovering {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
                .transition(.opacity)
            }
        }
        .clipShape(Circle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }
}
