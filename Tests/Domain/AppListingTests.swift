import CoreAudio
import Foundation
import Testing

@Suite("AppListing")
struct AppListingTests {
    private func process(
        _ object: UInt32, pid: pid_t, output: Bool = false, input: Bool = false, device: String? = nil
    ) -> AudioProcess {
        AudioProcess(
            objectID: AudioObjectID(object), pid: pid, isRunningOutput: output, isRunningInput: input,
            outputDeviceUID: device)
    }

    private func app(
        _ id: String, name: String? = nil, playing: Bool = false, mic: Bool = false
    ) -> AudioApp {
        AudioApp(
            id: id, name: name ?? id, icon: nil, objectIDs: [1], isPlaying: playing, isUsingMic: mic,
            outputDeviceUID: nil)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - group

    @Test("the processes of one app are one entry, with every audio object it owns")
    func groupsByOwner() {
        let processes = [
            process(1, pid: 100, output: true), process(2, pid: 101), process(3, pid: 200, input: true),
        ]
        let owners: [pid_t: AppOwner] = [
            100: AppOwner(id: "chrome", name: "Chrome", icon: nil),
            101: AppOwner(id: "chrome", name: "Chrome", icon: nil),
            200: AppOwner(id: "zoom", name: "Zoom", icon: nil),
        ]

        let groups = AppListing.group(processes) { owners[$0]! }

        #expect(Set(groups.keys) == ["chrome", "zoom"])
        #expect(groups["chrome"]?.objectIDs == [1, 2])
        #expect(groups["chrome"]?.isPlaying == true)
        #expect(groups["chrome"]?.isUsingMic == false)
        #expect(groups["zoom"]?.isPlaying == false)
        #expect(groups["zoom"]?.isUsingMic == true)
    }

    @Test("an app plays while any of its processes does, and sends to the first device it was heard on")
    func playingAndDevice() {
        let processes = [
            process(1, pid: 1),  // silent: says nothing about a device
            process(2, pid: 2, output: true, device: "speakers"),
            process(3, pid: 3, output: true, device: "headphones"),
        ]

        let group = AppListing.group(processes) { _ in AppOwner(id: "app", name: "App", icon: nil) }["app"]

        #expect(group?.isPlaying == true)
        #expect(group?.outputDeviceUID == "speakers")
    }

    @Test("no processes, no apps")
    func empty() {
        #expect(AppListing.group([]) { _ in AppOwner(id: "x", name: "x", icon: nil) }.isEmpty)
    }

    // MARK: - visible

    @Test("apps that play, or use the microphone, are listed; silent ones nobody touched are not")
    func listsWhatIsActive() {
        let apps = [app("a", playing: true), app("b", mic: true), app("c")]

        let visible = AppListing.visible(apps, settings: [:], lastActive: [:], hideBrowsers: false, now: now)

        #expect(Set(visible.map(\.id)) == ["a", "b"])
    }

    @Test("an app the user changed stays listed while silent")
    func keepsChangedApps() {
        let visible = AppListing.visible(
            [app("c")], settings: ["c": AppSetting(volume: 0.5)], lastActive: [:], hideBrowsers: false, now: now)

        #expect(visible.map(\.id) == ["c"])
    }

    @Test("an app that went quiet lingers for fifteen seconds, then goes")
    func lingers() {
        let apps = [app("c")]
        func listed(secondsAgo: TimeInterval) -> Bool {
            !AppListing.visible(
                apps, settings: [:], lastActive: ["c": now.addingTimeInterval(-secondsAgo)],
                hideBrowsers: false, now: now
            ).isEmpty
        }

        #expect(AppListing.lingerSeconds == 15)
        #expect(listed(secondsAgo: 14.9))
        #expect(!listed(secondsAgo: 15))
        #expect(!listed(secondsAgo: 60))
    }

    @Test("Chrome is left out while the extension lists its tabs, unless the user changed it")
    func hidesBrowsers() {
        let chrome = "com.google.Chrome"
        let apps = [app(chrome, playing: true), app("spotify", playing: true)]

        let hidden = AppListing.visible(apps, settings: [:], lastActive: [:], hideBrowsers: true, now: now)
        #expect(hidden.map(\.id) == ["spotify"])

        let shown = AppListing.visible(apps, settings: [:], lastActive: [:], hideBrowsers: false, now: now)
        #expect(Set(shown.map(\.id)) == [chrome, "spotify"])

        let changed = AppListing.visible(
            apps, settings: [chrome: AppSetting(muted: true)], lastActive: [:], hideBrowsers: true, now: now)
        #expect(Set(changed.map(\.id)) == [chrome, "spotify"])
    }

    @Test("the apps playing come first, then the rest by name, ignoring case")
    func sorting() {
        let apps = [
            app("z", name: "Zoom", mic: true), app("m", name: "music", playing: true),
            app("b", name: "Brave", mic: true), app("a", name: "Apple Music", playing: true),
        ]

        let visible = AppListing.visible(apps, settings: [:], lastActive: [:], hideBrowsers: false, now: now)

        #expect(visible.map(\.name) == ["Apple Music", "music", "Brave", "Zoom"])
    }
}
