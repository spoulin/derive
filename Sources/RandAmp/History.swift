import Foundation

/// A track that played, for the History tab and for avoiding repeats.
struct PlayedTrack: Codable, Identifiable, Equatable {
    /// Unique per play: the same track can be in the history more than once.
    var id = UUID()
    /// Bandcamp's track ID.
    let trackID: Int
    let title: String
    let album: String
    let artist: String
    let albumURL: URL
    /// The album cover, for the thumbnail.
    var artURL: URL? = nil
    /// The artist's site, to avoid the same artist twice in a row.
    let site: URL?
    let playedAt: Date
}

/// A small version of a Bandcamp cover (100 pixels): "a123_10.jpg" becomes "a123_3.jpg".
func coverThumbnail(_ url: URL?) -> URL? {
    guard let url else { return nil }
    return URL(string: url.absoluteString.replacingOccurrences(
        of: #"_\d+\.jpg$"#, with: "_3.jpg", options: .regularExpression))
}

/// The last tracks played, newest first, saved in UserDefaults.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    /// How many plays are kept.
    static let limit = 300
    /// How long a track or an album counts as recent, when repeats are avoided.
    static let recent: TimeInterval = 24 * 3600

    @Published private(set) var tracks: [PlayedTrack] { didSet { save() } }
    /// Off by default: the random pick ignores the history unless this is on.
    @Published var avoidRepeats: Bool {
        didSet { UserDefaults.standard.set(avoidRepeats, forKey: Self.avoidKey) }
    }

    private static let key = "playHistory"
    private static let avoidKey = "avoidRepeats"

    init() {
        tracks = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([PlayedTrack].self, from: $0) } ?? []
        avoidRepeats = UserDefaults.standard.bool(forKey: Self.avoidKey)
    }

    func add(_ track: PlayedTrack) {
        // The same track again right away (a restart) isn't a new play.
        if tracks.first?.trackID == track.trackID, track.trackID != 0 { return }
        tracks.insert(track, at: 0)
        if tracks.count > Self.limit { tracks.removeLast(tracks.count - Self.limit) }
    }

    func clear() { tracks = [] }

    /// Plays since midnight, for the tab's number.
    var playedToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return tracks.prefix { $0.playedAt >= start }.count
    }

    private var recentTracks: ArraySlice<PlayedTrack> {
        let since = Date().addingTimeInterval(-Self.recent)
        return tracks.prefix { $0.playedAt >= since }
    }

    /// Tracks played lately; empty when repeats aren't avoided.
    var recentTrackIDs: Set<Int> {
        avoidRepeats ? Set(recentTracks.map(\.trackID)) : []
    }

    /// Albums played lately; empty when repeats aren't avoided.
    var recentAlbums: Set<URL> {
        avoidRepeats ? Set(recentTracks.map(\.albumURL)) : []
    }

    /// The artist of the last track, to avoid them twice in a row; nil when repeats aren't avoided.
    var lastSite: URL? {
        avoidRepeats ? tracks.first?.site : nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
