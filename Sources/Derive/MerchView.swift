import AppKit
import Combine
import SwiftUI

/// Merch tab: what the artist playing sells on Bandcamp. A slideshow on top, every item below.
/// Items from the album playing come first. Clicking an item opens it on Bandcamp.
struct MerchView: View {
    @ObservedObject private var player = Player.shared
    @ObservedObject private var store = MerchStore.shared

    var body: some View {
        if let artist = player.currentArtist {
            content(for: artist)
                .task(id: artist.url) { await store.load(artist.url) }
        } else {
            message("Play something to see what the artist sells on Bandcamp.")
        }
    }

    @ViewBuilder private func content(for artist: Artist) -> some View {
        switch store.state(for: artist.url) {
        case nil, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            message(reason)
        case .loaded(let items) where items.isEmpty:
            message("\(artist.name) sells no merch on Bandcamp.")
        case .loaded(let items):
            loaded(sorted(items), artist: artist)
        }
    }

    /// Items of the album playing first, then what is still available, then sold out.
    private func sorted(_ items: [MerchItem]) -> [MerchItem] {
        let path = player.pageURL?.path
        func rank(_ item: MerchItem) -> Int {
            if item.path == path { return 0 }
            return item.soldOut ? 2 : 1
        }
        return items.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private func loaded(_ items: [MerchItem], artist: Artist) -> some View {
        let available = items.filter { !$0.soldOut }
        let slides = available.isEmpty ? items : available
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(artist.name) on Bandcamp · \(items.count) items")
                    .font(.caption).foregroundStyle(.secondary)
                MerchSlideshow(items: slides, albumPath: player.pageURL?.path)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 14) {
                    ForEach(items) { item in
                        MerchCard(item: item, fromAlbum: item.path == player.pageURL?.path)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One large item at a time, changing every 6 seconds with a fade, like the covers.
private struct MerchSlideshow: View {
    let items: [MerchItem]
    let albumPath: String?
    @State private var index = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        let item = items[index % items.count]
        VStack(spacing: 8) {
            ZStack {
                slide(item)
                    .id(item.id)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 1), value: item.id)

            if items.count > 1 {
                HStack(spacing: 16) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    Text("\(index % items.count + 1) / \(items.count)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in if items.count > 1 { index += 1 } }
        .onChange(of: items) { _ in index = 0 }
    }

    private func caption(badge: Bool, title: String, details: String) -> some View {
        VStack(spacing: 4) {
            if badge {
                Text("From the album playing")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(details)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ delta: Int) {
        index = (index + delta + items.count) % items.count
    }

    private func slide(_ item: MerchItem) -> some View {
        Button { NSWorkspace.shared.open(item.url) } label: {
            VStack(spacing: 6) {
                Color.clear
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        AsyncImage(url: item.imageURL(size: 16)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Room for the longest text is kept below the image, so the grid never moves
                // between slides, while the lines stay together when the title is short.
                ZStack(alignment: .top) {
                    caption(badge: true, title: "A\nA", details: " ").hidden()
                    caption(badge: item.path == albumPath, title: item.title,
                            details: [item.artist, item.type, item.price].compactMap { $0 }
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                }
            }
        }
        .buttonStyle(.plain)
        .help("Open on Bandcamp")
    }
}

private struct MerchCard: View {
    let item: MerchItem
    let fromAlbum: Bool

    var body: some View {
        Button { NSWorkspace.shared.open(item.url) } label: {
            VStack(alignment: .leading, spacing: 4) {
                // A fixed box with the image laid over it: a filled image must not widen the cell.
                Color.secondary.opacity(0.15)
                    .frame(height: 116)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        AsyncImage(url: item.imageURL(size: 37)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .topLeading) {
                    if fromAlbum {
                        Image(systemName: "music.note")
                            .font(.caption2.weight(.bold))
                            .padding(4)
                            .background(.orange, in: Circle())
                            .padding(4)
                            .help("From the album playing")
                    }
                }
                Text(item.title).font(.caption).lineLimit(2)
                Text(item.soldOut ? "Sold out" : item.price)
                    .font(.caption2).foregroundStyle(item.soldOut ? .orange : .secondary)
            }
            .opacity(item.soldOut ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .help([item.title, item.artist, item.type].compactMap { $0 }.joined(separator: " · "))
    }
}
