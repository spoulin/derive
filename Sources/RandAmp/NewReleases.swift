import Foundation

/// A release just added to Bandcamp, from Bandcamp Discover.
struct NewRelease: Identifiable, Equatable {
    let title: String
    let artist: String
    let url: URL
    let site: URL
    let artURL: URL?
    /// The release date the artist gave: it can be old (a reissue) or a little ahead.
    let releaseDate: Date?
    var id: URL { url }
}

/// The New Releases mode: Bandcamp Discover's "new arrivals", filtered by the styles you choose.
/// Several styles narrow the list (electronic + ambient: releases with both tags). Places are
/// tags too (montreal). It reads the endpoint the Discover page loads its results from; the page
/// itself is behind a check for robots, the endpoint isn't. Not a documented API: Bandcamp may
/// change it.
@MainActor
final class NewReleaseStore: ObservableObject {
    static let shared = NewReleaseStore()

    /// Bandcamp's main genres, as tags.
    static let genres = ["electronic", "rock", "metal", "alternative", "hip-hop-rap", "experimental",
                         "punk", "folk", "pop", "ambient", "soundtrack", "world", "jazz", "acoustic",
                         "funk", "r-b-soul", "devotional", "classical", "reggae", "country", "blues",
                         "latin"]

    /// The styles chosen, in the order added. None: everything new on Bandcamp.
    @Published private(set) var tags: [String] {
        didSet {
            UserDefaults.standard.set(tags, forKey: Self.tagsKey)
            releases = []
            loadedAt = nil
        }
    }
    /// The latest releases for these styles, newest first.
    @Published private(set) var releases: [NewRelease] = []
    /// How many releases Bandcamp has for these styles, all dates.
    @Published private(set) var total: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    /// The styles added lately, newest first, to add again in a click.
    @Published private(set) var recentTags: [String] {
        didSet { UserDefaults.standard.set(recentTags, forKey: Self.recentKey) }
    }

    private static let tagsKey = "newReleaseTags"
    private static let recentKey = "newReleaseRecentTags"
    private var loadedAt: Date?

    private init() {
        tags = UserDefaults.standard.stringArray(forKey: Self.tagsKey) ?? []
        recentTags = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    /// "Hip Hop", "#shoegaze " or "Montréal" as Bandcamp writes tags: "hip-hop", "shoegaze", "montreal".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    /// Adds a style once Bandcamp confirms it has new releases with it, alone and with the
    /// styles already chosen. Returns a message when it doesn't.
    func add(_ text: String) async -> String? {
        let tag = Self.normalized(text)
        guard !tag.isEmpty else { return nil }
        guard !tags.contains(tag) else { return "\(tag) is already chosen" }
        guard let check = try? await Self.discover(tags: tags + [tag], size: 1) else {
            return "Bandcamp isn't answering. Try again in a little while."
        }
        guard check.total > 0 else {
            return (try? await Self.discover(tags: [tag], size: 1))?.total == 0
                ? "Bandcamp has no releases tagged \(tag)"
                : "No releases have \(tag) and the styles already chosen"
        }
        tags.append(tag)
        recentTags = Array(([tag] + recentTags.filter { $0 != tag }).prefix(12))
        return nil
    }

    func remove(_ tag: String) { tags.removeAll { $0 == tag } }
    func clear() { tags = [] }

    /// Reads the latest releases, unless read in the last 30 minutes.
    func load(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 1800, !releases.isEmpty { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let asked = tags
        do {
            let page = try await Self.discover(tags: asked, size: 100)
            guard asked == tags else { return } // The styles changed meanwhile.
            releases = page.releases
            total = page.total
            loadedAt = Date()
            error = nil
        } catch {
            self.error = "Bandcamp isn't answering. Try again in a little while."
        }
    }

    private static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return format
    }()

    static func discover(tags: [String], size: Int) async throws -> (releases: [NewRelease], total: Int) {
        var request = URLRequest(url: URL(string: "https://bandcamp.com/api/discover/1/discover_web")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "category_id": 0, "tag_norm_names": tags, "geoname_id": 0, "slice": "new",
            "cursor": "*", "size": size, "include_result_types": ["a", "s"],
        ])
        let (data, response) = try await Bandcamp.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw FollowingError.notFound }
        let releases = (root["results"] as? [[String: Any]] ?? []).compactMap { item -> NewRelease? in
            guard let link = item["itemUrl"] as? String, let url = Self.withoutQuery(link),
                  let site = (item["bandUrl"] as? String).flatMap(Self.withoutQuery) else { return nil }
            let imageID = ((item["primaryImage"] as? [String: Any])?["imageId"] as? NSNumber)?.intValue
            return NewRelease(title: item["title"] as? String ?? "",
                              artist: item["bandName"] as? String ?? (site.host ?? ""),
                              url: url, site: site,
                              artURL: imageID.flatMap { URL(string: String(format: "https://f4.bcbits.com/img/a%010ld_9.jpg", $0)) },
                              releaseDate: (item["releaseDate"] as? String).flatMap(dateFormat.date(from:)))
        }
        return (releases, (root["resultCount"] as? NSNumber)?.intValue ?? releases.count)
    }

    /// Discover's links end with "?from=discover_page".
    private static func withoutQuery(_ link: String) -> URL? {
        guard var parts = URLComponents(string: link) else { return nil }
        parts.query = nil
        return parts.url
    }
}
