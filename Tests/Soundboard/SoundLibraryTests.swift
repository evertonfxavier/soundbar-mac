import AppKit
import Foundation
import Testing

@Suite("SoundLibrary")
struct SoundLibraryTests {
    /// A library in a folder of its own, and a place to make source files; both are removed by `cleanup`.
    private struct Sandbox {
        let folder = TestAudio.temporaryDirectory()
        var libraryDirectory: URL { folder.appendingPathComponent("library") }
        var sources: URL { folder.appendingPathComponent("sources") }

        func library() -> SoundLibrary { SoundLibrary(directory: libraryDirectory) }

        func audio(_ name: String = "clap.wav", seconds: Double = 0.2) throws -> URL {
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            return try TestAudio.writeWAV(to: sources.appendingPathComponent(name), seconds: seconds)
        }

        func png(_ name: String = "icon.png", width: Int = 300, height: Int = 200) throws -> URL {
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let url = sources.appendingPathComponent(name)
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            return url
        }

        func files(in subfolder: String) -> [String] {
            let url = libraryDirectory.appendingPathComponent(subfolder)
            return ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
        }

        func cleanup() { try? FileManager.default.removeItem(at: folder) }
    }

    @Test("adding a sound copies the audio in, so the original can go away, and the sound survives a restart")
    func addCopiesAndPersists() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let source = try box.audio()

        let library = box.library()
        let sound = try library.add(.init(name: "Aplausos", icon: .emoji("👏"), audio: source, volume: 0.6))
        try FileManager.default.removeItem(at: source)

