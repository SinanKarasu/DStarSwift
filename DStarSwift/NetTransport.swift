import Foundation
import Network

/// Abstraction over the network transport. Two implementations are planned:
///
///   - `BonjourUDPTransport` (this file, ready to use): UDP unicast to every
///     peer discovered via Bonjour. Zero-config on a LAN, no accounts, no
///     server. This is the "local play" path the user asked for.
///   - `GKMatchTransport` (future): wraps `GKMatch.send(...)`. Drops in
///     without `NetSession` changing because of this protocol.
///
/// Both deliver opaque `Data` blobs back to `onReceive`. The wire format
/// (`NetMessage` / JSON) lives one layer up so the transport stays format-free.
protocol NetTransport: AnyObject {
    /// Begin listening + start browsing for peers.
    func start()
    /// Tear down — closes listener, drops all connections, removes the
    /// service advertisement.
    func stop()

    /// Send a payload. `peer == nil` means "broadcast to every known peer".
    func send(_ data: Data, to peer: PeerId?)

    /// Called whenever a payload arrives. Always invoked on `callbackQueue`.
    var onReceive: ((Data, PeerId) -> Void)? { get set }

    /// Called when the discovered peer set changes (additions or removals).
    var onPeersChanged: (([PeerId]) -> Void)? { get set }

    /// The queue all callbacks fire on. Defaults to `.main` for the
    /// implementations here so it's safe to touch SwiftUI / game state.
    var callbackQueue: DispatchQueue { get }
}

// MARK: - Bonjour + UDP

/// Bonjour-discovered UDP unicast.
///
/// Each instance is both a listener (peers send to us) and a browser
/// (we discover peers). When a peer is discovered, we open an `NWConnection`
/// to them lazily on the first `send`. Discovery additions/removals fire
/// `onPeersChanged`.
///
/// Service type is `_dstar._udp` so multiple DStar instances on the same
/// LAN find each other. Each instance advertises a unique name that combines
/// the host's `localHostName` with a short random suffix — that name is the
/// `PeerId` used throughout the rest of the stack.
final class BonjourUDPTransport: NetTransport {

    // MARK: Configuration

    static let serviceType = "_dstar._udp"
    static let serviceDomain = "local."

    let serviceName: String
    private(set) var localPort: UInt16

    let callbackQueue: DispatchQueue
    var onReceive: ((Data, PeerId) -> Void)?
    var onPeersChanged: (([PeerId]) -> Void)?

    // MARK: Internals

    private let queue = DispatchQueue(label: "dstar.bonjour", qos: .userInteractive)
    private var listener: NWListener?
    private var browser: NWBrowser?

    /// Inbound NWConnections — one per remote peer that connected to us.
    private var inbound: [ObjectIdentifier: NWConnection] = [:]
    /// Outbound NWConnections — keyed by PeerId, opened lazily on first send.
    private var outbound: [PeerId: NWConnection] = [:]
    /// Discovered Bonjour endpoints, keyed by their advertised name.
    private var endpoints: [PeerId: NWEndpoint] = [:]

    /// Whether `start()` has been called. Guards against double-start.
    private var started = false

    init(
        serviceName: String? = nil,
        preferredPort: UInt16 = 0,
        callbackQueue: DispatchQueue = .main
    ) {
        self.serviceName = serviceName ?? Self.defaultName()
        self.localPort = preferredPort
        self.callbackQueue = callbackQueue
    }

    private static func defaultName() -> String {
        // `Host.current()` is macOS-only and deprecated; `hostName` works
        // on macOS / iOS / visionOS alike.
        let host = ProcessInfo.processInfo.hostName
            .components(separatedBy: ".").first ?? "DStar"
        let suffix = String(UInt32.random(in: 0...0xFFFF), radix: 16)
        return "DStar \(host) \(suffix)"
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        // Listener
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let port: NWEndpoint.Port = (localPort == 0)
                ? .any
                : NWEndpoint.Port(rawValue: localPort)!
            let listener = try NWListener(using: params, on: port)
            listener.service = NWListener.Service(
                name: serviceName,
                type: Self.serviceType,
                domain: Self.serviceDomain
            )
            listener.stateUpdateHandler = { [weak self] state in
                if case let .ready = state {
                    if let p = self?.listener?.port?.rawValue {
                        self?.localPort = p
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.acceptInbound(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("[DStarNet] listener failed: \(error)")
        }

        // Browser
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: Self.serviceDomain),
            using: NWParameters.udp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleBrowse(results: results)
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        guard started else { return }
        started = false
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        for c in inbound.values { c.cancel() }
        for c in outbound.values { c.cancel() }
        inbound.removeAll()
        outbound.removeAll()
        endpoints.removeAll()
        let cq = callbackQueue
        cq.async { [weak self] in
            self?.onPeersChanged?([])
        }
    }

    // MARK: Inbound

    private func acceptInbound(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(on: connection)
            case .failed, .cancelled:
                self.inbound.removeValue(forKey: ObjectIdentifier(connection))
            default:
                break
            }
        }
        inbound[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty {
                // Best-effort: the sender's name is in our endpoint table, but
                // an inbound NWConnection doesn't carry the Bonjour name. We
                // surface the remote endpoint's `debugDescription` as the
                // peer id for inbound-only callers; for ones we've also
                // discovered via the browser, NetSession dedups by message
                // content (id field inside ShipState).
                let peer = self.peerName(for: connection.endpoint)
                let cq = self.callbackQueue
                cq.async {
                    self.onReceive?(data, peer)
                }
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }

    private func peerName(for endpoint: NWEndpoint) -> PeerId {
        // Prefer the Bonjour service name if we've cached it.
        for (name, ep) in endpoints {
            if ep == endpoint { return name }
        }
        return endpoint.debugDescription
    }

    // MARK: Browser

    private func handleBrowse(results: Set<NWBrowser.Result>) {
        // Filter to actual peers (not ourselves) and update endpoint table.
        var fresh: [PeerId: NWEndpoint] = [:]
        for r in results {
            if case let .service(name, _, _, _) = r.endpoint {
                if name == serviceName { continue }
                fresh[name] = r.endpoint
            }
        }
        let added = Set(fresh.keys).subtracting(endpoints.keys)
        let removed = Set(endpoints.keys).subtracting(fresh.keys)
        // Drop outbound connections to peers that disappeared.
        for name in removed {
            outbound[name]?.cancel()
            outbound.removeValue(forKey: name)
        }
        endpoints = fresh

        let names = Array(fresh.keys).sorted()
        let cq = callbackQueue
        cq.async { [weak self] in
            self?.onPeersChanged?(names)
        }
        _ = added // hook for "new peer" events if we ever want them
    }

    // MARK: Send

    func send(_ data: Data, to peer: PeerId?) {
        queue.async { [weak self] in
            guard let self else { return }
            if let peer {
                self.send(data, toPeer: peer)
            } else {
                for name in self.endpoints.keys {
                    self.send(data, toPeer: name)
                }
            }
        }
    }

    private func send(_ data: Data, toPeer name: PeerId) {
        guard let endpoint = endpoints[name] else { return }
        let conn: NWConnection
        if let existing = outbound[name], existing.state != .cancelled {
            conn = existing
        } else {
            conn = NWConnection(to: endpoint, using: .udp)
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self, let conn else { return }
                if case .failed = state {
                    self.outbound.removeValue(forKey: name)
                    conn.cancel()
                }
            }
            conn.start(queue: queue)
            outbound[name] = conn
        }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }
}
