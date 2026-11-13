import AppKit
import SwiftUI
import WebKit

/// Your own Bandcamp session, opened by signing in on bandcamp.com in a window of the app.
/// RandAmp never sees the password: you type it in Bandcamp's own page, and the session
/// cookies stay in the app's web data. They are sent only with the community page requests,
/// where Bandcamp shows the artist's messages to signed-in followers.
@MainActor
final class BandcampSession: NSObject, ObservableObject {
    static let shared = BandcampSession()

    @Published private(set) var isSignedIn = false
    /// The Bandcamp username of the account signed in, once read.
    @Published private(set) var username: String? = UserDefaults.standard.string(forKey: "bandcampUsername") {
        didSet { UserDefaults.standard.set(username, forKey: "bandcampUsername") }
    }
    /// The fan ID of the account signed in, which Bandcamp needs to follow an artist.
    private(set) var fanID: Int? = UserDefaults.standard.object(forKey: "bandcampFanID") as? Int {
        didSet { UserDefaults.standard.set(fanID, forKey: "bandcampFanID") }
    }

    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }
    private var window: NSWindow?
    private var warmUp: WKWebView?

    override private init() {
        super.init()
        // WebKit loads the saved cookies only once a web view of its store exists.
        warmUp = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        Task {
            await refresh()
            // Signed in before the username was kept: read it, without linking anything.
            if isSignedIn, username == nil || fanID == nil { username = await readUsername() }
        }
    }

    /// Bandcamp sets js_logged_in (and identity) when you sign in.
    func refresh() async {
        let cookies = await bandcampCookies()
        isSignedIn = cookies.contains { $0.name == "js_logged_in" && $0.value == "1" }
            || cookies.contains { $0.name == "identity" && !$0.value.isEmpty }
    }

    /// The session cookies for a request to this URL, or nil when signed out or the site is not on
    /// bandcamp.com (a custom domain never gets them).
    func cookieHeader(for url: URL) async -> String? {
        guard isSignedIn, let host = url.host, host == "bandcamp.com" || host.hasSuffix(".bandcamp.com")
        else { return nil }
        let cookies = await bandcampCookies().filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    private func bandcampCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies.filter { $0.domain.hasSuffix("bandcamp.com") })
            }
        }
    }

    /// Opens Bandcamp's sign-in page in a window. It closes by itself once you're signed in.
    func signIn() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640),
                                configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://bandcamp.com/login")!))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to Bandcamp"
        window.contentView = NSHostingView(rootView: SignInView(webView: webView))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Forgets the session: removes Bandcamp's cookies and web data from the app.
    func signOut() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types).filter { $0.displayName.contains("bandcamp") }
        await dataStore.removeData(ofTypes: types, for: records)
        for cookie in await bandcampCookies() {
            await store.deleteCookie(cookie)
        }
        await refresh()
        username = nil
        fanID = nil
        CommunityStore.shared.reset()
    }

    private func didSignIn() {
        window?.close()
        window = nil
        CommunityStore.shared.reset()
        Task { await linkProfile() }
    }

    /// Links the profile of the account signed in, so its followed artists play, unless a
    /// profile is linked already.
    func linkProfile() async {
        guard let name = await readUsername() else { return }
        username = name
        let artists = ArtistStore.shared
        guard artists.profile == nil else { return }
        try? await artists.link(name)
    }

    /// Who is signed in, from the identities Bandcamp puts in its pages. The gift card page is
    /// on bandcamp.com itself, so it gets the session, and it carries them.
    private func readUsername() async -> String? {
        let page = URL(string: "https://bandcamp.com/gift_cards")!
        guard let cookies = await cookieHeader(for: page) else { return nil }
        var request = URLRequest(url: page)
        request.httpShouldHandleCookies = false
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await Bandcamp.session.data(for: request) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let start = html.range(of: #"id="pagedata""#),
              let json = Bandcamp.attribute("data-blob", in: String(html[start.lowerBound...])),
              let blob = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let fan = (blob["identities"] as? [String: Any])?["fan"] as? [String: Any]
        else { return nil }
        if let id = (fan["id"] as? NSNumber)?.intValue { fanID = id }
        if let name = fan["username"] as? String, !name.isEmpty { return name }
        // Otherwise the profile address, in whichever field holds it.
        for value in fan.values {
            if let text = value as? String, text.contains("bandcamp.com/"),
               let name = Following.username(from: text) {
                return name
            }
        }
        return nil
    }
}

