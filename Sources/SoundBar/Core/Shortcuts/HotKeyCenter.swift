import Carbon.HIToolbox
import Foundation

/// Registers global shortcuts with the system (Carbon's `RegisterEventHotKey`), which asks for no permission, and
/// tells which one was pressed. Everything happens on the main thread.
final class HotKeyCenter {
    private static let signature: OSType = 0x5342_484B  // 'SBHK'

    /// Called with the id `register` gave, when its shortcut is pressed.
    var onPress: ((UInt32) -> Void)?

    private var keys: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                guard status == noErr else { return status }
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().onPress?(pressed.id)
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        for key in keys.values { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Registers the shortcut: its id, or nil when the system refuses (another app already has it).
    func register(_ combo: KeyCombo) -> UInt32? {
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        nextID += 1
        keys[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        guard let key = keys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(key)
    }
}
