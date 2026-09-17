#if os(visionOS)
import RealityKit
import SwiftUI
import UIKit

enum DStarImmersiveSpace {
    static let id = "DStarImmersiveSpace"
}

struct DStarImmersiveView: View {
    @EnvironmentObject private var hud: DStarHUDState

    private let worldScale: Float = 0.001
    private let worldAnchorName = "dstar-world"
    private let hsiAnchorName = "dstar-head-hsi-anchor"
    private let hsiGlobeName = "dstar-head-hsi-globe"
    private let ringPrefix = "dstar-ring-"
    private let shipPrefix = "dstar-ship-"

    var body: some View {
        RealityView { content in
            let anchor = AnchorEntity(world: .zero)
            anchor.name = worldAnchorName
            anchor.addChild(makeRingworldEntity(scale: worldScale, brightness: hud.ambientLight))
            anchor.addChild(makeStarfieldEntity(scale: worldScale))
            content.add(anchor)

            // Keep the flight instrument in a stable lower-right position in
            // the wearer's view. The globe itself still rotates with the ship.
            let hsiAnchor = AnchorEntity(.head, trackingMode: .continuous)
            hsiAnchor.name = hsiAnchorName
            hsiAnchor.addChild(makeHeadTrackedHSI())
            content.add(hsiAnchor)
        } update: { content in
            if let anchor = content.entities.first(where: { $0.name == worldAnchorName }) {
                updateRingworld(in: anchor, brightness: hud.ambientLight)
                synchronizeShips(in: anchor, ships: hud.visibleShips)
            }
            updateHeadTrackedHSI(in: content, orientation: hud.orientation)
        }
    }

    private func makeHeadTrackedHSI() -> Entity {
        let root = Entity()
        root.name = hsiGlobeName
        // RealityKit's view direction is -Z. This places the 11 cm globe at a
        // comfortable instrument-panel distance, below and right of center.
        root.position = SIMD3<Float>(0.30, -0.22, -0.55)

        let latitudeSegments = 8
        let longitudeSegments = 16
        let radius: Float = 0.055
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity((latitudeSegments + 1) * longitudeSegments)

        for latitudeIndex in 0...latitudeSegments {
            let latitude = -Float.pi / 2
                + Float(latitudeIndex) * Float.pi / Float(latitudeSegments)
            let radial = cos(latitude)
            let y = sin(latitude)
            for longitudeIndex in 0..<longitudeSegments {
                let longitude = Float(longitudeIndex) * 2 * Float.pi
                    / Float(longitudeSegments)
                positions.append(SIMD3<Float>(
                    radius * radial * sin(longitude),
                    radius * y,
                    radius * radial * cos(longitude)
                ))
            }
        }

        var faceCounts: [UInt8] = []
        var indices: [UInt32] = []
        var materialIndices: [UInt32] = []
        faceCounts.reserveCapacity(latitudeSegments * longitudeSegments)
        indices.reserveCapacity(latitudeSegments * longitudeSegments * 4)
        materialIndices.reserveCapacity(latitudeSegments * longitudeSegments)

        for latitudeIndex in 0..<latitudeSegments {
            for longitudeIndex in 0..<longitudeSegments {
                let nextLongitude = (longitudeIndex + 1) % longitudeSegments
                let lower = latitudeIndex * longitudeSegments
                let upper = (latitudeIndex + 1) * longitudeSegments
                faceCounts.append(4)
                indices.append(contentsOf: [
                    UInt32(lower + longitudeIndex),
                    UInt32(lower + nextLongitude),
                    UInt32(upper + nextLongitude),
                    UInt32(upper + longitudeIndex)
                ])

                if longitudeIndex == 0 || latitudeIndex < latitudeSegments / 2 {
                    materialIndices.append(1) // red reference hemisphere/axis
                } else if longitudeIndex == longitudeSegments / 2 {
                    materialIndices.append(2) // green reciprocal axis
                } else {
                    materialIndices.append(0)
                }
            }
        }

        var descriptor = MeshDescriptor(name: "DStar head-tracked HSI")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .polygons(faceCounts, indices)
        descriptor.materials = .perFace(materialIndices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return root
        }

        func wireMaterial(_ color: UIColor) -> UnlitMaterial {
            var material = UnlitMaterial(color: color)
            material.triangleFillMode = .lines
            material.faceCulling = .none
            return material
        }

        let globe = ModelEntity(
            mesh: mesh,
            materials: [
                wireMaterial(UIColor(white: 0.88, alpha: 0.92)),
                wireMaterial(UIColor(red: 1, green: 0.08, blue: 0.08, alpha: 0.95)),
                wireMaterial(UIColor(red: 0.1, green: 1, blue: 0.2, alpha: 0.95))
            ]
        )
        root.addChild(globe)
        return root
    }

