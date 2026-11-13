import AppKit
import SwiftUI

/// History tab: the tracks played, newest first, and the Avoid repeats switch.
struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var dislikes = DislikeStore.shared
    @ObservedObject private var likes = LikeStore.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if history.tracks.isEmpty {
                Text("No tracks yet. The tracks you play are listed here, the last one first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // A new track goes on top: scroll up to it, so it is always in full view.
                ScrollViewReader { proxy in
                    List(history.tracks) { track in row(track).id(track.id) }
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .onChange(of: history.tracks.first?.id) { newest in
                            guard let newest else { return }
                            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(newest, anchor: .top) }
                        }
                }
            }
        }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("The list of tracks played is emptied. Thumbs down stay.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Avoid repeats", isOn: $history.avoidRepeats)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button("Clear…") { confirmClear = true }
                    .buttonStyle(.borderless)
                    .disabled(history.tracks.isEmpty)
                    .help("Empty the history")
            }
            Text(history.avoidRepeats
                 ? "The random pick skips the tracks and albums heard in the last 24 hours, and the artist just heard, as long as something else can play."
                 : "Turn on to keep the random pick from playing again what you heard in the last 24 hours.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ track: PlayedTrack) -> some View {
        let disliked = dislikes.contains(track.trackID)
        return HStack {
            // The cover plays the track too, like the play button.
            Button { Player.shared.playAgain(track) } label: {
                CoverThumbnail(url: track.artURL)
            }
            .buttonStyle(.plain)
            .opacity(disliked ? 0.45 : 1)
            .help("Play this track again")
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                Text("\(track.artist) — \(track.album)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .opacity(disliked ? 0.45 : 1)
            Spacer()
            // Right after a track starts, the relative date would say "in 0 secs".
            Text(Date().timeIntervalSince(track.playedAt) < 10 ? "now"
                 : track.playedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
            Button { Player.shared.playAgain(track) } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("Play this track again")
            Button { NSWorkspace.shared.open(track.albumURL) } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .help("Open the album on Bandcamp")
            Button {
                if likes.contains(track.trackID) {
                    likes.remove(track.trackID)
                } else {
                    likes.add(LikedTrack(id: track.trackID, title: track.title, album: track.album,
                                         artist: track.artist, albumURL: track.albumURL, artURL: track.artURL,
                                         likedAt: Date()))
                    if let entry = dislikes.tracks.first(where: { $0.id == track.trackID }) { dislikes.remove(entry) }
                }
            } label: {
                Image(systemName: likes.contains(track.trackID) ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.borderless)
            .disabled(track.trackID == 0)
            .help(likes.contains(track.trackID) ? "Remove the thumbs up" : "Thumbs up: keep this track in Liked")
            Button {
                if disliked {
                    if let entry = dislikes.tracks.first(where: { $0.id == track.trackID }) { dislikes.remove(entry) }
                } else {
                    dislikes.add(DislikedTrack(id: track.trackID, title: track.title, album: track.album,
                                               artist: track.artist, albumURL: track.albumURL,
                                               artURL: track.artURL))
                    likes.remove(track.trackID)
                }
            } label: {
                Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .buttonStyle(.borderless)
            .disabled(track.trackID == 0)
            .help(disliked ? "Remove the thumbs down" : "Thumbs down: never play this track again")
        }
    }
}

/// A small album cover for a list row; a music note when the cover isn't known.
struct CoverThumbnail: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: 34, height: 34)
            .overlay {
                if let thumbnail = coverThumbnail(url) {
                    AsyncImage(url: thumbnail) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                } else {
                    Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Liked tab: the tracks given a thumbs up, newest first.
struct LikedView: View {
    @ObservedObject private var likes = LikeStore.shared

    var body: some View {
        if likes.tracks.isEmpty {
            Text("No thumbs up yet. Click the thumbs up next to the play button to keep a track here.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("Tracks you gave a thumbs up. Click a cover or play to hear one again.")
                .font(.caption).foregroundStyle(.secondary)
            List(likes.tracks) { track in
                HStack {
                    Button { Player.shared.playLiked(track) } label: { CoverThumbnail(url: track.artURL) }
                        .buttonStyle(.plain)
                        .help("Play this track")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                        Text("\(track.artist) — \(track.album)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                    Button { Player.shared.playLiked(track) } label: { Image(systemName: "play.circle") }
                        .buttonStyle(.borderless)
                        .help("Play this track")
                    Button { NSWorkspace.shared.open(track.albumURL) } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Open the album on Bandcamp")
                    Button { likes.remove(track.id) } label: { Image(systemName: "hand.thumbsup.fill") }
                        .buttonStyle(.borderless)
                        .help("Remove the thumbs up")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
        }
    }
}
