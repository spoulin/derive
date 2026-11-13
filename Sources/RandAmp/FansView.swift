import AppKit
import SwiftUI

/// Fans tab: the fans you follow on Bandcamp. Click one to shuffle in their collection; the dice
/// picks one at random; Fans mix takes each album from a different fan's collection.
struct FansView: View {
    @ObservedObject private var store = FollowedFanStore.shared
    @ObservedObject private var player = Player.shared
    @ObservedObject private var guest = GuestCollection.shared
    @ObservedObject private var session = BandcampSession.shared
    @ObservedObject private var artists = ArtistStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if store.fans.isEmpty {
                Text(store.owner == nil
                     ? "Sign in to Bandcamp, or link your profile in the Artists tab, to see the fans you follow."
                     : "You follow no fans yet. Right-click a supporter in Community, or a fan under an album's comments, and choose Follow on Bandcamp. In someone's collection, the banner has a Follow button too.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(store.fans) { fan in row(fan) }
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
            }
        }
        .task { await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { player.shuffleRandomFan() } label: {
                    Label("Random Fan", systemImage: "dice")
                }
                .controlSize(.small)
                .disabled(store.fans.isEmpty)
                .help("Shuffle in the collection of a fan you follow, picked at random")
                Toggle("Fans mix", isOn: $player.fansMix)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(store.fans.isEmpty && !player.fansMix)
                Spacer()
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .disabled(store.owner == nil)
                        .help("Read the fans you follow on Bandcamp again")
                }
            }
            Text(player.fansMix
                 ? "Fans mix: each album comes from the collection of a fan you follow, picked at random."
                 : "Turn on Fans mix to take each album from a different fan's collection.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isPlaying(_ fan: FollowedFan) -> Bool {
        guest.username == fan.username || (player.fansMix && player.mixFan?.id == fan.id)
    }

    private func row(_ fan: FollowedFan) -> some View {
        HStack {
            Button { player.shuffleCollection(of: fan.username, avatar: fan.avatarURL) } label: {
                FanAvatar(url: fan.avatarURL, side: 36)
            }
            .buttonStyle(.plain)
            .help("Shuffle in \(fan.name)'s collection")
            VStack(alignment: .leading, spacing: 2) {
                Text(fan.name)
                if let location = fan.location {
                    Text(location).font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer()
            if isPlaying(fan) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .help("Playing from \(fan.name)'s collection")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Shuffle Their Collection") { player.shuffleCollection(of: fan.username, avatar: fan.avatarURL) }
            Button("Open on Bandcamp") { NSWorkspace.shared.open(fan.profileURL) }
            Divider()
            Button("Unfollow on Bandcamp") { Task { await setFollowing(false, fan) } }
        }
    }
}

/// A fan's picture, round. On hover, a play glyph says that a click plays their collection.
struct FanAvatar: View {
    let url: URL?
    let side: CGFloat
    @State private var hovering = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .overlay {
            if hovering {
                ZStack {
                    Color.black.opacity(0.35)
                    Image(systemName: "play.fill")
                        .font(.system(size: side * 0.35))
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

/// Follow or unfollow, in the banner of someone's collection.
struct FanFollowButton: View {
    let fanID: Int
    let username: String
    let name: String
    let avatarURL: URL?

    @ObservedObject private var store = FollowedFanStore.shared
    @State private var working = false
    @State private var hovering = false

    private var following: Bool { store.isFollowing(fanID) }

    var body: some View {
        Button {
            working = true
            Task {
                defer { working = false }
                await setFollowing(!following, FollowedFan(id: fanID, username: username, name: name,
                                                           avatarURL: avatarURL, location: nil))
            }
        } label: {
            HStack(spacing: 3) {
                if working {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: following ? (hovering ? "xmark" : "checkmark") : "plus")
                }
                Text(following ? (hovering ? "Unfollow" : "Following") : "Follow")
            }
        }
        .controlSize(.small)
        .disabled(working)
        .onHover { hovering = $0 }
        .help(following ? "You follow \(name) on Bandcamp. Click to unfollow."
              : "Follow \(name) on Bandcamp: they join your Fans tab")
    }
}

/// Follows or unfollows a fan on Bandcamp, then updates the Fans tab. Signed out, it opens the
/// sign-in window.
@MainActor
func setFollowing(_ follow: Bool, _ fan: FollowedFan) async {
    let session = BandcampSession.shared
    guard session.isSignedIn else { return session.signIn() }
    guard let now = await session.setFollowingFan(follow, fanID: fan.id, username: fan.username) else {
        Toast.shared.show("Bandcamp didn't take it. Try again, or on their profile page.",
                          symbol: "exclamationmark.triangle")
        return
    }
    FollowedFanStore.shared.setFollowing(now, fan)
    Toast.shared.show(now ? "Following \(fan.name): added to your Fans tab"
                          : "Unfollowed \(fan.name): removed from your Fans tab",
                      symbol: now ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus")
}

/// Follows or unfollows a fan known only by their profile link (a supporter, a fan comment):
/// their Bandcamp ID and name are read from their profile first.
@MainActor
func toggleFollowing(_ profileURL: URL?, avatar: URL? = nil) async {
    guard let username = profileURL.flatMap({ Following.username(from: $0.absoluteString) }) else { return }
    let store = FollowedFanStore.shared
    if let known = store.fans.first(where: { $0.username == username }) {
        return await setFollowing(false, known)
    }
    guard BandcampSession.shared.isSignedIn else { return BandcampSession.shared.signIn() }
    guard let page = try? await FanCollection.first(of: username) else {
        Toast.shared.show("Couldn't read \(username)'s profile on Bandcamp", symbol: "exclamationmark.triangle")
        return
    }
    await setFollowing(true, FollowedFan(id: page.fanID, username: username, name: page.name,
                                         avatarURL: page.photoURL ?? avatar, location: nil))
}
