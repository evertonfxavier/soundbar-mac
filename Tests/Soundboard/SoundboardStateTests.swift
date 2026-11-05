import Foundation
import Testing

@Suite("Soundboard state")
@MainActor
struct SoundboardStateTests {
    @MainActor private struct Setup {
        let folder = TestAudio.temporaryDirectory()
        let defaults: UserDefaults
        let board: Soundboard

        init(existing defaults: UserDefaults? = nil, folder shared: URL? = nil) {
            let suite = "soundbar-tests-\(UUID().uuidString)"
            let store = defaults ?? UserDefaults(suiteName: suite)!
            store.removePersistentDomain(forName: suite)
            self.defaults = store
            let directory = shared ?? folder
            board = Soundboard(
                library: SoundLibrary(directory: directory.appendingPathComponent("lib")),
                shortcuts: ShortcutManager(defaults: store), defaults: store)
        }

        func audio(_ name: String) throws -> URL {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
            return try TestAudio.writeWAV(to: folder.appendingPathComponent("src").appendingPathComponent(name))
        }

        func add(_ name: String, group: String? = nil) throws {
            try board.add(.init(name: name, icon: .emoji("x"), audio: try audio("\(name).wav"), group: group))
        }

        /// The soundboard only plays with the virtual microphone around: this is what the 1 s refresh learns.
        func installBlackHole() {
            board.update(
                processes: [],
                devices: [
                    .init(uid: "BlackHole2ch_UID", name: "BlackHole 2ch", hasInput: true, hasOutput: true)
                ])
        }

        func cleanup() { try? FileManager.default.removeItem(at: folder) }
    }

    @Test("the master volume is kept between 0 and 1 and remembered")
    func masterVolume() {
        let setup = Setup()
        defer { setup.cleanup() }
        #expect(setup.board.masterVolume == 1)
        setup.board.setMasterVolume(0.4)
        #expect(setup.board.masterVolume == 0.4)
        setup.board.setMasterVolume(7)
        #expect(setup.board.masterVolume == 1)
        setup.board.setMasterVolume(-1)
        #expect(setup.board.masterVolume == 0)
        setup.board.setMasterVolume(0.25)
        #expect(Setup(existing: setup.defaults, folder: setup.folder).board.masterVolume == 0.25)
    }

    @Test("sending to the call is on by default, and the choice is remembered")
    func sendsToCall() {
        let setup = Setup()
        defer { setup.cleanup() }
        #expect(setup.board.sendsToCall)
        setup.board.setSendsToCall(false)
        #expect(!setup.board.sendsToCall)
        #expect(!Setup(existing: setup.defaults, folder: setup.folder).board.sendsToCall)
    }

    @Test("without BlackHole the soundboard is off, with it (even before a call) it is on")
    func availability() {
        let setup = Setup()
        defer { setup.cleanup() }
        let mic = SoundboardRouting.Device(uid: "mic", name: "Microfone", hasInput: true, hasOutput: false)
        let blackHole = SoundboardRouting.Device(
            uid: "BlackHole2ch_UID", name: "BlackHole 2ch", hasInput: true, hasOutput: true)

        #expect(!setup.board.isAvailable)
        setup.board.update(processes: [], devices: [mic])
        #expect(!setup.board.isAvailable)
        setup.board.update(processes: [], devices: [mic, blackHole])
        #expect(setup.board.isAvailable)
        setup.board.update(processes: [], devices: [mic])
        #expect(!setup.board.isAvailable)
    }

    @Test("without BlackHole a sound does not play, not from the menu nor from a shortcut")
    func offWithoutBlackHole() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("Clap")
        let sound = setup.board.sounds[0]
        // A sound whose file is gone cannot play: playing it is how we tell that play() ran.
        try FileManager.default.removeItem(at: setup.board.library.audioURL(for: sound))

        setup.board.play(sound)
        setup.board.perform(.sound(sound.id))
        #expect(setup.board.errorMessage == nil)

