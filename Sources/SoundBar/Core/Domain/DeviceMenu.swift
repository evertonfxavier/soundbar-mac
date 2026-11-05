import Foundation

/// The devices the menu offers when the user switches the speaker or the microphone.
enum DeviceMenu {
    /// Every device with outputs, by name. The virtual microphone BlackHole is left out: sending the whole system
    /// sound into it would only silence the Mac.
    static func outputs(from devices: [SoundboardRouting.Device]) -> [SoundboardRouting.Device] {
        sorted(devices.filter { $0.hasOutput && !SoundboardRouting.isBlackHole($0) })
    }

    /// Every device with inputs, by name. BlackHole stays: some people do want it as the system microphone.
    static func inputs(from devices: [SoundboardRouting.Device]) -> [SoundboardRouting.Device] {
        sorted(devices.filter(\.hasInput))
    }

    private static func sorted(_ devices: [SoundboardRouting.Device]) -> [SoundboardRouting.Device] {
        devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
