import XCTest
import simd
@testable import DStarSwift

@MainActor
final class GameStateTests: XCTestCase {
    func testSpawnRobotCreatesHuntingControllerAndUniqueIDs() {
        let game = DStarGameState()
        let first = game.spawnRobot(near: .zero)
        let second = game.spawnRobot(near: .zero)

        XCTAssertEqual(first, 1000)
        XCTAssertEqual(second, 1001)
        XCTAssertEqual(game.others[first]?.objectClass, .robot)
        XCTAssertEqual(game.others[first]?.flags, DStarObjectFlags.robot)
        XCTAssertTrue(game.controllers[first] is AutopilotController)
    }

    func testLaunchedMissileBecomesFlyingObjectAndExpires() {
        let game = DStarGameState()
        game.me.position = .zero
        game.me.forward = SIMD3<Float>(0, 0, 1)

        game.apply(.keyCharacter("q"))
        XCTAssertEqual(game.armedMissiles, 1)
        game.apply(.keyCharacter("w"))

        guard let missile = game.others.values.first(where: {
            $0.objectClass == .missile
        }) else {
            return XCTFail("Firing should create a missile object")
        }
        XCTAssertEqual(missile.position.z, 24, accuracy: 0.0001)
        XCTAssertEqual(missile.speed, DStarGameParameters.missileSpeed)
        XCTAssertEqual(missile.time, DStarGameParameters.missileLife)
        XCTAssertEqual(game.armedMissiles, 0)
        XCTAssertEqual(game.missilesRemaining, DStarGameParameters.missilesPerLife - 1)
        XCTAssertTrue(game.controllers[missile.id] is MissileController)

        game.step(deltaTime: 0.5)
        XCTAssertGreaterThan(game.others[missile.id]?.position.z ?? 0, 24)
        game.step(deltaTime: 10)
        XCTAssertNil(game.others[missile.id])
        XCTAssertNil(game.controllers[missile.id])
    }

    func testFreezeStopsSimulationAndCallback() {
        let game = DStarGameState()
        game.me.position = .zero
        game.me.forward = SIMD3<Float>(0, 0, 1)
        var callbackCount = 0
        game.onLocalStateAdvanced = { _ in callbackCount += 1 }

        game.apply(.keyCharacter("f"))
        game.step(deltaTime: 1)

        XCTAssertEqual(game.me.position, .zero)
        XCTAssertEqual(callbackCount, 0)
    }

    func testRadarCyclesThroughShipsInIDOrder() {
        let game = DStarGameState()
        for id in [9, 3] {
            var ship = DStarObject()
            ship.id = id
            game.addShip(ship, controller: RemoteController())
        }

        game.apply(.keyCharacter("r"))
        game.apply(.tab)
        XCTAssertEqual(game.me.targetID, 3)
        game.apply(.tab)
        XCTAssertEqual(game.me.targetID, 9)
        game.apply(.tab)
        XCTAssertEqual(game.me.targetID, 3)
    }

    func testLegacyHUDMirrorsScoreTargetRangeLocksAndOrientation() {
        let game = DStarGameState()
        game.me.position = .zero
        game.me.score = 20
        game.me.flags |= DStarObjectFlags.radar
        game.me.targetID = 7

        var target = DStarObject()
        target.id = 7
        target.name = "Robot 7"
        target.position = SIMD3<Float>(3, 4, 0)
        target.targetID = game.me.id
        game.addShip(target, controller: RemoteController())

        let hud = DStarHUDState()
        hud.update(from: game)

        XCTAssertTrue(hud.showHelp)
        XCTAssertTrue(hud.radarOn)
        XCTAssertEqual(hud.score, 20)
        XCTAssertEqual(hud.radarTargetName, "Robot 7")
        XCTAssertEqual(hud.radarTargetRange ?? -1, 5, accuracy: 0.0001)
        XCTAssertEqual(hud.lockedBy, ["Robot 7"])
        XCTAssertEqual(hud.orientation, .identity)
    }

    func testAutopilotSteersTowardAndFiresAtCloseTarget() {
        var ship = DStarObject()
        ship.id = 1000
        ship.position = .zero
        ship.forward = SIMD3<Float>(0, 0, 1)
        ship.targetID = 0

        var target = DStarObject()
        target.id = 0
        target.position = SIMD3<Float>(0, 0, 100)

        let controller = AutopilotController()
        controller.step(
            ship: &ship,
            world: ShipWorld(
                dtime: 0.1,
                others: [target.id: target],
                input: DStarInputState(),
                mouseControl: false
            )
        )

        XCTAssertGreaterThan(ship.position.z, 0)
        XCTAssertNotEqual(ship.flags & DStarObjectFlags.laser, 0)
        XCTAssertEqual(ship.delta.x, 0, accuracy: 0.0001)
        XCTAssertEqual(ship.delta.y, 0, accuracy: 0.0001)
    }

    func testKinematicsKeepsBasisOrthonormal() {
        var ship = DStarObject()
        ship.position = .zero
        ship.delta = SIMD3<Float>(0.4, -0.25, 0.1)

        ShipKinematics.advance(ship: &ship, dtime: 0.5)

        XCTAssertEqual(simd_length(ship.forward), 1, accuracy: 0.0001)
        XCTAssertEqual(simd_length(ship.up), 1, accuracy: 0.0001)
        XCTAssertEqual(simd_length(ship.right), 1, accuracy: 0.0001)
        XCTAssertEqual(simd_dot(ship.forward, ship.up), 0, accuracy: 0.0001)
        XCTAssertEqual(simd_dot(ship.forward, ship.right), 0, accuracy: 0.0001)
        XCTAssertEqual(simd_dot(ship.up, ship.right), 0, accuracy: 0.0001)
    }

    func testRemoteControllerDeadReckonsAcrossFrames() {
        var ship = DStarObject()
        ship.id = 44
        ship.name = "Remote"
        var snapshot = ship
        snapshot.position = .zero
        snapshot.forward = SIMD3<Float>(0, 0, 1)
        snapshot.speed = 10
        let controller = RemoteController()
        controller.apply(snapshot)
        let world = ShipWorld(
            dtime: 0.5,
            others: [:],
            input: DStarInputState(),
            mouseControl: false
        )

        controller.step(ship: &ship, world: world)
        controller.step(ship: &ship, world: world)

        XCTAssertEqual(ship.position.z, 10, accuracy: 0.0001)
    }

    func testRemoteMissileExpiresAfterSnapshotsStop() {
        var ship = DStarObject()
        ship.id = 44
        ship.objectClass = .missile
        ship.time = 0.25
        let controller = RemoteController()
        controller.apply(ship)

        controller.step(
            ship: &ship,
            world: ShipWorld(
                dtime: 0.5,
                others: [:],
                input: DStarInputState(),
                mouseControl: false
            )
        )

        XCTAssertEqual(ship.status, .dead)
    }
}
