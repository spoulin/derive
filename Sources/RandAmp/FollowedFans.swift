import Foundation

/// A Bandcamp fan you follow, as Bandcamp lists them on your profile.
struct FollowedFan: Codable, Identifiable, Equatable {
    /// Bandcamp's fan ID.
    let id: Int
    let username: String
    let name: String
    /// Their profile photo, when they have one.
    let avatarURL: URL?
    let location: String?

    static func avatarURL(imageID: Int?) -> URL? {
        imageID.flatMap { URL(string: String(format: "https://f4.bcbits.com/img/%010d_21.jpg", $0)) }
    }
    var profileURL: URL { URL(string: "https://bandcamp.com/\(username)")! }
}

/// The fans you follow on Bandcamp, read from your profile (the account signed in, or the linked
/// profile) like the artists you follow. Following and unfollowing happen on Bandcamp, with the
/// session; this list then follows.
@MainActor
final class FollowedFanStore: ObservableObject {
    static let shared = FollowedFanStore()

    @Published private(set) var fans: [FollowedFan] { didSet { save() } }
    @Published private(set) var isSyncing = false

    private static let key = "followedFans"
    /// The releases of each fan's collection read so far, for the mix of all fans.
    private var collections: [Int: [CollectionItem]] = [:]

    private init() {
        fans = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([FollowedFan].self, from: $0) } ?? []
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(fans), forKey: Self.key)
    }

    /// Whose follows to read: the account signed in, or else the linked profile.
    var owner: String? { BandcampSession.shared.username ?? ArtistStore.shared.profile }

    func isFollowing(_ fanID: Int) -> Bool { fans.contains { $0.id == fanID } }

    /// Re-reads the list from Bandcamp. Keeps the one already here when Bandcamp doesn't answer.
    func refresh() async {
        guard let owner, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        if let list = try? await Self.fans(followedBy: owner) { fans = list }
    }

    /// After a follow or an unfollow on Bandcamp: the list changes right away.
    func setFollowing(_ following: Bool, _ fan: FollowedFan) {
        fans.removeAll { $0.id == fan.id }
        if following {
            fans.append(fan)
            fans.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func randomFan(excluding username: String? = nil) -> FollowedFan? {
        let others = fans.filter { $0.username != username }
        return (others.isEmpty ? fans : others).randomElement()
    }

    /// Some releases of a fan's collection: the first page, then one more batch. Kept until quit.
    func collection(of fan: FollowedFan) async -> [CollectionItem] {
        if let known = collections[fan.id] { return known }
        guard let page = try? await FanCollection.first(of: fan.username) else { return [] }
        var items = page.items
        if let token = page.nextToken, let more = try? await FanCollection.next(fanID: page.fanID, after: token) {
            items += more.items
        }
        if !items.isEmpty { collections[fan.id] = items }
        return items
    }

    /// Reads a fan's own following list: the first batch is in their profile page, the rest
    /// comes from the endpoint the page uses to load more.
    static func fans(followedBy username: String) async throws -> [FollowedFan] {
        let url = URL(string: "https://bandcamp.com/\(username)")!
        let (data, response) = try await Bandcamp.session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FollowingError.notFound }
        let page = String(decoding: data, as: UTF8.self)
        guard let start = page.range(of: #"id="pagedata""#),
              let blob = Bandcamp.attribute("data-blob", in: String(page[start.lowerBound...])),
              let root = try JSONSerialization.jsonObject(with: Data(blob.utf8)) as? [String: Any],
              let fanID = ((root["fan_data"] as? [String: Any])?["fan_id"] as? NSNumber)?.intValue
        else { throw FollowingError.notFound }

        var found: [Int: FollowedFan] = [:]
        let firstBatch = ((root["item_cache"] as? [String: Any])?["following_fans"] as? [String: Any])?
            .values.compactMap { $0 as? [String: Any] } ?? []
        firstBatch.compactMap(fan).forEach { found[$0.id] = $0 }

        var token = (root["following_fans_data"] as? [String: Any])?["last_token"] as? String
        var requests = 0
        while let current = token, requests < 20 {
            requests += 1
            var request = URLRequest(url: URL(string: "https://bandcamp.com/api/fancollection/1/following_fans")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "fan_id": fanID, "older_than_token": current, "count": 200,
            ])
            let (data, _) = try await Bandcamp.session.data(for: request)
            guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FollowingError.notFound
            }
            // "followeers" is Bandcamp's spelling.
            (answer["followeers"] as? [[String: Any]] ?? []).compactMap(fan).forEach { found[$0.id] = $0 }
            token = answer["more_available"] as? Bool == true ? answer["last_token"] as? String : nil
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func fan(_ item: [String: Any]) -> FollowedFan? {
        guard let id = (item["fan_id"] as? NSNumber)?.intValue else { return nil }
        let link = (item["trackpipe_url"] as? String) ?? (item["fan_url"] as? String) ?? ""
        guard let username = Following.username(from: link) else { return nil }
        let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? username
        let location = (item["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return FollowedFan(id: id, username: username, name: name,
                           avatarURL: FollowedFan.avatarURL(imageID: (item["image_id"] as? NSNumber)?.intValue),
                           location: location)
    }
}
