import SwiftUI
import simd

/// The screen-space instruments from the original DStar renderer, expressed
/// as SwiftUI so they work over both Metal and the visionOS window.
struct DStarLegacyHUD: View {
    @ObservedObject var hud: DStarHUDState

    private let red = Color(red: 1, green: 0.08, blue: 0.08)
    private let blue = Color(red: 0.08, green: 0.22, blue: 1)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if hud.showHelp {
                    Text(Self.helpText)
                        .font(.system(size: helpFontSize(for: geometry.size), design: .monospaced))
                        .foregroundStyle(red)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 50)
                        .padding(.top, 46)
                }

                DStarReticle(color: blue)
                    .frame(
                        width: min(190, geometry.size.width * 0.16),
                        height: min(140, geometry.size.height * 0.14)
                    )

                statusReadout
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 32)
                    .padding(.bottom, 62)

                DStarHSIView(orientation: hud.orientation)
                    .frame(width: 170, height: 145)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 48)
                    .padding(.bottom, 35)
            }
        }
        .accessibilityHidden(true)
    }

    private var statusReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hud.radarOn {
                if let name = hud.radarTargetName, let range = hud.radarTargetRange {
                    Text(String(format: "radar locked, range = %7.1f %@", range, name))
                        .foregroundStyle(red)
                } else {
                    Text("radar on")
                        .foregroundStyle(.yellow)
                }
            }

            Text("Score:    \(hud.score)")

            ForEach(hud.lockedBy, id: \.self) { name in
                Text("Locked by \(name)")
                    .foregroundStyle(.yellow)
            }

            if hud.armedMissiles > 0 {
                Text("missile armed: \(hud.armedMissiles)")
            }

            Text("missiles remaining: \(hud.missilesRemaining)")

            if hud.freezeFrame {
                Text("PAUSED")
                    .foregroundStyle(.yellow)
            } else if hud.autoPilot {
                Text("autopilot  •  \(hud.speedLabel)")
                    .foregroundStyle(.cyan)
            }
        }
        .font(.system(size: 15, design: .monospaced))
        .foregroundStyle(Color(white: 0.92))
        .shadow(color: .black, radius: 1)
    }

    private func helpFontSize(for size: CGSize) -> CGFloat {
        size.width < 900 || size.height < 650 ? 11 : 14
    }

    private static let helpText = """
    Mouse:
       Left = toggle mouse control
      Right = fire lasers

    Keys:
          h = this text
          0 = stop
          1 = 1/2 speed
          2 = full speed
      + / - = change speed
          r = toggle radar (blue=off, yellow=on, red=locked)
        Tab = next radar target
          q = arm missile
         F2 = arm missile
          w = fire missile
         F3 = fire missile
          a = toggle autopilot
          b = spawn AI robot
          f = pause / resume
        ESC = pause / resume
    """
}

private struct DStarReticle: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.stroke(Path(rect), with: .color(color), lineWidth: 1.5)

            let tick: CGFloat = min(size.width, size.height) * 0.12
            let midX = size.width / 2
            let midY = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: midX, y: 0))
            path.addLine(to: CGPoint(x: midX, y: tick))
            path.move(to: CGPoint(x: midX, y: size.height - tick))
            path.addLine(to: CGPoint(x: midX, y: size.height))
            path.move(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: tick, y: midY))
            path.move(to: CGPoint(x: size.width - tick, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}

private struct DStarHSIView: View {
    let orientation: DStarHUDOrientation

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radiusX = size.width * 0.47
            let radiusY = size.height * 0.46

            func point(_ world: SIMD3<Float>) -> CGPoint {
                let x = simd_dot(world, orientation.right)
                let y = simd_dot(world, orientation.up)
                return CGPoint(
                    x: center.x + CGFloat(x) * radiusX,
                    y: center.y - CGFloat(y) * radiusY
                )
            }

            func stroke(_ points: [SIMD3<Float>], color: Color) {
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: point(first))
                for p in points.dropFirst() { path.addLine(to: point(p)) }
                context.stroke(path, with: .color(color), lineWidth: 1.2)
            }

            let neutral = Color(white: 0.82)
            let samples = 48

            for longitudeIndex in 0..<8 {
                let longitude = Float(longitudeIndex) * .pi / 4
                let points = (0...samples).map { sample -> SIMD3<Float> in
                    let latitude = -.pi / 2 + Float(sample) * .pi / Float(samples)
                    let radial = cos(latitude)
                    return SIMD3<Float>(
                        radial * sin(longitude),
                        sin(latitude),
                        radial * cos(longitude)
                    )
                }
                let color: Color = longitudeIndex == 0 ? .red
                    : longitudeIndex == 4 ? .green : neutral
                stroke(points, color: color)
            }

            for latitudeIndex in -3...3 {
                let latitude = Float(latitudeIndex) * .pi / 8
                let radial = cos(latitude)
                let y = sin(latitude)
                let points = (0...samples).map { sample -> SIMD3<Float> in
                    let longitude = Float(sample) * 2 * .pi / Float(samples)
                    return SIMD3<Float>(radial * sin(longitude), y, radial * cos(longitude))
                }
                stroke(points, color: latitudeIndex < 0 ? .red : neutral)
            }
        }
        .shadow(color: .black, radius: 1)
    }
}
