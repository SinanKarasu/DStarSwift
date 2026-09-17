import simd

/// The scenery created by `become_master()` in the Sun/XGL game.
///
/// Scenery deliberately lives outside the multiplayer ship roster. That keeps
/// Bonjour ownership simple while giving both renderers one authoritative,
/// extensible world description for the reconstruction and future settings.
enum DStarLegacyBodyKind: String, CaseIterable {
    case primaryPlanet
    case secondaryPlanet
    case monolith
    case ringworld
}

struct DStarLegacyBody {
    let kind: DStarLegacyBodyKind
    let name: String
    let mesh: BSPNode?
    var motion: DStarObject

    func worldPoint(fromLocal point: SIMD3<Float>) -> SIMD3<Float> {
        motion.position
            + point.x * motion.right
            + point.y * motion.up
            + point.z * motion.forward
    }

    func localPoint(fromWorld point: SIMD3<Float>) -> SIMD3<Float> {
        let offset = point - motion.position
        return SIMD3<Float>(
            simd_dot(offset, motion.right),
            simd_dot(offset, motion.up),
            simd_dot(offset, motion.forward)
        )
    }
}

final class DStarLegacyWorld {
    // BSP nodes are immutable after construction, so every world instance can
    // share the relatively expensive legacy trees while keeping independent
    // body transforms and simulation clocks.
    private static let primaryPlanetMesh = BSPUtil.makeSphereTree(
        radius: 100,
        seed: 0xD57A_0100
    )
    private static let secondaryPlanetMesh = BSPUtil.makeSphereTree(
        radius: 50,
        seed: 0xD57A_0050
    )
    private static let monolithMesh = BSPUtil.makeMonolithTree()
    private static let ringworldMesh = BSPUtil.makeRingworldTree()

    private struct PositionRandom: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            return state
        }

        mutating func coordinate() -> Float {
            Float(Int(next() % 2_000) - 1_000)
        }
    }

    private let seed: UInt64
    private(set) var bodies: [DStarLegacyBody]
    private(set) var elapsedTime: Float = 0

    init(seed: UInt64 = 0x1986_2004) {
        self.seed = seed
        self.bodies = Self.makeBodies(seed: seed)
    }

    /// Advance using small fixed substeps so a temporarily stalled renderer
    /// does not distort the legacy Euler integration.
    func advance(to time: Float) {
        let target = max(time, 0)
        if target < elapsedTime {
            bodies = Self.makeBodies(seed: seed)
            elapsedTime = 0
        }

        var remaining = target - elapsedTime
        while remaining > 0.000_001 {
            let step = min(remaining, 1 / 60)
            for index in bodies.indices {
                ShipKinematics.advance(ship: &bodies[index].motion, dtime: step)
            }
            elapsedTime += step
            remaining -= step
        }
    }

    private static func makeBodies(seed: UInt64) -> [DStarLegacyBody] {
        var random = PositionRandom(state: seed)
        let primaryPosition = SIMD3<Float>(
            random.coordinate(), random.coordinate(), random.coordinate()
        )
        let secondaryPosition = SIMD3<Float>(
            random.coordinate(), random.coordinate(), random.coordinate()
        )

        return [
            DStarLegacyBody(
                kind: .primaryPlanet,
                name: "mars-100",
                mesh: primaryPlanetMesh,
                motion: planetMotion(position: primaryPosition)
            ),
            DStarLegacyBody(
                kind: .secondaryPlanet,
                name: "mars-50",
                mesh: secondaryPlanetMesh,
                motion: planetMotion(position: secondaryPosition)
            ),
            DStarLegacyBody(
                kind: .monolith,
                name: "TMA-2",
                mesh: monolithMesh,
                motion: monolithMotion()
            ),
            DStarLegacyBody(
                kind: .ringworld,
                name: "ringworld",
                mesh: ringworldMesh,
                motion: ringworldMotion()
            )
        ]
    }

    private static func baseMotion() -> DStarObject {
        var object = DStarObject()
        object.objectClass = .static
        object.status = .active
        object.speed = 0
        return object
    }

    private static func planetMotion(position: SIMD3<Float>) -> DStarObject {
        var object = baseMotion()
        object.name = "mars"
        object.position = position

        let yAxis = SIMD3<Float>(0, 1, 0)
        var forward = simd_cross(position, yAxis)
        if simd_length_squared(forward) < 0.000_001 {
            forward = SIMD3<Float>(0, 0, 1)
        } else {
            forward = simd_normalize(forward)
        }
        let up = simd_normalize(simd_cross(position, forward))
        let right = simd_normalize(simd_cross(forward, up))

        object.forward = forward
        object.up = up
        object.right = right
        object.delta = -simd_normalize(position) * 0.003
        object.speed = 3
        return object
    }

    private static func monolithMotion() -> DStarObject {
        var object = baseMotion()
        object.name = "TMA-2"
        object.position = SIMD3<Float>(0, -1_000, 0)
        object.delta = SIMD3<Float>(0, 0.005, 0)
        object.speed = 5
        return object
    }

    private static func ringworldMotion() -> DStarObject {
        var object = baseMotion()
        object.name = "ringworld"
        object.position = SIMD3<Float>(4_000, 0, 0)
        object.forward = SIMD3<Float>(1, 0, 0)
        object.right = SIMD3<Float>(0, -1, 0)
        object.up = SIMD3<Float>(0, 0, 1)
        object.delta = SIMD3<Float>(0.01, 0, 0)
        return object
    }
}
