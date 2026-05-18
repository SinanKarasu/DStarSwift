import Foundation
import Combine

/// Wires a `NetTransport` to a `DStarGameState`.
///
/// On the way out:
///   - Every `statusBroadcastHz` ticks, encodes `me` as `NetMessage.status`
///     and broadcasts to all known peers.
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

    init(transport: any NetTransport = BonjourUDPTransport(),
         game: DStarGameState? = nil) {
        self.transport = transport
        self.game = game
        if let bonjour = transport as? BonjourUDPTransport {
            self.localName = bonjour.serviceName
        } else {
            self.localName = "DStar"
        }
        self.transport.onReceive = { [weak self] data, peer in
            self?.handleIncoming(data, from: peer)
        }
        self.transport.onPeersChanged = { [weak self] names in
            self?.peers = names
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

        // Periodic status broadcast.
        let hz = DStarGameParameters.statusBroadcastHz
        broadcastTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / hz,
            repeats: true
        ) { [weak self] _ in
            self?.broadcastSelf()
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

    private func broadcastSelf() {
        guard isRunning, let game else { return }
        send(.status(ShipState(game.me)))
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
            if state.id == game.me.id { return }
            game.applyRemoteSnapshot(state.toDStarObject())

        case let .leaving(peer):
            // We don't know the peer's id directly without an earlier
            // welcome handshake — for v1, sweep any remote ship whose name
            // matches the leaving peer.
            for (id, ship) in game.others {
                if ship.name == peer { game.removeShip(id: id) }
            }

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
}
