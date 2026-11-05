import Foundation
import Testing

@Suite("L (the texts)")
struct LTests {
    private func placeholders(_ text: String) -> Int {
        text.components(separatedBy: "%@").count - 1
    }

    @Test("every text has all three languages, not empty")
    func complete() {
        for key in L.allCases {
            for language in ResolvedLanguage.allCases {
                let text = key.text(in: language)
                #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) in \(language)")
            }
        }
    }

    @Test("the three languages of a text take the same arguments")
    func samePlaceholders() {
        for key in L.allCases {
            let counts = ResolvedLanguage.allCases.map { placeholders(key.text(in: $0)) }
            #expect(Set(counts).count == 1, "\(key): \(counts)")
        }
    }

    @Test("the texts that are not names or symbols differ between the languages")
    func translated() {
        // the same word in all three languages (a name, or a word that is alike) is fine, but most are not
        let same = L.allCases.filter {
            let t = $0.translations
            return t.pt == t.en && t.en == t.es
        }
        #expect(same.count <= 4, "\(same)")
        // Portuguese and Spanish are alike, but a whole English text equal to the Portuguese one is a text that was not translated
        let untranslated = L.allCases.filter {
            let t = $0.translations
            return t.pt == t.en && t.pt.count > 8
        }
        #expect(untranslated.isEmpty, "\(untranslated)")
    }

    @Test("the arguments go where the %@ are, in order")
    func fills() {
        #expect(L.errStepFailed.formatted(in: .en, "Starting", "-10") == "Starting failed (error -10).")
        #expect(L.deviceOf.formatted(in: .pt, "Saída", "Alto-falantes") == "Dispositivo de Saída: Alto-falantes")
        #expect(L.newVersion.formatted(in: .es, "0.1.9") == "Nueva versión: v0.1.9")
    }

    @Test("a missing argument leaves nothing behind, and an extra one is ignored")
    func fillsEdgeCases() {
        #expect(L.newVersion.formatted(in: .en) == "New version: v")
        #expect(L.newVersion.formatted(in: .en, "1", "2") == "New version: v1")
        #expect(L.quit.formatted(in: .en, "ignored") == "Quit")
    }

    @Test("the texts are as before in Portuguese, the language the app had")
    func portugueseIsKept() {
        #expect(L.sectionSoundboard.text(in: .pt) == "SONOPLASTIA")
        #expect(L.statusLive.text(in: .pt) == "Os sons vão para a chamada.")
        #expect(L.output.text(in: .pt) == "Saída")
    }

    @Test("the text in use follows the language of the app")
    func followsCurrentLanguage() {
        // other tests must not see a different language, so the current one is only read here
        #expect(L.quit.string == L.quit.text(in: Language.current))
        #expect(L.errStepFailed.formatted("a", "b") == L.errStepFailed.formatted(in: Language.current, "a", "b"))
    }
}
