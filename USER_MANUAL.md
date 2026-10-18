# DStarSwift User Manual

DStarSwift is a work-in-progress space-flight game for macOS and visionOS.
You view the world from a spaceship, steer among stars and world bodies,
track other ships, launch missiles, and add robot opponents.

This manual adapts the player-facing ideas in Ed Falk's original DStar README
to the current Swift port. Ed created the original Sun/XGL game and its
OpenGL port for Linux; Sinan Karasu is developing the Swift/Metal port.
The original document describes historical behavior that is not all implemented here.

## Getting started

1. Open `DStarSwift.xcodeproj` in Xcode with the required platform SDKs installed.
2. For macOS, choose the **DStarSwift** scheme and **My Mac**. For visionOS,
   choose **DStarSwiftVision** and an Apple Vision Pro device or simulator.
3. Build and run. The project targets macOS 26.2 and visionOS 26.2 or later.
4. On Mac, click near the center of the game view to enable mouse steering.
5. Choose **Spawn Robot** to add a nearby AI ship for practice.
6. Press **r**, then **Tab**, to select a target. Try **a** for autopilot,
   or **q** followed by **w** to arm and launch a missile.

The mouse and keyboard flight controls below are implemented in the macOS view.
The visionOS view currently provides on-screen controls and an immersive scene;
it does not yet wire the same flight-input handlers into its Metal view.

## World engine v2 destination

On the `codex/world-engine-v2` branch, choose **Visit Cylinder** on Mac to move
to a stopped viewpoint facing the new O’Neill cylinder. Press **1** to begin a
half-speed approach. The cylinder has rotating green land bands, blue window
placeholders, silver rims, and a stationary gold axial hub. Docking, collisions,
and habitat gravity are not implemented yet. The same geometry appears in the
visionOS immersive scene; immersive navigation remains a separate development step.
See [World Engine v2](WORLD_ENGINE_V2.md) for placement and implementation details.

## Flying on Mac

Click the left mouse button to toggle mouse steering. Move the pointer away
from the center to turn; larger offsets produce stronger steering input.
Click again to disable manual turning. The pointer also sets your aiming direction.
Arrow keys modify steering input while mouse steering is enabled.

| Control | Action |
| --- | --- |
| Left mouse button | Toggle mouse steering |
| Hold right mouse button | Set laser firing state |
| 0 / 1 / 2 | Stop / half speed / normal full speed |
| + or = / - | Increase / decrease speed |
| h, ?, /, or F1 | Toggle help |
| r | Toggle radar |
| Tab | Cycle targets while radar is enabled |
| a or F4 | Toggle autopilot |
| Shift+A | Toggle autopilot with the aggressive-mode flag |
| q or F2 | Arm one missile |
| w or F3 | Launch the armed missile |
| b | Spawn a robot |
| f or Escape | Pause / resume the local simulation |
| p | Print position to the debug console |

On some keyboards, use Fn with a function key to send F1–F4.
The macOS **Game**, **Multiplayer**, and **Help** menus provide additional
shortcuts, including Command+0/1/2 for speed, Command+M to arm,
Command+Shift+M to launch, Command+B to spawn a robot, and Command+. to pause.

## Radar, autopilot, and weapons

Enable radar with **r** and use **Tab** to choose among roster objects.
Current target cycling follows object ID order; the original game's automatic
range-and-view-cone target acquisition should not be assumed.
Turning radar off clears the selected target.

Autopilot steers toward the selected target. Without a target, its turning
input decays and the ship drifts. The current controller can set laser firing
state when a target is close and ahead. Although Shift+A sets an aggressive-mode
flag, separate firing behavior for that flag is not yet enforced by the controller.

Missiles require two actions: **arm**, then **launch**. A missile inherits your
selected target when launched and uses its own guidance controller. Current
settings give you 20 missiles initially, a nominal missile speed three times
normal ship speed, and a five-second missile lifetime. Launches are blocked
when the missile-object limit is reached. These settings differ from the
historical README's fifteen-second lifetime and eight-missile limit.

Laser input, ship firing state, missile movement, and HUD feedback exist.
Complete combat resolution, scoring, death, and respawn behavior remain areas
for further work; do not treat the port as a finished competitive game.

## Reading the display

The status strip shows running/paused state, speed, enabled flight modes,
and armed/remaining missile counts. While Bonjour is running, it also shows
how many peers have been discovered. The legacy HUD includes score, targeting
information, and an orientation globe. A displayed score is not evidence that
complete scoring rules have been implemented.

## Robots and practice

Choose **Spawn Robot**, press **b**, or use the macOS Multiplayer menu.
Each robot starts near your ship and uses an AI controller that can pursue
targets and set its firing state. You do not need to start networking first.
There is currently no separate `dstar-robot` command-line program.

A useful practice session is to spawn one robot, enable radar, select it with
Tab, and compare manual steering with autopilot. Start at half speed if the
scene is hard to follow. Pause to inspect the display.

Ed Falk's original advice about pursuit still provides useful intuition:
following a turning ship directly can keep you on a similar path; turning
inside its arc can help close the distance. Treat the old combat tactics as
historical guidance while the port's gameplay is still developing.

## Local-network multiplayer

1. Run DStarSwift on participating devices on the same local network.
2. Choose **Start Bonjour** in each instance and allow local-network access
   if the operating system asks.
3. Watch the peer count. On Mac, the Multiplayer menu also lists peer names.
4. Choose **Stop Bonjour** to end that instance's network session.

The current transport discovers peers using Bonjour and exchanges UDP state
updates for players, locally simulated robots, and missiles. Peers are symmetric;
there is no original-style master/submaster election. Cross-subnet relays,
joining by hostname, and compatibility with the legacy C game's network
protocol are not provided as user features.

If no peers appear, check that Bonjour is started in both instances, local-network
access is allowed, and the network permits device-to-device discovery.
Simulator-to-device and multiple-simulator sessions still need dedicated
end-to-end validation. Local pause is not a synchronized multiplayer pause.

## visionOS and immersive mode

Choose **Enter Immersive** to open the RealityKit scene. The button changes to
**Exit Immersive** after a successful opening. The status label reports whether
the app is windowed, active, cancelled, or encountered an error.

The scene includes the legacy world, stars, replicated ship visuals, and a
head-relative orientation globe. Use the sun slider in the main window to
adjust ambient brightness. Full spatial flight controls and cockpit interaction
are future work.

If opening fails, rebuild the current project and retry. Its Info.plist enables
multiple scenes, which is required to open the immersive space alongside the
window. Keep the main window available for its controls.

## Further reading

- [README](README.md): project overview, credits, setup, and license.
- [Roadmap](ROADMAP.md): proposed work and historical features to revisit.
- [Porting plan](PORTING_PLAN.md): detailed implementation history and notes.
