import Foundation
import simd

enum DStarObjectClass: Int, Codable {
    case empty
    case `static`
    case player
    case missile
    /// Ship driven by an AutopilotController in this process.
    case robot
    /// Ship whose state is replicated from a network peer.
    case remote
}

enum DStarObjectState: Int, Codable {
    case active
    case sleeping
    case dead
    case killed
}

enum DStarGameType: Int, Codable {
    case freeForAll
    case teams
}

enum DStarBlastState: Int {
    case none
    case flash
    case wait
}

enum DStarNetStatus: Int, Codable {
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
    static let missileTurn: Float = 1.0
    static let missileSlew: Float = 1.0
    static let missileThreshold: Float = 5.0
    static let missileGain: Float = 6.0

    /// Local id of the player ship. Network peers get ids 1+.
    static let localShipId: Int = 0

    /// How often (Hz) to broadcast our own status to peers.
    static let statusBroadcastHz: Double = 20.0
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
    case visitHabitat
}

/// Owns the local player ship (`me`) plus a roster of other ships.
///
/// Each ship in the roster has an attached `ShipController` that drives it
/// every frame:
///   - the local player uses `PlayerController` (or `AutopilotController`
///     when the `a` key is toggled),
///   - spawned robots use `AutopilotController` with `huntsForTargets = true`,
///   - network peers use `RemoteController`.
///
/// `NetSession` calls `applyRemoteSnapshot(_:)` for each incoming
/// `NET_CURRENT_STATUS`-style message; the controller for that ship records
/// the snapshot and the next `step()` interpolates it.
final class DStarGameState {
    var gameType: DStarGameType = .freeForAll
    var blastState: DStarBlastState = .none
    var me = DStarObject()
    var autoPilot = false {
        didSet { rebuildMeController() }
    }
    var autoFire = false
    // The 1986 game opened with its command card visible. Keep that useful
    // first-run behavior; H/F1/? dismisses it once the pilot is oriented.
    var showHelp = true
    var freezeFrame = false
    var mouseControl = false
    var missilesRemaining = DStarGameParameters.missilesPerLife
    var armedMissiles = 0
    var dtime: Float = 1 / 60
    private(set) var elapsedTime: Float = 0
    var input = DStarInputState()

    /// Every ship other than `me`, keyed by id.
    private(set) var others: [Int: DStarObject] = [:]
    /// Controller per ship id (including `me`).
    private(set) var controllers: [Int: any ShipController] = [:]

    /// Optional callback fired after each step so that `NetSession` can
    /// broadcast our state without the game state knowing about networking.
    var onLocalStateAdvanced: ((DStarObject) -> Void)?

    init() {
        me.id = DStarGameParameters.localShipId
        me.position = SIMD3<Float>(
            Float.random(in: -1000...1000),
            Float.random(in: -1000...1000),
            Float.random(in: -1000...1000)
        )
        me.objectClass = .player
        me.status = .active
        me.speed = DStarGameParameters.defaultSpeed
        rebuildMeController()
    }

    // MARK: - Roster management

    /// Add or replace a ship in the roster. Used by NetSession when a new
    /// peer joins and by the spawn-robot UI action.
    func addShip(_ ship: DStarObject, controller: any ShipController) {
        guard ship.id != me.id else { return }
        others[ship.id] = ship
        controllers[ship.id] = controller
    }

    func removeShip(id: Int) {
        others.removeValue(forKey: id)
        controllers.removeValue(forKey: id)
    }

    /// Apply a fresh snapshot from a network peer. Idempotent — if the peer
    /// hasn't been seen yet, a `RemoteController` is created for them.
    func applyRemoteSnapshot(_ snapshot: DStarObject) {
        guard snapshot.id != me.id else { return }
        if let existing = controllers[snapshot.id] as? RemoteController {
            existing.apply(snapshot)
            // Keep id/name fields stable; everything else comes from peer.
            var s = snapshot
            s.objectClass = snapshot.objectClass == .missile ? .missile : .remote
            others[snapshot.id] = s
        } else {
            let controller = RemoteController()
            controller.apply(snapshot)
            var s = snapshot
            s.objectClass = snapshot.objectClass == .missile ? .missile : .remote
            addShip(s, controller: controller)
        }
    }

    /// Convenience: spawn a local AI opponent. Returns the id.
    @discardableResult
    func spawnRobot(near origin: SIMD3<Float>? = nil) -> Int {
        let id = nextAvailableLocalRobotId()
        var ship = DStarObject()
        ship.id = id
        ship.name = "Robot \(id)"
        ship.objectClass = .robot
        ship.status = .active
        ship.flags = DStarObjectFlags.robot
        let center = origin ?? me.position
        ship.position = center + SIMD3<Float>(
            Float.random(in: -300...300),
            Float.random(in: -300...300),
            Float.random(in: -300...300)
        )
        ship.speed = DStarGameParameters.defaultSpeed
        ship.targetID = me.id

        let ai = AutopilotController()
        ai.huntsForTargets = true
        addShip(ship, controller: ai)
        return id
    }

