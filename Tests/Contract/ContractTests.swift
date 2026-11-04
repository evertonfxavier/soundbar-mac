import Foundation
import Testing

/// contract/ at the root of the repository is what this app and the Chrome extension agree on. The extension's
/// specs (ChromeExtension/tests/contract) read the same files: if one side changes without the other, one of the two
/// suites fails.
@Suite("Contract with the Chrome extension")
struct ContractTests {
    private static let contractDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Contract
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // the repository
        .appendingPathComponent("contract")

    private static func data(_ path: String) throws -> Data {
        try Data(contentsOf: contractDir.appendingPathComponent(path))
    }

    private static func object(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data(path)) as? [String: Any])
    }

    @Test("the app listens where the extension looks, and accepts the Origin an extension has")
    @MainActor
    func addressAndOrigin() throws {
        let protocolJSON = try Self.object("protocol.json")

        #expect(Int(BrowserBridge.defaultPort) == protocolJSON["port"] as? Int)
        #expect(BrowserBridge.allowedOriginPrefix == protocolJSON["originPrefix"] as? String)
        #expect(protocolJSON["host"] as? String == "127.0.0.1")
    }

    @Test("it reads the tabs message of the fixture")
    func readsTabs() throws {
        let message = BridgeProtocol.decode(try Self.data("fixtures/tabs.json"))

        guard case .tabs(let dtos)? = message else {
            Issue.record("not a tabs message: \(String(describing: message))"); return
        }
        let tabs = dtos.map { $0.model(conn: 1) }

        #expect(tabs.count == 2)
        let video = tabs[0]
        #expect(video.tabID == 12)
        #expect(video.title == "Lo-fi beats to relax to")
        #expect(video.host == "www.youtube.com")
        #expect(video.favIconURL == URL(string: "https://www.youtube.com/favicon.ico"))
        #expect(video.audible)
        #expect(!video.muted)
        #expect(video.volume == 0.5)
        #expect(!video.mic)
        #expect(!video.micMuted)

        let call = tabs[1]
        #expect(call.tabID == 34)
        #expect(call.title == "")
        #expect(call.host == "meet.google.com")
        #expect(call.favIconURL == nil)
        #expect(!call.audible)
        #expect(call.muted)
        #expect(call.volume == 1)
        #expect(call.mic)
        #expect(call.micMuted)
    }

    @Test("it reads the ping of the fixture")
    func readsPing() throws {
        #expect(BridgeProtocol.decode(try Self.data("fixtures/ping.json")) == .ping)
    }

    @Test("it writes the set command exactly as the fixture shows it")
    func writesSet() throws {
        let written = try #require(BridgeProtocol.set(tabID: 12, volume: 0.5, muted: false, micMuted: true))

        let json = try #require(try JSONSerialization.jsonObject(with: written) as? NSDictionary)
        #expect(json == (try Self.object("fixtures/set.json") as NSDictionary))
    }

    @Test("it writes the pong exactly as the fixture shows it")
    func writesPong() throws {
        let written = try #require(try JSONSerialization.jsonObject(with: BridgeProtocol.pong) as? NSDictionary)

        #expect(written == (try Self.object("fixtures/pong.json") as NSDictionary))
    }
}
