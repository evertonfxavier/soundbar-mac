import CoreAudio

enum AudioDevices {
    /// Every audio device of the system, with whether it has inputs and outputs.
    static func all() -> [SoundboardRouting.Device] {
        let ids: [AudioObjectID] = CA.getArray(CA.system, kAudioHardwarePropertyDevices, initial: 0)
        return ids.compactMap { id in
            guard let uid = CA.deviceUID(id) else { return nil }
            return SoundboardRouting.Device(
                uid: uid, name: CA.deviceName(id),
                hasInput: CA.streamCount(id, input: true) > 0, hasOutput: CA.streamCount(id, input: false) > 0)
        }
    }

    static func defaultInputUID() -> String? {
        let device = CA.defaultDevice(input: true)
        return device == kAudioObjectUnknown ? nil : CA.deviceUID(device)
    }

    /// Makes the device the default input, or the default output (and the one for system alerts, as the Sound
    /// settings do). False when the device is gone or the system refuses.
    @discardableResult
    static func setDefault(uid: String, input: Bool) -> Bool {
        guard let device = CA.device(forUID: uid) else { return false }
        if input {
            return CA.set(CA.system, kAudioHardwarePropertyDefaultInputDevice, value: device)
        }
        let output = CA.set(CA.system, kAudioHardwarePropertyDefaultOutputDevice, value: device)
        CA.set(CA.system, kAudioHardwarePropertyDefaultSystemOutputDevice, value: device)
        return output
    }
}
