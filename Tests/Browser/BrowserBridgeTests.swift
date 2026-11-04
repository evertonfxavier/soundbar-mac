import Foundation
import Network
import Testing

/// The bridge against a real WebSocket client on the loopback, the way the Chrome extension talks to it.
///
/// Every wait here has a limit: a test that expects an answer that never comes must fail, not hold the pipeline.
@MainActor
@Suite("BrowserBridge")
struct BrowserBridgeTests {
    private let tabsJSON = #"""
        {"type":"tabs","tabs":[
          {"id":12,"title":"Lo-fi","host":"youtube.com","audible":true,"volume":0.5},
          {"id":34,"title":"Meet","host":"meet.google.com","mic":true}
        ]}
        """#

    /// What the bridge reported through `onChange` (the last call wins).
    private final class Seen {
        var tabs: [BrowserTab] = []
        var connected = false
    }

    private func start() async throws -> (bridge: BrowserBridge, seen: Seen, port: UInt16) {
        // a random port, tried again if something else holds it
        for _ in 0..<20 {
            let port = UInt16.random(in: 41_000...60_000)
            let bridge = BrowserBridge(port: port, handshakeTimeout: 0.5)
            let seen = Seen()
            bridge.onChange = { tabs, connected in
                seen.tabs = tabs
                seen.connected = connected
            }
            bridge.start()
            if await eventually({ bridge.isListening }) { return (bridge, seen, port) }
            bridge.stop()
        }
        throw TestError("no free port for the bridge")
    }

    private func client(port: UInt16, origin: String?) -> URLSessionWebSocketTask {
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)")!)
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let task = URLSession(configuration: configuration).webSocketTask(with: request)
        task.resume()
        return task
    }

    // MARK: - Who may connect

    @Test("it accepts a Chrome extension and lists its tabs")
    func acceptsAnExtension() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let extensionClient = client(port: port, origin: "chrome-extension://abcdefghijklmnop")
        defer { extensionClient.cancel() }

        try await extensionClient.send(.string(tabsJSON))

        #expect(await eventually { seen.connected && seen.tabs.count == 2 })
        #expect(seen.tabs.map(\.tabID) == [12, 34])
        #expect(seen.tabs.first?.audible == true)
        #expect(seen.tabs.first?.volume == 0.5)
        #expect(seen.tabs.last?.mic == true)
    }

    @Test("it answers a web page with an error, not with the upgrade: its Origin is http(s), not chrome-extension")
    func rejectsAWebPage() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }

        let answer = await handshakeStatusLine(port: port, origin: "https://evil.example")

        #expect(answer?.hasPrefix("HTTP/1.1 400") == true, "got \(String(describing: answer))")
        #expect(!seen.connected)
        #expect(seen.tabs.isEmpty)
    }

    @Test("it answers a client that says nothing about where it comes from with an error too")
    func rejectsNoOrigin() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }

        let answer = await handshakeStatusLine(port: port, origin: nil)

        #expect(answer?.hasPrefix("HTTP/1.1 400") == true, "got \(String(describing: answer))")
        #expect(!seen.connected)
    }

    @Test("it switches protocols for a Chrome extension")
    func upgradesAnExtension() async throws {
        let (bridge, _, port) = try await start()
        defer { bridge.stop() }

        let answer = await handshakeStatusLine(port: port, origin: "chrome-extension://abcdefghijklmnop")

        #expect(answer?.hasPrefix("HTTP/1.1 101") == true, "got \(String(describing: answer))")
    }

    @Test("a connection that was turned away is closed by the bridge, not left open")
    func closesWhatWasTurnedAway() async throws {
        let (bridge, _, port) = try await start()
        defer { bridge.stop() }

        _ = await handshakeStatusLine(port: port, origin: "https://evil.example", keepOpen: true)

        #expect(await eventually { bridge.connectionCount == 0 })
    }

    @Test("a connection that never says anything is dropped, one that does is kept")
    func dropsTheSilent() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let silent = client(port: port, origin: "chrome-extension://silent")
        let talking = client(port: port, origin: "chrome-extension://talking")
        defer {
            silent.cancel()
            talking.cancel()
        }
        try await talking.send(.string(tabsJSON))
        #expect(await eventually { seen.connected })
        #expect(await eventually { bridge.connectionCount == 2 })

        #expect(await eventually { bridge.connectionCount == 1 })  // the silent one went after the timeout
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(bridge.connectionCount == 1)
        #expect(seen.connected)
        #expect(seen.tabs.count == 2)
    }

    // MARK: - Messages

    @Test("a ping marks the extension connected and gets a pong")
    func pingPong() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let extensionClient = client(port: port, origin: "chrome-extension://x")
        defer { extensionClient.cancel() }

        try await extensionClient.send(.string(#"{"type":"ping"}"#))

        #expect(await receiveText(from: extensionClient) == .text(#"{"type":"pong"}"#))
        #expect(seen.connected)
        #expect(seen.tabs.isEmpty)
    }

    @Test("it sends a command to the tab it belongs to")
    func sendsACommand() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let extensionClient = client(port: port, origin: "chrome-extension://x")
        defer { extensionClient.cancel() }
        try await extensionClient.send(.string(tabsJSON))
        #expect(await eventually { seen.tabs.count == 2 })

        bridge.send(to: try #require(seen.tabs.first), volume: 0.25, muted: true, micMuted: false)

        guard case .text(let text) = await receiveText(from: extensionClient) else {
            Issue.record("the extension got no command")
            return
        }
        let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["type"] as? String == "set")
        #expect(json["tabId"] as? Int == 12)
        #expect(json["volume"] as? Double == 0.25)
        #expect(json["muted"] as? Bool == true)
        #expect(json["micMuted"] as? Bool == false)
    }

    @Test("it ignores messages it does not understand and goes on listening")
    func ignoresGarbage() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let extensionClient = client(port: port, origin: "chrome-extension://x")
        defer { extensionClient.cancel() }

        try await extensionClient.send(.string("not json"))
        try await extensionClient.send(.string(#"{"type":"reboot"}"#))
        try await extensionClient.send(.string(tabsJSON))

        #expect(await eventually { seen.tabs.count == 2 })
    }

    // MARK: - Connections coming and going

    @Test("the tabs of the extension are forgotten when it disconnects")
    func forgetsOnDisconnect() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let extensionClient = client(port: port, origin: "chrome-extension://x")
        try await extensionClient.send(.string(tabsJSON))
        #expect(await eventually { seen.tabs.count == 2 })

        extensionClient.cancel(with: .goingAway, reason: nil)

        #expect(await eventually { !seen.connected && seen.tabs.isEmpty })
    }

    @Test("two browsers are two connections, and their tab ids do not clash")
    func twoBrowsers() async throws {
        let (bridge, seen, port) = try await start()
        defer { bridge.stop() }
        let first = client(port: port, origin: "chrome-extension://one")
        let second = client(port: port, origin: "chrome-extension://two")
        defer {
            first.cancel()
            second.cancel()
        }

        try await first.send(.string(#"{"type":"tabs","tabs":[{"id":1,"title":"A"}]}"#))
        #expect(await eventually { seen.tabs.count == 1 })
        try await second.send(.string(#"{"type":"tabs","tabs":[{"id":1,"title":"B"}]}"#))
        #expect(await eventually { seen.tabs.count == 2 })

        #expect(Set(seen.tabs.map(\.title)) == ["A", "B"])
        #expect(Set(seen.tabs.map(\.id)).count == 2)
    }

    @Test("stopping closes the connections and stops listening")
    func stops() async throws {
        let (bridge, seen, port) = try await start()
        let extensionClient = client(port: port, origin: "chrome-extension://x")
        defer { extensionClient.cancel() }
        try await extensionClient.send(.string(tabsJSON))
        #expect(await eventually { seen.connected })

        bridge.stop()

        #expect(!bridge.isListening)
        #expect(!seen.connected)
        #expect(seen.tabs.isEmpty)
    }
}

// MARK: - Helpers

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Polls `condition` (on the main actor, which also lets the network callbacks run) until it holds, or five seconds pass.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// Opens a plain TCP connection, asks for a WebSocket upgrade the way a browser would, and returns the first line of
/// the answer (`nil` if there is none). With `keepOpen` the connection stays open afterwards, so the test can watch
/// the server close it.
func handshakeStatusLine(port: UInt16, origin: String?, keepOpen: Bool = false) async -> String? {
    let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let finished = Once()
    let line: String? = await withCheckedContinuation { continuation in
        func finish(_ value: String?) {
            finished.run { continuation.resume(returning: value) }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var request = "GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\n"
                request += "Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                request += "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                if let origin { request += "Origin: \(origin)\r\n" }
                request += "\r\n"
                connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                    let text = data.map { String(decoding: $0, as: UTF8.self) }
                    finish(text?.components(separatedBy: "\r\n").first)
                }
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }  // never wait longer than this
    }
    if !keepOpen { connection.cancel() }
    return line
}

/// Runs its closure the first time only, from any thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ work: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        work()
    }
}

/// What a client got from the server.
enum Received: Equatable {
    case text(String)
    /// The connection failed or was refused (a handshake the bridge turned away ends here).
    case failed
    /// Nothing came in time.
    case timedOut
}

/// The next message the client gets, or how it ended: it never waits longer than `seconds`.
func receiveText(from task: URLSessionWebSocketTask, within seconds: Double = 3) async -> Received {
    await withTaskGroup(of: Received.self) { group in
        group.addTask {
            do {
                switch try await task.receive() {
                case .string(let text): return .text(text)
                case .data(let data): return .text(String(decoding: data, as: UTF8.self))
                @unknown default: return .failed
                }
            } catch {
                return .failed
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return .timedOut
        }
        let first = await group.next() ?? .timedOut
        group.cancelAll()
        // the receive that is still waiting would keep the group open: ending the connection frees it
        if first == .timedOut { task.cancel() }
        return first
    }
}
