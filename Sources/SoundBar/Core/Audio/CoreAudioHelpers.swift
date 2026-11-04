import CoreAudio
import Foundation

/// Thin wrappers around the AudioObject property C API.
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(
        _ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var addr = address(selector, scope: scope, element: element)
        return AudioObjectHasProperty(obj, &addr)
    }

    static func isSettable(
        _ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> Bool {
        var addr = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(obj, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(obj, &addr, &settable) == noErr && settable.boolValue
    }

    static func get<T: BitwiseCopyable>(
        _ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        initial: T
    ) -> T? {
        var addr = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(obj, &addr) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let err = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
        return err == noErr ? value : nil
    }

    static func getArray<T: BitwiseCopyable>(
        _ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        initial: T
    ) -> [T] {
        var addr = address(selector, scope: scope, element: element)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        var values = [T](repeating: initial, count: count)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &values) == noErr else { return [] }
        return Array(values.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    static func getString(
        _ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var addr = address(selector, scope: scope)
        guard AudioObjectHasProperty(obj, &addr) else { return nil }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let err = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
        guard err == noErr, let str = value?.takeRetainedValue() else { return nil }
        return str as String
    }

    @discardableResult
    static func set<T: BitwiseCopyable>(
        _ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value: T
    ) -> Bool {
        var addr = address(selector, scope: scope, element: element)
        var v = value
        return AudioObjectSetPropertyData(obj, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    static func deviceUID(_ device: AudioObjectID) -> String? {
        getString(device, kAudioDevicePropertyDeviceUID)
    }

    static func deviceName(_ device: AudioObjectID) -> String {
        getString(device, kAudioObjectPropertyName) ?? "Desconhecido"
    }

    static func defaultDevice(input: Bool) -> AudioObjectID {
        let sel = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        return get(system, sel, initial: AudioObjectID(kAudioObjectUnknown)) ?? AudioObjectID(kAudioObjectUnknown)
    }

    static func device(forUID uid: String) -> AudioObjectID? {
        let devices: [AudioObjectID] = getArray(system, kAudioHardwarePropertyDevices, initial: 0)
        return devices.first { deviceUID($0) == uid }
    }

    static func streamCount(_ device: AudioObjectID, input: Bool) -> Int {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let streams: [AudioStreamID] = getArray(device, kAudioDevicePropertyStreams, scope: scope, initial: 0)
        return streams.count
    }
}

struct CoreAudioError: LocalizedError {
    let what: String
    let status: OSStatus
    var errorDescription: String? { "\(what) falhou (OSStatus \(status))" }
}

@inline(__always)
func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw CoreAudioError(what: what, status: status) }
}
