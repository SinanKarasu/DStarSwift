import Foundation
import simd

enum DStarObjectClass: Int {
    case empty
    case `static`
    case player
    case missile
}

enum DStarObjectState: Int {
    case active
    case sleeping
    case dead
    case killed
}

enum DStarGameType: Int {
    case freeForAll
    case teams
}

enum DStarBlastState: Int {
    case none
    case flash
    case wait
}

enum DStarNetStatus: Int {
    case unknown
    case slave
    case submaster
    case master
}

enum DStarObjectFlags {
    static let laser: UInt32 = 1
    static let radar: UInt32 = 2
    static let robot: UInt32 = 4
}

enum DStarGameParameters {
    static let maxPlayers = 40
    static let maxObjects = 100
    static let maxDescriptions = 20
    static let maxMissiles = 20
    static let missilesPerLife = 20

    static let viewScale: Float = 2.0
    static let rollRate: Float = 0.3

    static let displayIntervalUsec = 50_000
    static let flashIntervalUsec = 500_000
    static let deathIntervalSec = 5
    static let pollIntervalSec = 10
    static let sleepIntervalSec = 10

    static let defaultSpeed: Float = 25.0
    static let missileSpeed: Float = defaultSpeed * 3.0
    static let missileLife: Float = 5.0
    static let missileRegen: Float = 0.6
    static let missileRange: Float = 3000.0
}

struct DStarObject {
    var id: Int = -1
    var name: String = ""
    var team: Int = 0
    var score: Int = 0
    var objectClass: DStarObjectClass = .player
    var status: DStarObjectState = .active
    var flags: UInt32 = 0

    var position = SIMD3<Float>(0, 0, 0)
    var forward = SIMD3<Float>(0, 0, 1)
    var up = SIMD3<Float>(0, 1, 0)
    var right = SIMD3<Float>(1, 0, 0)
    var delta = SIMD3<Float>(0, 0, 0)
    var pointing = SIMD3<Float>(0, 0, 1)

    var speed: Float = DStarGameParameters.defaultSpeed
    var targetID: Int?
    var time: Float = 0
    var descriptionIndex: Int = 1
    var sequence: Int = 0
    var netStatus: DStarNetStatus = .unknown
}

struct DStarInputState {
    var mouseX: Float = 0.5
    var mouseY: Float = 0.5
    var leftButton = false
    var middleButton = false
    var rightButton = false

    var arrowUp = false
    var arrowDown = false
    var arrowLeft = false
    var arrowRight = false
    var functionKeys: Set<Int> = []
}

enum DStarInputAction {
    case setMouse(Float, Float)
    case setLeftButton(Bool)
    case setMiddleButton(Bool)
    case setRightButton(Bool)
    case setArrowUp(Bool)
    case setArrowDown(Bool)
    case setArrowLeft(Bool)
    case setArrowRight(Bool)
    case setFunctionKey(Int, Bool)
    case keyCharacter(String)
    case tab
    case escape
}

final class DStarGameState {
    var gameType: DStarGameType = .freeForAll
    var blastState: DStarBlastState = .none
    var me = DStarObject()
    var autoPilot = false
    var autoFire = false
    var showHelp = false
    var freezeFrame = false
    var mouseControl = false
    var missilesRemaining = DStarGameParameters.missilesPerLife
    var armedMissiles = 0
    var dtime: Float = 1 / 60
    var input = DStarInputState()

    init() {
        me.position = SIMD3<Float>(
            Float.random(in: -1000...1000),
            Float.random(in: -1000...1000),
            Float.random(in: -1000...1000)
        )
        me.objectClass = .player
        me.status = .active
        me.speed = DStarGameParameters.defaultSpeed
    }

    func apply(_ action: DStarInputAction) {
        switch action {
        case let .setMouse(x, y):
            input.mouseX = x
            input.mouseY = y
        case let .setLeftButton(isDown):
            input.leftButton = isDown
            if isDown {
                mouseControl.toggle()
            }
        case let .setMiddleButton(isDown):
            input.middleButton = isDown
        case let .setRightButton(isDown):
            input.rightButton = isDown
        case let .setArrowUp(isDown):
            input.arrowUp = isDown
        case let .setArrowDown(isDown):
            input.arrowDown = isDown
        case let .setArrowLeft(isDown):
            input.arrowLeft = isDown
        case let .setArrowRight(isDown):
            input.arrowRight = isDown
        case let .setFunctionKey(key, isDown):
            if isDown {
                input.functionKeys.insert(key)
            } else {
                input.functionKeys.remove(key)
            }
            if isDown {
                handleFunctionKey(key)
            }
        case let .keyCharacter(raw):
            handleCharacterKey(raw)
        case .tab:
            break
        case .escape:
            freezeFrame.toggle()
        }
    }

