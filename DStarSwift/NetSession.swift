import Foundation
import Combine

/// Wires a `NetTransport` to a `DStarGameState`.
///
/// On the way out:
///   - Every `statusBroadcastHz` ticks, encodes the player and locally-owned
///     robots as `NetMessage.status` and broadcasts them to all known peers.
///
/// On the way in:
///   - `.status` → `game.applyRemoteSnapshot(...)`.
///   - `.leaving` / `.died` → `game.removeShip(id:)`.
///   - other message types are accepted but not yet acted on (missile and
///     scoring authority will land in a follow-up slice).
///
/// Bonjour treats peers symmetrically — there is no master election in v1.
/// When the user is ready for host-authoritative play, swap in a transport
/// that designates a host and gate the missile / scoring branches here on
/// `isHost`.
@MainActor
final class NetSession: ObservableObject {

    // MARK: - SwiftUI observable state

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var peers: [PeerId] = []
    @Published private(set) var lastError: String?
    @Published var localName: String

    // MARK: - Wiring

    let transport: any NetTransport
    private weak var game: DStarGameState?
    private var broadcastTimer: Timer?
    private let networkNamespace: Int
    private var remoteShipIDsByOwner: [PeerId: Set<Int>] = [:]

    init(transport: any NetTransport = BonjourUDPTransport(),
         game: DStarGameState? = nil) {
        let resolvedName: String
        if let bonjour = transport as? BonjourUDPTransport {
            resolvedName = bonjour.serviceName
        } else {
            resolvedName = "DStar"
        }
        self.transport = transport
        self.game = game
        self.localName = resolvedName
        self.networkNamespace = Self.makeNetworkNamespace(for: resolvedName)
        self.transport.onReceive = { [weak self] data, peer in
            self?.handleIncoming(data, from: peer)
        }
        self.transport.onPeersChanged = { [weak self] names in
            self?.handlePeersChanged(names)
        }
    }

    /// Attach (or re-attach) the game state. Called from `DStarSwiftApp`
    /// once the renderer's game state is available.
    func attach(game: DStarGameState) {
        self.game = game
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        transport.start()

        // Periodic status broadcast. The timer is added to the current
        // (main) run loop; the closure fires on main but the compiler can't
        // see that, so we use `MainActor.assumeIsolated` to satisfy isolation.
        let hz = DStarGameParameters.statusBroadcastHz
        broadcastTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / hz,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.broadcastCurrentState()
            }
        }

        // Announce ourselves.
        send(.joining(peer: localName, name: localName))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        send(.leaving(peer: localName))
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        transport.stop()
        peers = []
    }

    // MARK: - Outbound

    /// Broadcast every object simulated by this process. Kept internal so
    /// unit tests can exercise the wire boundary without waiting on a timer.
    func broadcastCurrentState() {
        guard let game else { return }
        var ownedShips = [game.me]
        ownedShips.append(contentsOf: game.others.values.filter {
            $0.objectClass == .robot || $0.objectClass == .missile
        })

        for ship in ownedShips {
            var wireShip = ship
            wireShip.id = networkObjectID(for: ship.id)
            if let targetID = ship.targetID,
               targetID == game.me.id || game.others[targetID]?.objectClass == .robot {
                wireShip.targetID = networkObjectID(for: targetID)
            }
            wireShip.name = ship.id == game.me.id
                ? localName
                : "\(localName) • \(ship.name)"
            send(.status(ShipState(wireShip, ownerPeer: localName)))
        }
    }

    func send(_ message: NetMessage, to peer: PeerId? = nil) {
        do {
            let data = try message.encoded()
            transport.send(data, to: peer)
        } catch {
            lastError = "encode failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Inbound

    private func handleIncoming(_ data: Data, from peer: PeerId) {
        guard let message = NetMessage.decode(data) else {
            // Bad datagram — drop silently. Logging here would be noisy.
            return
        }
        guard let game else { return }
        switch message {
        case let .status(state):
            // Ignore our own loopback (some routers reflect broadcasts).
            if state.ownerPeer == localName { return }
            let owner = state.ownerPeer ?? peer
            remoteShipIDsByOwner[owner, default: []].insert(state.id)
            game.applyRemoteSnapshot(state.toDStarObject())

        case let .leaving(peer):
            removeRemoteShips(ownedBy: peer)

        case let .died(_, lastKnownId):
            game.removeShip(id: lastKnownId)

        case .joining, .welcome, .areYouThere,
             .missileRequest, .missileAssigned,
             .scored, .rename, .relay:
            // Accepted but not yet acted on. Land these in the
            // missile + scoring follow-up slice.
            break
        }
    }

    // MARK: - Peer identity and cleanup

    /// Maps a local object id into a per-peer namespace. Keeping the value
    /// below 2^53 also makes it safe if a future web client parses the JSON.
    func networkObjectID(for localID: Int) -> Int {
        (networkNamespace << 16) | (localID & 0xFFFF)
    }

    private static func makeNetworkNamespace(for peer: PeerId) -> Int {
        // FNV-1a is deterministic across processes (unlike Swift.Hasher).
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in peer.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return max(1, Int(hash & 0x7FFF_FFFF))
    }

    private func handlePeersChanged(_ names: [PeerId]) {
        let departed = Set(peers).subtracting(names)
        peers = names
        for peer in departed {
            removeRemoteShips(ownedBy: peer)
        }
    }

    private func removeRemoteShips(ownedBy peer: PeerId) {
        guard let game else { return }
        let ids = remoteShipIDsByOwner.removeValue(forKey: peer) ?? []
        for id in ids {
            game.removeShip(id: id)
        }

        // Compatibility cleanup for packets from versions without ownerPeer.
        for (id, ship) in game.others
        where (ship.objectClass == .remote || ship.objectClass == .missile) &&
              (ship.name == peer || ship.name.hasPrefix("\(peer) • ")) {
            game.removeShip(id: id)
        }
    }
}
