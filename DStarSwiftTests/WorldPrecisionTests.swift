import XCTest
import simd
@testable import DStarSwift

final class WorldPrecisionTests: XCTestCase {
    // ~46 billion light-years, represented as an integer address, never one giant Double.
    private let remote = SIMD3<Int64>(101_000_000_000_000_000, -101_000_000_000_000_000, 42)

    func testMillimetresSurviveAtCosmologicalDistances() throws {
        let start = try WorldPosition(sector: remote, offset: SIMD3(100, -30, 80))
        let end = try start.adding(metres: SIMD3(0.001, 299.792458, -0.002))
        let separation = end.metres(relativeTo: start)
        XCTAssertEqual(separation.x, 0.001, accuracy: 1e-9)
        XCTAssertEqual(separation.y, 299.792458, accuracy: 1e-9)
        XCTAssertEqual(separation.z, -0.002, accuracy: 1e-9)
    }

    func testSectorBoundaryCrossingAndNegativeNormalization() throws {
        let edge = try WorldPosition(sector: remote, offset: SIMD3(WorldPosition.sectorSize / 2 - 0.5, 0, 0))
        let next = try edge.adding(metres: SIMD3(0.501, -0.001, 0))
        XCTAssertEqual(next.sector.x, edge.sector.x + 1)
        XCTAssertEqual(next.metres(relativeTo: edge).x, 0.501, accuracy: 1e-6)
        XCTAssertEqual(next.offset.y, -0.001, accuracy: 1e-12)
        let roundTrip = try next.adding(metres: SIMD3(-0.501, 0.001, 0))
        XCTAssertEqual(roundTrip.metres(relativeTo: edge).x, 0, accuracy: 1e-6)
    }

    func testRejectsInvalidOrOverflowingAddresses() throws {
        XCTAssertThrowsError(try WorldPosition(offset: SIMD3(.infinity, 0, 0)))
        let edge = try WorldPosition(sector: SIMD3(Int64.max, 0, 0))
        XCTAssertThrowsError(try edge.adding(metres: SIMD3(WorldPosition.sectorSize, 0, 0)))
        let negative = try WorldPosition(sector: SIMD3(Int64.min, 0, 0))
        XCTAssertTrue(edge.metres(relativeTo: negative).x.isFinite)
    }

    func testSnapshotRebasesBeforeConvertingToRenderPrecision() throws {
        let anchor = try WorldPosition(sector: remote)
        let world = DStarWorld(frames: [
            WorldFrame(id: "root", anchor: anchor),
            WorldFrame(id: "child", parent: "root", pose: WorldPose(position: SIMD3(0.001, 0, 0)))
        ], instances: [WorldInstance(id: "mesh", frame: "child", geometry: HabitatGeometry.hub())])
        let item = try XCTUnwrap(world.snapshot(at: 0, relativeTo: anchor).first)
        XCTAssertEqual(item.pose.position.x, 0.001, accuracy: 1e-12)
        XCTAssertEqual(item.pose.renderPoint(.zero, relativeTo: .zero).x, 0.001, accuracy: 1e-8)
    }

    func testCommonAncestorAvoidsFlatteningHugeLocalTranslations() throws {
        let world = DStarWorld(frames: [
            WorldFrame(id: "distant", pose: WorldPose(position: SIMD3(1e26, 0, 0))),
            WorldFrame(id: "habitat", parent: "distant", pose: WorldPose(position: SIMD3(500, 0, 0))),
            WorldFrame(id: "port", parent: "habitat", pose: WorldPose(position: SIMD3(0.001, 0, 0)))
        ], instances: [])
        let relative = try world.displacement(from: WorldLocation(frame: "habitat"),
                                               to: WorldLocation(frame: "port"), at: 0)
        XCTAssertEqual(relative.x, 0.001, accuracy: 1e-12)
    }

    func testSeparateRootsSubtractAddressesAndRespectSourceAxes() throws {
        let anchor = try WorldPosition(sector: remote)
        let world = DStarWorld(frames: [
            WorldFrame(id: "a", pose: WorldPose(orientation: simd_quatd(angle: .pi / 2, axis: SIMD3(0, 1, 0))), anchor: anchor),
            WorldFrame(id: "b", anchor: try anchor.adding(metres: SIMD3(1, 0, 0)))
        ], instances: [])
        let result = try world.displacement(from: WorldLocation(frame: "a"), to: WorldLocation(frame: "b"), at: 0)
        XCTAssertEqual(result.x, 0, accuracy: 1e-10)
        XCTAssertEqual(result.z, 1, accuracy: 1e-10)
    }
}
