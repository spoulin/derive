import SwiftUI

/// Follow or unfollow the artist (or label) on Bandcamp, with your session. Signed out, it opens
/// the sign-in window. The followed list in Dérive changes right away.
struct FollowButton: View {
    let site: URL
    let name: String
    let bandID: Int?

    @ObservedObject private var session = BandcampSession.shared
    @ObservedObject private var store = ArtistStore.shared
    @State private var working = false
    @State private var hovering = false

    private var following: Bool { store.isFollowed(bandID: bandID, site: site) }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                if working {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: following ? (hovering ? "xmark" : "checkmark") : "plus")
                }
                Text(following ? (hovering ? "Unfollow" : "Following") : "Follow")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(following ? Color.primary : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(following ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.accentColor), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(working || bandID == nil)
        .onHover { hovering = $0 }
        .help(!session.isSignedIn ? "Sign in to Bandcamp to follow \(name)"
              : following ? "You follow \(name) on Bandcamp. Click to unfollow."
              : "Follow \(name) on Bandcamp: they join your followed artists")
    }

    private func toggle() {
        guard session.isSignedIn else { return session.signIn() }
        guard let bandID else { return }
        let follow = !following
        working = true
        Task {
            defer { working = false }
            guard let now = await session.setFollowing(follow, bandID: bandID) else {
                Toast.shared.show("Bandcamp didn't take it. Try again, or on the artist's page.",
                                  symbol: "exclamationmark.triangle")
                return
            }
            store.setFollowed(now, site: site, name: name, bandID: bandID)
            Toast.shared.show(now ? "Following \(name): added to your artists"
                                  : "Unfollowed \(name): removed from your artists",
                              symbol: now ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.minus")
        }
    }
}
