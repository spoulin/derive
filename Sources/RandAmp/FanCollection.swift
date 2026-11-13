import Foundation

/// A release in a Bandcamp fan's public collection.
struct CollectionItem: Equatable {
    let title: String
    let artist: String
    let url: URL
}

/// Reads a fan's public collection: the first items are in their profile page, the rest come in
/// batches from the endpoint the page uses to load more, like the following list.
enum FanCollection {
    struct Page {
        let fanID: Int
        let name: String
        /// Their profile photo, when they have one.
        let photoURL: URL?
        let total: Int
        let items: [CollectionItem]
        let nextToken: String?
    }

    static func first(of username: String) async throws -> Page {
        let url = URL(string: "https://bandcamp.com/\(username)")!
        let (data, response) = try await Bandcamp.session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FollowingError.notFound }
        let page = String(decoding: data, as: UTF8.self)
        guard let start = page.range(of: #"id="pagedata""#),
              let blob = Bandcamp.attribute("data-blob", in: String(page[start.lowerBound...])),
              let root = try JSONSerialization.jsonObject(with: Data(blob.utf8)) as? [String: Any],
              let fan = root["fan_data"] as? [String: Any],
              let fanID = (fan["fan_id"] as? NSNumber)?.intValue
        else { throw FollowingError.notFound }
        let collection = root["collection_data"] as? [String: Any]
        let cached = ((root["item_cache"] as? [String: Any])?["collection"] as? [String: Any])?
            .values.compactMap { $0 as? [String: Any] } ?? []
        let name = (fan["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? username
        let photoID = ((fan["photo"] as? [String: Any])?["image_id"] as? NSNumber)?.intValue
            ?? (fan["photo"] as? NSNumber)?.intValue
        let photo = photoID.flatMap { URL(string: String(format: "https://f4.bcbits.com/img/%010d_21.jpg", $0)) }
        return Page(fanID: fanID, name: name, photoURL: photo,
                    total: (collection?["item_count"] as? NSNumber)?.intValue ?? cached.count,
                    items: cached.compactMap(item),
                    nextToken: collection?["last_token"] as? String)
    }

    static func next(fanID: Int, after token: String) async throws -> (items: [CollectionItem], nextToken: String?) {
        var request = URLRequest(url: URL(string: "https://bandcamp.com/api/fancollection/1/collection_items")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "fan_id": fanID, "older_than_token": token, "count": 100,
        ])
        let (data, response) = try await Bandcamp.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw FollowingError.notFound }
        let items = (root["items"] as? [[String: Any]] ?? []).compactMap(item)
        let more = root["more_available"] as? Bool ?? false
        return (items, more ? root["last_token"] as? String : nil)
    }

    private static func item(_ raw: [String: Any]) -> CollectionItem? {
        guard let link = raw["item_url"] as? String, let url = URL(string: link) else { return nil }
        return CollectionItem(title: raw["item_title"] as? String ?? "", artist: raw["band_name"] as? String ?? "",
                              url: url)
    }
}

/// Someone else's collection, while RandAmp shuffles in it instead of your artists. Not saved:
/// at launch, RandAmp is back in your own collection.
@MainActor
final class GuestCollection: ObservableObject {
    static let shared = GuestCollection()

    @Published private(set) var username: String?
    /// Bandcamp's ID for this fan, to follow them.
    @Published private(set) var fanID: Int?
    @Published private(set) var name = ""
    @Published private(set) var avatarURL: URL?
    @Published private(set) var total = 0
    @Published private(set) var items: [CollectionItem] = []
    @Published private(set) var isLoading = false

    var isActive: Bool { username != nil }
    var profileURL: URL? { username.flatMap { URL(string: "https://bandcamp.com/\($0)") } }

    private var loadTask: Task<Void, Never>?

    /// Reads the first items, then the rest in the background, unhurried. Returns false when the
    /// collection can't be read or is empty.
    func enter(_ username: String, avatar: URL? = nil) async -> Bool {
        leave(announce: false)
        isLoading = true
        defer { isLoading = false }
        guard let first = try? await FanCollection.first(of: username), !first.items.isEmpty else {
            Toast.shared.show("Couldn't read \(username)'s collection on Bandcamp", symbol: "exclamationmark.triangle")
            return false
        }
        self.username = username
        fanID = first.fanID
        name = first.name
        avatarURL = first.photoURL ?? avatar
        total = first.total
        items = first.items
        loadTask = Task { @MainActor in
            var token = first.nextToken
            while let current = token, !Task.isCancelled, self.username == username {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let batch = try? await FanCollection.next(fanID: first.fanID, after: current) else { return }
                guard !Task.isCancelled, self.username == username else { return }
                items += batch.items
                token = batch.nextToken
            }
        }
        Toast.shared.show("Shuffling in \(name)'s collection. Click Back to mine to return.",
                          symbol: "person.crop.circle")
        return true
    }

    func leave(announce: Bool = true) {
        loadTask?.cancel()
        loadTask = nil
        guard username != nil else { return }
        let previous = name
        username = nil
        fanID = nil
        name = ""
        avatarURL = nil
        total = 0
        items = []
        if announce {
            Toast.shared.show("Back to your artists, out of \(previous)'s collection", symbol: "house")
        }
    }
}
