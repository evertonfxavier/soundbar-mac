import Foundation

/// What the user chose for one app: a volume and a mute switch. Saved between launches, so the shape
/// (`volume`, `muted`) must stay readable by older versions.
struct AppSetting: Codable, Equatable {
    /// The loudest an app can be set. Above 1 boosts it; the output is limited to full scale, so a boost may clip.
    static let maxVolume: Float = 1.5

    var volume: Float = 1
    var muted = false

    /// Untouched: no tap is needed for this app.
    var isDefault: Bool { !muted && abs(volume - 1) < 0.005 }

    /// The multiplier the tap applies to the app's audio.
    var gain: Float { muted ? 0 : volume }

    /// A volume kept to what the slider allows: 0 to `maxVolume`.
    static func clamp(_ volume: Float) -> Float { max(0, min(maxVolume, volume)) }
}
