import Foundation
import simd

/// Anything that can drive a `DStarObject` forward one tick.
///
/// Three concrete implementations:
///   - `PlayerController` — reads the local input state.
///   - `AutopilotController` — vector-steering port of the legacy
///     `autopilot.c:auto_control()`. Used by the in-game `a` toggle and by
///     spawned robots (a robot is just a headless player whose controller
///     is the autopilot).
///   - `RemoteController` — applies state received from a network peer; no
///     local simulation happens for this ship.
protocol ShipController: AnyObject {
    /// Mutate `ship` in place for one frame. `world` exposes the rest of the
    /// game state (other ships, time delta) for steering and AI decisions.
    func step(ship: inout DStarObject, world: ShipWorld)
}

/// Read-only slice of game state exposed to controllers.
struct ShipWorld {
    let dtime: Float
    /// All other ships in the roster, keyed by id. The acting ship is not
    /// included — the controller only sees who else is out there.
    let others: [Int: DStarObject]
    /// Local input — only meaningful for the `PlayerController`.
    let input: DStarInputState
    /// True if the player has toggled mouse-fly.
    let mouseControl: Bool
}

// MARK: - Player

/// The legacy `controlShip()` body, lifted verbatim. Runs the math from
/// `control_ship.c` against the player's input state.
final class PlayerController: ShipController {
    func step(ship: inout DStarObject, world: ShipWorld) {
        var newDelta = SIMD3<Float>(
            DStarGameParameters.viewScale * (world.input.mouseX - 0.5),
            DStarGameParameters.viewScale * (world.input.mouseY - 0.5),
            0
        )

        if world.input.arrowLeft  { newDelta.x = min(newDelta.x, -0.6) }
        if world.input.arrowRight { newDelta.x = max(newDelta.x,  0.6) }
        if world.input.arrowUp    { newDelta.y = max(newDelta.y,  0.6) }
        if world.input.arrowDown  { newDelta.y = min(newDelta.y, -0.6) }

        adjustVector(ship: &ship, delta: newDelta)
        if world.mouseControl {
            ship.delta.x = newDelta.x
            ship.delta.y = newDelta.y
        } else {
            ship.delta.x = 0
            ship.delta.y = 0
        }
        if world.input.rightButton {
            ship.flags |= DStarObjectFlags.laser
        } else {
            ship.flags &= ~DStarObjectFlags.laser
        }
        ship.delta.z = 0

        ShipKinematics.advance(ship: &ship, dtime: world.dtime)
    }

    private func adjustVector(ship: inout DStarObject, delta: SIMD3<Float>) {
        ship.pointing.x = delta.x * ship.right.x + delta.y * ship.up.x + ship.forward.x
        ship.pointing.y = delta.x * ship.right.y + delta.y * ship.up.y + ship.forward.y
        ship.pointing.z = delta.x * ship.right.z + delta.y * ship.up.z + ship.forward.z

        let mag2 = simd_length_squared(ship.pointing)
        if mag2 > 0, abs(mag2 - 1) > 0.000_001 {
            ship.pointing *= 1 / sqrt(mag2)
        }
    }
}

// MARK: - Autopilot

/// Port of `autopilot.c:auto_control()`.
///
/// Steers `ship` toward `ship.targetID` (resolved via `world.others`). When
/// no target is set, hold course. When inside `laserRange`, set the laser
/// flag — robots will then "fire" by virtue of being a normal ship with the
/// laser bit on. Logic is otherwise the legacy vector-feedback:
///
///   transform target into ship-local coords → divide by distance →
///   apply FEEDBACK_GAIN → clamp to max slew → set delta.
final class AutopilotController: ShipController {
    var feedbackGain: Float = 2.0
    var maxSlew: Float = 0.75
    var laserRange: Float = 200.0
    /// If true, this controller will pick a fresh target by nearest distance
    /// when no target id is set. This is what makes a robot "hunt".
    var huntsForTargets: Bool = false

    func step(ship: inout DStarObject, world: ShipWorld) {
        let target = resolveTarget(ship: ship, world: world)
        guard let target else {
            // No one to chase: damp delta and drift.
            ship.delta.x *= 0.9
            ship.delta.y *= 0.9
            ship.delta.z = 0
            ship.flags &= ~DStarObjectFlags.laser
            ShipKinematics.advance(ship: &ship, dtime: world.dtime)
            return
        }

        let toTarget = target.position - ship.position
        let dist = max(simd_length(toTarget), 0.0001)
        let local = SIMD3<Float>(
            simd_dot(toTarget, ship.right),
            simd_dot(toTarget, ship.up),
            simd_dot(toTarget, ship.forward)
        )

        var dx = (local.x / dist) * feedbackGain
        var dy = (local.y / dist) * feedbackGain
        dx = max(-maxSlew, min(maxSlew, dx))
        dy = max(-maxSlew, min(maxSlew, dy))

        ship.delta.x = dx
        ship.delta.y = dy
        ship.delta.z = 0

        let forwardDot = simd_dot(simd_normalize(toTarget), ship.forward)
        if dist < laserRange && forwardDot > 0.95 {
            ship.flags |= DStarObjectFlags.laser
        } else {
            ship.flags &= ~DStarObjectFlags.laser
        }

        ShipKinematics.advance(ship: &ship, dtime: world.dtime)
    }

