import MetalKit
import simd

private struct StarVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

private struct Uniforms {
    var viewProjection: simd_float4x4
}

final class DStarRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var starPipeline: MTLRenderPipelineState?
    private var meshPipeline: MTLRenderPipelineState?
    private var stars: MTLBuffer?
    private var starCount: Int = 0
    private let legacyWorld = DStarLegacyWorld()
    private var aspect: Float = 1.0
    private var lastFrameTime: CFAbsoluteTime = 0
    let gameState = DStarGameState()
    private var drawTrimLines = true
    private weak var attachedView: MTKView?
    private var feedbackFramesRemaining = 0

    /// Optional SwiftUI mirror. The renderer pushes flag changes here each
    /// frame so the help overlay / HUD can react to in-game key presses,
    /// and wires the HUD's `onCommand` callback so menu items can send
    /// input back into the game state.
    weak var hud: DStarHUDState? {
        didSet {
            guard let hud else { return }
            let game = gameState
            DispatchQueue.main.async { [weak self, game] in
                hud.onCommand = { [weak self] action in
                    self?.handleInput(action)
                }
                hud.onSpawnRobot = { [weak game] in
                    game?.spawnRobot()
                }
                hud.register(gameState: game)
            }
        }
    }

    /// The data source for background stars. Swap this for a `DESIStarfieldSource`
    /// later without touching the renderer.
    var starfieldSource: StarfieldSource = SphericalShellStarfield()

    private var depthStateFill: MTLDepthStencilState?
    private var depthStateLines: MTLDepthStencilState?

    private func makeDepthState(
        device: MTLDevice,
        write: Bool,
        compare: MTLCompareFunction
    ) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.isDepthWriteEnabled = write
        descriptor.depthCompareFunction = compare
        return device.makeDepthStencilState(descriptor: descriptor)
    }
	
    func configure(for view: MTKView) {
        guard let device = view.device else { return }
        self.attachedView = view
        self.device = device
        self.queue = device.makeCommandQueue()
        self.stars = makeStarBuffer(device: device)
        self.starPipeline = makePipeline(device: device, view: view, vertex: "starVertex", fragment: "starFragment")
        self.meshPipeline = makePipeline(device: device, view: view, vertex: "meshVertex", fragment: "meshFragment")
        self.depthStateFill = makeDepthState(device: device, write: true, compare: .less)
        self.depthStateLines = makeDepthState(device: device, write: false, compare: .lessEqual)

        updateTrimFeedbackUI()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let safeWidth = max(Float(size.width), 1.0)
        let safeHeight = max(Float(size.height), 1.0)
        aspect = safeWidth / safeHeight
    }

    func handleInput(_ action: DStarInputAction) {
        if case let .keyCharacter(raw) = action, raw == "l" || raw == "L" {
            drawTrimLines.toggle()
            feedbackFramesRemaining = 8
            print("Trim lines \(drawTrimLines ? "ON" : "OFF")")
            updateTrimFeedbackUI()
        }
        gameState.apply(action)
    }

    func draw(in view: MTKView) {
        guard
            let queue,
            let starPipeline,
            let meshPipeline,
            let stars,
            let depthStateFill,
            let depthStateLines,
            let passDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else { return }

        // Explicit depth clear avoids stale depth contents that can show up as flicker.
        passDescriptor.depthAttachment.loadAction = .clear
        passDescriptor.depthAttachment.storeAction = .dontCare
        passDescriptor.depthAttachment.clearDepth = 1.0
        if feedbackFramesRemaining > 0 {
            let c = drawTrimLines
                ? MTLClearColor(red: 0.0, green: 0.12, blue: 0.0, alpha: 1.0)
                : MTLClearColor(red: 0.12, green: 0.0, blue: 0.0, alpha: 1.0)
            passDescriptor.colorAttachments[0].clearColor = c
            feedbackFramesRemaining -= 1
        } else {
            passDescriptor.colorAttachments[0].clearColor = view.clearColor
        }

        let commandBuffer = queue.makeCommandBuffer()
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: passDescriptor)

        let now = CFAbsoluteTimeGetCurrent()
        let delta = lastFrameTime > 0 ? Float(now - lastFrameTime) : (1 / 60)
        lastFrameTime = now
        gameState.step(deltaTime: delta)
        legacyWorld.advance(to: gameState.elapsedTime)

        if let hud {
            let game = gameState
            DispatchQueue.main.async {
                hud.update(from: game)
            }
        }

        let projection = simd_float4x4.perspective(
            fovY: 65.0 * .pi / 180.0,
            aspect: max(aspect, 0.0001),
            nearZ: 20.0,
            farZ: 10_000.0
        )
        let ship = gameState.me
        let camera = gameState.look.orientation(relativeTo: DStarHUDOrientation(
            forward: ship.forward, up: ship.up, right: ship.right))
        let basis = simd_float4x4.basis(right: camera.right, up: camera.up, forward: camera.forward)
        let viewMatrix = simd_float4x4.rigidInverse(rotationAndBasis: basis, position: ship.position)
        // DStar's world is left-handed with +Z forward; Metal's perspective
        // matrix looks down -Z. The original OpenGL renderer performed this
        // same conversion with glScaled(1, 1, -1) before applying the view.
        let dstarToMetal = simd_float4x4(diagonal: SIMD4<Float>(1, 1, -1, 1))
        var uniforms = Uniforms(viewProjection: projection * dstarToMetal * viewMatrix)

        encoder?.setRenderPipelineState(starPipeline)
        encoder?.setVertexBuffer(stars, offset: 0, index: 0)
        encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder?.drawPrimitives(type: .point, vertexStart: 0, vertexCount: starCount)

        if let device {
            var triangleVertices: [StarVertex] = []
            var lineVertices: [StarVertex] = []
            var missileLineVertices: [StarVertex] = []

            for body in legacyWorld.bodies {
                var visible: [BSPNode] = []
                BSPUtil.collectVisiblePolygons(
                    node: body.mesh,
                    viewer: body.localPoint(fromWorld: ship.position),
                    out: &visible
                )
                let bodyVertices = makeMeshVertices(from: visible, body: body)
                triangleVertices.append(contentsOf: bodyVertices.0)
                lineVertices.append(contentsOf: bodyVertices.1)
            }

            triangleVertices = triangleVertices.map {
                StarVertex(position: $0.position - ship.position, color: $0.color)
            }

            // Both backends consume the same procedural geometry and frame snapshot.
            if let items = try? DStarWorld.arrival.snapshot(at: Double(gameState.elapsedTime),
                relativeTo: try WorldPosition(offset: SIMD3<Double>(ship.position)),
                frameTimes: ["station": Double(gameState.stationTime)]) {
                for item in items {
                    for index in item.geometry.indices {
                        triangleVertices.append(StarVertex(
                            position: item.pose.renderPoint(item.geometry.positions[Int(index)], relativeTo: .zero),
                            color: item.geometry.color))
                    }
                }
            }

            let habitatVertexCount = triangleVertices.count
            // Append every other ship's mesh into the same triangle buffer.
            // Player ship (`me`) is not drawn — the camera IS its cockpit.
            for other in gameState.others.values {
                if other.objectClass == .missile {
                    appendMissileLines(for: other, into: &missileLineVertices)
                } else {
                    appendFighterTriangles(for: other, into: &triangleVertices)
                }
            }

            for index in habitatVertexCount..<triangleVertices.count {
                triangleVertices[index].position -= ship.position
            }
            // Stars retain the legacy world-space camera; mesh geometry uses a nearby origin.
            let relativeView = simd_float4x4.rigidInverse(rotationAndBasis: basis, position: .zero)
            uniforms = Uniforms(viewProjection: projection * dstarToMetal * relativeView)
            lineVertices = lineVertices.map {
                StarVertex(position: $0.position - ship.position, color: $0.color)
            }
            missileLineVertices = missileLineVertices.map {
                StarVertex(position: $0.position - ship.position, color: $0.color)
            }

            if !triangleVertices.isEmpty {
                let triBuffer = device.makeBuffer(
                    bytes: triangleVertices,
                    length: MemoryLayout<StarVertex>.stride * triangleVertices.count
                )
                encoder?.setRenderPipelineState(meshPipeline)
                encoder?.setDepthStencilState(depthStateFill)
                encoder?.setVertexBuffer(triBuffer, offset: 0, index: 0)
                encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangleVertices.count)
            }

            if !drawTrimLines { lineVertices.removeAll(keepingCapacity: false) }
            lineVertices.append(contentsOf: missileLineVertices)
            if !lineVertices.isEmpty {
                let lineBuffer = device.makeBuffer(
                    bytes: lineVertices,
                    length: MemoryLayout<StarVertex>.stride * lineVertices.count
                )
                encoder?.setRenderPipelineState(meshPipeline)
                encoder?.setDepthStencilState(depthStateLines)
                // Slight bias helps suppress z-fighting shimmer on coplanar line overlays.
                encoder?.setDepthBias(0.0, slopeScale: 0.0, clamp: -0.0005)
                encoder?.setVertexBuffer(lineBuffer, offset: 0, index: 0)
                encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder?.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineVertices.count)
                encoder?.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
            }
        }

        encoder?.endEncoding()

        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }

    private func makeStarBuffer(device: MTLDevice) -> MTLBuffer? {
        let palette: [SIMD4<Float>] = [
            SIMD4<Float>(1, 1, 1, 1),   // white
            SIMD4<Float>(1, 0.4, 0.4, 1), // red giants
            SIMD4<Float>(0.6, 1, 0.7, 1), // green-tinted
            SIMD4<Float>(0.6, 0.7, 1, 1), // blue
        ]

        let points = starfieldSource.makeStars()
        var vertices: [StarVertex] = []
        vertices.reserveCapacity(points.count)
        for star in points {
            let idx = Int(min(star.colorIndex, 3))
            var color = palette[idx]
            color.w = star.magnitude
            vertices.append(StarVertex(position: star.position, color: color))
        }

        starCount = vertices.count
        guard !vertices.isEmpty else { return nil }
        let length = MemoryLayout<StarVertex>.stride * vertices.count
        return device.makeBuffer(bytes: vertices, length: length)
    }

    private func makePipeline(device: MTLDevice, view: MTKView, vertex: String, fragment: String) -> MTLRenderPipelineState? {
        guard let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        // `sampleCount` was renamed to `rasterSampleCount` in macOS 13.
        descriptor.rasterSampleCount = view.sampleCount
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeMeshVertices(
        from nodes: [BSPNode],
        body: DStarLegacyBody
    ) -> ([StarVertex], [StarVertex]) {
        var triangles: [StarVertex] = []
        var lines: [StarVertex] = []

        for node in nodes {
            guard node.vertices.count >= 3 else { continue }

            if node.color >= 0 {
                let c = BSPUtil.color(node.color)
                let base = body.worldPoint(fromLocal: node.vertices[0])
                for i in 1..<(node.vertices.count - 1) {
                    triangles.append(StarVertex(position: base, color: c))
                    triangles.append(StarVertex(
                        position: body.worldPoint(fromLocal: node.vertices[i]),
                        color: c
                    ))
                    triangles.append(StarVertex(
                        position: body.worldPoint(fromLocal: node.vertices[i + 1]),
                        color: c
                    ))
                }
            }

            if node.trimColor >= 0 {
                let c = BSPUtil.color(node.trimColor)
                for i in 0..<node.vertices.count {
                    let p0 = body.worldPoint(fromLocal: node.vertices[i])
                    let p1 = body.worldPoint(
                        fromLocal: node.vertices[(i + 1) % node.vertices.count]
                    )
                    lines.append(StarVertex(position: p0, color: c))
                    lines.append(StarVertex(position: p1, color: c))
                }
            }
        }

        return (triangles, lines)
    }

    /// Each ship's mesh is in local space (forward = +Z, up = +Y, right = +X).
    /// Transform by the ship's basis and position to put it in world space.
    /// The mesh is small (26 polys), so we just expand triangles inline.
    private func appendFighterTriangles(
        for ship: DStarObject,
        into triangles: inout [StarVertex]
    ) {
        let scale: Float = 8.0   // bare fighter is ~3 units long; bump for visibility
        let r = ship.right * scale
        let u = ship.up * scale
        let f = ship.forward * scale
        let p = ship.position

        @inline(__always)
        func toWorld(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3<Float>(
                v.x * r.x + v.y * u.x + v.z * f.x,
                v.x * r.y + v.y * u.y + v.z * f.y,
                v.x * r.z + v.y * u.z + v.z * f.z
            ) + p
        }

        for poly in FighterMesh.fighter1 {
            guard poly.vertices.count >= 3 else { continue }
            let c = BSPUtil.color(poly.color)
            let v0 = toWorld(poly.vertices[0])
            for i in 1..<(poly.vertices.count - 1) {
                let vi = toWorld(poly.vertices[i])
                let vj = toWorld(poly.vertices[i + 1])
                triangles.append(StarVertex(position: v0, color: c))
                triangles.append(StarVertex(position: vi, color: c))
                triangles.append(StarVertex(position: vj, color: c))
                if poly.doubleSided {
                    // Emit the back face too so the mesh is visible from any angle
                    // (the depth pipeline does the rest).
                    triangles.append(StarVertex(position: v0, color: c))
                    triangles.append(StarVertex(position: vj, color: c))
                    triangles.append(StarVertex(position: vi, color: c))
                }
            }
        }
    }

    /// Port of `missile_line.h`, with an extended red tail so a launched
    /// missile reads as a tracer at modern display resolutions.
    private func appendMissileLines(
        for missile: DStarObject,
        into lines: inout [StarVertex]
    ) {
        let red = BSPUtil.color(DStarColor.red.rawValue)
        let yellow = BSPUtil.color(DStarColor.yellow.rawValue)
        let scale: Float = 3
        let r = missile.right * scale
        let u = missile.up * scale
        let f = missile.forward * scale

        @inline(__always)
        func toWorld(_ v: SIMD3<Float>) -> SIMD3<Float> {
            missile.position + v.x * r + v.y * u + v.z * f
        }

        @inline(__always)
        func segment(_ a: SIMD3<Float>, _ b: SIMD3<Float>, color: SIMD4<Float>) {
            lines.append(StarVertex(position: toWorld(a), color: color))
            lines.append(StarVertex(position: toWorld(b), color: color))
        }

        // Red cross and body from the original 1986 line model.
        segment(SIMD3<Float>(0.5, 0, 0), SIMD3<Float>(-0.5, 0, 0), color: red)
        segment(SIMD3<Float>(0, 0.5, 0), SIMD3<Float>(0, -0.5, 0), color: red)
        segment(SIMD3<Float>(0, 0, 3), SIMD3<Float>(0, 0, 0), color: red)

        // Yellow four-stroke flare from missile_line.h.
        segment(SIMD3<Float>(1.5, 1.5, 0.5), SIMD3<Float>(-1.5, -1.5, -0.5), color: yellow)
        segment(SIMD3<Float>(-1.5, 1.5, 0.5), SIMD3<Float>(1.5, -1.5, -0.5), color: yellow)
        segment(SIMD3<Float>(1.5, -1.5, 0.5), SIMD3<Float>(-1.5, 1.5, -0.5), color: yellow)
        segment(SIMD3<Float>(-1.5, -1.5, 0.5), SIMD3<Float>(1.5, 1.5, -0.5), color: yellow)

        // The legacy three-unit body becomes almost sub-pixel on a Retina
        // display, so extend a bright wake behind it to make flight legible.
        segment(SIMD3<Float>(0, 0, -18), SIMD3<Float>(0, 0, 0), color: red)
    }

    private func updateTrimFeedbackUI() {
#if os(macOS)
        if let titleWindow = attachedView?.window {
            titleWindow.title = "DStarSwift  |  Trim: \(drawTrimLines ? "ON" : "OFF")  |  Toggle: L"
        }
#endif
    }
}
