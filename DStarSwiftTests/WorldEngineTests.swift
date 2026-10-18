import XCTest
import simd
@testable import DStarSwift

final class WorldEngineTests: XCTestCase {
    @MainActor
    func testArrivalStopsShipAndResetsFlightModes() {
        let game = DStarGameState()
        game.apply(.keyCharacter("a"))
        game.apply(.setLeftButton(true))
        game.apply(.visitHabitat)
        game.step(deltaTime: 1)
        XCTAssertEqual(game.me.position, SIMD3<Float>(350, 600, 550))
        XCTAssertEqual(game.me.forward, simd_normalize(SIMD3<Float>(0, -600, 750)))
        XCTAssertEqual(game.me.speed, 0)
        XCTAssertFalse(game.autoPilot)
        XCTAssertFalse(game.mouseControl)
    }

    func testChildTranslationFollowsParentRotation() throws {
        let world = DStarWorld(frames: [
            WorldFrame(id: "parent", pose: WorldPose(position: SIMD3(10, 0, 0)), spin: .pi / 2),
            WorldFrame(id: "child", parent: "parent", pose: WorldPose(position: SIMD3(2, 0, 0)))
        ], instances: [WorldInstance(id: "test", frame: "child", geometry: HabitatGeometry.hub())])
        let pose = try XCTUnwrap(world.snapshot(at: 1).first?.pose)
        XCTAssertEqual(pose.position.x, 10, accuracy: 1e-10)
        XCTAssertEqual(pose.position.z, -2, accuracy: 1e-10)
    }

    func testHabitatRotationLeavesHubFixedAndSupportsTimeRewind() throws {
        let initial = try DStarWorld.arrival.snapshot(at: 0)
        let later = try DStarWorld.arrival.snapshot(at: 15)
        let rewind = try DStarWorld.arrival.snapshot(at: 0)
        XCTAssertEqual(initial.map(\.id), later.map(\.id))
        let land = SIMD3<Float>(180, 0, 0)
        XCTAssertNotEqual(initial[0].pose.renderPoint(land, relativeTo: .zero),
                          later[0].pose.renderPoint(land, relativeTo: .zero))
        XCTAssertEqual(initial[3].pose.renderPoint(land, relativeTo: .zero),
                       later[3].pose.renderPoint(land, relativeTo: .zero))
        XCTAssertEqual(initial[0].pose.renderPoint(land, relativeTo: .zero),
                       rewind[0].pose.renderPoint(land, relativeTo: .zero))
    }

    func testSubtractsRenderOriginBeforeFloatConversion() {
        let origin = SIMD3<Double>(1e12, -1e12, 1e12)
        let pose = WorldPose(position: origin + SIMD3(0.25, 0.5, 1))
        XCTAssertEqual(pose.renderPoint(.zero, relativeTo: origin), SIMD3<Float>(0.25, 0.5, 1))
    }

    func testRejectsMalformedFrameGraphs() {
        func check(_ frames: [WorldFrame], _ expected: WorldDefinitionError) {
            XCTAssertThrowsError(try DStarWorld(frames: frames, instances: []).snapshot(at: 0)) {
                XCTAssertEqual($0 as? WorldDefinitionError, expected)
            }
        }
        check([WorldFrame(id: "a"), WorldFrame(id: "a")], .duplicateFrame("a"))
        check([WorldFrame(id: "a", parent: "missing")], .missingFrame("missing"))
        check([WorldFrame(id: "a", parent: "b"), WorldFrame(id: "b", parent: "a")], .cyclicFrame("a"))
    }

    func testCylinderGeometryHasFiniteNondegenerateTrianglesAndComplementaryBands() {
        let land = HabitatGeometry.bands(windows: false)
        let windows = HabitatGeometry.bands(windows: true)
        XCTAssertEqual(land.positions.count, 48 * 4)
        XCTAssertEqual(windows.positions.count, 48 * 4)
        for geometry in [land, windows, HabitatGeometry.rims(), HabitatGeometry.hub()] {
            XCTAssertEqual(geometry.indices.count % 3, 0)
            XCTAssertGreaterThan(geometry.boundingRadius, 0)
            for index in geometry.indices { XCTAssertLessThan(Int(index), geometry.positions.count) }
            for point in geometry.positions { XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite) }
            for i in stride(from: 0, to: geometry.indices.count, by: 3) {
                let a = geometry.positions[Int(geometry.indices[i])]
                let b = geometry.positions[Int(geometry.indices[i + 1])]
                let c = geometry.positions[Int(geometry.indices[i + 2])]
                XCTAssertGreaterThan(simd_length_squared(simd_cross(b - a, c - a)), 0)
            }
        }
    }
}
