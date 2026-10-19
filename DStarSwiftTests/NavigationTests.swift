import XCTest
import simd
@testable import DStarSwift

@MainActor
final class NavigationTests: XCTestCase {
    func testLookChangesViewWithoutChangingFlight() {
        let game = DStarGameState()
        game.apply(.visitHabitat)
        let forward = game.me.forward
        game.apply(.setLook(DStarLook(yaw: .pi / 2, pitch: 0)))
        game.step(deltaTime: 1)
        XCTAssertEqual(game.me.forward, forward)
        let view = game.look.orientation(relativeTo: .identity)
        XCTAssertEqual(view.forward.x, 1, accuracy: 0.0001)
        XCTAssertEqual(view.forward.z, 0, accuracy: 0.0001)
        game.apply(.setLook(DStarLook()))
        XCTAssertEqual(game.look.orientation(relativeTo: .identity), .identity)
    }

    func testLookKeepsOrthonormalBasisAndBoundsPitch() {
        let look = DStarLook(yaw: 45, pitch: 100)
        XCTAssertLessThan(look.pitch, .pi / 2)
        let view = look.orientation(relativeTo: .identity)
        XCTAssertEqual(simd_length(view.forward), 1, accuracy: 0.0001)
        XCTAssertEqual(simd_dot(view.forward, view.up), 0, accuracy: 0.0001)
        XCTAssertEqual(simd_dot(view.forward, view.right), 0, accuracy: 0.0001)
        XCTAssertEqual(DStarLook(yaw: .nan, pitch: .infinity), DStarLook())
    }

    func testSteeringDeadZoneClampAndRelease() {
        XCTAssertEqual(DStarLook.steering(SIMD2(0.05, -0.05)), .zero)
        XCTAssertEqual(DStarLook.steering(SIMD2(5, -5)), SIMD2(1, -1))
        let game = DStarGameState()
        game.apply(.visitHabitat)
        game.apply(.keyCharacter("a"))
        game.apply(.setGlobeSteering(SIMD2(0.5, 0)))
        XCTAssertFalse(game.autoPilot)
        let initial = game.me.forward
        game.step(deltaTime: 0.1)
        XCTAssertNotEqual(game.me.forward, initial)
        game.apply(.setGlobeSteering(.zero))
        let released = game.me.forward
        game.step(deltaTime: 0.1)
        XCTAssertEqual(game.me.forward, released)
        XCTAssertEqual(game.me.delta, .zero)
    }

    func testArrivalResetsLookAndSteering() {
        let game = DStarGameState()
        game.apply(.setLook(DStarLook(yaw: 1, pitch: 0.5)))
        game.apply(.setGlobeSteering(SIMD2(1, 1)))
        game.apply(.visitHabitat)
        XCTAssertEqual(game.look, DStarLook())
        XCTAssertEqual(game.input.globeSteering, .zero)
    }
}