extension BandcampSession {
    /// Follows or unfollows an artist or label on Bandcamp, as its Follow button does, with the
    /// session. Returns whether you follow it afterwards, or nil when it didn't work.
    func setFollowing(_ follow: Bool, bandID: Int, site: URL) async -> Bool? {
        if fanID == nil { _ = await readUsername() }
        guard isSignedIn, let fanID, let host = site.host else { return nil }
        // The site's own page, read with the session, carries the "crumb" token the follow needs.
        // A custom domain doesn't get the session; bandcamp.com stands in for it, as on the site.
        let base = host.hasSuffix(".bandcamp.com") ? URL(string: "https://\(host)")! : URL(string: "https://bandcamp.com")!
        let page = host.hasSuffix(".bandcamp.com") ? base : URL(string: "https://bandcamp.com/gift_cards")!
        guard let cookies = await cookieHeader(for: base) else { return nil }
        var pageRequest = URLRequest(url: page)
        pageRequest.httpShouldHandleCookies = false
        pageRequest.setValue(cookies, forHTTPHeaderField: "Cookie")
        let html = (try? await Bandcamp.session.data(for: pageRequest)).map { String(decoding: $0.0, as: UTF8.self) } ?? ""
        let crumbs = Bandcamp.attribute("data-crumbs", in: html)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] } ?? [:]
        var crumb = crumbs["fan_follow_band_cb"]

        let endpoint = base.appendingPathComponent("fan_follow_band_cb")
        for _ in 0..<3 {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = false
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "fan_id", value: "\(fanID)"),
                               URLQueryItem(name: "band_id", value: "\(bandID)"),
                               URLQueryItem(name: "action", value: follow ? "follow" : "unfollow")]
            if let crumb { form.queryItems?.append(URLQueryItem(name: "crumb", value: crumb)) }
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            guard let (data, _) = try? await Bandcamp.session.data(for: request) else { return nil }
            guard let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            // A stale token: Bandcamp sends a fresh one, and the request goes again with it.
            if answer["error"] as? String == "invalid_crumb", let fresh = answer["crumb"] as? String {
                crumb = fresh
                continue
            }
            guard answer["ok"] as? Bool == true else { return nil }
            return answer["is_following"] as? Bool ?? follow
        }
        return nil
    }

    /// Follows or unfollows a fan on Bandcamp, as the Follow button of their profile does.
    /// Returns whether you follow them afterwards, or nil when it didn't work.
    func setFollowingFan(_ follow: Bool, fanID followID: Int, username: String) async -> Bool? {
        if fanID == nil { _ = await readUsername() }
        guard isSignedIn, let fanID else { return nil }
        let base = URL(string: "https://bandcamp.com")!
        // Their profile, read with the session, carries the "crumb" token the follow needs.
        let page = URL(string: "https://bandcamp.com/\(username)")!
        guard let cookies = await cookieHeader(for: base) else { return nil }
        var pageRequest = URLRequest(url: page)
        pageRequest.httpShouldHandleCookies = false
        pageRequest.setValue(cookies, forHTTPHeaderField: "Cookie")
        let html = (try? await Bandcamp.session.data(for: pageRequest)).map { String(decoding: $0.0, as: UTF8.self) } ?? ""
        let crumbs = Bandcamp.attribute("data-crumbs", in: html)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] } ?? [:]
        var crumb = crumbs["fan_follow_cb"]

        for _ in 0..<3 {
            var request = URLRequest(url: base.appendingPathComponent("fan_follow_cb"))
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = false
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(page.absoluteString, forHTTPHeaderField: "Referer")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "fan_id", value: "\(fanID)"),
                               URLQueryItem(name: "follow_id", value: "\(followID)"),
                               URLQueryItem(name: "action", value: follow ? "follow" : "unfollow")]
            if let crumb { form.queryItems?.append(URLQueryItem(name: "crumb", value: crumb)) }
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            guard let (data, _) = try? await Bandcamp.session.data(for: request),
                  let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if answer["error"] as? String == "invalid_crumb", let fresh = answer["crumb"] as? String {
                crumb = fresh
                continue
            }
            guard answer["ok"] as? Bool == true else { return nil }
            return answer["is_following"] as? Bool ?? follow
        }
        return nil
    }
}

extension BandcampSession: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            await refresh()
            // Signed in and off the login page: the job is done.
            if isSignedIn, webView.url?.path.hasPrefix("/login") != true {
                didSignIn()
            }
        }
    }
}

extension BandcampSession: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in window = nil }
    }
}

/// Bandcamp's page, with a field below it for the link of the email Bandcamp sends to confirm
/// a new device. That link opens in the browser, whose session isn't the app's: pasted here, it
/// opens in this window and confirms the app's session.
private struct SignInView: View {
    let webView: WKWebView
    @State private var link = ""

    var body: some View {
        VStack(spacing: 0) {
            WebView(webView: webView)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Bandcamp sent you an email to confirm it's you? Don't click its link: copy it and paste it here.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("https://bandcamp.com/…", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(open)
                    Button("Open", action: open)
                        .disabled(url == nil)
                }
            }
            .padding(12)
        }
    }

    /// Any https link: email links often go through a click-tracking address before Bandcamp.
    private var url: URL? {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private func open() {
        guard let url else { return }
        webView.load(URLRequest(url: url))
        link = ""
    }
}

private struct WebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// "Sign in to Bandcamp…" or "Sign out of Bandcamp", for menus.
struct BandcampSessionButton: View {
    @ObservedObject private var session = BandcampSession.shared

    var body: some View {
        if session.isSignedIn {
            Button(session.username.map { "Sign Out of Bandcamp (\($0))" } ?? "Sign Out of Bandcamp") {
                Task { await session.signOut() }
            }
        } else {
            Button("Sign In to Bandcamp…") { session.signIn() }
        }
    }
}
