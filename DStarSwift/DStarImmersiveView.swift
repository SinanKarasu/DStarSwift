#if os(visionOS)
import RealityKit
import SwiftUI
import UIKit

enum DStarImmersiveSpace {
    static let id = "DStarImmersiveSpace"
}

struct DStarImmersiveView: View {
    private let worldScale: Float = 0.001

    var body: some View {
        RealityView { content in
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(makeRingworldEntity(scale: worldScale))
            anchor.addChild(makeStarfieldEntity(scale: worldScale))
            content.add(anchor)
        }
    }

    private func makeRingworldEntity(scale: Float) -> Entity {
        let root = Entity()
        guard let tree = BSPUtil.makeRingworldTree() else { return root }

        var nodes: [BSPNode] = []
        collectNodes(tree, into: &nodes)

        var grouped: [Int16: MeshAccumulator] = [:]
        for node in nodes where node.vertices.count >= 3 && node.color >= 0 {
            let color = node.color
            var acc = grouped[color] ?? MeshAccumulator()
            guard let base = UInt32(exactly: acc.positions.count) else { continue }

            for p in node.vertices {
                acc.positions.append(p * scale)
            }

            for i in 1..<(node.vertices.count - 1) {
                acc.indices.append(base)
                acc.indices.append(base + UInt32(i))
                acc.indices.append(base + UInt32(i + 1))
            }

            grouped[color] = acc
        }

        for (color, acc) in grouped {
            guard !acc.positions.isEmpty, !acc.indices.isEmpty else { continue }
            var descriptor = MeshDescriptor()
            descriptor.positions = MeshBuffer(acc.positions)
            descriptor.primitives = .triangles(acc.indices)

            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            let material = SimpleMaterial(
                color: uiColor(for: color).withAlphaComponent(0.95),
                roughness: 0.9,
                isMetallic: false
            )
            let part = ModelEntity(mesh: mesh, materials: [material])
            root.addChild(part)
        }

        return root
    }

    private func makeStarfieldEntity(scale: Float) -> Entity {
        let root = Entity()
        // VisionOS pays a steeper per-entity cost, so dial the count down.
        let source = SphericalShellStarfield(starCount: 1200)
        let starMesh = MeshResource.generateSphere(radius: 0.004)

        for star in source.makeStars() {
            let material = UnlitMaterial(color: visionStarColor(for: star.colorIndex))
            let entity = ModelEntity(mesh: starMesh, materials: [material])
            entity.position = star.position * scale
            root.addChild(entity)
        }

        return root
    }

    private func visionStarColor(for index: UInt8) -> UIColor {
        switch index {
        case 1: return UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1)
        case 2: return UIColor(red: 0.7, green: 1.0, blue: 0.8, alpha: 1)
        case 3: return UIColor(red: 0.6, green: 0.7, blue: 1.0, alpha: 1)
        default: return .white
        }
    }

    private func collectNodes(_ node: BSPNode?, into out: inout [BSPNode]) {
        guard let node else { return }
        out.append(node)
        collectNodes(node.frontChild, into: &out)
        collectNodes(node.backChild, into: &out)
    }

    private func uiColor(for index: Int16) -> UIColor {
        switch index {
        case DStarColor.black.rawValue: return .black
        case DStarColor.darkGray.rawValue: return .darkGray
        case DStarColor.gray.rawValue: return .gray
        case DStarColor.lightGray.rawValue: return .lightGray
        case DStarColor.white.rawValue: return .white
        case DStarColor.red.rawValue: return .systemRed
        case DStarColor.green.rawValue: return .systemGreen
        case DStarColor.blue.rawValue: return .systemBlue
        case DStarColor.yellow.rawValue: return .systemYellow
        default: return .white
        }
    }
}

private struct MeshAccumulator {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}
#endif
