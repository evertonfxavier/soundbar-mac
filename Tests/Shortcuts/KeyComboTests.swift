import Foundation
import Testing

@Suite("KeyCombo")
struct KeyComboTests {
    private let p: UInt32 = 0x23  // the P key
    private let all = KeyCombo.control | KeyCombo.option | KeyCombo.shift | KeyCombo.command

    @Test("it is written as the menus of the Mac write it: ⌃⌥⇧⌘ then the key")
    func display() {
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.command).display == "⌘P")
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.control | KeyCombo.option).display == "⌃⌥P")
        #expect(KeyCombo(keyCode: p, modifiers: all).display == "⌃⌥⇧⌘P")
        #expect(KeyCombo(keyCode: 0x31, modifiers: KeyCombo.option).display == "⌥Space")
        #expect(KeyCombo(keyCode: 0x7A, modifiers: KeyCombo.control).display == "⌃F1")
        #expect(KeyCombo(keyCode: 0x7E, modifiers: KeyCombo.command).display == "⌘↑")
    }

    @Test("it needs Control, Option or Command: Shift alone would fire while typing")
    func modifiers() {
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.command).isValid)
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.option).isValid)
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.control).isValid)
        #expect(!KeyCombo(keyCode: p, modifiers: KeyCombo.shift).isValid)
        #expect(!KeyCombo(keyCode: p, modifiers: 0).isValid)
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.shift | KeyCombo.command).isValid)
    }

    @Test("a key the app has no name for is not valid")
    func unknownKey() {
        #expect(!KeyCombo(keyCode: 0xFF, modifiers: KeyCombo.command).isValid)
        #expect(KeyCombo(keyCode: 0xFF, modifiers: KeyCombo.command).display == "⌘?")
    }

    @Test("bits that are not modifiers are dropped")
    func dropsOtherBits() {
        #expect(KeyCombo(keyCode: p, modifiers: KeyCombo.command | 0x1).modifiers == KeyCombo.command)
    }

    @Test("it is written and read back")
    func codable() throws {
        let combo = KeyCombo(keyCode: p, modifiers: KeyCombo.command | KeyCombo.option)
        let back = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(back == combo)
    }

    @Test("the modifiers of a key press become the Carbon bits")
    func carbonBits() {
        #expect(KeyCombo.carbonModifiers([.command, .shift]) == KeyCombo.command | KeyCombo.shift)
        #expect(KeyCombo.carbonModifiers([.control, .option]) == KeyCombo.control | KeyCombo.option)
        #expect(KeyCombo.carbonModifiers([]) == 0)
        #expect(KeyCombo.carbonModifiers([.capsLock, .function]) == 0)
    }

    @Test("every key name is unique, so two keys never look alike")
    func namesAreUnique() {
        let names = KeyCombo.keyNames.values
        #expect(Set(names).count == names.count)
    }
}
