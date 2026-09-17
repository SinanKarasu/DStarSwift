import XCTest
import simd
@testable import DStarSwift

@MainActor
final class LegacyWorldTests: XCTestCase {
    func testSunEraWorldRestoresEveryLegacyBody() {
        let world = DStarLegacyWorld(seed: 1)

        XCTAssertEqual(world.bodies.map(\.kind), DStarLegacyBodyKind.allCases)
        XCTAssertEqual(world.bodies.map(\.name), [
            "mars-100", "mars-50", "TMA-2", "ringworld"
        ])
        XCTAssertEqual(BSPUtil.nodes(in: world.bodies[0].mesh).count, 18 * 36)
        XCTAssertEqual(BSPUtil.nodes(in: world.bodies[1].mesh).count, 18 * 36)
        XCTAssertEqual(BSPUtil.nodes(in: world.bodies[2].mesh).count, 6)
        XCTAssertEqual(BSPUtil.nodes(in: world.bodies[3].mesh).count, 7 * 72)
    }

    func testRingworldUsesOriginalPlacementAndBasis() {
        let world = DStarLegacyWorld(seed: 1)
        guard let ring = world.bodies.first(where: { $0.kind == .ringworld }) else {
            return XCTFail("Ringworld missing")
        }

        XCTAssertEqual(ring.motion.position, SIMD3<Float>(4_000, 0, 0))
        XCTAssertEqual(ring.motion.forward, SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(ring.motion.right, SIMD3<Float>(0, -1, 0))
        XCTAssertEqual(ring.motion.up, SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(ring.motion.delta, SIMD3<Float>(0.01, 0, 0))
    }

    func testWorldMotionPreservesOrthonormalBodies() {
        let world = DStarLegacyWorld(seed: 2)
        let originalRingForward = world.bodies
            .first(where: { $0.kind == .ringworld })?.motion.forward

        world.advance(to: 2)

        XCTAssertEqual(world.elapsedTime, 2, accuracy: 0.0001)
        XCTAssertNotEqual(
            world.bodies.first(where: { $0.kind == .ringworld })?.motion.forward,
            originalRingForward
        )
        for body in world.bodies {
            XCTAssertEqual(simd_length(body.motion.forward), 1, accuracy: 0.0001)
            XCTAssertEqual(simd_length(body.motion.up), 1, accuracy: 0.0001)
            XCTAssertEqual(simd_length(body.motion.right), 1, accuracy: 0.0001)
            XCTAssertEqual(simd_dot(body.motion.forward, body.motion.up), 0, accuracy: 0.0001)
        }
    }

    func testBodyCoordinateTransformRoundTrips() {
        let world = DStarLegacyWorld(seed: 3)
        guard let monolith = world.bodies.first(where: { $0.kind == .monolith }) else {
            return XCTFail("Monolith missing")
        }
        let local = SIMD3<Float>(12, -3, 45)
        let worldPoint = monolith.worldPoint(fromLocal: local)

        XCTAssertEqual(monolith.localPoint(fromWorld: worldPoint).x, local.x, accuracy: 0.0001)
        XCTAssertEqual(monolith.localPoint(fromWorld: worldPoint).y, local.y, accuracy: 0.0001)
        XCTAssertEqual(monolith.localPoint(fromWorld: worldPoint).z, local.z, accuracy: 0.0001)
    }
}
