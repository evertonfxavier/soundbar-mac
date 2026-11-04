import Foundation
import Testing

@Suite("MicUsage")
struct MicUsageTests {
    private func app(_ id: String, name: String, mic: Bool = false) -> AudioApp {
        AudioApp(
            id: id, name: name, icon: nil, objectIDs: [], isPlaying: false, isUsingMic: mic, outputDeviceUID: nil)
    }

    private func tab(
        _ id: Int, title: String = "", host: String = "", mic: Bool = false, audible: Bool = false
    ) -> BrowserTab {
        BrowserTab(
            conn: 1, tabID: id, title: title, host: host, favIconURL: nil, audible: audible, muted: false,
            volume: 1, mic: mic, micMuted: false)
    }

    @Test("lists the apps that use the microphone")
    func appsUsingTheMic() {
        let apps = [app("zoom", name: "Zoom", mic: true), app("music", name: "Music")]

        #expect(MicUsage.userNames(apps: apps, tabs: []) == ["Zoom"])
    }

    @Test("lists the tabs that use it by host, or by title when the host is unknown")
    func tabsUsingTheMic() {
        let tabs = [tab(1, title: "Meet", host: "meet.google.com", mic: true), tab(2, title: "Local page", mic: true)]

        #expect(MicUsage.userNames(apps: [], tabs: tabs) == ["meet.google.com", "Local page"])
    }

    @Test("when a tab has the microphone, the browser itself is not named: the tab is")
    func browserLeftOutWhenATabHasTheMic() {
        let apps = [app("com.google.Chrome", name: "Google Chrome", mic: true), app("zoom", name: "Zoom", mic: true)]
        let tabs = [tab(1, host: "meet.google.com", mic: true)]

        #expect(MicUsage.userNames(apps: apps, tabs: tabs) == ["Zoom", "meet.google.com"])
    }

    @Test("without the extension, Chrome is named as itself")
    func browserNamedWithoutTabs() {
        let apps = [app("com.google.Chrome", name: "Google Chrome", mic: true)]

        #expect(MicUsage.userNames(apps: apps, tabs: []) == ["Google Chrome"])
    }

    @Test("a tab that does not use the microphone is not listed")
    func quietTab() {
        #expect(MicUsage.userNames(apps: [], tabs: [tab(1, host: "x.com", audible: true)]).isEmpty)
    }

    @Test("the menu bar shows a microphone while something uses it, crossed out when it is muted")
    func menuBarSymbol() {
        #expect(MicUsage.menuBarSymbol(userNames: ["Zoom"], inputMuted: false) == "mic.fill")
        #expect(MicUsage.menuBarSymbol(userNames: ["Zoom"], inputMuted: true) == "mic.slash.fill")
    }

    @Test("the menu bar shows the mixer when nothing uses the microphone, muted or not")
    func menuBarSymbolIdle() {
        #expect(MicUsage.menuBarSymbol(userNames: [], inputMuted: false) == "slider.vertical.3")
        #expect(MicUsage.menuBarSymbol(userNames: [], inputMuted: true) == "slider.vertical.3")
    }

    @Test("the extension hint shows only while Chrome is listed and the extension is not connected")
    func extensionHint() {
        let chrome = [app("com.google.Chrome", name: "Chrome")]
        let canary = [app("com.google.Chrome.canary", name: "Chrome Canary")]
        let other = [app("com.spotify.client", name: "Spotify")]

        #expect(MicUsage.showExtensionHint(extensionConnected: false, apps: chrome))
        #expect(MicUsage.showExtensionHint(extensionConnected: false, apps: canary))
        #expect(!MicUsage.showExtensionHint(extensionConnected: true, apps: chrome))
        #expect(!MicUsage.showExtensionHint(extensionConnected: false, apps: other))
        #expect(!MicUsage.showExtensionHint(extensionConnected: false, apps: []))
    }
}
