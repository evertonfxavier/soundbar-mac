import CoreAudio

/// Volume/mute of a hardware device (default speaker or microphone).
enum DeviceControl {
    private static func scope(_ input: Bool) -> AudioObjectPropertyScope {
        input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }

    /// Elements that carry the volume control: main if present, else channels 1 and 2.
    private static func volumeElements(_ dev: AudioObjectID, input: Bool) -> [AudioObjectPropertyElement] {
        if CA.has(dev, kAudioDevicePropertyVolumeScalar, scope: scope(input), element: kAudioObjectPropertyElementMain)
        {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { CA.has(dev, kAudioDevicePropertyVolumeScalar, scope: scope(input), element: $0) }
    }

    static func hasVolume(_ dev: AudioObjectID, input: Bool) -> Bool {
        volumeElements(dev, input: input).contains {
            CA.isSettable(dev, kAudioDevicePropertyVolumeScalar, scope: scope(input), element: $0)
        }
    }

    static func volume(_ dev: AudioObjectID, input: Bool) -> Float? {
        let values = volumeElements(dev, input: input).compactMap {
            CA.get(dev, kAudioDevicePropertyVolumeScalar, scope: scope(input), element: $0, initial: Float32(0))
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    static func setVolume(_ dev: AudioObjectID, input: Bool, _ value: Float) {
        let v = Float32(max(0, min(1, value)))
        for el in volumeElements(dev, input: input) {
            CA.set(dev, kAudioDevicePropertyVolumeScalar, scope: scope(input), element: el, value: v)
        }
    }

    static func hasMute(_ dev: AudioObjectID, input: Bool) -> Bool {
        CA.isSettable(dev, kAudioDevicePropertyMute, scope: scope(input))
    }

    static func isMuted(_ dev: AudioObjectID, input: Bool) -> Bool {
        (CA.get(dev, kAudioDevicePropertyMute, scope: scope(input), initial: UInt32(0)) ?? 0) != 0
    }

    static func setMuted(_ dev: AudioObjectID, input: Bool, _ muted: Bool) {
        CA.set(dev, kAudioDevicePropertyMute, scope: scope(input), value: UInt32(muted ? 1 : 0))
    }
}
