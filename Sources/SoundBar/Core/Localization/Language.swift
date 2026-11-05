import Combine
import Foundation

/// The language the texts are in right now. Core code (the error messages) reads it where it has no view to ask;
/// the `Localizer` sets it. It starts as the language the user picked in an earlier run, so even what is made before
/// the `Localizer` exists is in the right language.
enum Language {
    static let storageKey = "language"

    private static let lock = NSLock()
    private static var value: ResolvedLanguage = AppLanguage.stored().resolved()

    static var current: ResolvedLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

extension AppLanguage {
    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: Language.storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .auto
    }
}

/// The language choice of the menu: it is kept between runs and, when it changes, the views are drawn again.
@MainActor
final class Localizer: ObservableObject {
    @Published var choice: AppLanguage {
        didSet {
            guard choice != oldValue else { return }
            defaults.set(choice.rawValue, forKey: Language.storageKey)
            apply()
        }
    }

    /// The language the texts are in: the choice, or the system's when the choice is automatic.
    @Published private(set) var language: ResolvedLanguage

    private let defaults: UserDefaults
    private let systemLanguages: () -> [String]
    private let setsCurrent: Bool

    /// `setsCurrent` is false in tests, which must not change the language of the whole process.
    init(
        defaults: UserDefaults = .standard,
        systemLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        setsCurrent: Bool = true
    ) {
        self.defaults = defaults
        self.systemLanguages = systemLanguages
        self.setsCurrent = setsCurrent
        let stored = AppLanguage.stored(in: defaults)
        choice = stored
        language = stored.resolved(systemLanguages: systemLanguages())
        if setsCurrent { Language.current = language }
    }

    /// The name of a choice in the menu: the languages in their own language, "auto" in the current one.
    func name(of choice: AppLanguage) -> String {
        choice.nativeName ?? L.languageAutomatic.text(in: language)
    }

    private func apply() {
        language = choice.resolved(systemLanguages: systemLanguages())
        if setsCurrent { Language.current = language }
    }
}
