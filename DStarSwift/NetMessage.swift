import Foundation
import simd

/// Wire format for DStar multiplayer.
///
/// Modeled after the legacy `netio.h` message vocabulary, but using Codable
/// so endian / alignment / padding portability come for free. JSON for v1
/// (easy to inspect with tcpdump); flip to a binary Codable encoder later
/// without touching call sites.
enum NetMessage: Codable, Sendable, Equatable {

    // MARK: - Membership (legacy NET_JOINING / NET_WELCOME / NET_RENAME / NET_DIED)

    /// Sent by a fresh client on join. The master responds with `.welcome`.
    case joining(peer: PeerId, name: String)

    /// Master assigns a slot in the roster.
    case welcome(toPeer: PeerId, assignedId: Int, gameType: Int)

    /// Master renames a peer that collided with an existing id.
    case rename(peer: PeerId, newId: Int)

    /// Master announces that a peer has disconnected / timed out.
    case died(peer: PeerId, lastKnownId: Int)

    /// Self-initiated graceful leave, sent before tearing down.
    case leaving(peer: PeerId)

    // MARK: - Liveness (legacy NET_ARE_YOU_THERE)

    /// Master pings the slave. Slave responds with a `.status` next tick.
    case areYouThere(toPeer: PeerId)

    // MARK: - Gameplay state (legacy NET_CURRENT_STATUS)

    /// Periodic broadcast of one ship's state. Sent by every peer ~20Hz.
    case status(ShipState)

    // MARK: - Missiles (legacy NET_REQUEST_MISSILE / NET_MISSILE)

    /// Slave asks the master for a missile id.
    case missileRequest(from: PeerId)

    /// Master allocates a missile id.
    case missileAssigned(toPeer: PeerId, missileId: Int)

    // MARK: - Scoring (legacy NET_JUST_SCORED)

    case scored(attacker: Int, victim: Int, newAttackerScore: Int)

    // MARK: - Relay (legacy NET_BROADCAST)

    /// Wrap an inner message that the receiver should rebroadcast on its
    /// subnet. Only meaningful in a master/submaster topology — we don't
    /// emit it from the Bonjour transport, but the message type is present
    /// so a GKMatch (host-relay) transport can use it later.
    indirect case relay(inner: NetMessage)
}

/// Identifier the transport uses for a peer. For Bonjour this is the
/// resolved service name (typically `DStar — <hostname>`); for GKMatch it
/// would be the `GKPlayer.gamePlayerID`.
typealias PeerId = String

/// Snapshot of a ship's state on the wire, mirroring legacy NET_CURRENT_STATUS.
///
/// Encoding strategy: `SIMD3<Float>` is encoded as `[Float]` because Codable
/// for simd types is platform-quirky and `[Float]` round-trips trivially.
struct ShipState: Codable, Sendable, Equatable {
    /// Bonjour service name of the process that owns this object. Older
    /// packets may omit it, so it remains optional for wire compatibility.
    var ownerPeer: PeerId?
    var id: Int
    var name: String
    var team: Int
    var score: Int
    /// Optional so packets from builds predating flying missiles still decode.
    var objectClass: Int?
    var status: Int             // DStarObjectState raw
    var flags: UInt32

    var position: [Float]       // 3
    var forward: [Float]        // 3
    var up: [Float]             // 3
    var right: [Float]          // 3
    var delta: [Float]          // 3
    var pointing: [Float]       // 3

    var speed: Float
    var targetID: Int?
    var sequence: Int

    /// Convert from in-memory `DStarObject`.
    init(_ ship: DStarObject, ownerPeer: PeerId? = nil) {
        self.ownerPeer = ownerPeer
        id = ship.id
        name = ship.name
        team = ship.team
        score = ship.score
        objectClass = ship.objectClass.rawValue
        status = ship.status.rawValue
        flags = ship.flags
        position = [ship.position.x, ship.position.y, ship.position.z]
        forward  = [ship.forward.x,  ship.forward.y,  ship.forward.z]
        up       = [ship.up.x,       ship.up.y,       ship.up.z]
        right    = [ship.right.x,    ship.right.y,    ship.right.z]
        delta    = [ship.delta.x,    ship.delta.y,    ship.delta.z]
        pointing = [ship.pointing.x, ship.pointing.y, ship.pointing.z]
        speed = ship.speed
        targetID = ship.targetID
        sequence = ship.sequence
    }

    /// Convert back into a `DStarObject` for `applyRemoteSnapshot`.
    func toDStarObject() -> DStarObject {
        var o = DStarObject()
        o.id = id
        o.name = name
        o.team = team
        o.score = score
        o.status = DStarObjectState(rawValue: status) ?? .active
        o.flags = flags
        o.position = vec(position)
        o.forward = vec(forward)
        o.up = vec(up)
        o.right = vec(right)
        o.delta = vec(delta)
        o.pointing = vec(pointing)
        o.speed = speed
        o.targetID = targetID
        o.sequence = sequence
        o.objectClass = objectClass.flatMap(DStarObjectClass.init(rawValue:)) ?? .remote
        return o
    }

    private func vec(_ a: [Float]) -> SIMD3<Float> {
        guard a.count >= 3 else { return .zero }
        return SIMD3<Float>(a[0], a[1], a[2])
    }
}

// MARK: - Codable helpers

extension NetMessage {
    /// Encode to JSON Data. Used by the transport.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return try encoder.encode(self)
    }

    /// Decode from JSON Data. Returns nil on malformed input rather than
    /// throwing — the transport should drop bad datagrams, not crash.
    static func decode(_ data: Data) -> NetMessage? {
        try? JSONDecoder().decode(NetMessage.self, from: data)
    }
}
