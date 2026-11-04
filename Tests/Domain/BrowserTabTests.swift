import Foundation
import Testing

@Suite("BrowserTab")
struct BrowserTabTests {
    private func tab(
        conn: Int = 1, id: Int = 1, title: String = "", host: String = "", audible: Bool = false
    ) -> BrowserTab {
        BrowserTab(
            conn: conn, tabID: id, title: title, host: host, favIconURL: nil, audible: audible, muted: false,
            volume: 1, mic: false, micMuted: false)
    }

    @Test("the same tab id in two browsers is two tabs")
    func identityIncludesTheConnection() {
        #expect(tab(conn: 1, id: 7).id == "1:7")
        #expect(tab(conn: 2, id: 7).id == "2:7")
    }

    @Test("a tab is named by its title, or by its host when it has none")
    func displayName() {
        #expect(tab(title: "Lo-fi", host: "youtube.com").displayName == "Lo-fi")
        #expect(tab(title: "", host: "youtube.com").displayName == "youtube.com")
    }

    @Test("the tabs making sound come first, then the others by name")
    func sorting() {
        let tabs = [
            tab(id: 1, title: "Zeta"), tab(id: 2, title: "beta", audible: true),
            tab(id: 3, title: "Alpha"), tab(id: 4, title: "Omega", audible: true),
        ]

        #expect(BrowserTab.sorted(tabs).map(\.displayName) == ["beta", "Omega", "Alpha", "Zeta"])
    }

    @Test("sorting ignores case")
    func sortingIgnoresCase() {
        let tabs = [tab(id: 1, title: "b"), tab(id: 2, title: "A")]

        #expect(BrowserTab.sorted(tabs).map(\.displayName) == ["A", "b"])
    }
}
