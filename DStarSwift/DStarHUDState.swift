import Foundation
import Combine
import simd

struct DStarHUDShip: Equatable, Identifiable {
    let id: Int
    let name: String
    let objectClass: DStarObjectClass
    let position: SIMD3<Float>
    let forward: SIMD3<Float>
    let up: SIMD3<Float>
    let right: SIMD3<Float>
}

struct DStarHUDOrientation: Equatable {
    let forward: SIMD3<Float>
    let up: SIMD3<Float>
    let right: SIMD3<Float>

    static let identity = DStarHUDOrientation(
        forward: SIMD3<Float>(0, 0, 1),
        up: SIMD3<Float>(0, 1, 0),
        right: SIMD3<Float>(1, 0, 0)
    )
}

/// SwiftUI-observable mirror of a few `DStarGameState` flags so the help
/// overlay / status indicators can react to in-game key presses without
/// the renderer having to know about SwiftUI.
///
/// `DStarRenderer` calls `update(from:)` once per frame to push the
/// current game state out to SwiftUI. SwiftUI views and menu commands call
/// the `command…()` methods to send input actions back into the game.
@MainActor
final class DStarHUDState: ObservableObject {
    @Published private(set) var showHelp: Bool = false
    @Published private(set) var freezeFrame: Bool = false
    @Published private(set) var autoPilot: Bool = false
    @Published private(set) var radarOn: Bool = false
    @Published private(set) var mouseControl: Bool = false
    @Published private(set) var speedLabel: String = "full speed"
    @Published private(set) var missilesRemaining: Int = 0
    @Published private(set) var armedMissiles: Int = 0
    @Published private(set) var score: Int = 0
    @Published private(set) var radarTargetName: String?
    @Published private(set) var radarTargetRange: Float?
    @Published private(set) var lockedBy: [String] = []
    @Published private(set) var look = DStarLook()
    @Published private(set) var position: SIMD3<Float> = .zero
    @Published private(set) var orientation: DStarHUDOrientation = .identity
    @Published private(set) var visibleShips: [DStarHUDShip] = []
    @Published private(set) var simulationTime: Float = 0
    /// Effective brightness of lit geometry in the immersive scene. Stars
    /// stay unlit, so zero produces a black world with stars still visible.
    @Published var ambientLight: Double = 0.25

    /// Set by the renderer; the HUD uses it to forward menu/UI commands
    /// back into the game state.
    var onCommand: ((DStarInputAction) -> Void)?

    /// Set by the app; the renderer calls this once the `DStarGameState` is
    /// alive so `NetSession` can hold a reference to it. The didSet replay
    /// removes ordering dependence between SwiftUI onAppear and MTK setup.
    var onGameStateReady: ((DStarGameState) -> Void)? {
        didSet {
            if let readyGameState { onGameStateReady?(readyGameState) }
        }
    }
    private weak var readyGameState: DStarGameState?

    /// Set by the app; HUD UI calls this to spawn a robot.
    var onSpawnRobot: (() -> Void)?

    func update(from game: DStarGameState) {
        if look != game.look { look = game.look }
        if position != game.me.position { position = game.me.position }
        if showHelp != game.showHelp { showHelp = game.showHelp }
        if freezeFrame != game.freezeFrame { freezeFrame = game.freezeFrame }
        if autoPilot != game.autoPilot { autoPilot = game.autoPilot }
        let radar = (game.me.flags & DStarObjectFlags.radar) != 0
        if radarOn != radar { radarOn = radar }
        if mouseControl != game.mouseControl { mouseControl = game.mouseControl }
        if missilesRemaining != game.missilesRemaining {
            missilesRemaining = game.missilesRemaining
        }
        if armedMissiles != game.armedMissiles {
            armedMissiles = game.armedMissiles
        }
        if score != game.me.score { score = game.me.score }
        if simulationTime != game.elapsedTime { simulationTime = game.elapsedTime }

        let newOrientation = DStarHUDOrientation(
            forward: game.me.forward,
            up: game.me.up,
            right: game.me.right
        )
        if orientation != newOrientation { orientation = newOrientation }

        let target = game.me.targetID.flatMap { game.others[$0] }
        let targetName = target?.name
        if radarTargetName != targetName { radarTargetName = targetName }
        let targetRange = target.map { simd_distance(game.me.position, $0.position) }
        if radarTargetRange != targetRange { radarTargetRange = targetRange }

        let newLockedBy = game.others.values
            .filter { $0.status == .active && $0.targetID == game.me.id }
            .sorted { $0.id < $1.id }
            .map { $0.name }
        if lockedBy != newLockedBy { lockedBy = newLockedBy }

        let label = Self.speedLabel(for: game.me.speed)
        if speedLabel != label { speedLabel = label }
        let ships = game.others.values
            .sorted { $0.id < $1.id }
            .map {
                DStarHUDShip(
                    id: $0.id,
                    name: $0.name,
                    objectClass: $0.objectClass,
                    position: $0.position,
                    forward: $0.forward,
                    up: $0.up,
                    right: $0.right
                )
            }
        if visibleShips != ships { visibleShips = ships }
    }

    func register(gameState: DStarGameState) {
        readyGameState = gameState
        onGameStateReady?(gameState)
    }

    // MARK: - Commands the UI can issue

    func commandSpawnRobot() { onSpawnRobot?() }
    func commandToggleHelp() { onCommand?(.keyCharacter("h")) }
    func commandToggleFreeze() { onCommand?(.keyCharacter("f")) }
    func commandToggleAutopilot() { onCommand?(.keyCharacter("a")) }
    func commandToggleRadar() { onCommand?(.keyCharacter("r")) }
    func commandStop() { onCommand?(.keyCharacter("0")) }
    func commandHalfSpeed() { onCommand?(.keyCharacter("1")) }
    func commandFullSpeed() { onCommand?(.keyCharacter("2")) }
    func commandArmMissile() { onCommand?(.keyCharacter("q")) }
    func commandLaunchMissile() { onCommand?(.keyCharacter("w")) }

    private static func speedLabel(for speed: Float) -> String {
        let full = DStarGameParameters.defaultSpeed
        if speed <= 0.01 { return "stopped" }
        if abs(speed - full) < 0.01 { return "full speed" }
        if abs(speed - full * 0.5) < 0.01 { return "half speed" }
        return String(format: "speed %.1f", speed)
    }
}
