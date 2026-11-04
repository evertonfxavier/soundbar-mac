import Foundation
import Testing

@Suite("BridgeProtocol")
struct BridgeProtocolTests {
    private func decode(_ json: String) -> BridgeProtocol.Incoming? {
        BridgeProtocol.decode(Data(json.utf8))
    }

    @Test("reads the tabs the extension lists")
    func tabs() throws {
        let message = decode(
            """
            {"type":"tabs","tabs":[{"id":3,"title":"Lo-fi","host":"youtube.com","favIconUrl":"https://youtube.com/f.ico",
             "audible":true,"muted":false,"volume":0.5,"mic":true,"micMuted":true}]}
            """)

        guard case .tabs(let dtos)? = message else {
            Issue.record("not a tabs message: \(String(describing: message))"); return
        }
        let tab = try #require(dtos.first).model(conn: 9)

        #expect(tab.id == "9:3")
        #expect(tab.title == "Lo-fi")
        #expect(tab.host == "youtube.com")
        #expect(tab.favIconURL == URL(string: "https://youtube.com/f.ico"))
        #expect(tab.audible)
        #expect(!tab.muted)
        #expect(tab.volume == 0.5)
        #expect(tab.mic)
        #expect(tab.micMuted)
    }

    @Test("fills in what the extension left out: an untouched, quiet tab")
    func defaults() throws {
        guard case .tabs(let dtos)? = decode(#"{"type":"tabs","tabs":[{"id":1}]}"#) else {
            Issue.record("not a tabs message"); return
        }
        let tab = try #require(dtos.first).model(conn: 1)

        #expect(tab.title == "")
        #expect(tab.host == "")
        #expect(tab.favIconURL == nil)
        #expect(!tab.audible)
        #expect(!tab.muted)
        #expect(tab.volume == 1)
        #expect(!tab.mic)
        #expect(!tab.micMuted)
    }

    @Test("a tabs message with no list is an empty list")
    func noList() {
        #expect(decode(#"{"type":"tabs"}"#) == .tabs([]))
    }

    @Test("reads the ping")
    func ping() {
        #expect(decode(#"{"type":"ping"}"#) == .ping)
    }

    @Test(
        "ignores what it does not understand, without crashing",
        arguments: [
            "", "not json", "null", "[]", "{}", #"{"type":"reboot"}"#, #"{"type":7}"#, #"{"tabs":[]}"#,
            #"{"type":"tabs","tabs":[{"title":"no id"}]}"#,
        ])
    func garbage(_ text: String) {
        #expect(decode(text) == nil)
    }

    @Test("the pong is the one the extension expects")
    func pong() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: BridgeProtocol.pong) as? [String: String])

        #expect(json == ["type": "pong"])
    }

    @Test("a set command carries only the fields that are given")
    func setCommand() throws {
        func json(_ data: Data?) throws -> [String: Any] {
            let data = try #require(data)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        let onlyVolume = try json(BridgeProtocol.set(tabID: 5, volume: 0.25))
        #expect(Set(onlyVolume.keys) == ["type", "tabId", "volume"])
        #expect(onlyVolume["type"] as? String == "set")
        #expect(onlyVolume["tabId"] as? Int == 5)
        #expect(onlyVolume["volume"] as? Double == 0.25)

        let everything = try json(BridgeProtocol.set(tabID: 5, volume: 1, muted: true, micMuted: false))
        #expect(Set(everything.keys) == ["type", "tabId", "volume", "muted", "micMuted"])
        #expect(everything["muted"] as? Bool == true)
        #expect(everything["micMuted"] as? Bool == false)

        let nothingElse = try json(BridgeProtocol.set(tabID: 5))
        #expect(Set(nothingElse.keys) == ["type", "tabId"])
    }
}
