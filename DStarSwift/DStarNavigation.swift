import simd

/// View angles are local to the ship. Looking never modifies its flight basis.
struct DStarLook: Equatable {
    var yaw: Float = 0
    var pitch: Float = 0

    init(yaw: Float = 0, pitch: Float = 0) {
        self.yaw = yaw.isFinite ? yaw.truncatingRemainder(dividingBy: 2 * .pi) : 0
        self.pitch = pitch.isFinite ? min(max(pitch, -.pi * 0.45), .pi * 0.45) : 0
    }

    func orientation(relativeTo ship: DStarHUDOrientation) -> DStarHUDOrientation {
        let yawRotation = simd_quatf(angle: yaw, axis: ship.up)
        let right = yawRotation.act(ship.right)
        let pitchRotation = simd_quatf(angle: pitch, axis: right)
        let rotation = pitchRotation * yawRotation
        return DStarHUDOrientation(forward: rotation.act(ship.forward),
                                   up: rotation.act(ship.up), right: rotation.act(ship.right))
    }

    static func steering(_ displacement: SIMD2<Float>) -> SIMD2<Float> {
        func axis(_ value: Float) -> Float {
            guard value.isFinite else { return 0 }
            let magnitude = min(abs(value), 1)
            guard magnitude > 0.08 else { return 0 }
            return (value < 0 ? -1 : 1) * (magnitude - 0.08) / 0.92
        }
        return SIMD2(axis(displacement.x), axis(displacement.y))
    }
}
