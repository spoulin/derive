import AppKit
import AVFoundation

@MainActor
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var nowPlaying: String?
    @Published private(set) var artist: String?
    /// The cover on screen. Replaced only once the next one has downloaded, so views can crossfade.
    @Published private(set) var cover: NSImage?
    /// Changes with every new cover, to drive the crossfade.
    @Published private(set) var coverID = 0
    /// Dark tint taken from the cover, for the player window's background.
    @Published private(set) var tint = CoverColor.neutral
    @Published private(set) var pageURL: URL?
    @Published private(set) var errorMessage: String?
    /// Radio: after each track, a new random album and a random track from it.
    /// Off: the random album plays from its first track to its last.
    @Published var radio = UserDefaults.standard.bool(forKey: Player.radioKey) {
        didSet {
            UserDefaults.standard.set(radio, forKey: Self.radioKey)
            upcoming = nil
            if radio, album != nil { prefetch() }
        }
    }
    nonisolated static let radioKey = "radioMode"

    static let shared = Player()

    private let player = AVPlayer()
    private var album: Album?
    private var index = 0
    private var endObserver: NSObjectProtocol?
    private var artURL: URL?
    /// Release lists per artist site, read once per launch.
    private var sites: [URL: Site] = [:]

    private struct Pick {
        let album: Album
        let artist: Artist
        let index: Int
    }
    /// Radio: the next track, picked while the current one plays so the change has no gap.
    private var upcoming: Pick?
    private var prefetchTask: Task<Void, Never>?
    private var preloadedCover: (url: URL, image: NSImage)?

    init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    func toggle() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else if album != nil, player.currentItem != nil {
            player.play()
            isPlaying = true
        } else {
            Task { await startRandomAlbum() }
        }
    }

    func play() { if !isPlaying { toggle() } }
    func pause() { if isPlaying { toggle() } }

    func nextTrack() {
        guard album != nil else { return }
        advance()
    }

    func nextAlbum() {
        player.pause()
        Task { await startRandomAlbum() }
    }

    /// Thumbs down: never plays the current track again, and skips it now.
    func dislikeCurrent() {
        guard let album, index < album.tracks.count else { return }
        let track = album.tracks[index]
        guard track.id != 0 else { return }
        dislikes.add(DislikedTrack(id: track.id, title: track.title, album: album.title,
                                   artist: artist ?? "", albumURL: album.pageURL))
        advance()
    }

    private var dislikes: DislikeStore { .shared }

    private func startRandomAlbum() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard !ArtistStore.shared.artists.isEmpty else {
            errorMessage = "Add an artist to start"
            ArtistsWindow.show()
            return
        }
        let artists = ArtistStore.shared.enabled
        guard !artists.isEmpty else {
            errorMessage = "No artist is turned on"
            return
        }
        // Skip a prefetched pick whose artist was turned off or removed, or whose track was disliked.
        let ready = upcoming.flatMap { pick in
            artists.contains { $0.id == pick.artist.id }
                && !dislikes.contains(pick.album.tracks[pick.index].id) ? pick : nil
        }
        upcoming = nil
        var next = ready
        if next == nil { next = await randomPick(from: artists) }
        guard let pick = next else {
            errorMessage = "Couldn't reach Bandcamp"
            return
        }
        album = pick.album
        artist = pick.artist.name
        index = pick.index
        playCurrent()
        if radio { prefetch() }
    }

    private func randomPick(from artists: [Artist]) async -> Pick? {
        guard let (album, artist) = await randomAlbum(from: artists) else { return nil }
        let allowed = album.tracks.indices.filter { !dislikes.contains(album.tracks[$0].id) }
        guard let first = allowed.first else { return nil }
        return Pick(album: album, artist: artist, index: radio ? allowed.randomElement()! : first)
    }

    /// Picks the next radio track and downloads its cover in the background.
    private func prefetch() {
        prefetchTask?.cancel()
        let artists = ArtistStore.shared.enabled
        guard !artists.isEmpty else { return }
        prefetchTask = Task {
            guard let pick = await randomPick(from: artists), !Task.isCancelled, radio else { return }
            upcoming = pick
            if let url = pick.album.artURL,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = NSImage(data: data), !Task.isCancelled {
                preloadedCover = (url, image)
            }
        }
    }

    /// Every artist has the same chance, whatever the size of their catalog.
    /// When the picked artist fails, falls back to another one.
    private func randomAlbum(from artists: [Artist]) async -> (Album, Artist)? {
        for artist in artists.shuffled().prefix(3) {
            guard let site = await site(for: artist) else { continue }
            // A few releases may have no streamable tracks; try a handful of picks.
            for release in site.releases.shuffled().prefix(5) {
                // Needs at least one track that wasn't disliked.
                if let album = try? await Bandcamp.album(at: release),
                   album.tracks.contains(where: { !dislikes.contains($0.id) }) {
                    return (album, artist)
                }
            }
        }
        return nil
    }

    private func site(for artist: Artist) async -> Site? {
        if let site = sites[artist.url] { return site }
        let site = try? await Bandcamp.site(at: artist.url)
        sites[artist.url] = site
        return site
    }

    private func playCurrent() {
        guard let album, index < album.tracks.count else { return }
        let track = album.tracks[index]
        if album.artURL != artURL {
            artURL = album.artURL
            loadCover(album.artURL)
        }
        pageURL = album.pageURL
        nowPlaying = "\(album.title) — \(index + 1). \(track.title)"
        player.replaceCurrentItem(with: AVPlayerItem(url: track.url))
        player.play()
        isPlaying = true
    }

    private func advance() {
        guard let album else { return }
        if radio {
            player.pause()
            Task { await startRandomAlbum() }
            return
        }
        index += 1
        while index < album.tracks.count, dislikes.contains(album.tracks[index].id) { index += 1 }
        if index < album.tracks.count {
            playCurrent()
        } else {
            // Album finished: next press picks a new random album.
            self.album = nil
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            nowPlaying = nil
            artist = nil
            artURL = nil
            pageURL = nil
            showCover(nil)
        }
    }

    private func loadCover(_ url: URL?) {
        guard let url else { return showCover(nil) }
        if let preloaded = preloadedCover, preloaded.url == url {
            preloadedCover = nil
            return showCover(preloaded.image)
        }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  artURL == url // Another album started while this cover was downloading.
            else { return }
            showCover(image)
        }
    }

    private func showCover(_ image: NSImage?) {
        cover = image
        tint = image.map(CoverColor.tint) ?? CoverColor.neutral
        coverID += 1
    }
}
