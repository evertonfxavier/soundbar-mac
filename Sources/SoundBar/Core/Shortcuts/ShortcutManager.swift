import Combine
import Foundation

/// The global shortcuts: which key does what, kept between runs, and registered with the system while the app runs.
@MainActor
final class ShortcutManager: ObservableObject {
    enum AssignResult: Equatable {
        case ok
        /// No Control, Option or Command, or a key the app does not know.
        case invalid
        /// Another action of the app already uses it.
        case conflict(ShortcutAction)
        /// The system refused it: another app has it.
        case unavailable
    }

    private static let storageKey = "shortcutBindings"

    @Published private(set) var bindings: ShortcutBindings

    /// What to do when a shortcut is pressed.
    var onAction: ((ShortcutAction) -> Void)?

    private let defaults: UserDefaults
    private let center: HotKeyCenter
    private var registered: [ShortcutAction: UInt32] = [:]
    private var actionByID: [UInt32: ShortcutAction] = [:]

    init(defaults: UserDefaults = .standard, center: HotKeyCenter = HotKeyCenter()) {
        self.defaults = defaults
        self.center = center
        bindings = ShortcutBindings.decoded(defaults.data(forKey: Self.storageKey))
        center.onPress = { [weak self] id in
            MainActor.assumeIsolated {
                guard let self, let action = self.actionByID[id] else { return }
                self.onAction?(action)
            }
        }
        // A shortcut that another app has taken since the last run is dropped.
        for (action, combo) in bindings.combos where !register(action, combo) {
            bindings.set(nil, for: action)
        }
        persist()
    }

    func combo(for action: ShortcutAction) -> KeyCombo? { bindings.combo(for: action) }

    /// Gives `action` the shortcut `combo`, or takes its shortcut away when `combo` is nil.
    @discardableResult
    func assign(_ combo: KeyCombo?, to action: ShortcutAction) -> AssignResult {
        guard let combo else {
            unregister(action)
            bindings.set(nil, for: action)
            persist()
            return .ok
        }
        guard combo.isValid else { return .invalid }
        if combo == bindings.combo(for: action) { return .ok }
        if let other = bindings.conflict(for: combo, excluding: action) { return .conflict(other) }
        guard register(action, combo) else { return .unavailable }
        bindings.set(combo, for: action)
        persist()
        return .ok
    }

    /// The action that already has `combo`, other than `action`.
    func conflict(for combo: KeyCombo, excluding action: ShortcutAction?) -> ShortcutAction? {
        bindings.conflict(for: combo, excluding: action)
    }

    // MARK: - Registration

    /// Registers `combo` for `action`, keeping any earlier registration of the action until the caller drops it.
    private func register(_ action: ShortcutAction, _ combo: KeyCombo) -> Bool {
        guard let id = center.register(combo) else { return false }
        if let old = registered[action] { unregisterID(old) }
        registered[action] = id
        actionByID[id] = action
        return true
    }

    private func unregister(_ action: ShortcutAction) {
        if let id = registered.removeValue(forKey: action) { unregisterID(id) }
    }

    private func unregisterID(_ id: UInt32) {
        actionByID[id] = nil
        center.unregister(id)
    }

    private func persist() {
        if let data = bindings.encoded() { defaults.set(data, forKey: Self.storageKey) }
    }
}
