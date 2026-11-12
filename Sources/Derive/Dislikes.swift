import Foundation

/// A track the user gave a thumbs down. Kept with its names so the list can be shown and undone.
struct DislikedTrack: Codable, Identifiable, Equatable {
    /// Bandcamp's track ID, which stays the same (the audio links expire).
    let id: Int
    let title: String
    let album: String
    let artist: String
    let albumURL: URL
}

/// Tracks never to play again, saved in UserDefaults.
@MainActor
final class DislikeStore: ObservableObject {
    static let shared = DislikeStore()

    @Published private(set) var tracks: [DislikedTrack] { didSet { save() } }
    private var ids: Set<Int>

    private static let key = "dislikedTracks"

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([DislikedTrack].self, from: $0) } ?? []
        tracks = saved
        ids = Set(saved.map(\.id))
    }

    func contains(_ trackID: Int) -> Bool { ids.contains(trackID) }

    func add(_ track: DislikedTrack) {
        guard ids.insert(track.id).inserted else { return }
        tracks.insert(track, at: 0)
    }

    func remove(_ track: DislikedTrack) {
        ids.remove(track.id)
        tracks.removeAll { $0.id == track.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
