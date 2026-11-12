import ServiceManagement
import SwiftUI

/// Opens Dérive when the user logs in, through macOS login items (System Settings ›
/// General › Login Items). macOS keeps the setting, not the app.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a message to show when macOS refuses or needs the user's approval.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return "macOS didn't change the login item: \(error.localizedDescription)"
        }
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "Allow Dérive in System Settings › Login Items."
        }
        return nil
    }
}

/// The "…" menu of the menu bar window: Open at login, and Quit.
struct AppMenu: View {
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var message: String?

    var body: some View {
        Menu {
            Toggle("Open at Login", isOn: Binding(
                get: { openAtLogin },
                set: { newValue in
                    message = LoginItem.set(newValue)
                    openAtLogin = LoginItem.isEnabled
                }))
            Divider()
            Button("Quit Dérive") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(message ?? "Open at login, quit")
        // macOS can change it too (System Settings), so read it again when the menu bar opens.
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}
