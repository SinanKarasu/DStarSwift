import Foundation
import Combine

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

    /// Set by the renderer; the HUD uses it to forward menu/UI commands
    /// back into the game state.
    var onCommand: ((DStarInputAction) -> Void)?

    /// Set by the app; the renderer calls this once the `DStarGameState` is
    /// alive so `NetSession` can hold a reference to it.
    var onGameStateReady: ((DStarGameState) -> Void)?

    /// Set by the app; HUD UI calls this to spawn a robot.
    var onSpawnRobot: (() -> Void)?

    func update(from game: DStarGameState) {
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
        let label = Self.speedLabel(for: game.me.speed)
        if speedLabel != label { speedLabel = label }
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
