import Foundation

/// A browser tab reported by the Chrome extension.
struct BrowserTab: Identifiable, Equatable {
    /// Which connection (browser) reported it: tab ids repeat between browsers.
    let conn: Int
    let tabID: Int
    var title: String
    var host: String
    var favIconURL: URL?
    var audible: Bool
    var muted: Bool
    var volume: Float
    var mic: Bool
    var micMuted: Bool

    var id: String { "\(conn):\(tabID)" }
    var displayName: String { title.isEmpty ? host : title }

    /// The order of the list: tabs making sound first, then by name.
    static func sorted(_ tabs: [BrowserTab]) -> [BrowserTab] {
        tabs.sorted {
            ($0.audible ? 0 : 1, $0.displayName.lowercased()) < ($1.audible ? 0 : 1, $1.displayName.lowercased())
        }
    }
}

/// The browsers whose tabs the extension controls. While it is connected, their per-app row is redundant.
enum Browsers {
    static let chromeIDs: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary"]
}
