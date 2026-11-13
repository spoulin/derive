import Foundation

struct Artist: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Root of the artist's Bandcamp site, e.g. https://artist.bandcamp.com
    var url: URL
    var name: String
    var enabled = true
    /// Set for artists that come from the linked Bandcamp profile; nil for artists added by hand.
    var bandID: Int?

    var isFollowed: Bool { bandID != nil }
}

/// The artists the player picks from, saved in UserDefaults.
@MainActor
final class ArtistStore: ObservableObject {
    static let shared = ArtistStore()

    @Published var artists: [Artist] { didSet { save() } }
    /// Username of the linked Bandcamp profile, whose followed artists are kept in sync.
    @Published private(set) var profile: String? {
        didSet { UserDefaults.standard.set(profile, forKey: Self.profileKey) }
    }
    @Published private(set) var isSyncing = false
    @Published private(set) var syncError: String?

    private static let key = "artists"
    private static let profileKey = "followingProfile"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Artist].self, from: data) {
            artists = saved
        } else {
            artists = []
        }
        profile = UserDefaults.standard.string(forKey: Self.profileKey)
    }

    // MARK: Linked Bandcamp profile

    /// Reads the profile's followed artists, then links it. Throws when the list can't be read.
    func link(_ input: String) async throws {
        guard let username = Following.username(from: input) else { throw FollowingError.invalidProfile }
        let bands = try await Following.bands(of: username)
        guard !bands.isEmpty else { throw FollowingError.notFound }
        profile = username
        syncError = nil
        merge(bands)
    }

    /// Re-reads the linked profile: adds new follows, removes unfollowed ones.
    func refresh() async {
        guard let profile, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            merge(try await Following.bands(of: profile))
            syncError = nil
        } catch {
            syncError = "Couldn't refresh from Bandcamp. The list is kept as it was."
        }
    }

    /// Forgets the profile and removes its artists. Artists added by hand stay.
    func unlink() {
        profile = nil
        syncError = nil
        artists.removeAll(where: \.isFollowed)
    }

    func setFollowedEnabled(_ enabled: Bool) {
        for i in artists.indices where artists[i].isFollowed { artists[i].enabled = enabled }
    }

    /// Keeps on/off choices. An artist also added by hand is not added twice.
    private func merge(_ bands: [FollowedBand]) {
        let byID = Dictionary(bands.map { ($0.bandID, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [Artist] = artists.compactMap { artist in
            guard let id = artist.bandID else { return artist }
            guard let band = byID[id] else { return nil } // Unfollowed on Bandcamp.
            var kept = artist
            kept.name = band.name
            kept.url = band.url
            return kept
        }
        let known = Set(updated.compactMap(\.bandID))
        let hosts = Set(updated.compactMap(\.url.host))
        for band in bands where !known.contains(band.bandID) && !hosts.contains(band.url.host ?? "") {
            updated.append(Artist(url: band.url, name: band.name, bandID: band.bandID))
        }
        if updated != artists { artists = updated }
    }

    var enabled: [Artist] { artists.filter(\.enabled) }

    /// Whether you follow this site, as far as the followed list knows.
    func isFollowed(bandID: Int?, site: URL) -> Bool {
        artists.contains { $0.isFollowed && ($0.bandID == bandID || $0.url.host == site.host) }
    }

    /// After a follow or an unfollow in the app: the followed list changes right away, without
    /// waiting for the next refresh of the linked profile.
    func setFollowed(_ following: Bool, site: URL, name: String, bandID: Int) {
        if following {
            if let index = artists.firstIndex(where: { $0.url.host == site.host }) {
                artists[index].bandID = bandID
            } else {
                artists.append(Artist(url: site, name: name, bandID: bandID))
            }
        } else {
            artists.removeAll { $0.isFollowed && ($0.bandID == bandID || $0.url.host == site.host) }
        }
    }

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
