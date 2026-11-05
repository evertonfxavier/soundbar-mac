import AppKit
import Combine
import Foundation

/// Tells the user when a newer release is out. It asks GitHub a few seconds after launch, every hour while the app
/// stays open, and when the user opens the menu (at most every few minutes), unless the user turned that off (it is
/// the one thing the app does by itself on the network).
@MainActor
final class Updater: ObservableObject {
    /// The newer release, when there is one.
    @Published private(set) var available: UpdateInfo?
    @Published var checksForUpdates: Bool {
        didSet {
            guard checksForUpdates != oldValue else { return }
            defaults.set(checksForUpdates, forKey: Keys.enabled)
            if checksForUpdates {
                checkNow()
            } else {
                available = nil
            }
        }
    }

    /// How long a result is good for, in seconds, while the app stays open and nobody looks at it: the app can be
    /// left open for days, and the check is cheap but not free. A launch always asks (the answer is not kept between
    /// runs).
    nonisolated static let interval: TimeInterval = 3600

    /// How long a result is good for when the user opens the menu, which is when a stale answer shows. It keeps
    /// opening and closing the menu from asking GitHub every time.
    nonisolated static let openInterval: TimeInterval = 5 * 60

    private enum Keys {
        static let enabled = "checkForUpdates"
        static let lastCheck = "lastUpdateCheck"
    }

    private let checker: UpdateChecker
    private let defaults: UserDefaults
    private var checking = false
    private var timer: Timer?
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(
        checker: UpdateChecker = UpdateChecker(
            current: AppVersion(AppInfo.version) ?? AppVersion("0.0.0")!,
            fetch: UpdateChecker.live(userAgent: "SoundBar/\(AppInfo.version)")),
        defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default
    ) {
        self.checker = checker
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        checksForUpdates = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        // The menu is a window: when it comes up, or the app comes to the front, the user is looking at the answer.
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            observers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.checkIfDue(interval: Self.openInterval) }
                })
        }
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    /// Whether a result from `last` is old enough to ask again at `now`.
    nonisolated static func isDue(last: Date?, now: Date, interval: TimeInterval = Updater.interval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || last > now
    }

    /// Starts the checks: one a few seconds after launch (not while the app is still starting), whatever the time of
    /// the last one, then one every hour while the app stays open.
    func start(launchDelay: TimeInterval = 5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + launchDelay) { [weak self] in
            MainActor.assumeIsolated { self?.checkNow() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    /// Asks if the last answer is older than `interval`.
    func checkIfDue(interval: TimeInterval = Updater.interval) {
        guard Self.isDue(last: defaults.object(forKey: Keys.lastCheck) as? Date, now: Date(), interval: interval)
        else { return }
        checkNow()
    }

    /// Asks in the background unless it is off or already asking, whatever the clock says.
    func checkNow() {
        guard checksForUpdates, !checking else { return }
        checking = true
        Task {
            await check()
            checking = false
        }
    }

    /// Asks now, whatever the clock says. A failure (no network, a rate limit) is not shown: it is tried again later.
    func check() async {
        do {
            let found = try await checker.newerRelease()
            defaults.set(Date(), forKey: Keys.lastCheck)
            if checksForUpdates, found != available { available = found }
        } catch {
            NSLog("SoundBar: update check failed: \(error)")
        }
    }
}
