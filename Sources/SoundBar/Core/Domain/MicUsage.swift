import Foundation

/// What the menu says about the microphone and the browser extension, worked out from the lists it shows.
enum MicUsage {
    /// Names of everything using the microphone: apps and browser tabs. When a tab holds the microphone, the
    /// browser itself is left out (it is the tab that is using it).
    static func userNames(apps: [AudioApp], tabs: [BrowserTab]) -> [String] {
        let tabsHaveMic = tabs.contains(where: \.mic)
        var names =
            apps
            .filter { $0.isUsingMic && !(tabsHaveMic && Browsers.chromeIDs.contains($0.id)) }
            .map(\.name)
        names += tabs.filter(\.mic).map { $0.host.isEmpty ? $0.displayName : $0.host }
        return names
    }

    /// The icon of the menu bar: a microphone while anything uses it, the mixer otherwise.
    static func menuBarSymbol(userNames: [String], inputMuted: Bool) -> String {
        if !userNames.isEmpty { return inputMuted ? "mic.slash.fill" : "mic.fill" }
        return "slider.vertical.3"
    }

    /// Chrome is making sound but the extension is not connected: tell the user how to get per-tab control.
    static func showExtensionHint(extensionConnected: Bool, apps: [AudioApp]) -> Bool {
        !extensionConnected && apps.contains { Browsers.chromeIDs.contains($0.id) }
    }
}
