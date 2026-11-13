import Foundation

/// Ticket price and availability of a show, from its Songkick page, where Bandcamp's show links
/// go. Songkick puts them in the page's structured data (schema.org MusicEvent offers).
struct TicketInfo: Equatable {
    let low: Double?
    let high: Double?
    let currency: String?
    let soldOut: Bool
    let fewLeft: Bool

    /// "from $40", "$40–$60", "$120", or nil when there is no price.
    var priceText: String? {
        guard let low else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = currency ?? "USD"
        func text(_ value: Double) -> String {
            formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        if let high, high > low { return "\(text(low))–\(text(high))" }
        return text(low)
    }

    static func read(from page: URL) async -> TicketInfo? {
        guard page.host?.hasSuffix("songkick.com") == true,
              let (data, response) = try? await Bandcamp.session.data(from: page),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        let regex = try! NSRegularExpression(
            pattern: #"<script type="application/ld\+json">(.*?)</script>"#, options: .dotMatchesLineSeparators)
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let json = ns.substring(with: match.range(at: 1))
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { continue }
            let events = (parsed as? [[String: Any]]) ?? [(parsed as? [String: Any]) ?? [:]]
            for event in events where (event["@type"] as? String)?.hasSuffix("Event") == true {
                let offers = (event["offers"] as? [[String: Any]]) ?? [(event["offers"] as? [String: Any]) ?? [:]]
                guard let offer = offers.first, !offer.isEmpty else { continue }
                func number(_ key: String) -> Double? {
                    (offer[key] as? NSNumber)?.doubleValue ?? (offer[key] as? String).flatMap(Double.init)
                }
                let availability = (offer["availability"] as? String ?? "").lowercased()
                return TicketInfo(low: number("lowPrice") ?? number("price"),
                                  high: number("highPrice"),
                                  currency: offer["priceCurrency"] as? String,
                                  soldOut: availability.contains("soldout"),
                                  fewLeft: availability.contains("limited"))
            }
        }
        return nil
    }
}

/// Ticket info per show page, read once per launch, only for the shows on screen.
@MainActor
final class TicketStore: ObservableObject {
    static let shared = TicketStore()

    /// nil inside: read, but no ticket info on the page.
    @Published private(set) var tickets: [URL: TicketInfo?] = [:]
    private var loading: Set<URL> = []

    func load(_ page: URL) async {
        guard tickets[page] == nil, loading.insert(page).inserted else { return }
        let info = await TicketInfo.read(from: page)
        tickets[page] = .some(info)
        loading.remove(page)
    }
}
