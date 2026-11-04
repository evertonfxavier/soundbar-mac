import Foundation

/// The rules for sending the sounds into a call, with no hardware in them: which device is the virtual microphone,
/// which one is the real microphone, and when the feed has to run.
///
/// The call app is told to use the virtual microphone ("BlackHole"). SoundBar reads the real microphone, adds the
/// sounds to it and writes the result to the virtual one, which is what the other side of the call hears.
enum SoundboardRouting {
    struct Device: Equatable {
        let uid: String
        let name: String
        let hasInput: Bool
        let hasOutput: Bool
    }

    /// The virtual microphone: a BlackHole device (it has both input and output). The 2ch one is preferred.
    static func blackHole(in devices: [Device]) -> Device? {
        let found = devices.filter { isBlackHole($0) && $0.hasInput && $0.hasOutput }
        return found.first { $0.name.localizedCaseInsensitiveContains("2ch") } ?? found.first
    }

    /// The real microphone: the default input, unless that is the virtual one (the user may have chosen it
    /// as the system microphone), in which case the first input that is not.
    static func microphone(defaultInputUID: String?, devices: [Device]) -> Device? {
        let inputs = devices.filter { $0.hasInput && !isBlackHole($0) }
        return inputs.first { $0.uid == defaultInputUID } ?? inputs.first
    }

    /// The feed runs only while another app is reading the virtual microphone: that is when the user is in a call
    /// that uses it. Otherwise the real microphone is left alone (no indicator in the menu bar, no work).
    static func shouldFeed(blackHoleUID: String?, processes: [AudioProcess]) -> Bool {
        guard let blackHoleUID else { return false }
        return processes.contains { $0.isRunningInput && $0.inputDeviceUIDs.contains(blackHoleUID) }
    }

    private static func isBlackHole(_ device: Device) -> Bool {
        device.name.localizedCaseInsensitiveContains("blackhole")
            || device.uid.localizedCaseInsensitiveContains("blackhole")
    }
}
