import AppKit
import CoreAudio

/// An app that plays sound or uses the microphone, with every audio process it owns.
struct AudioApp: Identifiable, Equatable {
    let id: String
    var name: String
    var icon: NSImage?
    var objectIDs: [AudioObjectID]
    var isPlaying: Bool
    var isUsingMic: Bool
    var outputDeviceUID: String?
}

/// The default output or input device, as the menu shows it.
struct DeviceState: Equatable {
    var id = AudioObjectID(kAudioObjectUnknown)
    var name = "—"
    var volume: Float = 1
    var muted = false
    var hasVolume = false
    var uid: String?
}