        #expect(FileManager.default.fileExists(atPath: library.audioURL(for: sound).path))
        let reopened = box.library()
        #expect(reopened.sounds == [sound])
        #expect(reopened.sounds[0].name == "Aplausos")
        #expect(reopened.sounds[0].icon == .emoji("👏"))
        #expect(reopened.sounds[0].volume == 0.6)
    }

    @Test("without a name the sound is called after its file")
    func nameFromFile() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let sound = try box.library().add(.init(name: "  ", icon: .emoji(""), audio: try box.audio("buzina.wav")))
        #expect(sound.name == "buzina")
    }

    @Test("an emoji icon is one character, and an empty one becomes the default")
    func emojiIcon() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let long = try library.add(.init(name: "a", icon: .emoji(" 🎉🎉 x"), audio: try box.audio()))
        let empty = try library.add(.init(name: "b", icon: .emoji("   "), audio: try box.audio()))
        #expect(long.icon == .emoji("🎉"))
        #expect(empty.icon == .emoji(Sound.defaultEmoji))
    }

    @Test("an image icon is saved as a 128 pixel square PNG")
    func imageIcon() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let sound = try library.add(.init(name: "a", icon: .image(try box.png()), audio: try box.audio()))

        guard case .image(let fileName) = sound.icon else {
            Issue.record("the icon should be an image")
            return
        }
        #expect(box.files(in: "icons") == [fileName])
        let rep = NSBitmapImageRep(
            data: try Data(contentsOf: box.libraryDirectory.appendingPathComponent("icons/\(fileName)")))
        #expect(rep?.pixelsWide == 128)
        #expect(rep?.pixelsHigh == 128)
        #expect(library.image(named: fileName) != nil)
    }

    @Test("the volume is kept between 0 and 1")
    func volumeClamped() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let loud = try library.add(.init(name: "a", icon: .emoji("x"), audio: try box.audio(), volume: 4))
        let silent = try library.add(.init(name: "b", icon: .emoji("x"), audio: try box.audio(), volume: -1))
        #expect(loud.volume == 1)
        #expect(silent.volume == 0)
    }

    @Test("a sound needs an audio file")
    func needsAudio() {
        let box = Sandbox()
        defer { box.cleanup() }
        #expect(throws: SoundLibrary.LibraryError.noAudio) {
            try box.library().add(.init(name: "a", icon: .emoji("x"), audio: nil))
        }
    }

    @Test("a file that is not audio, or is too long, is refused and leaves nothing behind")
    func refusesBadAudio() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        try FileManager.default.createDirectory(at: box.sources, withIntermediateDirectories: true)
        let text = box.sources.appendingPathComponent("a.mp3")
        try Data("not audio".utf8).write(to: text)
        let long = try box.audio("long.wav", seconds: AudioDecoder.maxDuration + 1)

        #expect(throws: AudioDecoder.DecodeError.unreadable) {
            try library.add(.init(name: "a", icon: .emoji("x"), audio: text))
        }
        #expect(throws: AudioDecoder.DecodeError.self) {
            try library.add(.init(name: "b", icon: .emoji("x"), audio: long))
        }
        #expect(library.sounds.isEmpty)
        #expect(box.files(in: "sounds").isEmpty)
    }

    @Test("an unreadable image refuses the sound and removes the audio it had copied")
    func refusesBadImage() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let notImage = box.sources.appendingPathComponent("x.png")
        let audio = try box.audio()
        try Data("nope".utf8).write(to: notImage)
        let library = box.library()

        #expect(throws: SoundLibrary.LibraryError.iconUnreadable) {
            try library.add(.init(name: "a", icon: .image(notImage), audio: audio))
        }
        #expect(library.sounds.isEmpty)
        #expect(box.files(in: "sounds").isEmpty)
    }

    @Test("changing a sound keeps what was not changed, and replaces the old audio file")
    func updateKeepsAndReplaces() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let original = try library.add(.init(name: "old", icon: .emoji("🎺"), audio: try box.audio("a.wav")))

        try library.update(original.id, with: .init(name: "new", icon: .keep, audio: nil, volume: 0.3))
        #expect(library.sounds[0].name == "new")
        #expect(library.sounds[0].icon == .emoji("🎺"))
        #expect(library.sounds[0].fileName == original.fileName)
        #expect(library.sounds[0].volume == 0.3)

        try library.update(original.id, with: .init(name: "new", icon: .keep, audio: try box.audio("b.wav")))
        #expect(library.sounds[0].fileName != original.fileName)
        #expect(box.files(in: "sounds") == [library.sounds[0].fileName])
        #expect(box.library().sounds == library.sounds)
    }

    @Test("changing the icon image removes the old image")
    func updateReplacesImage() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let sound = try library.add(.init(name: "a", icon: .image(try box.png("one.png")), audio: try box.audio()))
        #expect(box.files(in: "icons").count == 1)

        try library.update(sound.id, with: .init(name: "a", icon: .image(try box.png("two.png")), audio: nil))
        #expect(box.files(in: "icons").count == 1)

        try library.update(sound.id, with: .init(name: "a", icon: .emoji("🎉"), audio: nil))
        #expect(box.files(in: "icons").isEmpty)
    }

    @Test("a failed change leaves the sound as it was")
    func failedUpdate() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let sound = try library.add(.init(name: "a", icon: .emoji("🎺"), audio: try box.audio()))
        let notImage = box.sources.appendingPathComponent("x.png")
        try Data("nope".utf8).write(to: notImage)

        #expect(throws: SoundLibrary.LibraryError.iconUnreadable) {
            try library.update(sound.id, with: .init(name: "z", icon: .image(notImage), audio: try box.audio("c.wav")))
        }
        #expect(library.sounds == [sound])
        #expect(box.files(in: "sounds") == [sound.fileName])
    }

    @Test("removing a sound deletes its files and forgets it")
    func remove() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let sound = try library.add(.init(name: "a", icon: .image(try box.png()), audio: try box.audio()))
        let keep = try library.add(.init(name: "b", icon: .emoji("x"), audio: try box.audio("k.wav")))

        library.remove(sound.id)

        #expect(library.sounds == [keep])
        #expect(box.files(in: "sounds") == [keep.fileName])
        #expect(box.files(in: "icons").isEmpty)
        #expect(box.library().sounds == [keep])
        library.remove(UUID())  // an unknown id is not an error
        #expect(library.sounds == [keep])
    }

    @Test("a sound whose audio file went missing is dropped when the library is opened")
    func dropsMissingAudio() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let library = box.library()
        let gone = try library.add(.init(name: "gone", icon: .emoji("x"), audio: try box.audio("g.wav")))
        let kept = try library.add(.init(name: "kept", icon: .emoji("x"), audio: try box.audio("k.wav")))
        try FileManager.default.removeItem(at: library.audioURL(for: gone))

        #expect(box.library().sounds == [kept])
    }

    @Test("a damaged index is not a crash: the library opens empty")
    func damagedIndex() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        _ = box.library()
        try Data("{ not json".utf8).write(to: box.libraryDirectory.appendingPathComponent("library.json"))
        #expect(box.library().sounds.isEmpty)
    }
}
