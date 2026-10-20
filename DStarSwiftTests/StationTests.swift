import XCTest
import simd
@testable import DStarSwift

@MainActor
final class StationTests: XCTestCase {
    func testBundledGLTFLoadsIntoBothRenderersWorldGeometry() throws {
        let parts = try DStarStationAsset.result.get()
        XCTAssertEqual(parts.count, 5)
        XCTAssertTrue(parts.allSatisfy { !$0.positions.isEmpty && $0.indices.count % 3 == 0 })
        let station = try DStarWorld.arrival.snapshot(at: 0).filter { $0.id.hasPrefix("station.") }
        XCTAssertEqual(station.count, parts.count)
        let points = station.flatMap { item in item.geometry.positions.map { item.pose.renderPoint($0, relativeTo: .zero) } }
        XCTAssertEqual(points.map(\.z).max()!, 1060, accuracy: 0.01)
        XCTAssertEqual(points.map(\.z).min()!, 879.4, accuracy: 0.01)
    }

    func testCaptureRejectsSpeedHeadingRollAndPosition() {
        let time: Float = 12
        let up = DStarStation.up(at: time)
        func capture(_ position: SIMD3<Float> = SIMD3(0,0,1035), _ forward: SIMD3<Float> = SIMD3(0,0,1),
                     _ orientation: SIMD3<Float>? = nil, _ speed: Float = 2) -> Bool {
            DStarStation.canCapture(position: position, forward: forward, up: orientation ?? up, speed: speed, at: time)
        }
        XCTAssertTrue(capture())
        XCTAssertFalse(capture(DStarStation.berth + SIMD3(4,0,0)))
        XCTAssertFalse(capture(DStarStation.berth, SIMD3(0,0,-1)))
        XCTAssertFalse(capture(DStarStation.berth, SIMD3(0,0,1), -up))
        XCTAssertFalse(capture(DStarStation.berth, SIMD3(0,0,1), up, 25))
    }

    func testApproachCaptureRotatingAttachmentAndUndock() {
        let game = DStarGameState()
        game.apply(.visitStation)
        XCTAssertEqual(game.me.position, SIMD3(0,0,800))
        XCTAssertEqual(game.me.speed, 0)
        game.apply(.stationMatchRoll)
        game.apply(.stationApproach)
        for _ in 0..<1200 { game.step(deltaTime: 0.1) }
        XCTAssertTrue(game.stationDocked)
        XCTAssertEqual(game.me.position, DStarStation.berth)
        XCTAssertEqual(game.me.speed, 0)
        game.step(deltaTime: 1)
        XCTAssertLessThan(simd_distance(game.me.up, DStarStation.up(at: game.stationTime)), 0.0001)
        game.apply(.stationUndock)
        game.step(deltaTime: 1)
        XCTAssertFalse(game.stationDocked)
        XCTAssertEqual(game.me.position, SIMD3(0,0,920))
    }

    func testStoppedSpinKeepsSimulationAndStationFrameConsistent() throws {
        let game = DStarGameState()
        game.step(deltaTime: 1)
        let clock = game.stationTime
        game.apply(.stationToggleSpin)
        game.step(deltaTime: 4)
        XCTAssertEqual(game.stationTime, clock)
        let a = try DStarWorld.arrival.snapshot(at: 1, frameTimes: ["station": Double(clock)])
        let b = try DStarWorld.arrival.snapshot(at: 5, frameTimes: ["station": Double(game.stationTime)])
        let first = try XCTUnwrap(a.first { $0.id == "station.0" })
        let second = try XCTUnwrap(b.first { $0.id == "station.0" })
        XCTAssertEqual(first.pose.orientation.vector, second.pose.orientation.vector)
    }
}
