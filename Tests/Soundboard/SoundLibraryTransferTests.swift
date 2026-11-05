import AppKit
import Foundation
import Testing

@Suite("SoundLibrary: order, groups, export and import")
struct SoundLibraryTransferTests {
    private struct Box {
        let folder = TestAudio.temporaryDirectory()
        func library(_ name: String = "lib") -> SoundLibrary {
            SoundLibrary(directory: folder.appendingPathComponent(name))
        }
        func audio(_ name: String = "a.wav", seconds: Double = 0.1) throws -> URL {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
            return try TestAudio.writeWAV(
                to: folder.appendingPathComponent("src").appendingPathComponent(name), seconds: seconds)
        }
        func archive(_ name: String = "out.zip") -> URL { folder.appendingPathComponent(name) }
        func cleanup() { try? FileManager.default.removeItem(at: folder) }
    }

    private func add(_ library: SoundLibrary, _ box: Box, _ name: String, group: String? = nil) throws -> Sound {
        try library.add(.init(name: name, icon: .emoji("🎺"), audio: try box.audio("\(name).wav"), group: group))
    }

    // MARK: - Group, trim, normalize

    @Test("the group, the trim and the normalizing are saved, trimmed of spaces, and survive a restart")
    func extraFieldsPersist() throws {
        let box = Box()
        defer { box.cleanup() }
        let library = box.library()
        let sound = try library.add(
            .init(
                name: "a", icon: .emoji("x"), audio: try box.audio(), group: "  Meetings ", trimStart: 0.02,
                trimEnd: 0.08, normalize: true))

        let reopened = box.library().sounds[0]
        #expect(reopened == sound)
        #expect(reopened.group == "Meetings")
        #expect(reopened.trimStart == 0.02)
        #expect(reopened.trimEnd == 0.08)
        #expect(reopened.normalize)
    }

    @Test("an empty group is no group, and changing a sound changes them")
    func updateExtraFields() throws {
        let box = Box()
        defer { box.cleanup() }
        let library = box.library()
        let sound = try add(library, box, "a", group: "   ")
        #expect(sound.group == nil)

        try library.update(
            sound.id,
            with: .init(
                name: "a", icon: .keep, audio: nil, group: "Jokes", trimStart: 0.01, trimEnd: 0.05, normalize: true)
        )
        #expect(library.sounds[0].group == "Jokes")
        #expect(library.sounds[0].trimEnd == 0.05)
        #expect(library.sounds[0].normalize)

        try library.update(sound.id, with: .init(name: "a", icon: .keep, audio: nil, group: nil))
        #expect(library.sounds[0].group == nil)
        #expect(library.sounds[0].trimEnd == nil)
    }

    @Test("the groups are listed in the order they first appear")
    func groups() throws {
        let box = Box()
        defer { box.cleanup() }
        let library = box.library()
        _ = try add(library, box, "a", group: "B")
        _ = try add(library, box, "b")
        _ = try add(library, box, "c", group: "A")
        _ = try add(library, box, "d", group: "B")
        #expect(library.groups == ["B", "A"])
    }

    // MARK: - Order

    @Test("a sound goes before another one, or to the end, and the order is kept")
    func moves() throws {
        let box = Box()
        defer { box.cleanup() }
        let library = box.library()
        let a = try add(library, box, "a")
        let b = try add(library, box, "b")
        let c = try add(library, box, "c")

        library.move(c.id, before: a.id)
        #expect(library.sounds.map(\.name) == ["c", "a", "b"])
        library.move(c.id, before: nil)
        #expect(library.sounds.map(\.name) == ["a", "b", "c"])
        library.move(a.id, before: c.id)
        #expect(library.sounds.map(\.name) == ["b", "a", "c"])
        #expect(box.library().sounds.map(\.name) == ["b", "a", "c"])
        library.move(b.id, before: b.id)  // onto itself: nothing
        library.move(UUID(), before: a.id)  // unknown: nothing
        #expect(library.sounds.map(\.name) == ["b", "a", "c"])
    }

    @Test("shifting moves by places and stops at the ends")
    func shifts() throws {
        let box = Box()
        defer { box.cleanup() }
        let library = box.library()
        let a = try add(library, box, "a")
        _ = try add(library, box, "b")
        let c = try add(library, box, "c")

        library.shift(c.id, by: -1)
        #expect(library.sounds.map(\.name) == ["a", "c", "b"])
        library.shift(c.id, by: -5)
        #expect(library.sounds.map(\.name) == ["c", "a", "b"])
        library.shift(a.id, by: 9)
        #expect(library.sounds.map(\.name) == ["c", "b", "a"])
        library.shift(a.id, by: 1)
        #expect(library.sounds.map(\.name) == ["c", "b", "a"])
        #expect(box.library().sounds.map(\.name) == ["c", "b", "a"])
    }

    // MARK: - Export and import

