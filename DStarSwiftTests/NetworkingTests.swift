import XCTest
@testable import DStarSwift

@MainActor
final class NetworkingTests: XCTestCase {
    func testNetMessageRoundTripsCompleteShipState() throws {
        var ship = DStarObject()
        ship.id = 42
        ship.name = "Remote Robot"
        ship.team = 2
        ship.score = 17
        ship.flags = DStarObjectFlags.robot | DStarObjectFlags.laser
        ship.position = SIMD3<Float>(1, 2, 3)
        ship.forward = SIMD3<Float>(0, 1, 0)
        ship.up = SIMD3<Float>(0, 0, 1)
        ship.right = SIMD3<Float>(1, 0, 0)
        ship.targetID = 7

        let original = NetMessage.status(ShipState(ship, ownerPeer: "Mac"))
        let decoded = NetMessage.decode(try original.encoded())

        XCTAssertEqual(decoded, original)
    }

    func testBroadcastIncludesPlayerAndLocallyOwnedRobotsWithNamespacedIDs() {
        let transport = FakeTransport()
        let game = DStarGameState()
        let robotID = game.spawnRobot(near: .zero)
        let session = NetSession(transport: transport, game: game)

        session.broadcastCurrentState()

        let states = transport.sent.compactMap { data -> ShipState? in
            guard case let .status(state) = NetMessage.decode(data) else { return nil }
            return state
        }
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(Set(states.compactMap(\.ownerPeer)), ["DStar"])
        XCTAssertTrue(states.contains { $0.id == session.networkObjectID(for: game.me.id) })
        XCTAssertTrue(states.contains { $0.id == session.networkObjectID(for: robotID) })
        XCTAssertFalse(states.contains { $0.id == DStarGameParameters.localShipId })
    }

    func testBroadcastIncludesFlyingMissile() {
        let transport = FakeTransport()
        let game = DStarGameState()
        game.apply(.keyCharacter("q"))
        game.apply(.keyCharacter("w"))
        let session = NetSession(transport: transport, game: game)

        session.broadcastCurrentState()

        let states = transport.sent.compactMap { data -> ShipState? in
            guard case let .status(state) = NetMessage.decode(data) else { return nil }
            return state
        }
        XCTAssertEqual(states.count, 2)
        XCTAssertEqual(
            states.filter { $0.objectClass == DStarObjectClass.missile.rawValue }.count,
            1
        )
    }

    func testIncomingStatusAddsRemoteAndLeavingRemovesAllOwnedShips() throws {
        let transport = FakeTransport()
        let game = DStarGameState()
        let session = NetSession(transport: transport, game: game)
        var player = DStarObject()
        player.id = 70_000
        player.name = "Vision Pro"
        var robot = DStarObject()
        robot.id = 70_001
        robot.name = "Vision Pro • Robot 1000"

        transport.inject(.status(ShipState(player, ownerPeer: "Vision Pro")), from: "endpoint")
        transport.inject(.status(ShipState(robot, ownerPeer: "Vision Pro")), from: "endpoint")

        XCTAssertEqual(game.others.count, 2)
        XCTAssertEqual(game.others[player.id]?.objectClass, .remote)

        transport.inject(.leaving(peer: "Vision Pro"), from: "endpoint")
        XCTAssertTrue(game.others.isEmpty)
        _ = session // retain through callback assertions
    }

    func testLoopedBackPacketIsIgnored() {
        let transport = FakeTransport()
        let game = DStarGameState()
        let session = NetSession(transport: transport, game: game)
        var ship = DStarObject()
        ship.id = session.networkObjectID(for: game.me.id)

        transport.inject(.status(ShipState(ship, ownerPeer: session.localName)), from: "self")

        XCTAssertTrue(game.others.isEmpty)
    }
}

@MainActor
private final class FakeTransport: NetTransport {
    let callbackQueue = DispatchQueue.main
    var onReceive: ((Data, PeerId) -> Void)?
    var onPeersChanged: (([PeerId]) -> Void)?
    private(set) var isStarted = false
    private(set) var sent: [Data] = []

    func start() { isStarted = true }

    func stop() {
        isStarted = false
        onPeersChanged?([])
    }

    func send(_ data: Data, to peer: PeerId?) {
        sent.append(data)
    }

    func inject(_ message: NetMessage, from peer: PeerId) {
        onReceive?(try! message.encoded(), peer)
    }
}
