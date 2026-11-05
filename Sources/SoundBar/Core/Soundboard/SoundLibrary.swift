import AppKit
import Foundation

/// The sounds the user added, kept in a folder (by default `~/Library/Application Support/SoundBar`):
/// `library.json` with the list, `sounds/` with a copy of each audio file and `icons/` with the image icons.
/// A copy, so a sound keeps working when the original file is moved or deleted.
final class SoundLibrary {
    /// What the user fills in to add or change a sound.
    struct Draft {
        enum Icon: Equatable {
            case emoji(String)
            case image(URL)
            /// Only when changing a sound: leave the icon as it is.
            case keep
        }

        var name: String
        var icon: Icon
        /// The audio file to copy in. Required to add a sound; when changing one, nil keeps the audio it has.
        var audio: URL?
        var volume: Float = 1
    }

    enum LibraryError: LocalizedError, Equatable {
        case noAudio
        case iconUnreadable

        var errorDescription: String? {
            switch self {
            case .noAudio: "Escolha um arquivo de áudio."
            case .iconUnreadable: "Não consegui ler essa imagem."
            }
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoundBar", isDirectory: true)
    }

    private static let iconSide = 128

    let directory: URL
    private(set) var sounds: [Sound] = []
    private var images: [String: NSImage] = [:]
    private let fileManager = FileManager.default

    private var soundsDirectory: URL { directory.appendingPathComponent("sounds", isDirectory: true) }
    private var iconsDirectory: URL { directory.appendingPathComponent("icons", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        load()
    }

    func audioURL(for sound: Sound) -> URL {
        soundsDirectory.appendingPathComponent(sound.fileName)
    }

    func image(named fileName: String) -> NSImage? {
        if let cached = images[fileName] { return cached }
        let image = NSImage(contentsOf: iconsDirectory.appendingPathComponent(fileName))
        images[fileName] = image
        return image
    }

    // MARK: - Changes

    @discardableResult
    func add(_ draft: Draft) throws -> Sound {
        guard let source = draft.audio else { throw LibraryError.noAudio }
        let id = UUID()
        let audio = try importAudio(source)
        let icon: SoundIcon
        do {
            icon = try resolve(draft.icon, keeping: .emoji(Sound.defaultEmoji))
        } catch {
            try? fileManager.removeItem(at: soundsDirectory.appendingPathComponent(audio))
            throw error
        }
        let sound = Sound(
            id: id, name: Self.name(draft.name, source: source), icon: icon, fileName: audio,
            volume: Self.clamped(draft.volume))
        sounds.append(sound)
        try save()
        return sound
    }

    func update(_ id: UUID, with draft: Draft) throws {
        guard let index = sounds.firstIndex(where: { $0.id == id }) else { return }
        let before = sounds[index]
        var sound = before

        var newAudio: String?
        if let source = draft.audio {
            newAudio = try importAudio(source)
            sound.fileName = newAudio ?? sound.fileName
        }
        do {
            sound.icon = try resolve(draft.icon, keeping: before.icon)
        } catch {
            if let newAudio { try? fileManager.removeItem(at: soundsDirectory.appendingPathComponent(newAudio)) }
            throw error
        }
        sound.name = Self.name(draft.name, source: draft.audio ?? audioURL(for: before))
        sound.volume = Self.clamped(draft.volume)

        sounds[index] = sound
        try save()

        if sound.fileName != before.fileName {
            try? fileManager.removeItem(at: audioURL(for: before))
        }
        if sound.icon != before.icon { removeImage(of: before.icon) }
    }

    func remove(_ id: UUID) {
        guard let index = sounds.firstIndex(where: { $0.id == id }) else { return }
        let sound = sounds.remove(at: index)
        try? fileManager.removeItem(at: audioURL(for: sound))
        removeImage(of: sound.icon)
        try? save()
    }

    // MARK: - Files

    /// Checks the file is audio and short enough, then copies it in under a name of its own.
    private func importAudio(_ source: URL) throws -> String {
        let seconds = try AudioDecoder.duration(of: source)
        guard seconds <= AudioDecoder.maxDuration else {
            throw AudioDecoder.DecodeError.tooLong(seconds: Int(seconds.rounded(.up)))
        }
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        try fileManager.copyItem(at: source, to: soundsDirectory.appendingPathComponent(fileName))
        return fileName
    }

    private func resolve(_ icon: Draft.Icon, keeping current: SoundIcon) throws -> SoundIcon {
        switch icon {
        case .keep:
            return current
        case .emoji(let text):
            let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
            return .emoji(first.map(String.init) ?? Sound.defaultEmoji)
        case .image(let url):
            let png = try Self.iconPNG(from: url)
            let fileName = "\(UUID().uuidString).png"
            try png.write(to: iconsDirectory.appendingPathComponent(fileName))
            return .image(fileName)
        }
    }

    private func removeImage(of icon: SoundIcon) {
        guard case .image(let fileName) = icon else { return }
        images[fileName] = nil
        try? fileManager.removeItem(at: iconsDirectory.appendingPathComponent(fileName))
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
            let saved = try? JSONDecoder().decode([Sound].self, from: data)
        else { return }
        sounds = saved.filter { fileManager.fileExists(atPath: audioURL(for: $0).path) }
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sounds).write(to: indexURL, options: .atomic)
    }

    // MARK: - Helpers

    private static func clamped(_ volume: Float) -> Float { max(0, min(1, volume)) }

    /// The name the user typed, or the name of the audio file when they typed none.
    private static func name(_ typed: String, source: URL) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? source.deletingPathExtension().lastPathComponent : trimmed
    }

    /// A square PNG of `iconSide` pixels: the image scaled to fill it, the overflow cropped.
    static func iconPNG(from url: URL) throws -> Data {
        let side = CGFloat(iconSide)
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: iconSide, pixelsHigh: iconSide, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { throw LibraryError.iconUnreadable }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let scale = max(side / image.size.width, side / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        image.draw(
            in: NSRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height),
            from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw LibraryError.iconUnreadable }
        return png
    }
}
