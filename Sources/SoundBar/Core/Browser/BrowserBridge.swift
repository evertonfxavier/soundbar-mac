import Foundation
import Network

/// Local WebSocket server (127.0.0.1 only) the Chrome extension connects to.
/// Only clients whose Origin is a chrome-extension:// URL are accepted, so web pages can't use it.
@MainActor
final class BrowserBridge {
    /// Where the extension looks for the app. The extension has the same number; contract/protocol.json holds it
    /// and both sides are checked against it.
    nonisolated static let defaultPort: UInt16 = 38765

    /// The Origin of a WebSocket opened by an extension. A web page has an http(s) origin and is turned away.
    nonisolated static let allowedOriginPrefix = "chrome-extension://"

    /// A connection that has said nothing the app understands (no `tabs`, no `ping`) by then is dropped. The extension
    /// sends its tabs the moment it connects, so it is never in doubt; what stays silent is a client that was turned
    /// away at the handshake (it gets an HTTP 400, but the socket is left open) or that is no extension at all.
    nonisolated static let defaultHandshakeTimeout: TimeInterval = 15

    let port: UInt16
    let handshakeTimeout: TimeInterval

    /// Called with every tab of every connection, and whether any extension is connected.
    var onChange: (@MainActor ([BrowserTab], Bool) -> Void)?

    /// The listener is up and accepting connections.
    private(set) var isListening = false

    /// How many connections are open, whether or not they have spoken yet.
    var connectionCount: Int { conns.count }

    private struct Conn {
        let connection: NWConnection
        var tabs: [BrowserTab] = []
        var ready = false
    }

    private var listener: NWListener?
    private var conns: [Int: Conn] = [:]
    private var nextID = 1

    init(
        port: UInt16 = BrowserBridge.defaultPort, handshakeTimeout: TimeInterval = BrowserBridge.defaultHandshakeTimeout
    ) {
        self.port = port
        self.handshakeTimeout = handshakeTimeout
    }

    func start() {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            NSLog("SoundBar: invalid bridge port \(port)")
            return
        }

        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 1 << 20
        ws.setClientRequestHandler(.main) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let ok = origin.hasPrefix(BrowserBridge.allowedOriginPrefix)
            return NWProtocolWebSocket.Response(status: ok ? .accept : .reject, subprotocol: nil)
        }

        let params = NWParameters.tcp
        // Bind to 127.0.0.1 explicitly: requiredInterfaceType alone still listens on all addresses.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
        params.allowLocalEndpointReuse = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

        do {
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in
                MainActor.assumeIsolated { self?.accept(c) }
            }
            l.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        self?.isListening = true
                    case .failed(let err):
                        NSLog("SoundBar: bridge listener failed: \(err)")
                        self?.isListening = false
                    case .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("SoundBar: cannot listen on port \(port): \(error)")
        }
    }

    /// Stops listening and drops every connection.
    func stop() {
        listener?.cancel()
        listener = nil
        let open = conns.values
        conns.removeAll()
        for conn in open { conn.connection.cancel() }
        isListening = false
        onChange?([], false)
    }

    // MARK: - Commands to the extension

    func send(to tab: BrowserTab, volume: Float? = nil, muted: Bool? = nil, micMuted: Bool? = nil) {
        guard let c = conns[tab.conn]?.connection,
            let data = BridgeProtocol.set(tabID: tab.tabID, volume: volume, muted: muted, micMuted: micMuted)
        else { return }
        sendText(data, on: c)
    }

    // MARK: - Connections

    private func accept(_ c: NWConnection) {
        let id = nextID
        nextID += 1
        conns[id] = Conn(connection: c)
        c.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.drop(id)
                default: break
                }
            }
        }
        c.start(queue: .main)
        receive(id, c)
        DispatchQueue.main.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.conns[id]?.ready == false { self.drop(id) }
            }
        }
    }

    private func receive(_ id: Int, _ c: NWConnection) {
        c.receiveMessage { [weak self] data, context, _, error in
            MainActor.assumeIsolated {
                guard let self, self.conns[id] != nil else { return }
                if let data,
                    let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                        as? NWProtocolWebSocket.Metadata
                {
                    switch meta.opcode {
                    case .text: self.handle(data, from: id)
                    case .close:
                        self.drop(id)
                        return
                    default: break
                    }
                }
                if error != nil {
                    self.drop(id)
                    return
                }
                self.receive(id, c)
            }
        }
    }

    private func handle(_ data: Data, from id: Int) {
        guard let message = BridgeProtocol.decode(data) else { return }
        switch message {
        case .tabs(let tabs):
            conns[id]?.tabs = tabs.map { $0.model(conn: id) }
            conns[id]?.ready = true
            notify()
        case .ping:
            if conns[id]?.ready != true {
                conns[id]?.ready = true
                notify()
            }
            if let c = conns[id]?.connection { sendText(BridgeProtocol.pong, on: c) }
        }
    }

    private func drop(_ id: Int) {
        guard let conn = conns.removeValue(forKey: id) else { return }
        conn.connection.cancel()
        notify()
    }

    private func notify() {
        let tabs = conns.keys.sorted().flatMap { conns[$0]?.tabs ?? [] }
        onChange?(tabs, conns.values.contains { $0.ready })
    }

    private func sendText(_ data: Data, on c: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "soundbar", metadata: [meta])
        c.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }
}