    private func updateHeadTrackedHSI(
        in content: RealityViewContent,
        orientation: DStarHUDOrientation
    ) {
        guard let anchor = content.entities.first(where: { $0.name == hsiAnchorName }),
              let globe = anchor.children.first(where: { $0.name == hsiGlobeName }) else {
            return
        }

        var basis = matrix_identity_float4x4
        basis.columns.0 = SIMD4<Float>(orientation.right, 0)
        basis.columns.1 = SIMD4<Float>(orientation.up, 0)
        basis.columns.2 = SIMD4<Float>(orientation.forward, 0)
        globe.orientation = simd_quatf(basis)
    }

    private func makeRingworldEntity(scale: Float, brightness: Double) -> Entity {
        let root = Entity()
        root.name = "dstar-ringworld"
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
                color: uiColor(for: color, brightness: brightness).withAlphaComponent(0.95),
                roughness: 0.9,
                isMetallic: false
            )
            let part = ModelEntity(mesh: mesh, materials: [material])
            part.name = "\(ringPrefix)\(color)"
            root.addChild(part)
        }

        return root
    }

    private func updateRingworld(in root: Entity, brightness: Double) {
        root.forEachDescendant(withPrefix: ringPrefix) { entity in
            guard let model = entity as? ModelEntity,
                  let raw = entity.name.split(separator: "-").last,
                  let color = Int16(raw) else { return }
            model.model?.materials = [
                SimpleMaterial(
                    color: uiColor(for: color, brightness: brightness).withAlphaComponent(0.95),
                    roughness: 0.9,
                    isMetallic: false
                )
            ]
        }
    }

    private func synchronizeShips(in root: Entity, ships: [DStarHUDShip]) {
        let desiredNames = Set(ships.map { "\(shipPrefix)\($0.id)" })
        for child in Array(root.children)
        where child.name.hasPrefix(shipPrefix) && !desiredNames.contains(child.name) {
            child.removeFromParent()
        }

        for ship in ships {
            let name = "\(shipPrefix)\(ship.id)"
            let entity: Entity
            if let existing = root.children.first(where: { $0.name == name }) {
                entity = existing
            } else {
                entity = makeObjectEntity(for: ship)
                entity.name = name
                root.addChild(entity)
            }

            var transform = matrix_identity_float4x4
            transform.columns.0 = SIMD4<Float>(ship.right, 0)
            transform.columns.1 = SIMD4<Float>(ship.up, 0)
            transform.columns.2 = SIMD4<Float>(ship.forward, 0)
            transform.columns.3 = SIMD4<Float>(ship.position * worldScale, 1)
            entity.transform = Transform(matrix: transform)
        }
    }

    private func makeObjectEntity(for ship: DStarHUDShip) -> Entity {
        if ship.objectClass == .missile {
            return makeMissileEntity()
        }

        var descriptor = MeshDescriptor()
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let fighterScale: Float = 8 * worldScale

        for polygon in FighterMesh.fighter1 where polygon.vertices.count >= 3 {
            guard let base = UInt32(exactly: positions.count) else { continue }
            positions.append(contentsOf: polygon.vertices.map { $0 * fighterScale })
            for i in 1..<(polygon.vertices.count - 1) {
                indices.append(base)
                indices.append(base + UInt32(i))
                indices.append(base + UInt32(i + 1))
            }
        }
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else {
            return Entity()
        }
        let color: UIColor = ship.objectClass == .robot ? .systemOrange : .systemCyan
        return ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
    }

    private func makeMissileEntity() -> Entity {
        let root = Entity()

        let flare = ModelEntity(
            mesh: .generateSphere(radius: 0.006),
            materials: [UnlitMaterial(color: .yellow)]
        )
        root.addChild(flare)

        let tail = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.0025, 0.0025, 0.055)),
            materials: [UnlitMaterial(color: .red)]
        )
        tail.position.z = -0.030
        root.addChild(tail)
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

    private func uiColor(for index: Int16, brightness: Double) -> UIColor {
        let base: UIColor
        switch index {
        case DStarColor.black.rawValue: base = .black
        case DStarColor.darkGray.rawValue: base = .darkGray
        case DStarColor.gray.rawValue: base = .gray
        case DStarColor.lightGray.rawValue: base = .lightGray
        case DStarColor.white.rawValue: base = .white
        case DStarColor.red.rawValue: base = .systemRed
        case DStarColor.green.rawValue: base = .systemGreen
        case DStarColor.blue.rawValue: base = .systemBlue
        case DStarColor.yellow.rawValue: base = .systemYellow
        default: base = .white
        }
        let amount = max(0, min(brightness, 1))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard base.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return base
        }
        return UIColor(
            red: red * amount,
            green: green * amount,
            blue: blue * amount,
            alpha: alpha
        )
    }
}

private extension Entity {
    func forEachDescendant(withPrefix prefix: String, _ body: (Entity) -> Void) {
        for child in children {
            if child.name.hasPrefix(prefix) { body(child) }
            child.forEachDescendant(withPrefix: prefix, body)
        }
    }
}

private struct MeshAccumulator {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}
#endif