    @Test("exporting and importing into an empty library brings everything back")
    func roundTrip() throws {
        let box = Box()
        defer { box.cleanup() }
        let source = box.library("one")
        let png = try png(box)
        _ = try source.add(
            .init(
                name: "Clap", icon: .image(png), audio: try box.audio("clap.wav"), volume: 0.4, group: "G",
                normalize: true))
        _ = try add(source, box, "Horn")

        try source.export(to: box.archive())
        #expect(FileManager.default.fileExists(atPath: box.archive().path))

        let target = box.library("two")
        let result = try target.importLibrary(from: box.archive())

        #expect(result == .init(added: 2, skipped: 0, failed: 0))
        #expect(target.sounds.map(\.name) == ["Clap", "Horn"])
        #expect(target.sounds[0].volume == 0.4)
        #expect(target.sounds[0].group == "G")
        #expect(target.sounds[0].normalize)
        #expect(target.sounds.allSatisfy { FileManager.default.fileExists(atPath: target.audioURL(for: $0).path) })
        guard case .image(let file) = target.sounds[0].icon else {
            Issue.record("the image icon should have come along")
            return
        }
        #expect(target.image(named: file) != nil)
        #expect(box.library("two").sounds.count == 2)  // and it was saved
    }

    @Test("importing twice does not add the same sounds again")
    func importIsIdempotent() throws {
        let box = Box()
        defer { box.cleanup() }
        let source = box.library("one")
        _ = try add(source, box, "a")
        try source.export(to: box.archive())
        let target = box.library("two")
        #expect(try target.importLibrary(from: box.archive()).added == 1)
        #expect(try target.importLibrary(from: box.archive()) == .init(added: 0, skipped: 1, failed: 0))
        #expect(target.sounds.count == 1)
    }

    @Test("importing into a library that has its own sounds keeps them")
    func importKeepsExisting() throws {
        let box = Box()
        defer { box.cleanup() }
        let source = box.library("one")
        _ = try add(source, box, "from-source")
        try source.export(to: box.archive())
        let target = box.library("two")
        _ = try add(target, box, "mine")
        try target.importLibrary(from: box.archive())
        #expect(target.sounds.map(\.name) == ["mine", "from-source"])
    }

    @Test("a file that is not a library is refused and changes nothing")
    func notALibrary() throws {
        let box = Box()
        defer { box.cleanup() }
        let target = box.library()
        _ = try add(target, box, "a")
        let junk = box.folder.appendingPathComponent("junk.zip")
        try Data("not a zip".utf8).write(to: junk)
        #expect(throws: SoundLibrary.LibraryError.notALibrary) { try target.importLibrary(from: junk) }
        // a zip with no library.json
        let empty = box.folder.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: empty.appendingPathComponent("readme.txt"))
        let zip = box.folder.appendingPathComponent("empty.zip")
        try ditto(["-c", "-k", empty.path, zip.path])
        #expect(throws: SoundLibrary.LibraryError.notALibrary) { try target.importLibrary(from: zip) }
        #expect(target.sounds.count == 1)
    }

    @Test("a sound whose file name is a path, or that points outside the archive, is counted as failed")
    func hostileNames() throws {
        let box = Box()
        defer { box.cleanup() }
        let secret = box.folder.appendingPathComponent("secret.wav")
        try TestAudio.writeWAV(to: secret)

        let stage = box.folder.appendingPathComponent("stage")
        try FileManager.default.createDirectory(
            at: stage.appendingPathComponent("sounds"), withIntermediateDirectories: true)
        let sounds = ["../../secret.wav", "/etc/hosts", "sub/dir.wav", "..", ".hidden.wav", ""].map {
            Sound(id: UUID(), name: "evil", icon: .emoji("x"), fileName: $0)
        }
        try JSONEncoder().encode(sounds).write(to: stage.appendingPathComponent("library.json"))
        let zip = box.folder.appendingPathComponent("evil.zip")
        try ditto(["-c", "-k", stage.path, zip.path])

        let target = box.library()
        let result = try target.importLibrary(from: zip)

        #expect(result == .init(added: 0, skipped: 0, failed: 6))
        #expect(target.sounds.isEmpty)
    }

    @Test("a sound whose audio is missing or is not audio is counted as failed, the others still come in")
    func badSoundsDoNotStopTheRest() throws {
        let box = Box()
        defer { box.cleanup() }
        let source = box.library("one")
        let good = try add(source, box, "good")
        let broken = try add(source, box, "broken")
        let missing = try add(source, box, "missing")
        // after the export is made from these files: one is no longer audio, the other is gone
        try Data("no".utf8).write(to: source.audioURL(for: broken))
        try FileManager.default.removeItem(at: source.audioURL(for: missing))
        try source.export(to: box.archive())

        let target = box.library("two")
        let result = try target.importLibrary(from: box.archive())

        #expect(result.added == 1)
        #expect(result.failed == 2)
        #expect(target.sounds.map(\.id) == [good.id])
    }

    private func png(_ box: Box) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let url = box.folder.appendingPathComponent("icon.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
