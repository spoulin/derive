import Foundation

/// An item for sale on an artist's Bandcamp merch page.
struct MerchItem: Identifiable, Equatable {
    let id: Int
    let title: String
    /// Set when a label sells it for one of its artists.
    let artist: String?
    let type: String
    let price: String
    let imageID: Int?
    /// Path of the item's page, e.g. /album/name for a CD or a record, /merch/name for the rest.
    let path: String
    let url: URL
    let soldOut: Bool

    /// Bandcamp image sizes: 16 is 700 px wide, 37 about 300 px.
    func imageURL(size: Int) -> URL? {
        imageID.flatMap { URL(string: String(format: "https://f4.bcbits.com/img/%010d_%d.jpg", $0, size)) }
    }
}

extension Bandcamp {
    /// Reads /merch of a site. Its first items are only in the HTML grid; the rest only in
    /// data-client-items, like /music.
    static func merch(at root: URL) async throws -> [MerchItem] {
        let (data, response) = try await Bandcamp.session.data(from: root.appendingPathComponent("merch"))
        let page = String(decoding: data, as: UTF8.self)
        let base = response.url ?? root
        var items = gridMerch(in: page, base: base) + clientMerch(in: page, base: base)
        var seen = Set<Int>()
        items.removeAll { !seen.insert($0.id).inserted }
        return items
    }

    private static func gridMerch(in page: String, base: URL) -> [MerchItem] {
        let ns = page as NSString
        let itemRegex = try! NSRegularExpression(
            pattern: #"<li data-item-id="(\d+)"[^>]*class="merch-grid-item[^"]*"[^>]*>(.*?)</li>"#,
            options: .dotMatchesLineSeparators)
        return itemRegex.matches(in: page, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let id = Int(ns.substring(with: match.range(at: 1))) else { return nil }
            let body = ns.substring(with: match.range(at: 2))
            guard let path = capture(#"<a href="([^"]+)""#, in: body),
                  let url = URL(string: path, relativeTo: base)?.absoluteURL else { return nil }
            let imageID = capture(#"/img/0*(\d+)_\d+\.jpg"#, in: body).flatMap(Int.init)
            let rawTitle = capture(#"<p class="title">\s*(.*?)\s*(?:<br>|</p>)"#, in: body) ?? ""
            let artist = capture(#"<span class="artist-override">\s*(.*?)\s*</span>"#, in: body)
            let type = capture(#"class="merchtype secondaryText">\s*(.*?)\s*<"#, in: body) ?? "Merch"
            let amount = capture(#"<span class="price">\s*(.*?)\s*</span>"#, in: body) ?? ""
            let currency = capture(#"<span class="currency">\s*(.*?)\s*</span>"#, in: body) ?? ""
            return MerchItem(id: id, title: plain(rawTitle), artist: artist.map(plain), type: plain(type),
                             price: [amount, currency].filter { !$0.isEmpty }.joined(separator: " "),
                             imageID: imageID, path: path, url: url,
                             soldOut: body.localizedCaseInsensitiveContains("sold out")
                                || body.contains("sold-out"))
        }
    }

    private static func clientMerch(in page: String, base: URL) -> [MerchItem] {
        guard let start = page.range(of: "id=\"merch-grid\""),
              let json = attribute("data-client-items", in: String(page[start.lowerBound...])),
              let items = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let id = (item["id"] as? NSNumber)?.intValue, let path = item["url"] as? String,
                  let url = URL(string: path, relativeTo: base)?.absoluteURL else { return nil }
            // Same style as the HTML grid: "$15 USD", "£12.50 GBP".
            let price = (item["price"] as? NSNumber).map { amount -> String in
                let code = item["currency"] as? String ?? "USD"
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = Locale(identifier: "en_US")
                formatter.currencyCode = code
                formatter.minimumFractionDigits = amount.doubleValue.rounded() == amount.doubleValue ? 0 : 2
                return "\(formatter.string(from: amount) ?? "\(amount)") \(code)"
            } ?? ""
            return MerchItem(id: id, title: item["title"] as? String ?? "", artist: item["album_artist"] as? String,
                             type: typeName((item["type_id"] as? NSNumber)?.intValue), price: price,
                             imageID: (item["img_id"] as? NSNumber)?.intValue, path: path, url: url,
                             soldOut: item["sold_out"] as? Bool ?? false)
        }
    }

    /// Bandcamp's merch type numbers, as seen on merch pages.
    private static func typeName(_ id: Int?) -> String {
        switch id {
        case 1: "Compact Disc"
        case 2, 15: "Vinyl"
        case 3: "Cassette"
        case 10: "Poster/Print"
        case 11: "Apparel"
        default: "Merch"
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// Removes tags and decodes the few entities found in merch titles.
    private static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&ndash;": "–", "&mdash;": "—", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Merch per artist site, read once per launch, for the Merch tab.
@MainActor
final class MerchStore: ObservableObject {
    static let shared = MerchStore()

    enum State: Equatable {
        case loading
        case loaded([MerchItem])
        case failed(String)
    }

    @Published private(set) var states: [URL: State] = [:]

    func state(for site: URL) -> State? { states[site] }

    func load(_ site: URL) async {
        if case .loaded = states[site] { return }
        if states[site] == .loading { return }
        states[site] = .loading
        do {
            states[site] = .loaded(try await Bandcamp.merch(at: site))
        } catch let error as URLError where error.code == .httpTooManyRedirects {
            states[site] = .failed(UnplayableReason.unreachable.detail)
        } catch {
            states[site] = .failed("Couldn't load the merch from Bandcamp.")
        }
    }
}
