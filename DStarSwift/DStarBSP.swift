import simd

enum DStarColor: Int16 {
    case black = 0
    case darkGray = 1
    case gray = 2
    case lightGray = 3
    case white = 4
    case red = 5
    case green = 6
    case blue = 7
    case yellow = 8
}

enum BSPFlags {
    static let poly: UInt16 = 1
    static let backView: UInt16 = 8
}

final class BSPNode {
    var flags: UInt16 = BSPFlags.poly
    var normal = SIMD3<Float>(0, 1, 0)
    var color: Int16 = DStarColor.gray.rawValue
    var trimColor: Int16 = -1
    var vertices: [SIMD3<Float>] = []
    var frontChild: BSPNode?
    var backChild: BSPNode?
}

enum BSPUtil {
    /// Small deterministic generator used for the legacy gray facets. The C
    /// game used process-seeded `random()`, but stable colors make macOS,
    /// visionOS, screenshots, and tests agree on the same reconstructed world.
    private struct LegacyRandom: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return state
        }

        mutating func gray() -> Int16 {
            DStarColor.darkGray.rawValue + Int16(next() % 4)
        }
    }

    static func color(_ index: Int16) -> SIMD4<Float> {
        switch index {
        case DStarColor.black.rawValue: return SIMD4<Float>(0, 0, 0, 1)
        case DStarColor.darkGray.rawValue: return SIMD4<Float>(0.25, 0.25, 0.25, 1)
        case DStarColor.gray.rawValue: return SIMD4<Float>(0.5, 0.5, 0.5, 1)
        case DStarColor.lightGray.rawValue: return SIMD4<Float>(0.75, 0.75, 0.75, 1)
        case DStarColor.white.rawValue: return SIMD4<Float>(1, 1, 1, 1)
        case DStarColor.red.rawValue: return SIMD4<Float>(1, 0, 0, 1)
        case DStarColor.green.rawValue: return SIMD4<Float>(0, 1, 0, 1)
        case DStarColor.blue.rawValue: return SIMD4<Float>(0, 0, 1, 1)
        case DStarColor.yellow.rawValue: return SIMD4<Float>(1, 1, 0, 1)
        default: return SIMD4<Float>(1, 1, 1, 1)
        }
    }

    static func vectorNormal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let u = b - a
        let v = c - a
        let n = simd_cross(u, v)
        let len = simd_length(n)
        return len > 0 ? (n / len) : SIMD3<Float>(0, 1, 0)
    }

    static func newPoly(vertices: [SIMD3<Float>], color: Int16, trimColor: Int16) -> BSPNode {
        let node = BSPNode()
        node.flags = BSPFlags.poly
        node.vertices = vertices
        node.normal = vectorNormal(vertices[2], vertices[1], vertices[0])
        node.color = color
        node.trimColor = trimColor
        return node
    }

    static func genRing(
        r1: Float,
        r2: Float,
        y1: Float,
        y2: Float,
        nlon: Int,
        flags: UInt16,
        color: ((Float) -> Int16)?
    ) -> [BSPNode] {
        var result: [BSPNode] = []
        result.reserveCapacity(nlon)

        var lon1: Float = 0
        for j in 0..<nlon {
            let lon2 = 360 * Float(j + 1) / Float(nlon)
            let p0 = SIMD3<Float>(cosd(lon1) * r1, y1, sind(lon1) * r1)
            let p1 = SIMD3<Float>(cosd(lon1) * r2, y2, sind(lon1) * r2)
            let p2 = SIMD3<Float>(cosd(lon2) * r2, y2, sind(lon2) * r2)
            let p3 = SIMD3<Float>(cosd(lon2) * r1, y1, sind(lon2) * r1)
            let clr = color?(lon1) ?? Int16(Int.random(in: Int(DStarColor.darkGray.rawValue)...Int(DStarColor.lightGray.rawValue)))
            let node = newPoly(vertices: [p0, p1, p2, p3], color: clr, trimColor: -1)
            node.flags |= flags
            result.append(node)
            lon1 = lon2
        }

        return result
    }

    static func buildBSPTree(_ input: [BSPNode]) -> BSPNode? {
        var list = input
        return makeTree(&list)
    }

    static func collectVisiblePolygons(node: BSPNode?, viewer: SIMD3<Float>, out: inout [BSPNode]) {
        guard let node else { return }
        let vector = viewer - node.vertices[0]
        let dot = simd_dot(vector, node.normal)
        if dot < 0 {
            collectVisiblePolygons(node: node.frontChild, viewer: viewer, out: &out)
            if (node.flags & BSPFlags.backView) != 0 {
                out.append(node)
            }
            collectVisiblePolygons(node: node.backChild, viewer: viewer, out: &out)
        } else {
            collectVisiblePolygons(node: node.backChild, viewer: viewer, out: &out)
            out.append(node)
            collectVisiblePolygons(node: node.frontChild, viewer: viewer, out: &out)
        }
    }

    static func makeRingworldTree() -> BSPNode? {
        let radius: Float = 2000
        let width2: Float = 40
        let depth: Float = 5
        let nlon = 72
        var polys: [BSPNode] = []

        polys += genRing(r1: radius, r2: radius, y1: width2, y2: -width2, nlon: nlon, flags: BSPFlags.backView, color: nil)
        polys += genRing(r1: radius - 0.5, r2: radius - 0.5, y1: -width2, y2: width2, nlon: nlon, flags: 0, color: ringColors)
        polys += genRing(r1: radius - depth, r2: radius, y1: width2, y2: width2, nlon: nlon, flags: BSPFlags.backView, color: nil)
        polys += genRing(r1: radius - depth * 2, r2: radius - depth, y1: width2, y2: width2, nlon: nlon, flags: BSPFlags.backView, color: nil)
        polys += genRing(r1: radius, r2: radius - depth, y1: -width2, y2: -width2, nlon: nlon, flags: BSPFlags.backView, color: nil)
        polys += genRing(r1: radius - depth, r2: radius - depth * 2, y1: -width2, y2: -width2, nlon: nlon, flags: BSPFlags.backView, color: nil)
        polys += genRing(r1: radius * 0.25, r2: radius * 0.25, y1: -width2, y2: width2, nlon: nlon, flags: BSPFlags.backView, color: shadowSquare)

        return buildBSPTree(polys)
    }

    /// Port of `gen_sphere()` from the Sun/XGL-era `bsp_utils.c`.
    static func makeSphereTree(
        radius: Float,
        latitudeSegments: Int = 18,
        longitudeSegments: Int = 36,
        seed: UInt64 = 0xD57A
    ) -> BSPNode? {
        guard radius > 0, latitudeSegments > 1, longitudeSegments > 2 else {
            return nil
        }

        var random = LegacyRandom(state: seed)
        var polygons: [BSPNode] = []
        polygons.reserveCapacity(latitudeSegments * longitudeSegments)

        var radial1: Float = 0
        var y1 = radius

        for latitudeIndex in 0..<latitudeSegments {
            let latitude2 = 90 - 180 * Float(latitudeIndex + 1)
                / Float(latitudeSegments)
            let radial2 = radius * cosd(latitude2)
            let y2 = radius * sind(latitude2)
            var longitude1: Float = 0

            for longitudeIndex in 0..<longitudeSegments {
                let longitude2 = 360 * Float(longitudeIndex + 1)
                    / Float(longitudeSegments)
                let vertices = [
                    SIMD3<Float>(cosd(longitude1) * radial1, y1, sind(longitude1) * radial1),
                    SIMD3<Float>(cosd(longitude1) * radial2, y2, sind(longitude1) * radial2),
                    SIMD3<Float>(cosd(longitude2) * radial2, y2, sind(longitude2) * radial2),
                    SIMD3<Float>(cosd(longitude2) * radial1, y1, sind(longitude2) * radial1)
                ]
                let node = newPoly(vertices: vertices, color: random.gray(), trimColor: -1)
                node.flags |= BSPFlags.backView
                polygons.append(node)
                longitude1 = longitude2
            }

            radial1 = radial2
            y1 = y2
        }

        return linkConvexBackChain(polygons)
    }

    /// Exact 80 × 20 × 180 TMA-2 mesh from `monolith_bsp.h`.
    static func makeMonolithTree() -> BSPNode? {
        let x: Float = 40
        let y: Float = 10
        let z: Float = 90
        let faces: [([SIMD3<Float>], Int16)] = [
            ([[-x, -y, -z], [ x, -y, -z], [ x,  y, -z], [-x,  y, -z]], DStarColor.lightGray.rawValue),
            ([[-x, -y,  z], [ x, -y,  z], [ x,  y,  z], [-x,  y,  z]], DStarColor.lightGray.rawValue),
            ([[-x, -y, -z], [-x, -y,  z], [-x,  y,  z], [-x,  y, -z]], DStarColor.gray.rawValue),
            ([[ x, -y, -z], [ x, -y,  z], [ x,  y,  z], [ x,  y, -z]], DStarColor.gray.rawValue),
            ([[-x, -y, -z], [ x, -y, -z], [ x, -y,  z], [-x, -y,  z]], DStarColor.darkGray.rawValue),
            ([[-x,  y, -z], [ x,  y, -z], [ x,  y,  z], [-x,  y,  z]], DStarColor.darkGray.rawValue)
        ]
        let nodes = faces.map { vertices, color -> BSPNode in
            let node = newPoly(vertices: vertices, color: color, trimColor: -1)
            node.flags |= BSPFlags.backView
            return node
        }
        return linkConvexBackChain(nodes.reversed())
    }

    static func nodes(in root: BSPNode?) -> [BSPNode] {
        guard let root else { return [] }
        var result: [BSPNode] = []
        var stack = [root]
        while let node = stack.popLast() {
            result.append(node)
            if let back = node.backChild { stack.append(back) }
            if let front = node.frontChild { stack.append(front) }
        }
        return result
    }

    private static func linkConvexBackChain<S: Sequence>(_ input: S) -> BSPNode?
    where S.Element == BSPNode {
        let nodes = Array(input)
        for index in nodes.indices.dropLast() {
            nodes[index].backChild = nodes[index + 1]
        }
        return nodes.first
    }

    private static func makeTree(_ list: inout [BSPNode]) -> BSPNode? {
        guard !list.isEmpty else { return nil }
        guard let node = findCandidate(&list) else { return nil }
        var front: [BSPNode] = []
        var back: [BSPNode] = []
        for item in list {
            if frontBack(node: node, test: item) {
                front.append(item)
            } else {
                back.append(item)
            }
        }
        node.frontChild = makeTree(&front)
        node.backChild = makeTree(&back)
        return node
    }

    private static func findCandidate(_ list: inout [BSPNode]) -> BSPNode? {
        guard !list.isEmpty else { return nil }
        if list.count == 1 {
            return list.removeFirst()
        }

        var bestIndex = 0
        var bestCuts = Int.max
        for i in list.indices {
            let n = countCuts(node: list[i], list: list, best: bestCuts)
            if n < bestCuts {
                bestCuts = n
                bestIndex = i
                if n == 0 { break }
            }
        }
        return list.remove(at: bestIndex)
    }

    private static func countCuts(node: BSPNode, list: [BSPNode], best: Int) -> Int {
        var cuts = 0
        for test in list {
            if test === node { continue }
            if checkCut(node: node, test: test) {
                cuts += 1
                if cuts >= best { return cuts }
            }
        }
        return cuts
    }

    private static func checkCut(node: BSPNode, test: BSPNode) -> Bool {
        let p0 = node.vertices[0]
        let n = node.normal
        var f = 0
        var b = 0
        for p in test.vertices {
            let d = simd_dot(p - p0, n)
            if d > 0.0001 {
                f += 1
            } else if d < -0.0001 {
                b += 1
            }
            if f > 0 && b > 0 { return true }
        }
        return false
    }

    private static func frontBack(node: BSPNode, test: BSPNode) -> Bool {
        let p0 = node.vertices[0]
        let n = node.normal
        for p in test.vertices {
            let d = simd_dot(p - p0, n)
            if d > 0.0001 { return true }
            if d < -0.0001 { return false }
        }
        return false
    }

    nonisolated private static func ringColors(lon: Float) -> Int16 {
        let i = Int(lon)
        return ((i % 18) > 9) ? DStarColor.blue.rawValue : DStarColor.darkGray.rawValue
    }

    nonisolated private static func shadowSquare(lon: Float) -> Int16 {
        let i = Int(lon)
        return ((i % 18) > 9) ? -1 : DStarColor.black.rawValue
    }

    private static func sind(_ degrees: Float) -> Float {
        sin(degrees * .pi / 180)
    }

    private static func cosd(_ degrees: Float) -> Float {
        cos(degrees * .pi / 180)
    }
}
