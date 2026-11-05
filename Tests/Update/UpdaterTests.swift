import AppKit
import Foundation
import Testing

@Suite("Updater")
@MainActor
struct UpdaterTests {
    private let current = AppVersion("0.1.2")!

    private func defaults() -> UserDefaults {
        let suite = "soundbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private nonisolated static func release(_ tag: String) -> Data {
        let repo = UpdateChecker.repository
        return Data(
            """
            {"tag_name": "\(tag)", "html_url": "https://github.com/\(repo)/releases/tag/\(tag)", "assets": []}
            """.utf8)
    }

    @Test("it is due when it never asked, or a while ago, or the clock went backwards")
    func isDue() {
        let now = Date()
        #expect(Updater.isDue(last: nil, now: now))
        #expect(Updater.isDue(last: now.addingTimeInterval(-Updater.interval), now: now))
        #expect(!Updater.isDue(last: now.addingTimeInterval(-Updater.interval + 60), now: now))
        #expect(!Updater.isDue(last: now, now: now))
        #expect(Updater.isDue(last: now.addingTimeInterval(3600), now: now))
    }

    @Test("a newer release becomes the available update, and the time of the check is kept")
    func findsUpdate() async {
        let store = defaults()
        let updater = Updater(checker: UpdateChecker(current: current) { _ in Self.release("v0.1.3") }, defaults: store)
        await updater.check()
        #expect(updater.available?.version.description == "0.1.3")
        #expect(store.object(forKey: "lastUpdateCheck") as? Date != nil)
    }

    @Test("when up to date there is nothing available, and it clears an update that has since gone")
    func upToDate() async {
        let answer = Locked("v0.1.3")
        let updater = Updater(
            checker: UpdateChecker(current: current) { _ in Self.release(answer.value) }, defaults: defaults())
        await updater.check()
        #expect(updater.available != nil)
        answer.value = "v0.1.2"
        await updater.check()
        #expect(updater.available == nil)
    }

    @Test("a failed check changes nothing, and does not count as having asked")
    func failure() async {
        let store = defaults()
        let updater = Updater(
            checker: UpdateChecker(current: current) { _ in throw UpdateError.http(403) }, defaults: store)
        await updater.check()
        #expect(updater.available == nil)
        #expect(store.object(forKey: "lastUpdateCheck") == nil)
    }

    @Test("it is on by default, and switching it off is remembered and hides the update")
    func switchOff() async {
        let store = defaults()
        let updater = Updater(checker: UpdateChecker(current: current) { _ in Self.release("v0.1.3") }, defaults: store)
        #expect(updater.checksForUpdates)
        await updater.check()
        #expect(updater.available != nil)

        updater.checksForUpdates = false

        #expect(updater.available == nil)
        #expect(store.bool(forKey: "checkForUpdates") == false)
        #expect(
            !Updater(checker: UpdateChecker(current: current) { _ in Self.release("v0.1.3") }, defaults: store)
                .checksForUpdates)
    }

    @Test("switched off, it does not ask")
    func offDoesNotAsk() async throws {
        let store = defaults()
        let asked = Locked(0)
        let updater = Updater(
            checker: UpdateChecker(current: current) { _ in
                asked.value += 1
                return Self.release("v0.1.3")
            }, defaults: store)
        updater.checksForUpdates = false
        updater.checkIfDue()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(asked.value == 0)
    }
}

private final class Locked<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite("Updater at launch")
@MainActor
struct UpdaterLaunchTests {
    private func defaults(lastCheck: Date?) -> UserDefaults {
        let suite = "soundbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let lastCheck { defaults.set(lastCheck, forKey: "lastUpdateCheck") }
        return defaults
    }

    @Test("starting asks right away, even if it asked a minute ago (the answer is not kept between runs)")
    func launchAsksEvenIfAskedRecently() async throws {
        let asked = Counter()
        let updater = Updater(
            checker: UpdateChecker(current: AppVersion("0.1.2")!) { _ in
                asked.count += 1
                return Self.releaseData("v0.1.4")
            }, defaults: defaults(lastCheck: Date().addingTimeInterval(-60)))

        updater.start(launchDelay: 0)
        #expect(await eventually { updater.available != nil })

        #expect(asked.count == 1)
        #expect(updater.available?.version.description == "0.1.4")
    }

