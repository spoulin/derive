import AppKit
import SwiftUI

/// The New Releases section of the side panel, in two tabs: the styles to choose, and the latest
/// releases in those styles. Both have the mode's switch on top.
struct NewReleasesView: View {
    enum Part { case styles, latest }
    let part: Part

    @ObservedObject private var store = NewReleaseStore.shared
    @ObservedObject private var player = Player.shared
    @ObservedObject private var info = ArtistInfoStore.shared
    @State private var input = ""
    @State private var message: String?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch part {
            case .styles:
                styles
            case .latest:
                Text(store.tags.isEmpty ? "All styles, newest added first"
                                        : "\(store.tags.joined(separator: " + ")), newest added first")
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                releases
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: store.tags) { await store.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("New releases").font(.headline)
                Spacer()
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await store.load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Read the latest releases again")
                }
            }
            Text("Each album is one of the latest added to Bandcamp in these styles, picked at random. Library, at the top, goes back to your artists.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(store.tags.isEmpty ? "All styles" : "Styles").font(.subheadline.weight(.semibold))
                if let total = store.total, !store.tags.isEmpty {
                    Text("\(total.formatted()) releases on Bandcamp")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !store.tags.isEmpty {
                    Button("Clear") { store.clear() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Every style: everything new on Bandcamp")
                }
            }
            if !store.tags.isEmpty {
                FlowLayout {
                    ForEach(store.tags, id: \.self) { tag in
                        Button { store.remove(tag) } label: {
                            HStack(spacing: 3) {
                                Text(tag)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .chip(selected: true)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(tag)")
                    }
                }
            }
            HStack {
                TextField("Add a style or a place: shoegaze, montreal…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .disabled(adding)
                if adding { ProgressView().controlSize(.small) }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            Text("Each style added narrows the list: releases with all of them.")
                .font(.caption).foregroundStyle(.secondary)
            suggestions("From the album playing", playingTags)
            suggestions("Recent", store.recentTags)
            suggestions("Genres", NewReleaseStore.genres)
        }
    }

    /// The tags of the album playing, as Bandcamp writes them in its links.
    private var playingTags: [String] {
        guard let page = player.pageURL, case .loaded(let artist) = info.state(for: page) else { return [] }
        var seen = Set<String>()
        return artist.tags.map(NewReleaseStore.normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// A row of styles to add in a click, without those already chosen. Nothing when empty.
    @ViewBuilder private func suggestions(_ title: String, _ tags: [String]) -> some View {
        let available = tags.filter { !store.tags.contains($0) }
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(available, id: \.self) { tag in
                        Button { add(tag) } label: { Text(tag).chip(selected: false) }
                            .buttonStyle(.plain)
                            .disabled(adding)
                            .help("Add \(tag)")
                    }
                }
            }
        }
    }

    @ViewBuilder private var releases: some View {
        if let error = store.error, store.releases.isEmpty {
            Text(error).foregroundStyle(.secondary)
        } else if store.releases.isEmpty, !store.isLoading {
            Text("No new releases in these styles.").foregroundStyle(.secondary)
        } else {
            List(store.releases) { release in row(release) }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
        }
    }

    private func row(_ release: NewRelease) -> some View {
        HStack {
            Button { play(release) } label: { CoverThumbnail(url: release.artURL) }
                .buttonStyle(.plain)
                .help("Play this release")
            VStack(alignment: .leading, spacing: 2) {
                Text(release.title)
                Text(release.artist).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            // The list is in the order the releases were added; this is the date the artist gave.
            if let date = release.releaseDate {
                let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
                Text(thisYear ? date.formatted(.dateTime.month(.abbreviated).day())
                              : date.formatted(.dateTime.year()))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Release date")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Play") { play(release) }
            Button("Open on Bandcamp") { NSWorkspace.shared.open(release.url) }
        }
    }

    private func play(_ release: NewRelease) {
        let artist = ArtistStore.shared.artists.first { $0.url.host == release.site.host }
            ?? Artist(url: release.site, name: release.artist)
        player.playAlbum(at: release.url, by: artist, keepNewReleases: true)
    }

    private func add() {
        let text = input
        add(text)
    }

    private func add(_ text: String) {
        adding = true
        message = nil
        Task {
            defer { adding = false }
            if let problem = await store.add(text) {
                message = problem
            } else {
                input = ""
            }
        }
    }
}

private extension View {
    func chip(selected: Bool) -> some View {
        font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
    }
}