        setup.installBlackHole()
        setup.board.play(sound)
        #expect(setup.board.errorMessage != nil)
    }

    @Test("the call can only be muted while the sounds are going into a call")
    func callMuteNeedsACall() {
        let setup = Setup()
        defer { setup.cleanup() }
        setup.board.toggleCallMute()
        #expect(!setup.board.callMuted)
    }

    @Test("the grid shows the group that is selected, and the search")
    func visible() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("Clap", group: "Fun")
        try setup.add("Clock", group: "Work")
        try setup.add("Horn")

        #expect(setup.board.visibleSounds.map(\.name) == ["Clap", "Clock", "Horn"])
        #expect(setup.board.groups == ["Fun", "Work"])
        setup.board.selectedGroup = "Fun"
        #expect(setup.board.visibleSounds.map(\.name) == ["Clap"])
        setup.board.query = "clo"
        #expect(setup.board.visibleSounds.isEmpty)
        setup.board.selectedGroup = nil
        #expect(setup.board.visibleSounds.map(\.name) == ["Clock"])
    }

    @Test("when the last sound of the selected group goes, the group is left")
    func groupDisappears() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("Clap", group: "Fun")
        try setup.add("Horn")
        setup.board.selectedGroup = "Fun"
        setup.board.remove(setup.board.sounds[0])
        #expect(setup.board.selectedGroup == nil)
        #expect(setup.board.visibleSounds.map(\.name) == ["Horn"])
    }

    @Test("moving a sound changes the order the grid shows")
    func ordering() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("a")
        try setup.add("b")
        try setup.add("c")
        let sounds = setup.board.sounds
        setup.board.move(sounds[2], before: sounds[0])
        #expect(setup.board.sounds.map(\.name) == ["c", "a", "b"])
        setup.board.shift(sounds[0], by: 1)
        #expect(setup.board.sounds.map(\.name) == ["c", "b", "a"])
        setup.board.move(sounds[2], before: nil)
        #expect(setup.board.sounds.map(\.name) == ["b", "a", "c"])
    }

    @Test("removing a sound gives back its shortcut")
    func removingFreesTheShortcut() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("a")
        let sound = setup.board.sounds[0]
        let combo = KeyCombo(keyCode: 0x5A, modifiers: KeyCombo.control | KeyCombo.option | KeyCombo.command)
        #expect(setup.board.shortcuts.assign(combo, to: .sound(sound.id)) == .ok)
        setup.board.remove(sound)
        #expect(setup.board.shortcuts.combo(for: .sound(sound.id)) == nil)
        #expect(setup.board.shortcuts.assign(combo, to: .stopAll) == .ok)
    }

    @Test("a shortcut of a sound plays it; one of a sound that is gone does nothing")
    func performSound() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("a")
        setup.board.perform(.sound(setup.board.sounds[0].id))
        setup.board.perform(.sound(UUID()))
        setup.board.perform(.stopAll)
        setup.board.perform(.micMute)
        #expect(setup.board.errorMessage == nil)
    }

    @Test("a section that leaves nothing is reported, not played")
    func emptyTrimIsReported() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.board.add(
            .init(
                name: "a", icon: .emoji("x"), audio: try setup.audio("a.wav"), trimStart: 5, trimEnd: nil))
        setup.installBlackHole()
        setup.board.perform(.sound(setup.board.sounds[0].id))
        #expect(setup.board.errorMessage == AudioDecoder.DecodeError.emptyTrim.errorDescription)
    }

    @Test("the library can be exported and imported through the soundboard")
    func exportImport() throws {
        let setup = Setup()
        let other = Setup()
        defer {
            setup.cleanup()
            other.cleanup()
        }
        try setup.add("a")
        let zip = setup.folder.appendingPathComponent("lib.zip")
        try setup.board.exportLibrary(to: zip)
        let result = try other.board.importLibrary(from: zip)
        #expect(result.added == 1)
        #expect(other.board.sounds.map(\.name) == ["a"])
    }

    @Test("the problem with a shortcut is told in words, and nothing when it went well")
    func shortcutProblems() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("Clap")
        let clap = setup.board.sounds[0]
        #expect(setup.board.problem(with: .ok) == nil)
        #expect(setup.board.problem(with: .invalid) == L.shortcutNeedsModifier.string)
        #expect(setup.board.problem(with: .unavailable) == L.shortcutUnavailable.string)
        #expect(setup.board.problem(with: .conflict(.sound(clap.id))) == L.shortcutInUse.formatted("Clap"))
        #expect(setup.board.problem(with: .conflict(.callMute)) == L.shortcutInUse.formatted(L.actionCallMute.string))
    }

    @Test("the names of the actions are those of the sounds, or the action")
    func actionNames() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        try setup.add("Clap")
        #expect(setup.board.name(of: .sound(setup.board.sounds[0].id)) == "Clap")
        #expect(setup.board.name(of: .sound(UUID())) == "?")
        #expect(setup.board.name(of: .stopAll) == L.actionStopAll.string)
        #expect(setup.board.name(of: .micMute) == L.actionMicMute.string)
    }

    @Test("the preview plays the part that is kept, at the volume of the sound times the master volume")
    func previewPlayer() throws {
        let setup = Setup()
        defer { setup.cleanup() }
        let url = try TestAudio.writeWAV(
            to: setup.folder.appendingPathComponent("p.wav"), sampleRate: 8000, seconds: 2, values: [0.3])
        setup.board.setMasterVolume(0.5)

        let whole = try setup.board.previewPlayer(url: url, trimStart: 0, trimEnd: nil, normalize: false, volume: 0.8)
        let part = try setup.board.previewPlayer(url: url, trimStart: 0.5, trimEnd: 1.0, normalize: true, volume: 1)

        #expect(abs(whole.duration - 2) < 0.05)
        #expect(abs(whole.volume - 0.4) < 0.001)
        #expect(abs(part.duration - 0.5) < 0.05)
        #expect(abs(part.volume - 0.5) < 0.001)
        #expect(throws: AudioDecoder.DecodeError.emptyTrim) {
            try setup.board.previewPlayer(url: url, trimStart: 5, trimEnd: nil, normalize: false, volume: 1)
        }
    }
}
