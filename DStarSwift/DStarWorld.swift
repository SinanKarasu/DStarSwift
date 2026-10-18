import simd

/// World-engine v2 uses metres, seconds, +Y up and the game's +Z forward.
/// Keep placement in Double; reduce to Float only after subtracting the render origin.
struct WorldPose {
    var position: SIMD3<Double> = .zero
    var orientation = simd_quatd(angle: 0, axis: SIMD3<Double>(0, 1, 0))

    func applying(_ child: WorldPose) -> WorldPose {
        WorldPose(position: position + orientation.act(child.position),
                  orientation: simd_normalize(orientation * child.orientation))
    }

    func renderPoint(_ point: SIMD3<Float>, relativeTo origin: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3<Float>(position - origin + orientation.act(SIMD3<Double>(point)))
    }
}

struct WorldFrame {
    let id: String
    var parent: String?
    var pose = WorldPose()
    /// Radians per second about local +Y, evaluated from the simulation epoch.
    var spin: Double = 0
}

struct WorldGeometry {
    let id: String
    let positions: [SIMD3<Float>]
    let indices: [UInt32]
    let color: SIMD4<Float>

    var boundingRadius: Float { positions.map { simd_length($0) }.max() ?? 0 }
}

struct WorldInstance {
    let id: String
    let frame: String
    let geometry: WorldGeometry
}

struct WorldDrawItem {
    let id: String
    let pose: WorldPose
    let geometry: WorldGeometry
}

enum WorldDefinitionError: Error, Equatable {
    case duplicateFrame(String)
    case missingFrame(String)
    case cyclicFrame(String)
    case invalidTime
}

/// Immutable definitions are shared by both rendering adapters. No GPU or RealityKit types.
struct DStarWorld {
    let frames: [WorldFrame]
    let instances: [WorldInstance]

    func snapshot(at time: Double) throws -> [WorldDrawItem] {
        guard time.isFinite else { throw WorldDefinitionError.invalidTime }
        var definitions: [String: WorldFrame] = [:]
        for frame in frames {
            guard definitions[frame.id] == nil else {
                throw WorldDefinitionError.duplicateFrame(frame.id)
            }
            definitions[frame.id] = frame
        }
        var resolved: [String: WorldPose] = [:]
        var visiting = Set<String>()
        func resolve(_ id: String) throws -> WorldPose {
            if let pose = resolved[id] { return pose }
            guard let frame = definitions[id] else { throw WorldDefinitionError.missingFrame(id) }
            guard visiting.insert(id).inserted else { throw WorldDefinitionError.cyclicFrame(id) }
            var local = frame.pose
            local.orientation = simd_normalize(local.orientation * simd_quatd(
                angle: (frame.spin * time).truncatingRemainder(dividingBy: 2 * .pi),
                axis: SIMD3<Double>(0, 1, 0)))
            let pose = try frame.parent.map { try resolve($0).applying(local) } ?? local
            visiting.remove(id)
            resolved[id] = pose
            return pose
        }
        // Validate unused frames as well, so authoring mistakes cannot stay hidden.
        for frame in frames { _ = try resolve(frame.id) }
        return try instances.map {
            WorldDrawItem(id: $0.id, pose: try resolve($0.frame), geometry: $0.geometry)
        }
    }

    static let arrival = DStarWorld(
        frames: [
            WorldFrame(id: "habitat", pose: WorldPose(position: SIMD3<Double>(350, 0, 1300))),
            WorldFrame(id: "habitat.rotating", parent: "habitat", spin: 0.08),
            WorldFrame(id: "habitat.hub", parent: "habitat")
        ],
        instances: [
            WorldInstance(id: "cylinder.land", frame: "habitat.rotating",
                          geometry: HabitatGeometry.bands(windows: false)),
            WorldInstance(id: "cylinder.windows", frame: "habitat.rotating",
                          geometry: HabitatGeometry.bands(windows: true)),
            WorldInstance(id: "cylinder.rims", frame: "habitat.rotating",
                          geometry: HabitatGeometry.rims()),
            WorldInstance(id: "cylinder.hub", frame: "habitat.hub",
                          geometry: HabitatGeometry.hub())
        ])
}

/// First habitat: open axial entrances, three land bands alternating with blue window bands.
/// Explicit reverse triangles make both the exterior and interior visible in both backends.
enum HabitatGeometry {
    private static func surface(id: String, radius: Float, y0: Float, y1: Float,
                                color: SIMD4<Float>, include: (Int) -> Bool) -> WorldGeometry {
        var points: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let segments = 96
        for i in 0..<segments where include(i) {
            let a = Float(i) * 2 * .pi / Float(segments)
            let b = Float(i + 1) * 2 * .pi / Float(segments)
            let base = UInt32(points.count)
            points += [SIMD3(radius * cos(a), y0, radius * sin(a)),
                       SIMD3(radius * cos(b), y0, radius * sin(b)),
                       SIMD3(radius * cos(b), y1, radius * sin(b)),
                       SIMD3(radius * cos(a), y1, radius * sin(a))]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3,
                        base + 2, base + 1, base, base + 3, base + 2, base]
        }
        return WorldGeometry(id: id, positions: points, indices: indices, color: color)
    }

    static func bands(windows: Bool) -> WorldGeometry {
        surface(id: windows ? "windows" : "land", radius: 180, y0: -300, y1: 300,
                color: windows ? SIMD4(0.12, 0.35, 0.65, 1) : SIMD4(0.25, 0.55, 0.24, 1)) {
            (($0 / 16) % 2 == 1) == windows
        }
    }

    static func rims() -> WorldGeometry {
        let lower = surface(id: "lower", radius: 182, y0: -305, y1: -292,
                            color: SIMD4(0.75, 0.77, 0.8, 1)) { _ in true }
        let upper = surface(id: "upper", radius: 182, y0: 292, y1: 305,
                            color: lower.color) { _ in true }
        return WorldGeometry(id: "rims", positions: lower.positions + upper.positions,
                             indices: lower.indices + upper.indices.map { $0 + UInt32(lower.positions.count) },
                             color: lower.color)
    }

    static func hub() -> WorldGeometry {
        surface(id: "hub", radius: 18, y0: -350, y1: 350,
                color: SIMD4(0.9, 0.65, 0.2, 1)) { _ in true }
    }
}
