import Foundation
import Testing

@Suite("Localizer")
@MainActor
struct LocalizerTests {
    private func defaults() -> UserDefaults {
        let suite = "soundbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func localizer(_ defaults: UserDefaults, system: [String] = ["pt-BR"]) -> Localizer {
        Localizer(defaults: defaults, systemLanguages: { system }, setsCurrent: false)
    }

    @Test("it starts on automatic, which is the system's language")
    func defaultsToAuto() {
        let pt = localizer(defaults(), system: ["pt-BR"])
        #expect(pt.choice == .auto)
        #expect(pt.language == .pt)
        #expect(localizer(defaults(), system: ["es-ES"]).language == .es)
        #expect(localizer(defaults(), system: ["de-DE"]).language == .en)
    }

    @Test("choosing a language changes the texts and is kept for the next run")
    func choiceIsKept() {
        let store = defaults()
        let first = localizer(store)
        first.choice = .en
        #expect(first.language == .en)

        let reopened = localizer(store)
        #expect(reopened.choice == .en)
        #expect(reopened.language == .en)
    }

    @Test("going back to automatic follows the system again")
    func backToAuto() {
        let store = defaults()
        let localizer = localizer(store, system: ["es-MX"])
        localizer.choice = .pt
        #expect(localizer.language == .pt)
        localizer.choice = .auto
        #expect(localizer.language == .es)
        #expect(store.string(forKey: Language.storageKey) == "auto")
    }

    @Test("a value in the settings that is not a language is ignored")
    func garbageIsIgnored() {
        let store = defaults()
        store.set("klingon", forKey: Language.storageKey)
        #expect(localizer(store).choice == .auto)
    }

    @Test("the languages are named in their own language, and automatic in the current one")
    func names() {
        let localizer = localizer(defaults(), system: ["en-US"])
        #expect(localizer.name(of: .pt) == "Português")
        #expect(localizer.name(of: .auto) == "Automatic")
        localizer.choice = .es
        #expect(localizer.name(of: .auto) == "Automático")
        #expect(localizer.name(of: .en) == "English")
    }

    @Test("a test localizer does not change the language of the process")
    func doesNotTouchTheGlobal() {
        let before = Language.current
        let localizer = localizer(defaults(), system: ["es-ES"])
        localizer.choice = .en
        #expect(Language.current == before)
    }
}