    @Test("the periodic check respects the interval")
    func periodicCheckIsThrottled() async throws {
        let asked = Counter()
        let updater = Updater(
            checker: UpdateChecker(current: AppVersion("0.1.2")!) { _ in
                asked.count += 1
                return Self.releaseData("v0.1.4")
            }, defaults: defaults(lastCheck: Date().addingTimeInterval(-60)))

        updater.checkIfDue()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(asked.count == 0)
    }

    @Test("switching the check back on asks at once")
    func switchingOnAsks() async throws {
        let asked = Counter()
        let store = defaults(lastCheck: Date())
        store.set(false, forKey: "checkForUpdates")
        let updater = Updater(
            checker: UpdateChecker(current: AppVersion("0.1.2")!) { _ in
                asked.count += 1
                return Self.releaseData("v0.1.4")
            }, defaults: store)
        #expect(!updater.checksForUpdates)

        updater.checksForUpdates = true
        #expect(await eventually { updater.available != nil })

        #expect(asked.count == 1)
    }

    private nonisolated static func releaseData(_ tag: String) -> Data {
        let repo = UpdateChecker.repository
        return Data(
            """
            {"tag_name": "\(tag)", "html_url": "https://github.com/\(repo)/releases/tag/\(tag)", "assets": []}
            """.utf8)
    }
}

private final class Counter: @unchecked Sendable {
    var count = 0
}

@Suite("Updater when the menu opens")
@MainActor
struct UpdaterMenuOpenTests {
    private nonisolated static func releaseData(_ tag: String) -> Data {
        let repo = UpdateChecker.repository
        return Data(
            """
            {"tag_name": "\(tag)", "html_url": "https://github.com/\(repo)/releases/tag/\(tag)", "assets": []}
            """.utf8)
    }

    private func updater(lastCheck: Date?, asked: Counter, center: NotificationCenter) -> Updater {
        let suite = "soundbar-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        if let lastCheck { store.set(lastCheck, forKey: "lastUpdateCheck") }
        return Updater(
            checker: UpdateChecker(current: AppVersion("0.1.0")!) { _ in
                asked.count += 1
                return Self.releaseData("v0.1.7")
            }, defaults: store, notificationCenter: center)
    }

    @Test("opening the menu asks again when the last answer is older than a few minutes, and shows the new version")
    func menuOpenAsksWhenStale() async throws {
        let center = NotificationCenter()
        let asked = Counter()
        let updater = updater(
            lastCheck: Date().addingTimeInterval(-Updater.openInterval - 60), asked: asked, center: center)

        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        #expect(await eventually { updater.available != nil })

        #expect(asked.count == 1)
        #expect(updater.available?.version.description == "0.1.7")
    }

    @Test("opening the menu again right away does not ask again")
    func menuOpenIsThrottled() async throws {
        let center = NotificationCenter()
        let asked = Counter()
        let updater = updater(lastCheck: Date().addingTimeInterval(-60), asked: asked, center: center)

        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(asked.count == 0)
        #expect(updater.available == nil)
    }

    @Test("the app coming to the front asks too, and two notices at once ask only once")
    func becomingActiveAsksOnce() async throws {
        let center = NotificationCenter()
        let asked = Counter()
        let updater = updater(lastCheck: nil, asked: asked, center: center)

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        #expect(await eventually { updater.available != nil })

        #expect(asked.count == 1)
    }

    @Test("with the check switched off, opening the menu asks nothing")
    func offMeansOff() async throws {
        let center = NotificationCenter()
        let asked = Counter()
        let updater = updater(lastCheck: nil, asked: asked, center: center)
        updater.checksForUpdates = false
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = asked.count

        center.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(asked.count == before)
        #expect(updater.available == nil)
    }

    @Test("the hourly check respects its own, longer interval")
    func hourlyInterval() {
        #expect(Updater.interval == 3600)
        #expect(Updater.openInterval < Updater.interval)
    }
}
