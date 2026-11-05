import Foundation
import Testing

@Suite("Sound model")
struct SoundModelTests {
    private func sound(
        _ name: String, group: String? = nil, id: UUID = UUID()
    ) -> Sound {
        Sound(id: id, name: name, icon: .emoji("🔊"), fileName: "\(name).wav", group: group)
    }

    @Test("a library written before groups, trims and normalizing still opens, with their defaults")
    func oldLibraryOpens() throws {
        let id = UUID()
        let json = """
            [{"id": "\(id.uuidString)", "name": "Clap", "icon": {"emoji": {"_0": "👏"}}, "fileName": "a.wav", "volume": 0.5}]
            """
        let sounds = try JSONDecoder().decode([Sound].self, from: Data(json.utf8))
        #expect(sounds.count == 1)
        #expect(sounds[0].name == "Clap")
        #expect(sounds[0].volume == 0.5)
        #expect(sounds[0].group == nil)
        #expect(sounds[0].trimStart == 0)
        #expect(sounds[0].trimEnd == nil)
        #expect(sounds[0].normalize == false)
    }

    @Test("a sound with all its fields survives being written and read")
    func roundTrip() throws {
        var original = sound("Clap", group: "Meetings")
        original.trimStart = 0.25
        original.trimEnd = 1.5
        original.normalize = true
        original.volume = 0.7
        let data = try JSONEncoder().encode([original])
        #expect(try JSONDecoder().decode([Sound].self, from: data) == [original])
    }

    @Test("the gain is the volume of the sound times the master volume, which stays between 0 and 1")
    func gain() {
        var clap = sound("Clap")
        clap.volume = 0.5
        #expect(clap.gain(master: 1) == 0.5)
        #expect(clap.gain(master: 0.5) == 0.25)
        #expect(clap.gain(master: 0) == 0)
        #expect(clap.gain(master: 3) == 0.5)
        #expect(clap.gain(master: -1) == 0)
    }

    @Test("a group shows only its sounds; no group shows all")
    func filterByGroup() {
        let list = [sound("a", group: "X"), sound("b", group: "Y"), sound("c")]
        #expect(SoundFilter.apply(list, group: nil, query: "").map(\.name) == ["a", "b", "c"])
        #expect(SoundFilter.apply(list, group: "X", query: "").map(\.name) == ["a"])
        #expect(SoundFilter.apply(list, group: "none", query: "").isEmpty)
    }

    @Test("the search ignores case and accents, and the spaces around it")
    func filterByQuery() {
        let list = [sound("Aplausos"), sound("Água"), sound("Buzina")]
        #expect(SoundFilter.apply(list, group: nil, query: "aplau").map(\.name) == ["Aplausos"])
        #expect(SoundFilter.apply(list, group: nil, query: "AGUA").map(\.name) == ["Água"])
        #expect(SoundFilter.apply(list, group: nil, query: "  buz ").map(\.name) == ["Buzina"])
        #expect(SoundFilter.apply(list, group: nil, query: "   ").count == 3)
        #expect(SoundFilter.apply(list, group: nil, query: "zzz").isEmpty)
    }

    @Test("group and search work together")
    func filterByBoth() {
        let list = [sound("Clap", group: "X"), sound("Clip", group: "Y"), sound("Clop", group: "X")]
        #expect(SoundFilter.apply(list, group: "X", query: "cl").map(\.name) == ["Clap", "Clop"])
        #expect(SoundFilter.apply(list, group: "X", query: "clip").isEmpty)
    }

    @Test("the groups come in the order they first appear, without repeats or empty names")
    func groupsInOrder() {
        let list = [
            sound("a", group: "B"), sound("b"), sound("c", group: "A"), sound("d", group: "B"), sound("e", group: ""),
        ]
        #expect(SoundFilter.groups(of: list) == ["B", "A"])
        #expect(SoundFilter.groups(of: []).isEmpty)
    }
}
