import Foundation
import Testing

@Suite("ShortcutBindings")
struct ShortcutBindingsTests {
    private let cmdP = KeyCombo(keyCode: 0x23, modifiers: KeyCombo.command)
    private let cmdO = KeyCombo(keyCode: 0x1F, modifiers: KeyCombo.command)

    @Test("an action has the combination it was given")
    func sets() {
        var bindings = ShortcutBindings()
        #expect(bindings.set(cmdP, for: .callMute) == nil)
        #expect(bindings.combo(for: .callMute) == cmdP)
        #expect(bindings.combo(for: .stopAll) == nil)
    }

    @Test("two actions cannot share a combination: the one that has it is named and nothing changes")
    func conflicts() {
        var bindings = ShortcutBindings()
        bindings.set(cmdP, for: .callMute)
        #expect(bindings.set(cmdP, for: .stopAll) == .callMute)
        #expect(bindings.combo(for: .stopAll) == nil)
        #expect(bindings.conflict(for: cmdP) == .callMute)
        #expect(bindings.conflict(for: cmdP, excluding: .callMute) == nil)
    }

    @Test("setting the same combination again on the same action is not a conflict")
    func sameAction() {
        var bindings = ShortcutBindings()
        bindings.set(cmdP, for: .micMute)
        #expect(bindings.set(cmdP, for: .micMute) == nil)
    }

    @Test("nil clears it, and then another action may use it")
    func clears() {
        var bindings = ShortcutBindings()
        bindings.set(cmdP, for: .callMute)
        bindings.set(nil, for: .callMute)
        #expect(bindings.combo(for: .callMute) == nil)
        #expect(bindings.set(cmdP, for: .stopAll) == nil)
    }

    @Test("the shortcut of a sound is its own, by the id of the sound")
    func soundsAreSeparate() {
        let a = UUID()
        let b = UUID()
        var bindings = ShortcutBindings()
        bindings.set(cmdP, for: .sound(a))
        bindings.set(cmdO, for: .sound(b))
        #expect(bindings.combo(for: .sound(a)) == cmdP)
        #expect(bindings.combo(for: .sound(b)) == cmdO)
        #expect(bindings.conflict(for: cmdP, excluding: .sound(b)) == .sound(a))
    }

    @Test("what is written is read back, and what cannot be read is left out")
    func storage() throws {
        let id = UUID()
        var bindings = ShortcutBindings()
        bindings.set(cmdP, for: .callMute)
        bindings.set(cmdO, for: .sound(id))
        #expect(ShortcutBindings.decoded(bindings.encoded()) == bindings)

        // an action that no longer exists, a combination that is not valid, and a bad file
        let stored: [String: KeyCombo] = [
            "callMute": cmdP, "gone": cmdO, "stopAll": KeyCombo(keyCode: 0x23, modifiers: KeyCombo.shift),
            "sound:not-a-uuid": cmdO,
        ]
        let decoded = ShortcutBindings.decoded(try JSONEncoder().encode(stored))
        #expect(decoded.combos == [.callMute: cmdP])
        #expect(ShortcutBindings.decoded(Data("nope".utf8)).combos.isEmpty)
        #expect(ShortcutBindings.decoded(nil).combos.isEmpty)
    }

    @Test("the keys of the actions round-trip")
    func actionKeys() {
        let id = UUID()
        for action in [ShortcutAction.stopAll, .callMute, .micMute, .sound(id)] {
            #expect(ShortcutAction(storageKey: action.storageKey) == action)
        }
        #expect(ShortcutAction(storageKey: "sound:") == nil)
        #expect(ShortcutAction(storageKey: "") == nil)
    }
}
