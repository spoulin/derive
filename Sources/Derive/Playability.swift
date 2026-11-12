import Foundation

/// Why an artist's music can't be played from the app.
enum UnplayableReason: String, Codable {
    /// Every release has no audio on Bandcamp, even in a web browser.
    case noAudio
    /// The site sends the app around in a redirect loop (some custom domains do this for apps
    /// that aren't web browsers).
    case unreachable
    /// The site lists no releases.
    case noReleases

    var label: String {
        switch self {
        case .noAudio: "No audio on Bandcamp"
        case .unreachable: "Site can't be read by the app"
        case .noReleases: "No releases on Bandcamp"
        }
    }

    var detail: String {
        switch self {
        case .noAudio: "This artist's releases have no tracks to listen to on Bandcamp, even in a web browser."
        case .unreachable: "This artist uses their own domain. Bandcamp sends apps that aren't web browsers around in a loop there, so the app can't read it. It plays in a web browser."
        case .noReleases: "This artist's Bandcamp page lists no releases."
        }
    }
}

/// Artists found unplayable, by site host, saved in UserDefaults. They are skipped when picking
/// at random for a week, then tried again in case the artist changed something.
@MainActor
final class PlayabilityStore: ObservableObject {
    static let shared = PlayabilityStore()

    struct Mark: Codable {
        let reason: UnplayableReason
        let checked: Date
    }

    @Published private(set) var marks: [String: Mark] { didSet { save() } }

    private static let key = "unplayableArtists"
    private static let recheckAfter: TimeInterval = 7 * 24 * 60 * 60

    init() {
        marks = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: Mark].self, from: $0) } ?? [:]
    }

    func reason(for url: URL) -> UnplayableReason? {
        url.host.flatMap { marks[$0]?.reason }
    }

    /// True while the mark is less than a week old.
    func shouldSkip(_ url: URL) -> Bool {
        guard let host = url.host, let mark = marks[host] else { return false }
        return Date().timeIntervalSince(mark.checked) < Self.recheckAfter
    }

    func mark(_ url: URL, _ reason: UnplayableReason) {
        guard let host = url.host else { return }
        marks[host] = Mark(reason: reason, checked: Date())
    }

    func clear(_ url: URL) {
        guard let host = url.host, marks[host] != nil else { return }
        marks[host] = nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(marks) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
