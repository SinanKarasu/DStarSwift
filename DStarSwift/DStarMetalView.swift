import MetalKit
import SwiftUI

#if os(macOS)
import AppKit

final class DStarInputMTKView: MTKView {
    var onInput: ((DStarInputAction) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        handleKey(event, isDown: true)
    }

    override func keyUp(with event: NSEvent) {
        handleKey(event, isDown: false)
    }

    override func mouseDown(with event: NSEvent) {
        onInput?(.setLeftButton(true))
        updateMouse(event)
    }

    override func mouseUp(with event: NSEvent) {
        onInput?(.setLeftButton(false))
        updateMouse(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onInput?(.setRightButton(true))
        updateMouse(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onInput?(.setRightButton(false))
        updateMouse(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onInput?(.setMiddleButton(true))
        updateMouse(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        onInput?(.setMiddleButton(false))
        updateMouse(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateMouse(event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateMouse(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateMouse(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        updateMouse(event)
    }

    private func updateMouse(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let x = Float(min(max(p.x / width, 0), 1))
        let y = Float(min(max(1 - (p.y / height), 0), 1))
        onInput?(.setMouse(x, y))
    }

    private func handleKey(_ event: NSEvent, isDown: Bool) {
        // macOS virtual key codes — stable across hardware layouts.
        switch event.keyCode {
        case 123: onInput?(.setArrowLeft(isDown))
        case 124: onInput?(.setArrowRight(isDown))
        case 125: onInput?(.setArrowDown(isDown))
        case 126: onInput?(.setArrowUp(isDown))
        case 122: onInput?(.setFunctionKey(1, isDown))   // F1
        case 120: onInput?(.setFunctionKey(2, isDown))   // F2
        case 99:  onInput?(.setFunctionKey(3, isDown))   // F3
        case 118: onInput?(.setFunctionKey(4, isDown))   // F4
        default: break
        }

        if isDown {
            if event.keyCode == 53 {
                onInput?(.escape)
                return
            }
            if event.keyCode == 48 {
                onInput?(.tab)
                return
            }
            // Drop modifier-only events (e.g. holding Cmd alone has no characters).
            // Cmd-X shortcuts are routed by the menu bar via SwiftUI .commands.
            if event.modifierFlags.contains(.command) { return }
            if let raw = event.charactersIgnoringModifiers, raw.count == 1 {
                onInput?(.keyCharacter(raw))
            }
        }
    }
}

struct DStarMetalView: NSViewRepresentable {
    @ObservedObject var hud: DStarHUDState

    func makeCoordinator() -> DStarRenderer {
        let renderer = DStarRenderer()
        renderer.hud = hud
        return renderer
    }

    func makeNSView(context: Context) -> DStarInputMTKView {
        let view = DStarInputMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.05, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.delegate = context.coordinator
        view.onInput = { action in
            context.coordinator.handleInput(action)
        }
        context.coordinator.configure(for: view)
        return view
    }

    func updateNSView(_ nsView: DStarInputMTKView, context: Context) {
        context.coordinator.hud = hud
    }
}
#else
struct DStarMetalView: UIViewRepresentable {
    @ObservedObject var hud: DStarHUDState

    func makeCoordinator() -> DStarRenderer {
        let renderer = DStarRenderer()
        renderer.hud = hud
        return renderer
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.05, alpha: 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.delegate = context.coordinator
        context.coordinator.configure(for: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.hud = hud
    }
}
#endif