    /// Launch one armed missile from the nose of the local ship. Missiles are
    /// ordinary roster objects, which lets rendering and Bonjour replication
    /// use the same paths as ships and robots.
    @discardableResult
    func launchMissile() -> Int? {
        guard armedMissiles > 0, missilesRemaining > 0 else { return nil }
        let flyingMissiles = others.values.filter { $0.objectClass == .missile }.count
        guard flyingMissiles < DStarGameParameters.maxMissiles else { return nil }

        let id = nextAvailableLocalMissileID()
        var missile = DStarObject()
        missile.id = id
        missile.name = "missile \(id)"
        missile.team = me.id
        missile.objectClass = .missile
        missile.status = .active
        // Begin just beyond the camera's near plane so the launch flash and
        // tracer are visible immediately instead of spending a frame clipped.
        missile.position = me.position + me.forward * 24
        missile.forward = me.forward
        missile.up = me.up
        missile.right = me.right
        missile.pointing = me.pointing
        missile.speed = DStarGameParameters.missileSpeed
        missile.targetID = me.targetID
        missile.time = DStarGameParameters.missileLife

        addShip(missile, controller: MissileController())
        armedMissiles -= 1
        missilesRemaining -= 1
        return id
    }

    private func nextAvailableLocalRobotId() -> Int {
        // Robots get ids 1000+ to stay clear of network-assigned peer ids
        // (which the master allocates in 1...maxPlayers).
        var id = 1000
        while others[id] != nil { id += 1 }
        return id
    }

    private func nextAvailableLocalMissileID() -> Int {
        var id = 2000
        while others[id] != nil { id += 1 }
        return id
    }

    // MARK: - Input

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
            cycleRadarTarget()
        case .escape:
            freezeFrame.toggle()
        case .visitHabitat:
            me.position = SIMD3<Float>(350, 600, 550)
            me.forward = simd_normalize(SIMD3<Float>(0, -600, 750))
            me.right = SIMD3<Float>(1, 0, 0)
            me.up = simd_cross(me.forward, me.right)
            me.delta = .zero
            me.speed = 0
            me.flags &= ~DStarObjectFlags.laser
            input = DStarInputState()
            mouseControl = false
            autoPilot = false
            autoFire = false
            rebuildMeController()
        }
    }

    /// Cycle radar target through the roster of other ships in id order.
    private func cycleRadarTarget() {
        guard (me.flags & DStarObjectFlags.radar) != 0 else { return }
        let ids = others.keys.sorted()
        guard !ids.isEmpty else {
            me.targetID = nil
            return
        }
        if let current = me.targetID,
           let idx = ids.firstIndex(of: current),
           idx + 1 < ids.count {
            me.targetID = ids[idx + 1]
        } else {
            me.targetID = ids.first
        }
    }

    // MARK: - Per-frame step

    func step(deltaTime: Float) {
        dtime = max(deltaTime, 0)
        if freezeFrame { return }
        elapsedTime += dtime

        // Drive the local player.
        let meWorld = ShipWorld(
            dtime: dtime,
            others: others,
            input: input,
            mouseControl: mouseControl
        )
        controllers[me.id]?.step(ship: &me, world: meWorld)

        // Drive every other ship. Each controller sees the rest of the world
        // (including the freshly-updated `me`) but not its own ship.
        let snapshotOfMe = me
        var updated: [Int: DStarObject] = [:]
        updated.reserveCapacity(others.count)
        for (id, _) in others {
            var ship = others[id]!
            var visibleOthers = others
            visibleOthers.removeValue(forKey: id)
            visibleOthers[me.id] = snapshotOfMe
            let world = ShipWorld(
                dtime: dtime,
                others: visibleOthers,
                input: input,
                mouseControl: mouseControl
            )
            controllers[id]?.step(ship: &ship, world: world)
            if ship.objectClass == .missile && ship.status != .active {
                controllers.removeValue(forKey: id)
            } else {
                updated[id] = ship
            }
        }
        others = updated

        onLocalStateAdvanced?(me)
    }

    // MARK: - Player keys

    private func handleFunctionKey(_ key: Int) {
        switch key {
        case 1:
            showHelp.toggle()
        case 2:
            if armedMissiles == 0 && missilesRemaining > 0 {
                armedMissiles = 1
            }
        case 3:
            launchMissile()
        case 4:
            autoPilot.toggle()
            if !autoPilot { autoFire = false }
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
        case "+", "=":
            me.speed = min(me.speed + DStarGameParameters.defaultSpeed * 0.25,
                           DStarGameParameters.defaultSpeed * 4)
        case "-", "_":
            me.speed = max(me.speed - DStarGameParameters.defaultSpeed * 0.25, 0)
        case "h", "?", "/":
            showHelp.toggle()
        case "A":
            autoFire = !autoPilot
            fallthrough
        case "a":
            autoPilot.toggle()
            if !autoPilot { autoFire = false }
        case "r":
            me.flags ^= DStarObjectFlags.radar
            if (me.flags & DStarObjectFlags.radar) == 0 {
                me.targetID = nil
            }
        case "q", "Q":
            if armedMissiles == 0 && missilesRemaining > 0 {
                armedMissiles = 1
            }
        case "w", "W":
            launchMissile()
        case "f":
            freezeFrame.toggle()
        case "p":
            print(String(format: "pos = (%8.1f, %8.1f, %8.1f)",
                         me.position.x, me.position.y, me.position.z))
        case "b":
            // 'b' = spawn a robot, handy for quick local testing.
            spawnRobot()
        default:
            break
        }
    }

    // MARK: - Local controller swap

    private let playerController = PlayerController()
    private let autopilotController: AutopilotController = {
        let a = AutopilotController()
        a.huntsForTargets = false
        return a
    }()

    private func rebuildMeController() {
        controllers[me.id] = autoPilot ? autopilotController : playerController
    }
}
