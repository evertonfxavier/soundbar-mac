import Foundation

/// The messages the Chrome extension and the app exchange over the local WebSocket. contract/fixtures/ holds one
/// example of each, and both this file and the extension's code are checked against them.
enum BridgeProtocol {
    /// One tab, as the extension writes it.
    struct TabDTO: Decodable, Equatable {
        let id: Int
        let title: String?
        let host: String?
        let favIconUrl: String?
        let audible: Bool?
        let muted: Bool?
        let volume: Double?
        let mic: Bool?
        let micMuted: Bool?

        func model(conn: Int) -> BrowserTab {
            BrowserTab(
                conn: conn, tabID: id, title: title ?? "", host: host ?? "",
                favIconURL: favIconUrl.flatMap { URL(string: $0) },
                audible: audible ?? false, muted: muted ?? false, volume: Float(volume ?? 1),
                mic: mic ?? false, micMuted: micMuted ?? false)
        }
    }

    /// What the extension can say.
    enum Incoming: Equatable {
        case tabs([TabDTO])
        case ping
    }

    private struct Envelope: Decodable {
        let type: String
        let tabs: [TabDTO]?
    }

    /// The message in `data`, or `nil` for anything this version does not understand.
    static func decode(_ data: Data) -> Incoming? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.type {
        case "tabs": return .tabs(envelope.tabs ?? [])
        case "ping": return .ping
        default: return nil
        }
    }

    /// The answer to a ping.
    static let pong = Data(#"{"type":"pong"}"#.utf8)

    /// A command for one tab. Only the fields that are given change.
    static func set(tabID: Int, volume: Float? = nil, muted: Bool? = nil, micMuted: Bool? = nil) -> Data? {
        var message: [String: Any] = ["type": "set", "tabId": tabID]
        if let volume { message["volume"] = Double(volume) }
        if let muted { message["muted"] = muted }
        if let micMuted { message["micMuted"] = micMuted }
        return try? JSONSerialization.data(withJSONObject: message)
    }
}
