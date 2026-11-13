import Foundation

/// An artist or label that a Bandcamp fan follows.
struct FollowedBand {
    let bandID: Int
    let name: String
    let url: URL
}

enum FollowingError: LocalizedError {
    case invalidProfile, notFound
    var errorDescription: String? {
        switch self {
        case .invalidProfile: "Paste a Bandcamp profile, like bandcamp.com/yourname."
        case .notFound: "Couldn't read the artists this profile follows."
        }
    }
}

/// Reads the public "following" list of a Bandcamp fan profile. No sign-in needed.
/// The first batch is in the profile page; the rest comes from the endpoint the page itself
/// uses to load more. That endpoint isn't a documented API, so Bandcamp may change it.
enum Following {
    /// Accepts "https://bandcamp.com/name/following/artists_and_labels", "bandcamp.com/name" or "name".
    static func username(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("/") && !text.contains(".") {
            return text.isEmpty ? nil : text
        }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), ["bandcamp.com", "www.bandcamp.com"].contains(url.host?.lowercased() ?? ""),
              let name = url.pathComponents.dropFirst().first, !name.isEmpty
        else { return nil }
        return name
    }

    static func profileURL(for username: String) -> URL {
        URL(string: "https://bandcamp.com/\(username)/following/artists_and_labels")!
    }

    static func bands(of username: String) async throws -> [FollowedBand] {
        let (data, _) = try await Bandcamp.session.data(from: profileURL(for: username))
        let page = String(decoding: data, as: UTF8.self)
        guard let blob = Bandcamp.attribute("data-blob", in: page),
              let root = try JSONSerialization.jsonObject(with: Data(blob.utf8)) as? [String: Any],
              let fanID = (root["fan_data"] as? [String: Any])?["fan_id"] as? NSNumber
        else { throw FollowingError.notFound }

        var found: [Int: FollowedBand] = [:]
        let firstBatch = ((root["item_cache"] as? [String: Any])?["following_bands"] as? [String: Any])?
            .values.compactMap { $0 as? [String: Any] } ?? []
        firstBatch.compactMap(band).forEach { found[$0.bandID] = $0 }

        var token = (root["following_bands_data"] as? [String: Any])?["last_token"] as? String
        var requests = 0
        while let current = token, requests < 20 {
            requests += 1
            let more = try await nextBatch(fanID: fanID.intValue, olderThan: current)
            more.bands.forEach { found[$0.bandID] = $0 }
            token = more.hasMore ? more.lastToken : nil
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func nextBatch(fanID: Int, olderThan token: String) async throws
        -> (bands: [FollowedBand], hasMore: Bool, lastToken: String?) {
        var request = URLRequest(url: URL(string: "https://bandcamp.com/api/fancollection/1/following_bands")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "fan_id": fanID, "older_than_token": token, "count": 200,
        ])
        let (data, _) = try await Bandcamp.session.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FollowingError.notFound
        }
        // "followeers" is Bandcamp's spelling.
        let items = root["followeers"] as? [[String: Any]] ?? []
        return (items.compactMap(band), root["more_available"] as? Bool ?? false, root["last_token"] as? String)
    }

    private static func band(_ item: [String: Any]) -> FollowedBand? {
        guard let id = item["band_id"] as? NSNumber,
              let hints = item["url_hints"] as? [String: Any] else { return nil }
        let host: String
        if let custom = hints["custom_domain"] as? String, !custom.isEmpty {
            host = custom
        } else if let sub = hints["subdomain"] as? String, !sub.isEmpty {
            host = "\(sub).bandcamp.com"
        } else {
            return nil
        }
        guard let url = URL(string: "https://\(host.lowercased())") else { return nil }
        return FollowedBand(bandID: id.intValue, name: item["name"] as? String ?? host, url: url)
    }
}
