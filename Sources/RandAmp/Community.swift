import Foundation

/// What anyone can read on an artist's Bandcamp community page (/community): the latest posts
/// and the fans who bought something lately. The text of the artist's messages is only for
/// signed-in followers: Bandcamp sends a row of saxophone emoji in its place.
struct Community: Equatable {
    struct Supporter: Equatable, Identifiable {
        let id: Int
        let name: String
        let location: String?
        let avatarURL: URL?
        let profileURL: URL?
    }

    struct Story: Equatable, Identifiable {
        enum Kind: Equatable {
            /// A new album or track, playable in RandAmp.
            case release(title: String, artist: String?, artURL: URL?, url: URL?, featuredTrack: String?,
                         preorder: Bool)
            /// A listening party on Bandcamp Live.
            case listeningParty(title: String, text: String, start: Date?, artURL: URL?, url: URL?)
            /// A message from the artist; `text` is nil when only followers can read it.
            case message(text: String?)
        }

        let id: String
        let kind: Kind
        let date: Date?
        let likes: Int
        let comments: Int
    }

    let pageURL: URL
    /// Bandcamp's ID of the site, to follow it.
    let bandID: Int?
    let stories: [Story]
    let supporters: [Supporter]
}

extension Bandcamp {
    /// Reads /community of a site. Returns nil when the artist has no community page.
    static func community(at root: URL) async throws -> Community? {
        let page = root.appendingPathComponent("community")
        var request = URLRequest(url: page)
        // Signed in, Bandcamp shows the artist's messages to their followers.
        if let cookies = await BandcampSession.shared.cookieHeader(for: page) {
            request.httpShouldHandleCookies = false
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await Bandcamp.session.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let start = html.range(of: #"id="pagedata""#),
              let json = attribute("data-blob", in: String(html[start.lowerBound...])),
              let blob = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let community = blob["community"] as? [String: Any],
              let feed = community["feed"] as? [String: Any]
        else { return nil }

        let stories = (feed["stories"] as? [[String: Any]] ?? []).compactMap(story)
        let supporters = (community["recent_supporters"] as? [[String: Any]] ?? []).compactMap { fan in
            Community.Supporter(
                id: (fan["fan_id"] as? NSNumber)?.intValue ?? 0,
                name: fan["name"] as? String ?? "",
                location: (fan["location"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                // Size 21 is 120 pixels wide, sharp at the size shown; 42 is only 50.
                avatarURL: (fan["image_id"] as? NSNumber).flatMap { imageURL(id: $0.intValue, size: 21) },
                profileURL: (fan["username"] as? String).flatMap { URL(string: "https://bandcamp.com/\($0)") })
        }
        let bandID = ((community["band"] as? [String: Any])?["id"] as? NSNumber)?.intValue
        return Community(pageURL: response.url ?? page, bandID: bandID, stories: stories, supporters: supporters)
    }

    private static func story(_ item: [String: Any]) -> Community.Story? {
        guard let type = item["story_type"] as? String else { return nil }
        let id = item["token"] as? String ?? "\(type)-\((item["story_id"] as? NSNumber)?.intValue ?? 0)"
        let title = item["item_title"] as? String ?? ""
        let art = (item["item_art_id"] as? NSNumber).flatMap { URL(string: "https://f4.bcbits.com/img/a\($0)_2.jpg") }
        let text = (item["message_text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let kind: Community.Story.Kind
        switch type {
        case "nr":
            kind = .release(title: title, artist: item["item_artist"] as? String, artURL: art,
                            url: releaseURL(item["item_url_hints"] as? [String: Any]),
                            featuredTrack: item["featured_track_title"] as? String,
                            preorder: item["is_preorder"] as? Bool ?? false)
        case "la":
            let live = item["live_announcement_info"] as? [String: Any]
            kind = .listeningParty(title: title, text: text,
                                   start: (live?["scheduled_start_date"] as? String).flatMap(date),
                                   artURL: art,
                                   url: (live?["live_event_url"] as? String).flatMap(URL.init(string:)))
        case "sm":
            // Locked messages come as saxophones and spaces.
            let readable = text.contains { !$0.isWhitespace && $0 != "🎷" }
            kind = .message(text: readable ? text : nil)
        default:
            return nil
        }
        return Community.Story(id: id, kind: kind, date: (item["date"] as? String).flatMap(date),
                               likes: (item["num_likes"] as? NSNumber)?.intValue ?? 0,
                               comments: (item["comment_count"] as? NSNumber)?.intValue ?? 0)
    }

    /// The page of a release from Bandcamp's URL hints: its custom domain or subdomain, then its slug.
    private static func releaseURL(_ hints: [String: Any]?) -> URL? {
        guard let hints, let slug = hints["slug"] as? String else { return nil }
        let host: String
        if let domain = hints["custom_domain"] as? String, !domain.isEmpty, hints["custom_domain_verified"] as? Bool == true {
            host = domain
        } else if let subdomain = hints["subdomain"] as? String {
            host = "\(subdomain).bandcamp.com"
        } else {
            return nil
        }
        let kind = (hints["item_type"] as? String) == "t" ? "track" : "album"
        return URL(string: "https://\(host)/\(kind)/\(slug)")
    }

    /// Bandcamp's dates: "06 Nov 2026 08:01:31 GMT".
    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }

    private static func imageURL(id: Int, size: Int) -> URL? {
        URL(string: String(format: "https://f4.bcbits.com/img/%010d_%d.jpg", id, size))
    }
}

/// Community page per artist site, read once per launch.
@MainActor
final class CommunityStore: ObservableObject {
    static let shared = CommunityStore()

    enum State: Equatable {
        case loading
        case loaded(Community?)
        case failed(String)
    }

    @Published private(set) var states: [URL: State] = [:]

    func state(for site: URL) -> State? { states[site] }

    /// Forgets the pages read, after signing in or out, so they're read again with or without
    /// the session.
    func reset() { states = [:] }

    func load(_ site: URL) async {
        if case .loaded = states[site] { return }
        if states[site] == .loading { return }
        states[site] = .loading
        do {
            states[site] = .loaded(try await Bandcamp.community(at: site))
        } catch let error as URLError where error.code == .httpTooManyRedirects {
            states[site] = .failed(UnplayableReason.unreachable.detail)
        } catch {
            states[site] = .failed("Couldn't load the community page from Bandcamp.")
        }
    }
}
