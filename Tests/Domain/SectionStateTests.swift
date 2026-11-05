import Foundation
import Testing

@Suite("SectionState")
@MainActor
struct SectionStateTests {
    private func defaults() -> UserDefaults {
        let suite = "soundbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("every section starts open")
    func startsOpen() {
        let state = SectionState(defaults: defaults())
        for section in MenuSection.allCases { #expect(state.isExpanded(section)) }
    }

    @Test("a section folds and unfolds on its own, without touching the others")
    func independent() {
        let state = SectionState(defaults: defaults())
        state.toggle(.apps)
        #expect(!state.isExpanded(.apps))
        #expect(state.isExpanded(.chromeTabs))
        #expect(state.isExpanded(.soundboard))
        state.toggle(.soundboard)
        #expect(!state.isExpanded(.apps) && !state.isExpanded(.soundboard))
        state.toggle(.apps)
        #expect(state.isExpanded(.apps))
        #expect(!state.isExpanded(.soundboard))
    }

    @Test("what was folded stays folded the next time the app runs")
    func remembered() {
        let store = defaults()
        let first = SectionState(defaults: store)
        first.toggle(.chromeTabs)
        first.toggle(.soundboard)
        first.toggle(.soundboard)

        let second = SectionState(defaults: store)
        #expect(!second.isExpanded(.chromeTabs))
        #expect(second.isExpanded(.soundboard))
        #expect(second.isExpanded(.apps))
    }

    @Test("a stored name that is not a section is ignored")
    func garbage() {
        let store = defaults()
        store.set(["apps", "nothing", ""], forKey: "collapsedSections")
        let state = SectionState(defaults: store)
        #expect(!state.isExpanded(.apps))
        #expect(state.collapsed == [.apps])
    }

    @Test("the section texts are in the three languages and differ between expanded and collapsed")
    func texts() {
        for language in ResolvedLanguage.allCases {
            #expect(L.sectionExpanded.text(in: language) != L.sectionCollapsed.text(in: language))
            #expect(L.collapseSection.text(in: language) != L.expandSection.text(in: language))
        }
    }
}