    func step(deltaTime: Float) {
        dtime = max(deltaTime, 0)
        if freezeFrame {
            return
        }
        controlShip()
    }

    private func handleFunctionKey(_ key: Int) {
        switch key {
        case 2:
            armedMissiles += 1
        case 3:
            if armedMissiles > 0 && missilesRemaining > 0 {
                armedMissiles -= 1
                missilesRemaining -= 1
            }
        default:
            break
        }
    }

    private func handleCharacterKey(_ raw: String) {
        switch raw {
        case "0":
            me.speed = 0
        case "1":
            me.speed = DStarGameParameters.defaultSpeed * 0.5
        case "2":
            me.speed = DStarGameParameters.defaultSpeed
        case "h":
            showHelp.toggle()
        case "A":
            autoFire = !autoPilot
            fallthrough
        case "a":
            if autoPilot {
                autoPilot = false
                autoFire = false
            } else {
                autoPilot = true
            }
        case "r":
            me.flags ^= DStarObjectFlags.radar
            if (me.flags & DStarObjectFlags.radar) == 0 {
                me.targetID = nil
            }
        case "q", "Q":
            armedMissiles += 1
        case "w", "W":
            if armedMissiles > 0 && missilesRemaining > 0 {
                armedMissiles -= 1
                missilesRemaining -= 1
            }
        case "f":
            freezeFrame.toggle()
        default:
            break
        }
    }

    private func controlShip() {
        var newDelta = SIMD3<Float>(
            DStarGameParameters.viewScale * (input.mouseX - 0.5),
            DStarGameParameters.viewScale * (input.mouseY - 0.5),
            0
        )

        if input.arrowLeft { newDelta.x = min(newDelta.x, -0.6) }
        if input.arrowRight { newDelta.x = max(newDelta.x, 0.6) }
        if input.arrowUp { newDelta.y = max(newDelta.y, 0.6) }
        if input.arrowDown { newDelta.y = min(newDelta.y, -0.6) }

        if !autoPilot {
            adjustVector(delta: newDelta)
            if mouseControl {
                me.delta.x = newDelta.x
                me.delta.y = newDelta.y
            } else {
                me.delta.x = 0
                me.delta.y = 0
            }
            if input.rightButton {
                me.flags |= DStarObjectFlags.laser
            } else {
                me.flags &= ~DStarObjectFlags.laser
            }
            me.delta.z = 0
        } else {
            me.delta.x *= 0.9
            me.delta.y *= 0.9
            if input.middleButton {
                me.flags |= DStarObjectFlags.laser
            }
            me.delta.z = 0
        }

        adjustVectors()
    }

    private func adjustVector(delta: SIMD3<Float>) {
        me.pointing.x = delta.x * me.right.x + delta.y * me.up.x + me.forward.x
        me.pointing.y = delta.x * me.right.y + delta.y * me.up.y + me.forward.y
        me.pointing.z = delta.x * me.right.z + delta.y * me.up.z + me.forward.z

        let mag2 = simd_length_squared(me.pointing)
        if mag2 > 0, abs(mag2 - 1) > 0.000_001 {
            me.pointing *= 1 / sqrt(mag2)
        }
    }

    private func adjustVectors() {
        let delta1 = me.delta * dtime
        var delta2 = SIMD3<Float>(
            delta1.x * me.right.x + delta1.y * me.up.x,
            delta1.x * me.right.y + delta1.y * me.up.y,
            delta1.x * me.right.z + delta1.y * me.up.z
        )

        var forward2 = me.forward + delta2
        let forwardLength = simd_length(forward2)
        if forwardLength > 0 {
            forward2 /= forwardLength
        }

        delta2 = SIMD3<Float>(
            delta1.z * me.right.x,
            delta1.z * me.right.y,
            delta1.z * me.right.z
        )
        var up2 = me.up + delta2

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

        me.position += me.speed * dtime * forward2
        me.forward = forward2
        me.up = up2
        me.right = right2
    }
}
