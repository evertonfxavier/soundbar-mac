import AppKit
import Combine
import CoreAudio
import ServiceManagement

/// The state behind the menu, and what the menu asks for: it watches the apps and the devices, keeps what the user
/// chose for each app, and runs one `AppTap` per app that has a volume or a mute set.
///
/// The rules that need no hardware are in Core/Domain (`AppListing`, `MicUsage`, `AppSetting`) and are tested there.
@MainActor
final class Mixer: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var settings: [String: AppSetting] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var output = DeviceState()
    @Published private(set) var input = DeviceState()
    @Published private(set) var permission: AudioCapturePermission.Status = .unknown
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    @Published private(set) var browserTabs: [BrowserTab] = []
    @Published private(set) var browserConnected = false

    private let bridge = BrowserBridge()

    /// Names of everything currently using the microphone (apps and browser tabs).
    var micUserNames: [String] { MicUsage.userNames(apps: apps, tabs: browserTabs) }

    var menuBarSymbol: String { MicUsage.menuBarSymbol(userNames: micUserNames, inputMuted: input.muted) }

    /// Chrome is audible but the extension isn't connected: tell the user how to get per-tab control.
    var showExtensionHint: Bool { MicUsage.showExtensionHint(extensionConnected: browserConnected, apps: apps) }

    private var taps: [String: AppTap] = [:]
    private var lastActive: [String: Date] = [:]
    private var failedAt: [String: Date] = [:]
    private var timer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private let myPID = ProcessInfo.processInfo.processIdentifier
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: Keys.appSettings),
            let saved = try? JSONDecoder().decode([String: AppSetting].self, from: data)
        {
            settings = saved
        }
        permission = AudioCapturePermission.status()
        bridge.onChange = { [weak self] tabs, connected in
            guard let self else { return }
            let sorted = BrowserTab.sorted(tabs)
            if sorted != self.browserTabs { self.browserTabs = sorted }
            if connected != self.browserConnected { self.browserConnected = connected }
        }
        bridge.start()
        listenForDeviceChanges()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Destroy the taps when the app quits, so the apps that were muted get their audio back at once.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
    }

    private enum Keys {
        static let appSettings = "appSettings"
        static let inputVolumeBeforeMute = "inputVolumeBeforeMute"
    }

    // MARK: - Per-app controls

    func setting(for id: String) -> AppSetting { settings[id] ?? AppSetting() }

    func setVolume(_ volume: Float, for id: String) {
        var s = setting(for: id)
        s.volume = AppSetting.clamp(volume)
        update(s, for: id)
    }

    func toggleMute(_ id: String) {
        var s = setting(for: id)
        s.muted.toggle()
        update(s, for: id)
    }

    func reset(_ id: String) { update(AppSetting(), for: id) }

    private func update(_ s: AppSetting, for id: String) {
        settings[id] = s.isDefault ? nil : s
        persist()
        guard ensurePermission() else { return }
        failedAt[id] = nil
        if let app = apps.first(where: { $0.id == id }) { syncTap(app, allowTeardown: false) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Keys.appSettings) }
    }

    private func ensurePermission() -> Bool {
        permission = AudioCapturePermission.status()
        switch permission {
        case .authorized:
            return true
        case .unknown:
            // Preflight unavailable or never asked: ask, then apply once granted.
            AudioCapturePermission.request { [weak self] granted in
                guard let self else { return }
                self.permission = granted ? .authorized : AudioCapturePermission.status()
                if granted { self.refresh() }
            }
            return false
        case .denied:
            return false
        }
    }

    func requestPermission() {
        if AudioCapturePermission.status() == .denied {
            NSWorkspace.shared.open(AudioCapturePermission.settingsURL)
        } else {
            _ = ensurePermission()
        }
    }

    // MARK: - Browser tab controls (via Chrome extension)

    func setTabVolume(_ tab: BrowserTab, _ v: Float) {
        updateTab(tab.id) { $0.volume = v }
        bridge.send(to: tab, volume: v)
    }

    func toggleTabMute(_ tab: BrowserTab) {
        let m = !tab.muted
        updateTab(tab.id) { $0.muted = m }
        bridge.send(to: tab, muted: m)
    }

    func toggleTabMic(_ tab: BrowserTab) {
        let m = !tab.micMuted
        updateTab(tab.id) { $0.micMuted = m }
        bridge.send(to: tab, micMuted: m)
    }

    func resetTab(_ tab: BrowserTab) {
        updateTab(tab.id) {
            $0.volume = 1
            $0.muted = false
            $0.micMuted = false
        }
        bridge.send(to: tab, volume: 1, muted: false, micMuted: false)
    }

    private func updateTab(_ id: String, _ change: (inout BrowserTab) -> Void) {
        if let i = browserTabs.firstIndex(where: { $0.id == id }) { change(&browserTabs[i]) }
    }

    // MARK: - Device controls

    func setOutputVolume(_ v: Float) {
        DeviceControl.setVolume(output.id, input: false, v)
        output.volume = v
    }

    func toggleOutputMute() {
        DeviceControl.setMuted(output.id, input: false, !output.muted)
        refreshDevices()
    }

    func setInputVolume(_ v: Float) {
        DeviceControl.setVolume(input.id, input: true, v)
        input.volume = v
        if v > 0 { defaults.set(v, forKey: Keys.inputVolumeBeforeMute) }
    }

    /// Mutes the default microphone, for every app. Falls back to volume 0 when the
    /// device has no mute control (common on built-in mics).
    func toggleInputMute() {
        let dev = input.id
        if DeviceControl.hasMute(dev, input: true) {
            DeviceControl.setMuted(dev, input: true, !input.muted)
        } else if input.muted {
            let restore = defaults.object(forKey: Keys.inputVolumeBeforeMute) as? Float ?? 0.75
            DeviceControl.setVolume(dev, input: true, restore)
        } else {
            defaults.set(input.volume, forKey: Keys.inputVolumeBeforeMute)
            DeviceControl.setVolume(dev, input: true, 0)
        }
        refreshDevices()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("SoundBar: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Refresh loop

    func refresh() {
        let procs = ProcessScanner.scan().filter { $0.pid != myPID }
        ProcessScanner.forget(pidsNotIn: Set(procs.map(\.pid)))

        let groups = AppListing.group(procs, ownerOf: ProcessScanner.owner(for:))

        let now = Date()
        for g in groups.values where g.isPlaying || g.isUsingMic { lastActive[g.id] = now }

        if permission != .authorized { permission = AudioCapturePermission.status() }
        if permission == .authorized {
            for g in groups.values { syncTap(g, allowTeardown: true) }
        }
        for id in Array(taps.keys) where groups[id] == nil {
            taps[id]?.stop()
            taps[id] = nil
        }

        let visible = AppListing.visible(
            Array(groups.values), settings: settings, lastActive: lastActive,
            hideBrowsers: browserConnected && !browserTabs.isEmpty, now: now)
        if visible != apps { apps = visible }

        refreshDevices()
    }

    private func syncTap(_ app: AudioApp, allowTeardown: Bool) {
        let s = setting(for: app.id)
        let existing = taps[app.id]

        if s.isDefault {
            if allowTeardown, let existing {
                existing.stop()
                taps[app.id] = nil
            } else {
                existing?.setGain(1)
            }
            return
        }

        let targetUID = app.outputDeviceUID ?? existing?.outputUID ?? CA.deviceUID(CA.defaultDevice(input: false))
        guard let targetUID else { return }

        if let existing, existing.objectIDs == Set(app.objectIDs), existing.outputUID == targetUID {
            existing.setGain(s.gain)
            return
        }

        if let failed = failedAt[app.id], Date().timeIntervalSince(failed) < 5 { return }

        existing?.stop()
        taps[app.id] = nil
        do {
            taps[app.id] = try AppTap(objectIDs: app.objectIDs, outputUID: targetUID, gain: s.gain, label: app.name)
            errors[app.id] = nil
            failedAt[app.id] = nil
        } catch {
            errors[app.id] = error.localizedDescription
            failedAt[app.id] = Date()
            NSLog("SoundBar: tap for \(app.id) failed: \(error)")
        }
    }

    private func refreshDevices() {
        output = deviceState(input: false)
        input = deviceState(input: true)
    }

    private func deviceState(input isInput: Bool) -> DeviceState {
        let dev = CA.defaultDevice(input: isInput)
        guard dev != kAudioObjectUnknown else { return DeviceState() }
        let hasVol = DeviceControl.hasVolume(dev, input: isInput)
        let vol = DeviceControl.volume(dev, input: isInput) ?? 1
        var muted = DeviceControl.isMuted(dev, input: isInput)
        if isInput, !DeviceControl.hasMute(dev, input: true), hasVol, vol <= 0.001 { muted = true }
        return DeviceState(id: dev, name: CA.deviceName(dev), volume: vol, muted: muted, hasVolume: hasVol)
    }

    private func listenForDeviceChanges() {
        for sel in [
            kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyProcessObjectList,
        ] {
            var addr = CA.address(sel)
            AudioObjectAddPropertyListenerBlock(CA.system, &addr, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    func shutdown() {
        for tap in taps.values { tap.stop() }
        taps.removeAll()
    }
}
