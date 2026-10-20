#if os(visionOS)
import RealityKit
import SwiftUI
import UIKit

enum DStarImmersiveSpace {
    static let id = "DStarImmersiveSpace"
}

struct DStarImmersiveView: View {
    @EnvironmentObject private var hud: DStarHUDState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var legacyWorld = DStarLegacyWorld()

    private let worldScale: Float = 0.001
    private let worldAnchorName = "dstar-world"
    private let worldBodyPrefix = "dstar-world-body-"
    private let worldMaterialPrefix = "dstar-world-material-"
    private let shipPrefix = "dstar-ship-"

    var body: some View {
        RealityView { content, attachments in
            let anchor = AnchorEntity(world: .zero)
            anchor.name = worldAnchorName
            anchor.addChild(makeLegacyWorldEntity(scale: worldScale, brightness: hud.ambientLight))
            anchor.addChild(makeStarfieldEntity(scale: worldScale))
            let habitat = makeHabitatEntity()
            content.add(habitat)
            applyCamera(to: habitat, cameraRelative: true)
            content.add(anchor)
            applyCamera(to: anchor)
            // Keep the exit independent of the game world and room origin.
            let exitAnchor = AnchorEntity(.head, trackingMode: .continuous)
            if let exit = attachments.entity(for: "exit-immersive") {
                exit.position = SIMD3<Float>(0, -0.22, -0.8)
                exitAnchor.addChild(exit)
            }
            content.add(exitAnchor)
            if let panel = attachments.entity(for: "navigation") {
                panel.position = SIMD3<Float>(0.35, 1.05, -0.8)
                content.add(panel)
            }

        } update: { content, _ in
            if let anchor = content.entities.first(where: { $0.name == worldAnchorName }) {
                legacyWorld.advance(to: hud.simulationTime)
                updateLegacyWorld(in: anchor, brightness: hud.ambientLight)
                if let habitat = content.entities.first(where: { $0.name == "world-v2" }) {
                    applyHabitatSnapshot(to: habitat)
                    applyCamera(to: habitat, cameraRelative: true)
                }
                synchronizeShips(in: anchor, ships: hud.visibleShips)
                applyCamera(to: anchor)
            }
        } attachments: {
            Attachment(id: "exit-immersive") {
                Button {
                    Task { await exitImmersiveSpace() }
                } label: {
                    Label("Exit Immersive", systemImage: "rectangle.portrait.and.arrow.right")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(hud.isImmersiveTransitioning)
                .glassBackgroundEffect()
            }
            Attachment(id: "navigation") {
                DStarNavigationGlobe(hud: hud)
            }
        }
        .onAppear {
            hud.isImmersiveActive = true
            hud.immersiveStatus = "Immersive Active"
        }
        .onDisappear {
            hud.onCommand?(.setGlobeSteering(.zero))
            hud.isImmersiveActive = false
            hud.immersiveStatus = "Windowed"
        }
    }

    @MainActor
    private func exitImmersiveSpace() async {
        guard !hud.isImmersiveTransitioning else { return }
        hud.isImmersiveTransitioning = true
        defer { hud.isImmersiveTransitioning = false }
        hud.onCommand?(.setGlobeSteering(.zero))
        await dismissImmersiveSpace()
        hud.isImmersiveActive = false
        hud.immersiveStatus = "Windowed"
    }

    /// Reflect DStar +Z into RealityKit -Z after applying the inverse cockpit pose.
    /// Head tracking remains entirely under RealityKit's control.
    private func applyCamera(to root: Entity, cameraRelative: Bool = false) {
        let camera = hud.look.orientation(relativeTo: hud.orientation)
        let basis = simd_float3x3(columns: (camera.right, camera.up, camera.forward))
        let inverse = simd_quatf(basis).inverse
        let reflected = simd_quatf(ix: -inverse.imag.x, iy: -inverse.imag.y,
                                   iz: inverse.imag.z, r: inverse.real)
        root.scale = SIMD3<Float>(1, 1, -1)
        root.orientation = reflected
        root.position = cameraRelative ? .zero : reflected.act(SIMD3<Float>(-hud.position.x, -hud.position.y,
                                                   hud.position.z) * worldScale)
    }

    private func makeHabitatEntity() -> Entity {
        let root = Entity()
        root.name = "world-v2"
        guard let items = try? DStarWorld.arrival.snapshot(at: Double(hud.simulationTime),
            relativeTo: try WorldPosition(offset: SIMD3<Double>(hud.position)),
            frameTimes: ["station": Double(hud.stationTime)]) else { return root }
        for item in items {
            var descriptor = MeshDescriptor(name: item.geometry.id)
            descriptor.positions = MeshBuffer(item.geometry.positions.map { $0 * worldScale })
            descriptor.primitives = .triangles(item.geometry.indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            let c = item.geometry.color
            let material = UnlitMaterial(color: UIColor(red: CGFloat(c.x), green: CGFloat(c.y),
                                                       blue: CGFloat(c.z), alpha: CGFloat(c.w)))
            let part = ModelEntity(mesh: mesh, materials: [material])
            part.name = item.id
            root.addChild(part)
        }
        applyHabitatSnapshot(to: root)
        return root
    }

    private func applyHabitatSnapshot(to root: Entity) {
        guard let items = try? DStarWorld.arrival.snapshot(at: Double(hud.simulationTime),
            relativeTo: try WorldPosition(offset: SIMD3<Double>(hud.position)),
            frameTimes: ["station": Double(hud.stationTime)]) else { return }
        for item in items {
            guard let part = root.children.first(where: { $0.name == item.id }) else { continue }
            part.position = SIMD3<Float>(item.pose.position) * worldScale
            part.orientation = simd_quatf(ix: Float(item.pose.orientation.imag.x),
                                         iy: Float(item.pose.orientation.imag.y),
                                         iz: Float(item.pose.orientation.imag.z),
                                         r: Float(item.pose.orientation.real))
        }
    }

    private func makeLegacyWorldEntity(scale: Float, brightness: Double) -> Entity {
        let root = Entity()
        root.name = "dstar-legacy-world"
        for body in legacyWorld.bodies {
            root.addChild(makeLegacyBodyEntity(body, scale: scale, brightness: brightness))
        }
        return root
    }

    private func makeLegacyBodyEntity(
        _ body: DStarLegacyBody,
        scale: Float,
        brightness: Double
    ) -> Entity {
        let root = Entity()
        root.name = "\(worldBodyPrefix)\(body.kind.rawValue)"

        let nodes = BSPUtil.nodes(in: body.mesh)

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
            part.name = "\(worldMaterialPrefix)\(color)"
            root.addChild(part)
        }

        applyLegacyTransform(body.motion, to: root, scale: scale)
        return root
    }

    private func updateLegacyWorld(in root: Entity, brightness: Double) {
        for body in legacyWorld.bodies {
            guard let entity = root.findDescendant(
                named: "\(worldBodyPrefix)\(body.kind.rawValue)"
            ) else { continue }
            applyLegacyTransform(body.motion, to: entity, scale: worldScale)
        }

        root.forEachDescendant(withPrefix: worldMaterialPrefix) { entity in
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

    private func applyLegacyTransform(
        _ motion: DStarObject,
        to entity: Entity,
        scale: Float
    ) {
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4<Float>(motion.right, 0)
        transform.columns.1 = SIMD4<Float>(motion.up, 0)
        transform.columns.2 = SIMD4<Float>(motion.forward, 0)
        transform.columns.3 = SIMD4<Float>(motion.position * scale, 1)
        entity.transform = Transform(matrix: transform)
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

    func findDescendant(named name: String) -> Entity? {
        for child in children {
            if child.name == name { return child }
            if let match = child.findDescendant(named: name) { return match }
        }
        return nil
    }
}

private struct MeshAccumulator {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}
#endif
