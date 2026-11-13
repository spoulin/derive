import Foundation

/// What a release page says about its artist and about the release itself, for the Artist tab.
/// Every Bandcamp release page carries the artist's sidebar (photo, bio, links, shows), so a
/// single request gives both.
struct ArtistInfo: Equatable {
    struct Link: Equatable, Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }

    struct Show: Equatable, Identifiable {
        let id: Int
        /// As Bandcamp writes it, without the year: "Nov 20".
        let date: String
        let venue: String
        let place: String
        let url: URL?
    }

    struct FanComment: Equatable, Identifiable {
        let id: Int
        let name: String
        let text: String
        let favoriteTrack: String?
        let avatarURL: URL?
        let profileURL: URL?
    }

    let name: String
    /// Bandcamp's ID of the site (artist or label), to follow it.
    let bandID: Int?
    let location: String?
    let photoURL: URL?
    let bio: String
    let links: [Link]
    let shows: [Show]

    let releaseTitle: String
    let releaseDate: Date?
    let about: String
    let credits: String
    let tags: [String]
    let comments: [FanComment]
}

extension Bandcamp {
    static func info(at page: URL) async throws -> ArtistInfo {
        let (data, response) = try await Bandcamp.session.data(from: page)
        let html = String(decoding: data, as: UTF8.self)
        let base = response.url ?? page

        let sidebar = section(of: html, from: #"id="bio-container""#, length: 12000)
        let name = capture(#"<p id="band-name-location">\s*<span class="title">(.*?)</span>"#, in: sidebar)
            .map(plainText) ?? metaSiteName(in: html) ?? ""
        let location = capture(#"<span class="location secondaryText">(.*?)</span>"#, in: sidebar)
            .map(plainText).flatMap { $0.isEmpty ? nil : $0 }
        let photo = capture(#"class="popupImage" href="([^"]+)""#, in: sidebar).flatMap(URL.init(string:))
        let bio = capture(#"<p id="bio-text">(.*?)</p>"#, in: sidebar).map(plainText) ?? ""
        let links = captures(#"<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>"#,
                             in: capture(#"<ol id="band-links">(.*?)</ol>"#, in: sidebar) ?? "")
            .compactMap { groups -> ArtistInfo.Link? in
                guard let url = URL(string: unescape(groups[0])), url.scheme?.hasPrefix("http") == true
                else { return nil }
                return ArtistInfo.Link(title: plainText(groups[1]), url: url)
            }

        let showList = capture(#"<div id="showography"[^>]*>(.*?)</ul>"#, in: html) ?? ""
        let shows = captures(#"<li>(.*?)</li>"#, in: showList).enumerated().compactMap { index, groups -> ArtistInfo.Show? in
            let item = groups[0]
            guard let date = capture(#"class="showDate secondaryText">(.*?)</div>"#, in: item),
                  let venue = capture(#"class="showVenue">(.*?)</div>"#, in: item) else { return nil }
            return ArtistInfo.Show(
                id: index, date: plainText(date), venue: plainText(venue),
                place: capture(#"class="showLoc secondaryText">(.*?)</div>"#, in: item).map(plainText) ?? "",
                url: capture(#"href="([^"]+)""#, in: venue).flatMap { URL(string: unescape($0)) })
        }

        let tralbum = attribute("data-tralbum", in: html)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let current = tralbum?["current"] as? [String: Any]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm:ss zzz"
        let releaseDate = ((current?["release_date"] as? String) ?? (tralbum?["album_release_date"] as? String))
            .flatMap(dateFormatter.date(from:))

        let tags = captures(#"<a class="tag"[^>]*>(.*?)</a>"#, in: html).map { plainText($0[0]) }

        let collectors = section(of: html, from: #"class="collected-by"#, length: 60000)
        let comments = collectors.components(separatedBy: #"<div class="writing">"#).dropFirst()
            .enumerated().compactMap { index, block -> ArtistInfo.FanComment? in
                guard let nameRange = block.range(
                    of: #"<a class="name[^"]*"[^>]*>(.*?)</a>"#, options: .regularExpression) else { return nil }
                let name = capture(#">(.*?)</a>"#, in: String(block[nameRange])).map(plainText) ?? ""
                var text = String(block[nameRange.upperBound...])
                if let end = text.range(of: #"<span class="fav-track">|</div>"#, options: .regularExpression) {
                    text = String(text[..<end.lowerBound])
                }
                let favorite = capture(#"<span class="fav-track">\s*Favorite track:\s*(.*?)\.?\s*</span>"#,
                                       in: block).map(plainText)
                let comment = plainText(text)
                guard !comment.isEmpty else { return nil }
                return ArtistInfo.FanComment(
                    id: index, name: name, text: comment, favoriteTrack: favorite,
                    avatarURL: capture(#"class="thumb" src="([^"]+)""#, in: block).flatMap(URL.init(string:)),
                    profileURL: capture(#"<a class="pic" href="([^"]+)""#, in: block)
                        .flatMap { URL(string: unescape($0), relativeTo: base)?.absoluteURL })
            }

        let band = attribute("data-band", in: html)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        return ArtistInfo(
            name: name, bandID: (band?["id"] as? NSNumber)?.intValue, location: location, photoURL: photo, bio: bio, links: links, shows: shows,
            releaseTitle: current?["title"] as? String ?? "", releaseDate: releaseDate,
            about: (current?["about"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            credits: (current?["credits"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags, comments: comments)
    }

    /// The text from a marker on, at most `length` characters, so the patterns of one part of
    /// the page don't match another.
    private static func section(of html: String, from marker: String, length: Int) -> String {
        guard let start = html.range(of: marker) else { return "" }
        return String(html[start.lowerBound...].prefix(length))
    }

    private static func metaSiteName(in html: String) -> String? {
        capture(#"<meta property="og:site_name" content="([^"]*)""#, in: html).map(unescape)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text).first?.first
    }

    /// Every match of a pattern, as its capture groups.
    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        let regex = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).map { i in
                match.range(at: i).location == NSNotFound ? "" : ns.substring(with: match.range(at: i))
            }
        }
    }

    /// Readable text from a bit of Bandcamp HTML: line breaks kept, the "... more" link of long
    /// bios dropped, tags removed, entities decoded.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<span class="peekaboo-link">.*?<a>more</a></span>"#,
                                             with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<span class="lightweightBreak"></span>"#, with: "")
        text = text.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = unescape(text).replacingOccurrences(of: "&nbsp;", with: " ")
        let lines = text.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Artist and release info per release page, read once per launch.
@MainActor
final class ArtistInfoStore: ObservableObject {
    static let shared = ArtistInfoStore()

    enum State: Equatable {
        case loading
        case loaded(ArtistInfo)
        case failed(String)
    }

    @Published private(set) var states: [URL: State] = [:]

    func state(for page: URL) -> State? { states[page] }

    func load(_ page: URL) async {
        if case .loaded = states[page] { return }
        if states[page] == .loading { return }
        states[page] = .loading
        do {
            states[page] = .loaded(try await Bandcamp.info(at: page))
        } catch {
            states[page] = .failed("Couldn't load the artist's page from Bandcamp.")
        }
    }
}
