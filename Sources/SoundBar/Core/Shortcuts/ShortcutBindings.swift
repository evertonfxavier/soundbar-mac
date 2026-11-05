import Foundation

/// What a global shortcut can do.
enum ShortcutAction: Hashable {
    case sound(UUID)
    case stopAll
    case callMute
    case micMute

    var storageKey: String {
        switch self {
        case .sound(let id): "sound:\(id.uuidString)"
        case .stopAll: "stopAll"
        case .callMute: "callMute"
        case .micMute: "micMute"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "stopAll": self = .stopAll
        case "callMute": self = .callMute
        case "micMute": self = .micMute
        default:
            guard storageKey.hasPrefix("sound:"), let id = UUID(uuidString: String(storageKey.dropFirst(6))) else {
                return nil
            }
            self = .sound(id)
        }
    }
}

/// Which key combination does what. Two actions never share a combination.
struct ShortcutBindings: Equatable {
    private(set) var combos: [ShortcutAction: KeyCombo] = [:]

    func combo(for action: ShortcutAction) -> KeyCombo? { combos[action] }

    /// The action that uses `combo`, other than `action`.
    func conflict(for combo: KeyCombo, excluding action: ShortcutAction? = nil) -> ShortcutAction? {
        combos.first { $0.value == combo && $0.key != action }?.key
    }

    /// Sets (or, with nil, clears) the combination of an action. Returns the action that already has it, in which
    /// case nothing changes.
    @discardableResult
    mutating func set(_ combo: KeyCombo?, for action: ShortcutAction) -> ShortcutAction? {
        guard let combo else {
            combos[action] = nil
            return nil
        }
        if let other = conflict(for: combo, excluding: action) { return other }
        combos[action] = combo
        return nil
    }

    // MARK: - Storage

    func encoded() -> Data? {
        try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: combos.map { ($0.key.storageKey, $0.value) }))
    }

    /// What `encoded` wrote. What cannot be read (an action that no longer exists, a bad value) is left out.
    static func decoded(_ data: Data?) -> ShortcutBindings {
        var bindings = ShortcutBindings()
        guard let data, let stored = try? JSONDecoder().decode([String: KeyCombo].self, from: data) else {
            return bindings
        }
        for (key, combo) in stored {
            if let action = ShortcutAction(storageKey: key), combo.isValid { bindings.set(combo, for: action) }
        }
        return bindings
    }
}
