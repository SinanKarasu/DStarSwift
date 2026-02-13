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
    private var ringworldRoot: BSPNode?
    private var aspect: Float = 1.0
    private var lastFrameTime: CFAbsoluteTime = 0
    private let gameState = DStarGameState()
    private var drawTrimLines = true

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
        self.device = device
        self.queue = device.makeCommandQueue()
        self.stars = makeStarBuffer(device: device)
        self.starPipeline = makePipeline(device: device, view: view, vertex: "starVertex", fragment: "starFragment")
        self.meshPipeline = makePipeline(device: device, view: view, vertex: "meshVertex", fragment: "meshFragment")
        self.depthStateFill = makeDepthState(device: device, write: true, compare: .less)
        self.depthStateLines = makeDepthState(device: device, write: false, compare: .lessEqual)

        self.ringworldRoot = BSPUtil.makeRingworldTree()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let safeWidth = max(Float(size.width), 1.0)
        let safeHeight = max(Float(size.height), 1.0)
        aspect = safeWidth / safeHeight
    }

    func handleInput(_ action: DStarInputAction) {
        if case let .keyCharacter(raw) = action, raw == "l" || raw == "L" {
            drawTrimLines.toggle()
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

        let commandBuffer = queue.makeCommandBuffer()
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: passDescriptor)

        let now = CFAbsoluteTimeGetCurrent()
        let delta = lastFrameTime > 0 ? Float(now - lastFrameTime) : (1 / 60)
        lastFrameTime = now
        gameState.step(deltaTime: delta)

        let projection = simd_float4x4.perspective(
            fovY: 65.0 * .pi / 180.0,
            aspect: max(aspect, 0.0001),
            nearZ: 1.0,
            farZ: 10_000.0
        )
        let ship = gameState.me
        let basis = simd_float4x4.basis(right: ship.right, up: ship.up, forward: ship.forward)
        let viewMatrix = simd_float4x4.rigidInverse(rotationAndBasis: basis, position: ship.position)
        var uniforms = Uniforms(viewProjection: projection * viewMatrix)

        encoder?.setRenderPipelineState(starPipeline)
        encoder?.setVertexBuffer(stars, offset: 0, index: 0)
        encoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder?.drawPrimitives(type: .point, vertexStart: 0, vertexCount: starCount)

        if let device {
            var visible: [BSPNode] = []
            BSPUtil.collectVisiblePolygons(node: ringworldRoot, viewer: ship.position, out: &visible)
            let (triangleVertices, lineVertices) = makeMeshVertices(from: visible)

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

            if drawTrimLines, !lineVertices.isEmpty {
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
        var vertices: [StarVertex] = []
        vertices.reserveCapacity(LegacyStarfield.points.count)

        let starTotal = LegacyStarfield.points.count
        let other = starTotal / 8
        let whiteCount = starTotal - other * 3

        for i in 0..<starTotal {
            let color: SIMD4<Float>
            if i < whiteCount {
                color = SIMD4<Float>(1, 1, 1, 1)
            } else if i < whiteCount + other {
                color = SIMD4<Float>(1, 0, 0, 1)
            } else if i < whiteCount + other * 2 {
                color = SIMD4<Float>(0, 1, 0, 1)
            } else {
                color = SIMD4<Float>(0, 0, 1, 1)
            }

            vertices.append(StarVertex(position: LegacyStarfield.points[i], color: color))
        }

        starCount = vertices.count
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
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeMeshVertices(from nodes: [BSPNode]) -> ([StarVertex], [StarVertex]) {
        var triangles: [StarVertex] = []
        var lines: [StarVertex] = []

        for node in nodes {
            guard node.vertices.count >= 3 else { continue }

            if node.color >= 0 {
                let c = BSPUtil.color(node.color)
                let base = node.vertices[0]
                for i in 1..<(node.vertices.count - 1) {
                    triangles.append(StarVertex(position: base, color: c))
                    triangles.append(StarVertex(position: node.vertices[i], color: c))
                    triangles.append(StarVertex(position: node.vertices[i + 1], color: c))
                }
            }

            if node.trimColor >= 0 {
                let c = BSPUtil.color(node.trimColor)
                for i in 0..<node.vertices.count {
                    let p0 = node.vertices[i]
                    let p1 = node.vertices[(i + 1) % node.vertices.count]
                    lines.append(StarVertex(position: p0, color: c))
                    lines.append(StarVertex(position: p1, color: c))
                }
            }
        }

        return (triangles, lines)
    }
}
