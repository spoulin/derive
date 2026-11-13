import AppKit
import SwiftUI

/// The version of the app, and where to get a newer one. Releases are on GitHub, made by the
/// Release workflow from a version tag; the app isn't notarized, so it doesn't update itself.
enum AppInfo {
    /// From the build: the version tag of a release, 0.0.0 for a build without one.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static let releasesPage = URL(string: "https://github.com/spoulin/derive/releases/latest")!
}

/// "Dérive 1.2.0" and "Check for Updates…", for the "…" menus.
struct AboutMenuItems: View {
    var body: some View {
        Button("Dérive \(AppInfo.version)") {}
            .disabled(true)
        Button("Check for Updates…") { NSWorkspace.shared.open(AppInfo.releasesPage) }
    }
}
