import AppKit
import AVFoundation

@MainActor
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false { didSet { updateNowPlaying() } }
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
    /// Where the track playing is, for the timeline.
    let clock = PlaybackClock()
    private var timeObserver: Any?
    private var album: Album?
    private var index = 0
    private var endObserver: NSObjectProtocol?
    private var artURL: URL?
    /// The artist of the album playing, for picking their next album when it ends.
    @Published private(set) var currentArtist: Artist?
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
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
    }

    private func tick(_ time: CMTime) {
        guard !clock.isSeeking, time.seconds.isFinite else { return }
        clock.elapsed = time.seconds
        // Bandcamp's duration first; the file's own once known, for the rare track without one.
        if clock.duration <= 0, let item = player.currentItem, item.duration.seconds.isFinite {
            clock.duration = item.duration.seconds
        }
    }

    private var scanTimer: Timer?

    /// While a media key is held: moves 4 seconds every quarter second, forward (1) or back (-1).
    func startScanning(_ direction: Double) {
        stopScanning()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seek(to: self.clock.elapsed + direction * 4)
            }
        }
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    /// The previous key: back to the start of the track (a random player has no previous track).
    func restartTrack() {
        seek(to: 0)
    }

    /// Moves in the track playing, in seconds from its start.
    func seek(to seconds: Double) {
        guard player.currentItem != nil, clock.duration > 0 else { return }
        let target = min(max(seconds, 0), clock.duration - 0.5)
        clock.elapsed = target
        clock.isSeeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.clock.isSeeking = false
                self?.updateNowPlaying()
            }
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

    /// Plays a random album of this artist, from its first track, and turns radio mode off.
    /// Works even when the artist is turned off.
    func playArtist(_ artist: Artist) {
        radio = false
        player.pause()
        Task { await startRandomAlbum(only: artist) }
    }

    /// Plays one release from its first track (skipping thumbs down), and turns radio mode off so
    /// the whole release plays. Used by the Community tab's new releases.
    func playAlbum(at url: URL, by artist: Artist) {
        radio = false
        player.pause()
        Task {
            guard !isLoading else { return }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            guard let album = try? await Bandcamp.album(at: url),
                  let first = album.tracks.indices.first(where: { !dislikes.contains(album.tracks[$0].id) })
            else {
                errorMessage = "Couldn't play this release"
                return
            }
            start(Pick(album: album, artist: artist, index: first))
        }
    }

    /// Plays one track given a thumbs down, to check it before undoing it.
    /// Afterwards, playback goes on as usual (the rest of its album, or radio).
    func playDisliked(_ track: DislikedTrack) {
        player.pause()
        Task {
            guard !isLoading else { return }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            guard let album = try? await Bandcamp.album(at: track.albumURL),
                  let index = album.tracks.firstIndex(where: { $0.id == track.id }),
                  let site = ArtistStore.siteURL(from: track.albumURL.absoluteString)
            else {
                errorMessage = "Couldn't play \(track.title)"
                return
            }
            start(Pick(album: album, artist: Artist(url: site, name: track.artist), index: index))
        }
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

    /// - Parameters:
    ///   - chosen: picks from this artist only.
    ///   - excluded: an album not to pick again (the one that just ended). When the chosen
    ///     artist has no other album, any artist is picked instead.
    private func startRandomAlbum(only chosen: Artist? = nil, excluding excluded: URL? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if let chosen {
            if let pick = await randomPick(from: [chosen], excluding: excluded, skipMarked: false) {
                return start(pick)
            }
            guard excluded != nil else {
                let reason = playability.reason(for: chosen.url).map { ": \($0.label)" } ?? ""
                errorMessage = "Couldn't play \(chosen.name)\(reason)"
                return
            }
        }
        guard !ArtistStore.shared.artists.isEmpty else {
            errorMessage = "Add an artist to start"
            PlayerWindow.showArtists()
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
        start(pick)
    }

    private func start(_ pick: Pick) {
        upcoming = nil
        album = pick.album
        artist = pick.artist.name
        currentArtist = pick.artist
        index = pick.index
        playCurrent()
        if radio { prefetch() }
    }

    private func randomPick(from artists: [Artist], excluding excluded: URL? = nil,
                            skipMarked: Bool = true) async -> Pick? {
        guard let (album, artist) = await randomAlbum(from: artists, excluding: excluded,
                                                      skipMarked: skipMarked) else { return nil }
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
    /// - Parameter skipMarked: leaves out artists found unplayable in the last week. False when
    ///   the user asked for this artist: it is tried anyway.
    private func randomAlbum(from artists: [Artist], excluding excluded: URL? = nil,
                             skipMarked: Bool = true) async -> (Album, Artist)? {
        let candidates = skipMarked ? artists.filter { !playability.shouldSkip($0.url) } : artists
        for artist in candidates.shuffled().prefix(3) {
            guard let site = await site(for: artist) else { continue }
            let releases = site.releases.filter { $0 != excluded }
            var empty = 0
            // A few releases may have no streamable tracks; try a handful of picks.
            for release in releases.shuffled().prefix(5) {
                guard let album = try? await Bandcamp.album(at: release) else { continue }
                if album.tracks.isEmpty { empty += 1; continue }
                playability.clear(artist.url)
                // Needs at least one track that wasn't disliked.
                if album.tracks.contains(where: { !dislikes.contains($0.id) }) {
                    return (album, artist)
                }
            }
            // Only when every release was looked at and none has audio.
            if excluded == nil, !releases.isEmpty, empty == releases.count {
                playability.mark(artist.url, .noAudio)
            }
        }
        return nil
    }

    private var playability: PlayabilityStore { .shared }

    private func site(for artist: Artist) async -> Site? {
        if let site = sites[artist.url] { return site }
        do {
            let site = try await Bandcamp.site(at: artist.url)
            sites[artist.url] = site
            return site
        } catch let error as URLError where error.code == .httpTooManyRedirects {
            playability.mark(artist.url, .unreachable)
            return nil
        } catch BandcampError.noAlbums {
            playability.mark(artist.url, .noReleases)
            return nil
        } catch {
            return nil // Network trouble: nothing is learned about the artist.
        }
    }

    /// Progress of "Check which artists can play", nil when not running.
    @Published private(set) var checkProgress: (done: Int, total: Int)?

    /// Looks at every artist once, one at a time to go easy on Bandcamp, and marks or clears
    /// them. Reads the site, then up to three releases until one has audio.
    func checkPlayability(of artists: [Artist]) async {
        guard checkProgress == nil else { return }
        checkProgress = (0, artists.count)
        defer { checkProgress = nil }
        for (done, artist) in artists.enumerated() {
            checkProgress = (done, artists.count)
            guard let site = await site(for: artist) else { continue }
            var empty = 0
            var playable = false
            for release in site.releases.shuffled().prefix(3) {
                guard let album = try? await Bandcamp.album(at: release) else { continue }
                if album.tracks.isEmpty { empty += 1 } else { playable = true; break }
            }
            if playable {
                playability.clear(artist.url)
            } else if empty == site.releases.count {
                playability.mark(artist.url, .noAudio)
            }
        }
    }

    /// Keeps Control Center and the media keys in step with what plays.
    private func updateNowPlaying() {
        guard let album, index < album.tracks.count else { return NowPlaying.update(nil) }
        let track = album.tracks[index]
        let elapsed = player.currentTime().seconds
        NowPlaying.update(NowPlaying.Info(
            title: track.title, album: album.title, artist: artist ?? "",
            duration: track.duration, elapsed: elapsed.isFinite ? elapsed : 0,
            isPlaying: isPlaying, cover: cover))
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
        clock.elapsed = 0
        clock.duration = track.duration
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
        } else if let currentArtist {
            // Album finished: another random album by the same artist.
            Task { await startRandomAlbum(only: currentArtist, excluding: album.pageURL) }
        } else {
            self.album = nil
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            nowPlaying = nil
            artist = nil
            artURL = nil
            pageURL = nil
            clock.elapsed = 0
            clock.duration = 0
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
        defer { updateNowPlaying() }
        cover = image
        tint = image.map(CoverColor.tint) ?? CoverColor.neutral
        coverID += 1
    }
}

/// Elapsed time and duration of the track playing. Apart from Player, so its four updates a
/// second redraw only the timeline.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    /// While a seek runs, the time observer would move the bar back to the old position.
    var isSeeking = false
}
