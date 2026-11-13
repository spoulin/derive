import AppKit
import SwiftUI

/// Artist tab: who plays the release playing, where they play next, and what fans wrote about
/// the release. Read from the release page, so it follows the album playing.
struct ArtistInfoView: View {
    @ObservedObject private var player = Player.shared
    @ObservedObject private var store = ArtistInfoStore.shared

    var body: some View {
        if let page = player.pageURL {
            content(for: page)
                .task(id: page) { await store.load(page) }
        } else {
            message("Play something to see who the artist is.")
        }
    }

    @ViewBuilder private func content(for page: URL) -> some View {
        switch store.state(for: page) {
        case nil, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason):
            message(reason)
        case .loaded(let info):
            loaded(info, page: page)
        }
    }

    private func loaded(_ info: ArtistInfo, page: URL) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(info)
                if !info.bio.isEmpty { ExpandableText(text: info.bio, lines: 6) }
                if !info.links.isEmpty { links(info.links) }
                if !info.shows.isEmpty { shows(info.shows) }
                release(info, page: page)
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
    }

    /// The artist's photo as a banner, with the name and place over it.
    @ViewBuilder private func header(_ info: ArtistInfo) -> some View {
        let names = VStack(alignment: .leading, spacing: 2) {
            Text(info.name).font(.title2.weight(.semibold))
            if let location = info.location {
                Text(location).font(.callout).foregroundStyle(.secondary)
            }
        }
        if let photo = info.photoURL {
            Color.clear
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .overlay {
                    AsyncImage(url: photo) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    names
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                                   startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            names
        }
    }

    private func links(_ links: [ArtistInfo.Link]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(links) { link in
                Button { NSWorkspace.shared.open(link.url) } label: {
                    Label(link.title, systemImage: "link")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(link.url.absoluteString)
            }
        }
    }

    private func shows(_ shows: [ArtistInfo.Show]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Upcoming shows (\(shows.count))")
            ExpandableList(items: shows, visible: 5) { show in
                Button { if let url = show.url { NSWorkspace.shared.open(url) } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(show.date)
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(show.venue).font(.callout.weight(.medium))
                            Text(show.place).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(show.url == nil)
                .help(show.url == nil ? "" : "Open the show's page")
            }
        }
    }

    @ViewBuilder private func release(_ info: ArtistInfo, page: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Playing from")
                    Text(info.releaseTitle).font(.headline)
                    if let date = info.releaseDate {
                        // Bandcamp gives the day at midnight GMT: read it in GMT, or it
                        // shows the day before west of Greenwich.
                        Text("Released \(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "GMT")!)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { NSWorkspace.shared.open(page) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
                    .help("Open on Bandcamp")
            }
            if !info.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(info.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            if !info.about.isEmpty { ExpandableText(text: info.about, lines: 5) }
            if !info.credits.isEmpty {
                ExpandableText(text: info.credits, lines: 3).font(.caption).foregroundStyle(.secondary)
            }
            if !info.comments.isEmpty { comments(info.comments) }
        }
    }

    private func comments(_ comments: [ArtistInfo.FanComment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What fans wrote")
            ForEach(comments) { comment in
                HStack(alignment: .top, spacing: 10) {
                    AsyncImage(url: comment.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.quaternary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Button { if let url = comment.profileURL { NSWorkspace.shared.open(url) } } label: {
                            Text(comment.name).font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Open their Bandcamp profile")
                        Text(comment.text).font(.callout).textSelection(.enabled)
                        if let track = comment.favoriteTrack {
                            Text("Favorite track: \(track)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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

/// Text cut after a few lines, with More / Less.
private struct ExpandableText: View {
    let text: String
    let lines: Int
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if text.count > lines * 60 || text.components(separatedBy: "\n").count > lines {
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .onChange(of: text) { _ in expanded = false }
    }
}

/// The first items of a list, with a button to show the rest.
private struct ExpandableList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let visible: Int
    @ViewBuilder let row: (Item) -> Row
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(expanded ? items : Array(items.prefix(visible))) { row($0) }
            if items.count > visible {
                Button(expanded ? "Show fewer" : "Show all \(items.count)") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

/// Lays its views out left to right, wrapping to a new line when the width runs out.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
