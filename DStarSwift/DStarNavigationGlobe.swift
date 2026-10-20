import SwiftUI
import simd

/// Shared mouse/indirect-pinch control; no raw eye or skeletal hand tracking required.
struct DStarNavigationGlobe: View {
    @ObservedObject var hud: DStarHUDState
    @Environment(\.scenePhase) private var scenePhase
    @State private var steering = false
    @State private var startLook: DStarLook?
    @GestureState private var dragging = false

    var body: some View {
        VStack(spacing: 8) {
            Picker("Globe mode", selection: $steering) {
                Text("Look").tag(false)
                Text("Steer").tag(true)
            }
            .pickerStyle(.segmented)
            interactiveGlobe.frame(width: 120, height: 120)
                .accessibilityLabel(steering ? "Drag globe to steer ship" : "Drag globe to look around")
                .accessibilityHint("Cyan dot shows viewing direction; white center marks ship heading.")
            Text(steering ? "Drag to turn · release to stop" : "Drag to look · cyan marks view")
                .font(.caption2)
            Group {
                Button("Visit Docking Core") { release(); hud.onCommand?(.visitStation) }
                if case .failure = DStarStationAsset.result {
                    Text("Station model failed to load").foregroundStyle(.red)
                }
                Text(hud.stationDocked ? "Docked" : String(format: "Berth %.0f m · roll %.0f°", hud.stationRange, hud.stationRollDegrees))
                    .font(.caption).monospacedDigit()
                Text(String(format: "Axis %.1f m · heading %.0f°", hud.stationLateral, hud.stationHeadingDegrees))
                    .font(.caption2).monospacedDigit()
                HStack {
                    Button("Approach") { release(); hud.onCommand?(.stationApproach) }
                    Button("Undock") { hud.onCommand?(.stationUndock) }.disabled(!hud.stationDocked)
                }
                HStack {
                    Button("Roll ↶") { hud.onCommand?(.stationRoll(-5 * .pi / 180)) }
                    Button("Roll ↷") { hud.onCommand?(.stationRoll(5 * .pi / 180)) }
                }
                Button(hud.stationMatchRoll ? "Release Roll Match" : "Match Station Roll") { hud.onCommand?(.stationMatchRoll) }
                Button(hud.stationSpinning ? "Stop Station Spin" : "Start Station Spin") { hud.onCommand?(.stationToggleSpin) }
            }.font(.caption)
            Button("Center View") { release(); hud.onCommand?(.setLook(DStarLook())) }
            HStack {
                Button(hud.freezeFrame ? "Resume" : "Pause") { release(); hud.commandToggleFreeze() }
                Button("Stop") { release(); hud.commandStop() }
                Button("½ Speed") { hud.commandHalfSpeed() }
            }.font(.caption)
        }
        .frame(width: 220)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onChange(of: dragging) { _, active in if !active { release() } }
        .onChange(of: steering) { _, _ in release() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { release() } }
        .onDisappear { release() }
    }

    private var globe: some View {
        ZStack {
            Circle().fill(.black.opacity(0.45))
            DStarHSIView(orientation: hud.orientation)
            // Project the local viewing direction onto the ship's instrument.
            let direction = hud.look.orientation(relativeTo: .identity).forward
            Circle().fill(.cyan).frame(width: 10, height: 10)
                .offset(x: CGFloat(direction.x) * 65, y: -CGFloat(direction.y) * 65)
            Text("SHIP").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .offset(y: 12)
            Circle().stroke(.white, lineWidth: 1).frame(width: 6, height: 6)
        }
        .contentShape(Circle())
    }

    @ViewBuilder
    private var interactiveGlobe: some View {
#if os(visionOS)
        GeometryReader3D { geometry in
            globe.gesture(DragGesture(minimumDistance: 2, coordinateSpace3D: geometry.coordinateSpace3D())
                .updating($dragging) { _, active, _ in active = true }
                .onChanged { value in
                    // Apple's unified conversion expresses the spatial gesture in this
                    // view's local axes/points, even when attached to a RealityKit entity.
                    handleDrag(x: Float(value.translation3D.x), y: Float(value.translation3D.y))
                }
                .onEnded { _ in release() })
        }
#else
        globe.gesture(DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .updating($dragging) { _, active, _ in active = true }
            .onChanged { value in
                handleDrag(x: Float(value.translation.width), y: Float(value.translation.height))
            }
            .onEnded { _ in release() })
#endif
    }

    private func handleDrag(x: Float, y: Float) {
        if steering {
            hud.onCommand?(.setGlobeSteering(SIMD2(x / 65, -y / 65)))
        } else {
            if startLook == nil { startLook = hud.look }
            let initial = startLook ?? DStarLook()
            hud.onCommand?(.setLook(DStarLook(yaw: initial.yaw + x * 0.012,
                                            pitch: initial.pitch + y * 0.012)))
        }
    }

    private func release() {
        startLook = nil
        hud.onCommand?(.setGlobeSteering(.zero))
    }
}
