import AVFoundation
import Foundation

@MainActor
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var nowPlaying: String?
    @Published private(set) var artist: String?
    @Published private(set) var artURL: URL?
    @Published private(set) var pageURL: URL?
    @Published private(set) var errorMessage: String?

    static let shared = Player()

    private let player = AVPlayer()
    private var album: Album?
    private var index = 0
    private var endObserver: NSObjectProtocol?
    /// Release lists per artist site, read once per launch.
    private var sites: [URL: Site] = [:]

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

    private func startRandomAlbum() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let artists = ArtistStore.shared.enabled
        guard !artists.isEmpty else {
            errorMessage = "No artist is turned on"
            return
        }
        if let (picked, from) = await randomAlbum(from: artists) {
            album = picked
            artist = from.name
            index = 0
            playCurrent()
        } else {
            errorMessage = "Couldn't reach Bandcamp"
        }
    }

    /// Every artist has the same chance, whatever the size of their catalog.
    /// When the picked artist fails, falls back to another one.
    private func randomAlbum(from artists: [Artist]) async -> (Album, Artist)? {
        for artist in artists.shuffled().prefix(3) {
            guard let site = await site(for: artist) else { continue }
            // A few releases may have no streamable tracks; try a handful of picks.
            for release in site.releases.shuffled().prefix(5) {
                if let album = try? await Bandcamp.album(at: release), !album.tracks.isEmpty {
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
        artURL = album.artURL
        pageURL = album.pageURL
        nowPlaying = "\(album.title) — \(index + 1). \(track.title)"
        player.replaceCurrentItem(with: AVPlayerItem(url: track.url))
        player.play()
        isPlaying = true
    }

    private func advance() {
        guard let album else { return }
        index += 1
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
        }
    }
}
