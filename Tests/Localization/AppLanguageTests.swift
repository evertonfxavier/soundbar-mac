import Testing

@Suite("AppLanguage")
struct AppLanguageTests {
    @Test("a language that was picked is that language, whatever the system says")
    func pickedWins() {
        #expect(AppLanguage.pt.resolved(systemLanguages: ["en-US"]) == .pt)
        #expect(AppLanguage.en.resolved(systemLanguages: ["pt-BR"]) == .en)
        #expect(AppLanguage.es.resolved(systemLanguages: ["pt-BR"]) == .es)
    }

    @Test("automatic follows the system, in any of its regional forms")
    func autoFollowsSystem() {
        #expect(AppLanguage.auto.resolved(systemLanguages: ["pt-BR"]) == .pt)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["pt-PT"]) == .pt)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["en-GB"]) == .en)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["es-419"]) == .es)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["ES_MX"]) == .es)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["pt"]) == .pt)
    }

    @Test("automatic takes the first language of the system's list that the app speaks")
    func autoTakesFirstSupported() {
        #expect(AppLanguage.auto.resolved(systemLanguages: ["fr-FR", "es-ES", "pt-BR"]) == .es)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["ja-JP", "pt-BR", "en-US"]) == .pt)
    }

    @Test("when the system speaks none of them, it is English")
    func autoFallsBackToEnglish() {
        #expect(AppLanguage.auto.resolved(systemLanguages: ["ja-JP", "fr-FR"]) == .en)
        #expect(AppLanguage.auto.resolved(systemLanguages: []) == .en)
        #expect(AppLanguage.auto.resolved(systemLanguages: ["", "-"]) == .en)
    }

    @Test("the languages are named in their own language, and automatic is left to the caller")
    func nativeNames() {
        #expect(AppLanguage.pt.nativeName == "Português")
        #expect(AppLanguage.en.nativeName == "English")
        #expect(AppLanguage.es.nativeName == "Español")
        #expect(AppLanguage.auto.nativeName == nil)
    }

    @Test("the menu offers automatic first, then the three languages")
    func order() {
        #expect(AppLanguage.allCases == [.auto, .pt, .en, .es])
    }
}
