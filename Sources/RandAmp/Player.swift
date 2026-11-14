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
            guard radio != oldValue else { return }
            Toast.shared.show(radio ? "Radio on: a new random album and track after each track"
                                    : "Radio off: the album plays to the end",
                              symbol: radio ? "dot.radiowaves.left.and.right" : "square.stack")
        }
    }
    nonisolated static let radioKey = "radioMode"

    /// Favorites: each track is picked at random among the tracks given a thumbs up.
    @Published var favoritesOnly = UserDefaults.standard.bool(forKey: "favoritesOnly") {
        didSet {
            UserDefaults.standard.set(favoritesOnly, forKey: "favoritesOnly")
            upcoming = nil
            // Paused: Play then starts from the new source rather than resuming.
            if !isPlaying, album != nil { pendingSwitch = true }
            guard favoritesOnly != oldValue else { return }
            if favoritesOnly { guest.leave(); fansMix = false; newReleases = false }
            if favoritesOnly, likes.tracks.isEmpty {
                favoritesOnly = false
                Toast.shared.show("No thumbs up yet: give tracks a thumbs up to play your favorites",
                                  symbol: "hand.thumbsup")
                return
            }
            Toast.shared.show(favoritesOnly ? "Favorites on: random tracks from your thumbs up only"
                                            : "Favorites off: random tracks from all your artists",
                              symbol: favoritesOnly ? "heart.fill" : "heart")
        }
    }

    /// Fans mix: each album comes from the collection of a fan you follow, picked at random.
    @Published var fansMix = UserDefaults.standard.bool(forKey: "fansMix") {
        didSet {
            UserDefaults.standard.set(fansMix, forKey: "fansMix")
            upcoming = nil
            // Paused: Play then starts from the new source rather than resuming.
            if !isPlaying, album != nil { pendingSwitch = true }
            if !fansMix { mixFan = nil }
            guard fansMix != oldValue else { return }
            if fansMix { guest.leave(announce: false); favoritesOnly = false; newReleases = false }
            if fansMix, FollowedFanStore.shared.fans.isEmpty {
                fansMix = false
                Toast.shared.show("You follow no fans yet: follow some from Community or a fan's collection",
                                  symbol: "person.2")
                return
            }
            Toast.shared.show(fansMix ? "Fans mix on: albums from the collections of the fans you follow"
                                      : "Fans mix off: back to your artists",
                              symbol: fansMix ? "person.2.fill" : "house")
        }
    }
    /// In the fans mix, the fan whose collection the album playing comes from.
    @Published private(set) var mixFan: FollowedFan?

    /// New Releases: each album is one of the latest added to Bandcamp, in the styles chosen.
    @Published var newReleases = UserDefaults.standard.bool(forKey: "newReleases") {
        didSet {
            UserDefaults.standard.set(newReleases, forKey: "newReleases")
            upcoming = nil
            // Paused: Play then starts from the new source rather than resuming.
            if !isPlaying, album != nil { pendingSwitch = true }
            guard newReleases != oldValue else { return }
            if newReleases { guest.leave(announce: false); favoritesOnly = false; fansMix = false }
            let styles = NewReleaseStore.shared.tags
            Toast.shared.show(newReleases
                              ? "New releases on: just added to Bandcamp" + (styles.isEmpty ? "" : ", \(styles.joined(separator: " + "))")
                              : "New releases off: back to your artists",
                              symbol: newReleases ? "sparkles" : "house")
        }
    }

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
        } else if pendingSwitch {
            // What plays changed while paused: Play starts from the new source.
            pendingSwitch = false
            Task { await startRandomAlbum() }
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

    /// What plays changed (Library or New Releases, × in the footer…): the music stops, and nothing
    /// starts by itself. Play then picks from the new source.
    private var pendingSwitch = false
    func switchSource() {
        if album != nil { stop() }
    }

    /// Library or New Releases, from the panel's selector, the menus, the Dock or a link: the
    /// music stops, and Play then picks from the other side.
    func setNewReleases(_ on: Bool) {
        guard on != newReleases else { return }
        newReleases = on
        switchSource()
    }

    /// Plays a random album of this artist, from its first track, and turns radio mode off.
    /// Works even when the artist is turned off.
    func playArtist(_ artist: Artist) {
        guest.leave()
        radio = false
        favoritesOnly = false
        fansMix = false
        newReleases = false
        player.pause()
        Task { await startRandomAlbum(only: artist) }
    }

    /// Plays one release from its first track (skipping thumbs down), and turns radio mode off so
    /// the whole release plays. Used by the Community tab's new releases, and by the New tab, which
    /// keeps the New Releases mode on: another new release follows.
    func playAlbum(at url: URL, by artist: Artist, keepNewReleases: Bool = false) {
        guest.leave()
        radio = false
        favoritesOnly = false
        fansMix = false
        if !keepNewReleases { newReleases = false }
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
        playTrack(id: track.id, title: track.title, artist: track.artist, albumURL: track.albumURL)
    }

    /// Plays a track of the history again. Afterwards, playback goes on as usual.
    func playAgain(_ track: PlayedTrack) {
        playTrack(id: track.trackID, title: track.title, artist: track.artist, albumURL: track.albumURL)
    }

    private func playTrack(id: Int, title: String, artist name: String, albumURL: URL) {
        player.pause()
        Task {
            guard !isLoading else { return }
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            guard let album = try? await Bandcamp.album(at: albumURL),
                  let index = album.tracks.firstIndex(where: { $0.id == id }),
                  let site = ArtistStore.siteURL(from: albumURL.absoluteString)
            else {
                errorMessage = "Couldn't play \(title)"
                return
            }
            // The listed artist when there is one, so the artist tabs follow it.
            let artist = ArtistStore.shared.artists.first { $0.url.host == site.host }
                ?? Artist(url: site, name: name)
            start(Pick(album: album, artist: artist, index: index))
        }
    }

    /// Thumbs down: never plays the current track again, and skips it now.
    func dislikeCurrent() {
        guard let album, index < album.tracks.count else { return }
        let track = album.tracks[index]
        guard track.id != 0 else { return }
        dislikes.add(DislikedTrack(id: track.id, title: track.title, album: album.title,
                                   artist: artist ?? "", albumURL: album.pageURL, artURL: album.artURL))
        likes.remove(track.id)
        Toast.shared.show("Thumbs down: “\(track.title)” won't play again. Undo it in the Thumbs down tab.",
                          symbol: "hand.thumbsdown")
        advance()
    }

    /// Bandcamp's ID of the track playing, for the thumbs up button.
    var currentTrackID: Int? {
        guard let album, index < album.tracks.count, album.tracks[index].id != 0 else { return nil }
        return album.tracks[index].id
    }

    /// Thumbs up on the track playing, or off again when it has one. Playback goes on.
    func likeCurrent() {
        guard let album, index < album.tracks.count else { return }
        let track = album.tracks[index]
        guard track.id != 0 else { return }
        if likes.contains(track.id) {
            likes.remove(track.id)
            Toast.shared.show("Thumbs up removed from “\(track.title)”", symbol: "hand.thumbsup")
        } else {
            likes.add(LikedTrack(id: track.id, title: track.title, album: album.title, artist: artist ?? "",
                                 albumURL: album.pageURL, artURL: album.artURL, likedAt: Date()))
            Toast.shared.show("Thumbs up: “\(track.title)” is in your Liked tab", symbol: "hand.thumbsup.fill")
        }
    }

    /// Plays a liked track again. Afterwards, playback goes on as usual.
    func playLiked(_ track: LikedTrack) {
        playTrack(id: track.id, title: track.title, artist: track.artist, albumURL: track.albumURL)
    }

    private var dislikes: DislikeStore { .shared }
    private var likes: LikeStore { .shared }

    /// - Parameters:
    ///   - chosen: picks from this artist only.
    ///   - excluded: an album not to pick again (the one that just ended). When the chosen
    ///     artist has no other album, any artist is picked instead.
    private func startRandomAlbum(only chosen: Artist? = nil, excluding excluded: URL? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        if chosen == nil, guest.isActive {
            if let pick = await randomGuestPick(excluding: excluded) { return start(pick) }
            errorMessage = "Couldn't play from \(guest.name)'s collection"
            return
        }
        if chosen == nil, newReleases {
            if let pick = await randomNewRelease(excluding: excluded) { return start(pick) }
            errorMessage = NewReleaseStore.shared.error ?? "No new releases to play in these styles"
            return
        }
        if chosen == nil, fansMix {
            if let pick = await randomFanMixPick(excluding: excluded) { return start(pick) }
            errorMessage = "Couldn't play from the collections of the fans you follow"
            return
        }
        if chosen == nil, favoritesOnly {
            if let pick = await randomFavorite() { return start(pick) }
            errorMessage = likes.tracks.isEmpty ? "No thumbs up yet" : "Bandcamp isn't answering right now. Try again in a little while."
            return
        }
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
            errorMessage = "Bandcamp isn't answering right now. Try again in a little while."
            return
        }
        start(pick)
    }

    private func start(_ pick: Pick) {
        upcoming = nil
        pendingSwitch = false
        album = pick.album
        artist = pick.artist.name
        currentArtist = pick.artist
        index = pick.index
        playCurrent()
        if radio, !favoritesOnly, !guest.isActive, !fansMix, !newReleases { prefetch() }
    }

    private var guest: GuestCollection { .shared }

    /// Shuffles in a fan's public collection instead of your artists, until you leave it.
    func shuffleCollection(of username: String, avatar: URL? = nil) {
        favoritesOnly = false
        fansMix = false
        newReleases = false
        Task {
            guard await guest.enter(username, avatar: avatar) else { return }
            player.pause()
            await startRandomAlbum()
        }
    }

    /// Back to your own artists: a new random pick right away while playing, at the next Play
    /// otherwise.
    func leaveCollection() {
        guard guest.isActive else { return }
        guest.leave()
        switchSource()
    }

    /// Shuffles in the collection of a fan you follow, picked at random (not the one playing).
    func shuffleRandomFan() {
        guard let fan = FollowedFanStore.shared.randomFan(excluding: guest.username) else {
            Toast.shared.show("You follow no fans yet", symbol: "person.2")
            return
        }
        shuffleCollection(of: fan.username, avatar: fan.avatarURL)
    }

    /// The fans mix: a fan you follow at random, then a release of their collection.
    private func randomFanMixPick(excluding excluded: URL? = nil) async -> Pick? {
        let store = FollowedFanStore.shared
        // A few tries: a collection may be private, empty, or not answer.
        for fan in store.fans.shuffled().prefix(3) {
            let items = await store.collection(of: fan)
            if let pick = await randomCollectionPick(from: items, excluding: excluded) {
                mixFan = fan
                return pick
            }
        }
        return nil
    }

    /// One of the latest releases added to Bandcamp in the styles chosen, not heard lately when
    /// there is one: a random track of it in radio mode, its first track otherwise.
    private func randomNewRelease(excluding excluded: URL? = nil) async -> Pick? {
        let store = NewReleaseStore.shared
        await store.load()
        let items = store.releases.map { CollectionItem(title: $0.title, artist: $0.artist, url: $0.url) }
        return await randomCollectionPick(from: items, excluding: excluded)
    }

    private func randomGuestPick(excluding excluded: URL? = nil) async -> Pick? {
        await randomCollectionPick(from: guest.items, excluding: excluded)
    }

    /// A random release of a fan's collection: a random track of it in radio mode, its first
    /// track otherwise. Avoiding repeats, one not heard lately when there is one.
    private func randomCollectionPick(from collection: [CollectionItem], excluding excluded: URL? = nil) async -> Pick? {
        let recentAlbums = history.recentAlbums
        let recentTracks = history.recentTrackIDs
        let items = collection.filter { $0.url != excluded }
        let fresh = items.filter { !recentAlbums.contains($0.url) }
        // A few tries: a release may have no audio, or be gone.
        for item in (fresh.isEmpty ? items : fresh).shuffled().prefix(4) {
            guard let album = try? await Bandcamp.album(at: item.url) else { continue }
            let allowed = album.tracks.indices.filter { !dislikes.contains(album.tracks[$0].id) }
            guard !allowed.isEmpty, let site = ArtistStore.siteURL(from: item.url.absoluteString) else { continue }
            let unheard = allowed.filter { !recentTracks.contains(album.tracks[$0].id) }
            let artist = ArtistStore.shared.artists.first { $0.url.host == site.host }
                ?? Artist(url: site, name: item.artist.isEmpty ? (site.host ?? "") : item.artist)
            let index = radio ? (unheard.isEmpty ? allowed : unheard).randomElement()! : allowed[0]
            return Pick(album: album, artist: artist, index: index)
        }
        return nil
    }

    /// A random track among the thumbs up, other than the one playing; avoiding repeats, one not
    /// heard lately when there is one.
    private func randomFavorite() async -> Pick? {
        let current = currentTrackID
        var candidates = likes.tracks.filter { $0.id != current && !dislikes.contains($0.id) }
        if candidates.isEmpty { candidates = likes.tracks }
        let recent = history.recentTrackIDs
        let fresh = candidates.filter { !recent.contains($0.id) }
        // A few tries: a track may have been taken off Bandcamp.
        for liked in (fresh.isEmpty ? candidates : fresh).shuffled().prefix(4) {
            guard let album = try? await Bandcamp.album(at: liked.albumURL),
                  let index = album.tracks.firstIndex(where: { $0.id == liked.id }),
                  let site = ArtistStore.siteURL(from: liked.albumURL.absoluteString) else { continue }
            let artist = ArtistStore.shared.artists.first { $0.url.host == site.host }
                ?? Artist(url: site, name: liked.artist)
            return Pick(album: album, artist: artist, index: index)
        }
        return nil
    }

    private func randomPick(from artists: [Artist], excluding excluded: URL? = nil,
                            skipMarked: Bool = true) async -> Pick? {
        // With Avoid repeats on, first look past what played lately; when nothing else is left,
        // play something again rather than nothing.
        var found = await randomAlbum(from: artists, excluding: excluded, skipMarked: skipMarked,
                                      avoidRecent: history.avoidRepeats)
        if found == nil, history.avoidRepeats {
            found = await randomAlbum(from: artists, excluding: excluded, skipMarked: skipMarked,
                                      avoidRecent: false)
        }
        guard let (album, artist) = found else { return nil }
        let allowed = album.tracks.indices.filter { !dislikes.contains(album.tracks[$0].id) }
        guard let first = allowed.first else { return nil }
        guard radio else { return Pick(album: album, artist: artist, index: first) }
        let recent = history.recentTrackIDs
        let fresh = allowed.filter { !recent.contains(album.tracks[$0].id) }
        return Pick(album: album, artist: artist, index: (fresh.isEmpty ? allowed : fresh).randomElement()!)
    }

    private var history: HistoryStore { .shared }

    /// Picks the next radio track and downloads its cover in the background.
    private func prefetch() {
        prefetchTask?.cancel()
        let artists = ArtistStore.shared.enabled
        guard !artists.isEmpty else { return }
        prefetchTask = Task {
            guard let pick = await randomPick(from: artists), !Task.isCancelled, radio else { return }
            upcoming = pick
            if let url = pick.album.artURL,
               let (data, _) = try? await Bandcamp.session.data(from: url),
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
                             skipMarked: Bool = true, avoidRecent: Bool = false) async -> (Album, Artist)? {
        let candidates = skipMarked ? artists.filter { !playability.shouldSkip($0.url) } : artists
        var order = candidates.shuffled()
        // Avoid repeats: the artist just heard goes last, so another one plays when there is one.
        if avoidRecent, order.count > 1, let last = history.lastSite,
           let position = order.firstIndex(where: { $0.url == last }) {
            order.append(order.remove(at: position))
        }
        let recentTracks = avoidRecent ? history.recentTrackIDs : []
        let recentAlbums = avoidRecent ? history.recentAlbums : []
        bandcampDown = false
        for artist in order.prefix(3) {
            if bandcampDown { return nil }
            guard let site = await site(for: artist) else { continue }
            let releases = site.releases.filter { $0 != excluded }
            var empty = 0
            // A few releases may have no streamable tracks; try a handful of picks.
            for release in releases.shuffled().prefix(5) {
                guard let album = try? await Bandcamp.album(at: release) else { continue }
                if album.tracks.isEmpty { empty += 1; continue }
                playability.clear(artist.url)
                // Needs at least one track that wasn't disliked; avoiding repeats, one not heard
                // lately in radio, or an album not heard lately otherwise.
                let playable = album.tracks.filter { !dislikes.contains($0.id) }
                let fresh = radio ? playable.contains { !recentTracks.contains($0.id) }
                                  : !recentAlbums.contains(album.pageURL)
                if !playable.isEmpty, fresh {
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

    /// Set when a site couldn't be read for reasons that aren't the artist's; a pick then stops.
    private var bandcampDown = false

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
            // Network trouble, or Bandcamp having trouble: nothing is learned about the artist,
            // and the pick stops instead of trying more.
            bandcampDown = true
            return nil
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
        history.add(PlayedTrack(trackID: track.id, title: track.title, album: album.title,
                                artist: artist ?? "", albumURL: album.pageURL, artURL: album.artURL,
                                site: currentArtist?.url, playedAt: Date()))
        player.replaceCurrentItem(with: AVPlayerItem(url: track.url))
        player.play()
        isPlaying = true
    }

    private func advance() {
        guard let album else { return }
        // A new random pick after each track: radio (in your artists or someone's collection),
        // and favorites. Otherwise the album goes on.
        if radio || favoritesOnly {
            player.pause()
            Task { await startRandomAlbum() }
            return
        }
        index += 1
        while index < album.tracks.count, dislikes.contains(album.tracks[index].id) { index += 1 }
        if index < album.tracks.count {
            playCurrent()
        } else if guest.isActive || fansMix || newReleases {
            // Album finished, in someone's collection, the fans mix or the new releases: another
            // album from there.
            Task { await startRandomAlbum(excluding: album.pageURL) }
        } else if let currentArtist {
            // Album finished: another random album by the same artist.
            Task { await startRandomAlbum(only: currentArtist, excluding: album.pageURL) }
        } else {
            stop()
        }
    }

    /// Stops and unloads the album: nothing playing, an empty cover. Play then picks a new one.
    func stop() {
        player.pause()
        album = nil
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        nowPlaying = nil
        artist = nil
        artURL = nil
        pageURL = nil
        clock.elapsed = 0
        clock.duration = 0
        upcoming = nil
        pendingSwitch = false
        showCover(nil)
    }

    private func loadCover(_ url: URL?) {
        guard let url else { return showCover(nil) }
        if let preloaded = preloadedCover, preloaded.url == url {
            preloadedCover = nil
            return showCover(preloaded.image)
        }
        Task {
            guard let (data, _) = try? await Bandcamp.session.data(from: url),
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
