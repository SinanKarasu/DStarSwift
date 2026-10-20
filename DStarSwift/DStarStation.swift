import Foundation
import simd
import SwiftGLTF

/// Deliberately small static-asset profile shared by Metal and RealityKit.
/// SwiftGLTF owns parsing, resource loading and accessor decoding. The adapter
/// rejects features our unlit WorldGeometry renderer cannot represent.
enum DStarStationAsset {
    enum AssetError: Error { case missingFile, unsupportedProfile }
    static let result: Result<[WorldGeometry], Error> = Result {
        guard let url = Bundle.main.url(forResource: "DockingCore", withExtension: "gltf") else {
            throw AssetError.missingFile
        }
        return try load(url: url)
    }

    static func load(url: URL) throws -> [WorldGeometry] {
        let container = try Container(url: url)
        let document = container.document
        let scene = try document.scene?.resolve(in: document) ?? document.scenes.first
        var parts: [WorldGeometry] = []
        func visit(_ node: Node, parent: simd_float4x4, depth: Int) throws {
            guard depth <= document.nodes.count, node.skin == nil, node.weights == nil else {
                throw AssetError.unsupportedProfile
            }
            var transform = node.matrix ?? matrix_identity_float4x4
            // glTF matrices and TRS are mutually exclusive. SwiftGLTF supplies
            // identity when matrix is absent, so compose TRS explicitly here.
            if node.translation != nil || node.rotation != nil || node.scale != nil {
                transform = simd_float4x4(simd_quatf(vector: node.rotation ?? SIMD4(0,0,0,1)))
                let scale = node.scale ?? SIMD3(repeating: 1)
                transform.columns.0 *= scale.x; transform.columns.1 *= scale.y; transform.columns.2 *= scale.z
                transform.columns.3 = SIMD4(node.translation ?? .zero, 1)
            }
            transform = parent * transform
            if let mesh = try node.mesh?.resolve(in: document) {
                for primitive in mesh.primitives {
                    guard primitive.mode == .TRIANGLES, primitive.targets.isEmpty,
                          let position = try primitive.attributes[.POSITION]?.resolve(in: document),
                          position.type == .VEC3 else { throw AssetError.unsupportedProfile }
                    let values = try container.floatComponents(for: position)
                    var points: [SIMD3<Float>] = []
                    for i in stride(from: 0, to: values.count, by: 3) {
                        let p = transform * SIMD4(values[i], values[i+1], values[i+2], 1)
                        guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { throw AssetError.unsupportedProfile }
                        points.append(SIMD3(p.x,p.y,p.z))
                    }
                    var indices = Array(0..<UInt32(points.count))
                    if let accessor = try primitive.indices?.resolve(in: document) {
                        // Small static assets only: every integer is exactly representable.
                        let numbers = try container.floatComponents(for: accessor)
                        guard numbers.allSatisfy({ $0 >= 0 && $0 < Float(points.count) && $0 < 16_777_216 && $0.rounded() == $0 }) else {
                            throw AssetError.unsupportedProfile
                        }
                        indices = numbers.map(UInt32.init)
                    }
                    guard indices.count % 3 == 0 else { throw AssetError.unsupportedProfile }
                    let material = try primitive.material?.resolve(in: document)
                    guard material?.isUnlit == true, material?.pbrMetallicRoughness?.baseColorTexture == nil else {
                        throw AssetError.unsupportedProfile
                    }
                    parts.append(WorldGeometry(id: "station.\(parts.count)", positions: points, indices: indices,
                                               color: material?.pbrMetallicRoughness?.baseColorFactor ?? SIMD4(repeating: 1)))
                }
            }
            for child in node.children { try visit(child.resolve(in: document), parent: transform, depth: depth + 1) }
        }
        for root in scene?.nodes ?? [] { try visit(root.resolve(in: document), parent: matrix_identity_float4x4, depth: 0) }
        guard !parts.isEmpty else { throw AssetError.unsupportedProfile }
        return parts
    }
}

/// Prototype station. World +Z is the docking axis; the source asset uses +Y.
enum DStarStation {
    static let center = SIMD3<Float>(0, 0, 1000)
    static let berth = SIMD3<Float>(0, 0, 1035)
    static let spin: Float = 0.08
    static func up(at time: Float) -> SIMD3<Float> {
        simd_quatf(angle: spin * time, axis: SIMD3(0,0,1)).act(SIMD3(0,1,0))
    }
    static func rollError(up: SIMD3<Float>, at time: Float) -> Float {
        acos(max(-1, min(1, simd_dot(up, self.up(at: time)))))
    }
    static func canCapture(position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>, speed: Float,
                           at time: Float) -> Bool {
        simd_distance(position, berth) <= 3 && abs(speed) <= 2.5 &&
        simd_dot(forward, SIMD3(0,0,1)) >= cos(5 * .pi / 180) && rollError(up: up, at: time) <= 5 * .pi / 180
    }
}
