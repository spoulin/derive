import Foundation

struct Artist: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Root of the artist's Bandcamp site, e.g. https://sonnovdrone.bandcamp.com
    var url: URL
    var name: String
    var enabled = true
}

/// The artists the player picks from, saved in UserDefaults.
@MainActor
final class ArtistStore: ObservableObject {
    static let shared = ArtistStore()

    @Published var artists: [Artist] { didSet { save() } }

    private static let key = "artists"
    static let defaultArtists = [
        Artist(url: URL(string: "https://sonnovdrone.bandcamp.com")!, name: "Sonnov")
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Artist].self, from: data) {
            artists = saved
        } else {
            artists = Self.defaultArtists
        }
    }

    var enabled: [Artist] { artists.filter(\.enabled) }

    /// Checks the site on Bandcamp, then adds it. Throws when it has no playable releases.
    func add(_ input: String) async throws {
        guard let url = Self.siteURL(from: input) else { throw AddError.invalidURL }
        guard !artists.contains(where: { $0.url.host == url.host }) else { throw AddError.duplicate }
        let site = try await Bandcamp.site(at: url)
        artists.append(Artist(url: url, name: site.name))
    }

    func remove(_ artist: Artist) {
        artists.removeAll { $0.id == artist.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(artists) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Accepts "name.bandcamp.com", a full URL, or any page of the site, and keeps only its root.
    static func siteURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let parsed = URL(string: text), let host = parsed.host?.lowercased(),
              host.contains(".") else { return nil }
        return URL(string: "https://\(host)")
    }

    enum AddError: LocalizedError {
        case invalidURL, duplicate
        var errorDescription: String? {
            switch self {
            case .invalidURL: "That doesn't look like a web address."
            case .duplicate: "This artist is already in the list."
            }
        }
    }
}
