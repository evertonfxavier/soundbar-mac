import Foundation
import Testing

/// These register real global shortcuts with the system, on keys nobody uses (F17, F18, F19 with Control, Option and
/// Command), and give them back when the manager goes away.
@Suite("ShortcutManager", .serialized)
@MainActor
struct ShortcutManagerTests {
    private let f17 = KeyCombo(keyCode: 0x40, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)
    private let f18 = KeyCombo(keyCode: 0x4F, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)
    private let f19 = KeyCombo(keyCode: 0x50, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)

    private func defaults() -> UserDefaults {
        let suite = "soundbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("a shortcut is assigned, registered with the system and remembered")
    func assigns() {
        let store = defaults()
        let manager = ShortcutManager(defaults: store)
        #expect(manager.assign(f17, to: .callMute) == .ok)
        #expect(manager.combo(for: .callMute) == f17)

        // a new manager reads it back from the settings and registers it again (the first one still holds the key,
        // so it lets go first)
        _ = manager.assign(nil, to: .callMute)
        let writer = ShortcutManager(defaults: store)
        #expect(writer.assign(f17, to: .callMute) == .ok)
        #expect(ShortcutBindings.decoded(store.data(forKey: "shortcutBindings")).combo(for: .callMute) == f17)
    }

    @Test("what is not a valid shortcut is refused")
    func refusesInvalid() {
        let manager = ShortcutManager(defaults: defaults())
        #expect(manager.assign(KeyCombo(keyCode: 0x23, modifiers: KeyCombo.shift), to: .stopAll) == .invalid)
        #expect(manager.assign(KeyCombo(keyCode: 0xFF, modifiers: KeyCombo.command), to: .stopAll) == .invalid)
        #expect(manager.combo(for: .stopAll) == nil)
    }

    @Test("a combination that another action has is refused, and naming that action")
    func refusesConflict() {
        let manager = ShortcutManager(defaults: defaults())
        #expect(manager.assign(f18, to: .callMute) == .ok)
        #expect(manager.assign(f18, to: .stopAll) == .conflict(.callMute))
        #expect(manager.combo(for: .stopAll) == nil)
        #expect(manager.conflict(for: f18, excluding: .stopAll) == .callMute)
        #expect(manager.conflict(for: f18, excluding: .callMute) == nil)
    }

    @Test("changing the shortcut of an action lets the old one go")
    func changes() {
        let manager = ShortcutManager(defaults: defaults())
        #expect(manager.assign(f17, to: .callMute) == .ok)
        #expect(manager.assign(f18, to: .callMute) == .ok)
        #expect(manager.combo(for: .callMute) == f18)
        // the old combination is free for another action
        #expect(manager.assign(f17, to: .stopAll) == .ok)
    }

    @Test("clearing a shortcut removes it, and is remembered")
    func clears() {
        let store = defaults()
        let manager = ShortcutManager(defaults: store)
        _ = manager.assign(f19, to: .micMute)
        #expect(manager.assign(nil, to: .micMute) == .ok)
        #expect(manager.combo(for: .micMute) == nil)
        #expect(ShortcutBindings.decoded(store.data(forKey: "shortcutBindings")).combos.isEmpty)
    }

    @Test("a combination that another app has is reported as unavailable")
    func unavailable() {
        let first = ShortcutManager(defaults: defaults())
        let second = ShortcutManager(defaults: defaults())
        #expect(first.assign(f19, to: .callMute) == .ok)
        // the system gives a combination to one registration only
        #expect(second.assign(f19, to: .callMute) == .unavailable)
        #expect(second.combo(for: .callMute) == nil)
    }

    @Test("a stored shortcut that the system refuses at launch is dropped")
    func dropsTakenOnLaunch() {
        let holder = ShortcutManager(defaults: defaults())
        #expect(holder.assign(f18, to: .stopAll) == .ok)

        let store = defaults()
        var stored = ShortcutBindings()
        stored.set(f18, for: .callMute)
        store.set(stored.encoded(), forKey: "shortcutBindings")
        let manager = ShortcutManager(defaults: store)

        #expect(manager.combo(for: .callMute) == nil)
        #expect(ShortcutBindings.decoded(store.data(forKey: "shortcutBindings")).combos.isEmpty)
    }

    @Test("pressing a shortcut runs its action")
    func firesTheAction() {
        let center = HotKeyCenter()
        let manager = ShortcutManager(defaults: defaults(), center: center)
        var done: [ShortcutAction] = []
        manager.onAction = { done.append($0) }
        #expect(manager.assign(f17, to: .stopAll) == .ok)

        // the id the system would report is the one the manager registered: id 1 is the first
        center.onPress?(1)
        center.onPress?(99)  // an id nobody has: ignored

        #expect(done == [.stopAll])
    }
}
