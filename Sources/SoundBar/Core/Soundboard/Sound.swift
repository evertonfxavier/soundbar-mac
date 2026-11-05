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
}
