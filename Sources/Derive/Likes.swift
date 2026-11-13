import Foundation

/// A track the user gave a thumbs up. Kept with its names and cover for the Liked tab.
struct LikedTrack: Codable, Identifiable, Equatable {
    /// Bandcamp's track ID.
    let id: Int
    let title: String
    let album: String
    let artist: String
    let albumURL: URL
    var artURL: URL? = nil
    let likedAt: Date
}

/// Tracks given a thumbs up, newest first, saved in UserDefaults.
@MainActor
final class LikeStore: ObservableObject {
    static let shared = LikeStore()

    @Published private(set) var tracks: [LikedTrack] { didSet { save() } }
    private var ids: Set<Int>

    private static let key = "likedTracks"

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([LikedTrack].self, from: $0) } ?? []
        tracks = saved
        ids = Set(saved.map(\.id))
    }

    func contains(_ trackID: Int) -> Bool { ids.contains(trackID) }

    func add(_ track: LikedTrack) {
        guard ids.insert(track.id).inserted else { return }
        tracks.insert(track, at: 0)
    }

    func remove(_ trackID: Int) {
        ids.remove(trackID)
        tracks.removeAll { $0.id == trackID }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