    private func resolveTarget(ship: DStarObject, world: ShipWorld) -> DStarObject? {
        if let tid = ship.targetID, let t = world.others[tid] {
            return t
        }
        if huntsForTargets {
            return world.others.values.min { lhs, rhs in
                simd_distance_squared(lhs.position, ship.position)
                    < simd_distance_squared(rhs.position, ship.position)
            }
        }
        return nil
    }
}

// MARK: - Missile

/// Homing behavior from the legacy `fly_missiles()` loop. An untargeted or
/// out-of-cone missile continues straight until its five-second life expires.
final class MissileController: ShipController {
    func step(ship: inout DStarObject, world: ShipWorld) {
        ship.time -= world.dtime
        guard ship.time > 0 else {
            ship.status = .dead
            return
        }

        if let targetID = ship.targetID,
           let target = world.others[targetID],
           target.status == .active {
            let toTarget = target.position - ship.position
            let distanceSquared = simd_length_squared(toTarget)

            if distanceSquared <= DStarGameParameters.missileThreshold
                * DStarGameParameters.missileThreshold {
                ship.status = .killed
                return
            }

            if distanceSquared <= DStarGameParameters.missileRange
                * DStarGameParameters.missileRange {
                let distance = max(sqrt(distanceSquared), 0.0001)
                let direction = toTarget / distance
                let forwardDot = simd_dot(direction, ship.forward)

                if forwardDot >= 0.7071 {
                    var dx = simd_dot(toTarget, ship.right)
                        * DStarGameParameters.missileGain / distance
                    var dy = simd_dot(toTarget, ship.up)
                        * DStarGameParameters.missileGain / distance
                    dx = max(-DStarGameParameters.missileTurn,
                             min(DStarGameParameters.missileTurn, dx))
                    dy = max(-DStarGameParameters.missileTurn,
                             min(DStarGameParameters.missileTurn, dy))

                    let maxChange = DStarGameParameters.missileSlew * world.dtime
                    ship.delta.x += max(-maxChange, min(maxChange, dx - ship.delta.x))
                    ship.delta.y += max(-maxChange, min(maxChange, dy - ship.delta.y))
                    // A tracked target renews life slightly, matching the
                    // original game's MISSILE_REGEN behavior.
                    ship.time += DStarGameParameters.missileRegen * world.dtime
                } else {
                    ship.targetID = nil
                }
            } else {
                ship.targetID = nil
            }
        } else {
            ship.targetID = nil
        }

        ship.delta.z = 0
        ShipKinematics.advance(ship: &ship, dtime: world.dtime)
        ship.pointing = ship.forward
    }
}

// MARK: - Remote

/// State received from a network peer is applied wholesale; we do no local
/// simulation. The renderer just draws wherever the peer says it is.
/// `NetSession` calls `apply(_:)` whenever a NET_CURRENT_STATUS arrives.
final class RemoteController: ShipController {
    private(set) var snapshot: DStarObject?

    func apply(_ snapshot: DStarObject) {
        self.snapshot = snapshot
    }

    func step(ship: inout DStarObject, world: ShipWorld) {
        if let snap = snapshot {
            let keepId = ship.id
            let keepName = ship.name
            ship = snap
            ship.id = keepId
            ship.name = keepName
            snapshot = nil
        }
        if ship.objectClass == .missile {
            ship.time -= world.dtime
            guard ship.time > 0 else {
                ship.status = .dead
                return
            }
        }
        // Tiny dead-reckon between snapshots so motion looks smooth at
        // network rates lower than render rate.
        ship.position += ship.speed * world.dtime * ship.forward
    }
}

// MARK: - Shared kinematics

/// The "integrate forward/up/right and move along forward" math from the
/// legacy `adjust_vectors()` in `control_ship.c`. Lifted out so both
/// PlayerController and AutopilotController can call it.
enum ShipKinematics {
    static func advance(ship: inout DStarObject, dtime: Float) {
        let delta1 = ship.delta * dtime
        var delta2 = SIMD3<Float>(
            delta1.x * ship.right.x + delta1.y * ship.up.x,
            delta1.x * ship.right.y + delta1.y * ship.up.y,
            delta1.x * ship.right.z + delta1.y * ship.up.z
        )

        var forward2 = ship.forward + delta2
        let forwardLength = simd_length(forward2)
        if forwardLength > 0 {
            forward2 /= forwardLength
        }

        delta2 = SIMD3<Float>(
            delta1.z * ship.right.x,
            delta1.z * ship.right.y,
            delta1.z * ship.right.z
        )
        var up2 = ship.up + delta2

        var right2 = SIMD3<Float>(
            forward2.z * up2.y - forward2.y * up2.z,
            forward2.x * up2.z - forward2.z * up2.x,
            forward2.y * up2.x - forward2.x * up2.y
        )
        let rightLength = simd_length(right2)
        if rightLength > 0 {
            right2 /= rightLength
        }

        up2 = SIMD3<Float>(
            right2.z * forward2.y - right2.y * forward2.z,
            right2.x * forward2.z - right2.z * forward2.x,
            right2.y * forward2.x - right2.x * forward2.y
        )

        ship.position += ship.speed * dtime * forward2
        ship.forward = forward2
        ship.up = up2
        ship.right = right2
    }
}
