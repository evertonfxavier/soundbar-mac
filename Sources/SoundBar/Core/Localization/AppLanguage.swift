import Foundation

/// The languages the app speaks.
enum ResolvedLanguage: String, CaseIterable, Equatable {
    case pt
    case en
    case es
}

/// What the user picked in the menu: one of the languages, or "auto", which follows the system.
enum AppLanguage: String, CaseIterable, Equatable {
    case auto
    case pt
    case en
    case es

    /// The language to use. `auto` takes the first of the system's preferred languages that the app speaks
    /// (`pt-BR`, `en-GB` and `es-419` are Portuguese, English and Spanish), and English when it speaks none.
    func resolved(systemLanguages: [String] = Locale.preferredLanguages) -> ResolvedLanguage {
        switch self {
        case .pt: return .pt
        case .en: return .en
        case .es: return .es
        case .auto:
            for identifier in systemLanguages {
                let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased() ?? ""
                if let language = ResolvedLanguage(rawValue: code) { return language }
            }
            return .en
        }
    }

    /// How the language is named in the menu: in its own language, so it can be found whatever the current one is.
    /// (`auto` is named by the caller, in the current language.)
    var nativeName: String? {
        switch self {
        case .auto: nil
        case .pt: "Português"
        case .en: "English"
        case .es: "Español"
        }
    }
}
