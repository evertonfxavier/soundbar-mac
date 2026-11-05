import Foundation

/// What a sound shows on its button: an emoji, or an image the user picked (a file name inside the library).
enum SoundIcon: Codable, Equatable {
    case emoji(String)
    case image(String)
}

/// One sound of the soundboard. The audio and the icon image are files inside the library folder, by name.
struct Sound: Codable, Identifiable, Equatable {
    static let defaultEmoji = "🔊"

    var id = UUID()
    var name: String
    var icon: SoundIcon
    var fileName: String
    /// 0...1: the volume of this sound, both in the call and in the user's own speakers.
    var volume: Float = 1
    /// The group the button is in (a tab of the soundboard), or nil.
    var group: String?
    /// The part of the file that is played, in seconds: from `trimStart` to `trimEnd` (nil: the end of the file).
    var trimStart: Double = 0
    var trimEnd: Double?
    /// Bring the sound to a volume like the others' (see `AudioAnalysis`).
    var normalize = false

    enum CodingKeys: String, CodingKey {
        case id, name, icon, fileName, volume, group, trimStart, trimEnd, normalize
    }
}

extension Sound {
    /// Reads a sound; what an older version did not write (group, trim, normalize) gets its default, so a library
    /// made before them still opens.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        icon = try values.decode(SoundIcon.self, forKey: .icon)
        fileName = try values.decode(String.self, forKey: .fileName)
        volume = try values.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        group = try values.decodeIfPresent(String.self, forKey: .group)
        trimStart = try values.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try values.decodeIfPresent(Double.self, forKey: .trimEnd)
        normalize = try values.decodeIfPresent(Bool.self, forKey: .normalize) ?? false
    }

    /// The loudness of the sound: its own volume times the master volume of the soundboard.
    func gain(master: Float) -> Float { volume * max(0, min(1, master)) }
}

/// Which sounds the soundboard shows: those of a group, and those whose name has what the user typed.
enum SoundFilter {
    static func apply(_ sounds: [Sound], group: String?, query: String) -> [Sound] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sounds.filter { sound in
            if let group, sound.group != group { return false }
            return needle.isEmpty
                || sound.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The groups in use, in the order they first appear, without the empty ones.
    static func groups(of sounds: [Sound]) -> [String] {
        var seen = Set<String>()
        return sounds.compactMap(\.group).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
