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
    /// Only root frames may define a universal anchor.
    var anchor: WorldPosition = .zero
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
    case invalidFrame(String)
    case anchoredChild(String)
}

/// Immutable definitions are shared by both rendering adapters. No GPU or RealityKit types.
struct DStarWorld {
    let frames: [WorldFrame]
    let instances: [WorldInstance]

    private struct ResolvedFrame {
        var position: WorldPosition
        var orientation: simd_quatd
    }

    private func definitions(at time: Double, frameTimes: [String: Double] = [:]) throws -> [String: WorldFrame] {
        guard time.isFinite, frameTimes.values.allSatisfy(\.isFinite) else { throw WorldDefinitionError.invalidTime }
        var result: [String: WorldFrame] = [:]
        for frame in frames {
            guard result[frame.id] == nil else { throw WorldDefinitionError.duplicateFrame(frame.id) }
            guard frame.pose.position.allFinite, frame.spin.isFinite,
                  frame.pose.orientation.vector.allFinite,
                  simd_length_squared(frame.pose.orientation.vector) > 0 else {
                throw WorldDefinitionError.invalidFrame(frame.id)
            }
            if frame.parent != nil && frame.anchor != .zero { throw WorldDefinitionError.anchoredChild(frame.id) }
            let frameTime = frameTimes[frame.id] ?? time
            var evaluated = frame
            evaluated.pose.orientation = simd_normalize(frame.pose.orientation * simd_quatd(
                angle: frame.spin * frameTime.truncatingRemainder(dividingBy: frame.spin == 0 ? 1 : 2 * .pi / abs(frame.spin)),
                axis: SIMD3<Double>(0, 1, 0)))
            result[frame.id] = evaluated
        }
        // Validate every branch, including ones with no geometry.
        for frame in frames {
            var path = Set<String>()
            var next: String? = frame.id
            while let id = next {
                guard path.insert(id).inserted else { throw WorldDefinitionError.cyclicFrame(id) }
                guard let current = result[id] else { throw WorldDefinitionError.missingFrame(id) }
                next = current.parent
            }
        }
        return result
    }

    /// Output poses are relative to the supplied observer, never absolute astronomical Doubles.
    func snapshot(at time: Double, relativeTo origin: WorldPosition = .zero, frameTimes: [String: Double] = [:]) throws -> [WorldDrawItem] {
        let definitions = try definitions(at: time, frameTimes: frameTimes)
        var resolved: [String: ResolvedFrame] = [:]
        func resolve(_ id: String) throws -> ResolvedFrame {
            if let value = resolved[id] { return value }
            guard let frame = definitions[id] else { throw WorldDefinitionError.missingFrame(id) }
            let result: ResolvedFrame
            if let parent = frame.parent {
                let base = try resolve(parent)
                result = ResolvedFrame(position: try base.position.adding(metres: base.orientation.act(frame.pose.position)),
                                       orientation: simd_normalize(base.orientation * frame.pose.orientation))
            } else {
                result = ResolvedFrame(position: try frame.anchor.adding(metres: frame.pose.position),
                                       orientation: frame.pose.orientation)
            }
            resolved[id] = result
            return result
        }
        return try instances.map {
            let frame = try resolve($0.frame)
            return WorldDrawItem(id: $0.id,
                                 pose: WorldPose(position: frame.position.metres(relativeTo: origin),
                                                 orientation: frame.orientation), geometry: $0.geometry)
        }
    }

    /// Resolve locally via the lowest shared ancestor. A huge ancestor translation
    /// never participates in a calculation between two objects inside that frame.
    func displacement(from source: WorldLocation, to target: WorldLocation, at time: Double) throws -> SIMD3<Double> {
        let definitions = try definitions(at: time)
        func chain(_ location: WorldLocation) throws -> [(String, WorldPose)] {
            var values: [(String, WorldPose)] = []
            var id = location.frame
            var pose = WorldPose(position: location.offset)
            while true {
                guard let frame = definitions[id] else { throw WorldDefinitionError.missingFrame(id) }
                values.append((id, pose))
                guard let parent = frame.parent else { break }
                pose = frame.pose.applying(pose)
                id = parent
            }
            return values
        }
        let sources = try chain(source)
        let targets = try chain(target)
        for (id, start) in sources {
            if let end = targets.first(where: { $0.0 == id })?.1 {
                // Return a vector in the source frame's axes, not its parent's axes.
                return start.orientation.inverse.act(end.position - start.position)
            }
        }
        // Separate roots: subtract universal addresses, then rotate into source axes.
        func absolute(_ location: WorldLocation, _ chain: [(String, WorldPose)]) throws -> ResolvedFrame {
            var result = ResolvedFrame(position: .zero, orientation: simd_quatd(angle: 0, axis: SIMD3(0, 1, 0)))
            for (id, _) in chain.reversed() {
                let frame = definitions[id]!
                if frame.parent == nil { result.position = frame.anchor }
                result.position = try result.position.adding(metres: result.orientation.act(frame.pose.position))
                result.orientation = simd_normalize(result.orientation * frame.pose.orientation)
            }
            result.position = try result.position.adding(metres: result.orientation.act(location.offset))
            return result
        }
        let start = try absolute(source, sources)
        let end = try absolute(target, targets)
        return start.orientation.inverse.act(end.position.metres(relativeTo: start.position))
    }

    static let arrival = DStarWorld(
        frames: [
            WorldFrame(id: "habitat", pose: WorldPose(position: SIMD3<Double>(350, 0, 1300))),
            WorldFrame(id: "habitat.rotating", parent: "habitat", spin: 0.08),
            WorldFrame(id: "habitat.hub", parent: "habitat"),
            WorldFrame(id: "station", pose: WorldPose(position: SIMD3<Double>(DStarStation.center),
                orientation: simd_quatd(angle: .pi / 2, axis: SIMD3(1,0,0))), spin: Double(DStarStation.spin))
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
        ] + ((try? DStarStationAsset.result.get()) ?? []).map {
            WorldInstance(id: $0.id, frame: "station", geometry: $0)
        })
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

private extension SIMD3 where Scalar == Double {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
private extension SIMD4 where Scalar == Double {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
}
