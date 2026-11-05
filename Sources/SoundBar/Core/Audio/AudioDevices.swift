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
}
