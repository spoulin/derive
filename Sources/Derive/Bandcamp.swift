import Foundation

struct Track {
    /// Bandcamp's track ID; 0 when the page doesn't give one.
    let id: Int
    let title: String
    let url: URL
    /// In seconds; 0 when the page doesn't give it.
    var duration: Double = 0
}

struct Album {
    let title: String
    let artURL: URL?
    let pageURL: URL
    let tracks: [Track]
}

/// An artist (or label) site and the release pages it lists.
struct Site {
    let name: String
    let releases: [URL]
}

enum BandcampError: Error {
    case parse
    case noAlbums
}

enum Bandcamp {
    /// Reads the /music page of a site. Albums come first; tracks only when there are no albums.
    static func site(at root: URL) async throws -> Site {
        let (page, finalURL) = try await fetch(root.appendingPathComponent("music"))
        let name = metaContent("og:site_name", in: page) ?? root.host ?? root.absoluteString
        var albums: [String] = []
        var tracks: [String] = []
        // The first items are only in the HTML grid; the rest are only in data-client-items.
        for (type, path) in gridItems(in: page) + clientItems(in: page) {
            if type == "album" { albums.append(path) } else if type == "track" { tracks.append(path) }
        }
        var releases = Array(Set(albums.isEmpty ? tracks : albums))
            .compactMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL }
        // A site with a single release redirects /music to that release.
        if releases.isEmpty, attribute("data-tralbum", in: page) != nil {
            releases = [finalURL]
        }
        guard !releases.isEmpty else { throw BandcampError.noAlbums }
        return Site(name: name, releases: releases)
    }

    private static func gridItems(in page: String) -> [(String, String)] {
        let regex = try! NSRegularExpression(
            pattern: #"data-item-id="(album|track)-\d+"[^>]*>\s*<a href="([^"]+)""#)
        let ns = page as NSString
        return regex.matches(in: page, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)), unescape(ns.substring(with: $0.range(at: 2))))
        }
    }

    private static func clientItems(in page: String) -> [(String, String)] {
        guard let json = attribute("data-client-items", in: page),
              let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let type = item["type"] as? String, let path = item["page_url"] as? String
            else { return nil }
            return (type, path)
        }
    }

    static func album(at url: URL) async throws -> Album {
        let (page, _) = try await fetch(url)
        guard let json = attribute("data-tralbum", in: page),
              let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let infos = root["trackinfo"] as? [[String: Any]]
        else { throw BandcampError.parse }
        let tracks: [Track] = infos
            .sorted { ($0["track_num"] as? Int ?? 0) < ($1["track_num"] as? Int ?? 0) }
            .compactMap { info in
                guard let file = info["file"] as? [String: String],
                      let src = file["mp3-128"], let url = URL(string: src) else { return nil }
                let id = (info["track_id"] as? NSNumber ?? info["id"] as? NSNumber)?.intValue ?? 0
                return Track(id: id, title: info["title"] as? String ?? "", url: url,
                             duration: (info["duration"] as? NSNumber)?.doubleValue ?? 0)
            }
        let current = root["current"] as? [String: Any]
        let art = (root["art_id"] as? NSNumber).flatMap {
            URL(string: "https://f4.bcbits.com/img/a\($0)_10.jpg")
        }
        return Album(title: current?["title"] as? String ?? "", artURL: art, pageURL: url, tracks: tracks)
    }

    private static func fetch(_ url: URL) async throws -> (String, URL) {
        let (data, response) = try await URLSession.shared.data(from: url)
        return (String(decoding: data, as: UTF8.self), response.url ?? url)
    }

    private static func metaContent(_ property: String, in html: String) -> String? {
        guard let tag = html.range(of: "property=\"\(property)\"") else { return nil }
        let rest = String(html[tag.upperBound...].prefix(500))
        guard let value = attribute("content", in: rest), !value.isEmpty else { return nil }
        return value
    }

    /// Extracts and HTML-unescapes the value of a double-quoted attribute.
    static func attribute(_ name: String, in html: String) -> String? {
        guard let start = html.range(of: "\(name)=\"") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return unescape(String(rest[..<end]))
    }

    static func unescape(_ text: String) -> String {
        var out = text
        let regex = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let code = (text as NSString).substring(with: match.range(at: 1))
            let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            if let value, let scalar = Unicode.Scalar(value) {
                out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }
        // NSString replacement is code-unit based; Swift's String would miss an
        // entity followed by a combining character.
        let named = ["&quot;": "\"", "&lt;": "<", "&gt;": ">", "&amp;": "&"]
        let result = NSMutableString(string: out)
        for (entity, char) in named {
            result.replaceOccurrences(of: entity, with: char, options: .literal,
                                      range: NSRange(location: 0, length: result.length))
        }
        return result as String
    }
}
