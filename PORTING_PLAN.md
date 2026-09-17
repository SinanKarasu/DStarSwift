# DStar C/OpenGL -> Swift/Metal Port Plan

## Current status
- Implemented first render slice in Swift/Metal:
  - `MTKView` host in SwiftUI.
  - Metal pipeline and shaders for star points.
  - Camera/projection transform and animated view rotation.
  - Star color grouping aligned with original `draw_starfield_gl.c` behavior
    (majority white, then red/green/blue groups).
- Implemented requested next three slices:
  - Ported exact legacy star coordinates from `starfield.h` (`400` points).
  - Added Swift game state models/constants based on C headers and control math.
  - Added keyboard + mouse input mapping through a custom `MTKView`.
- Implemented BSP/ringworld geometry conversion:
  - Ported `Bsp_Node` equivalent and BSP tree build candidate-selection logic.
  - Ported ring generation and ringworld polygon assembly (`gen_ringworld` path).
  - Added BSP visibility traversal and Metal mesh rendering for filled polygons.

## Source mapping
- `<legacy-dstar-root>/dstar/dstar.c`
  -> `GameLoop` Swift type:
  - Holds `Dtime`, timers, and high-level state transitions.
  - Calls update and network polling each frame.

- `<legacy-dstar-root>/dstar/graphics_gl.c`
  -> `Renderer` + input layer:
  - Replace fixed-function GL draw calls with Metal buffers/pipelines.
  - Replace GLUT callbacks with SwiftUI/AppKit event handling.

- `<legacy-dstar-root>/dstar/draw_starfield_gl.c`
  -> `StarfieldSystem`:
  - Keep star generation and color partitioning.
  - Draw as Metal point primitives.

- `<legacy-dstar-root>/dstar/draw_bsp_gl.c`
  -> `BSPMeshRenderer`:
  - Convert BSP-generated polygons into indexed triangle/line buffers.
  - Render with one fill pipeline + one wireframe/overlay pipeline.

- `<legacy-dstar-root>/dstar/control*.c`
  -> `InputSystem` and gameplay systems:
  - Convert key/button state bitfields to Swift structs.
  - Keep gameplay math and rule behavior equivalent.

## Next implementation slices
1. Add culling parity details (per-node backface rules + trim lines where used by other objects).
2. Port object update loop (`normal_action`, missile/fire, autopilot behavior parity).
3. Port additional BSP assets (fighters/monolith) from legacy headers/data.

## macOS pass — May 2026

- Keyboard parity with the original `special_key()` (`special_gl.c`):
  - Legacy keys handled in `DStarGameState.handleCharacterKey` /
    `handleFunctionKey`: `0/1/2`, `+/-`, `h/?/F1`, `a/A/F4`, `r`, `Tab` (radar
    cycle stub), `q/F2` arm, `w/F3` launch, `f/Esc` freeze, `p` debug print,
    `l` trim-line toggle.
  - macOS virtual key codes routed through `DStarInputMTKView`. `Cmd` is
    explicitly dropped before character routing so menu shortcuts don't
    double-fire.
- Menu bar (`DStarSwiftApp.body` `.commands`):
  - Quit (`⌘Q`, system default) — preserved.
  - `Game` menu: Pause `⌘.`, Autopilot `⌘A`, Radar `⌘R`, Stop/Half/Full
    `⌘0/1/2`, Arm/Launch `⌘M / ⌘⇧M`.
  - Help: `⌘?` toggles the on-screen key-binding overlay.
- On-screen HUD (`ContentView`): translucent status strip (paused / speed /
  autopilot / radar / mouse-fly / missile counts) plus help overlay panel.
- `DStarHUDState` is the SwiftUI mirror; the renderer pushes flag changes
  out every frame and accepts commands back through `onCommand`.

## Starfield abstraction (preparing for DESI)

- `StarfieldSource` protocol (`StarfieldSource.swift`) decouples the renderer
  from any specific star data set. Three implementations live alongside it:
  - `SphericalShellStarfield` — procedural, seeded SplitMix64, ~5000 points
    in a 1000–8000 unit shell with volume-uniform radius and a unit-sphere
    direction. This is the default for both macOS and visionOS now.
  - `LegacyStarfieldSource` — the original 400-point hand-rolled list,
    retained for A/B comparison.
  - `DESIStarfieldSource` — stub that currently falls back to the procedural
    shell. The intended implementation:
    1. Bundle a DESI catalog excerpt (DR1 BGS or LRG slice, Parquet or FITS).
    2. Parser converts each row from `(RA, Dec, redshift)` →
       Cartesian, with redshift mapped to comoving distance via a small
       hard-coded ΛCDM lookup table (Planck18 cosmology).
    3. Apply a scene scale so the brightest local DESI distances fall in a
       useful gameplay range (~5 kpc to ~5 Gpc compressed into game units).
    4. Tag each `StarPoint` with `magnitude` from observed flux and assign
       `colorIndex` from rough color cuts (red / green / blue bins).
- Renderer change to swap data sources: set
  `renderer.starfieldSource = DESIStarfieldSource(...)` before `configure(for:)`.

## VisionOS pass (after macOS is solid)

Open items captured from the user request:

1. Ambient lighting must be adjustable down to pitch black.
   - Approach: render in `.full` `ImmersionStyle` (we already opt in) and
     drive a per-frame ambient term on the ringworld material from a HUD
     slider 0…1. At 0 the only thing visible is the unlit star sprites and
     emissive surfaces, so the user gets near-pitch-black space.
   - Implementation note: SimpleMaterial in RealityKit can't easily be
     tweaked per-frame; either pre-bake N levels or switch to a custom
     `ShaderGraphMaterial` with a `BaseColor` exposed parameter.

2. Keyboard interface, preferably Logitech Muse.
   - Phase A: connect a Bluetooth keyboard, reuse the macOS key bindings
     by routing UIKey events into the existing `DStarInputAction` enum.
   - Phase B: Logitech Muse (Apple Pencil-class stylus for Vision Pro).
     Use the `SpatialEventCollection` / `HoverEffectComponent` APIs to
     map Muse tip motion → steering, side button → arm, double-tap →
     launch. Mirror the macOS bindings into a small `MuseInputAdapter`.

3. DESI fly-through:
   - Same `StarfieldSource` already feeds the visionOS scene, so once the
     DESI loader exists the immersive view picks it up unchanged. Cull
     by distance and stream chunks if the full catalog overflows memory.

## Verification

- Automated suite: `xcodebuild -project DStarSwift.xcodeproj
  -scheme DStarSwift -destination 'platform=macOS' test`.
- Build smoke-test: `xcodebuild -project DStarSwift.xcodeproj
  -scheme DStarSwift -destination 'platform=macOS' build`.
- Manual: launch the macOS app, confirm:
  - star field has visible depth (parallax when moving),
  - `h` and `⌘?` both show the help panel,
  - `f`, `Esc`, and `⌘.` all toggle freeze,
  - HUD speed label updates with `0/1/2/+/-`.

## Multi-ship + robots + Bonjour networking

Landed on `claude/11newfeatures` after the macOS pass:

### Roster

- `DStarObject` is still a value type; `DStarGameState` now owns
  `me` (the local player at id `0`) and `others: [Int: DStarObject]`
  (every robot / network peer keyed by id).
- Each ship has a `ShipController` (in `controllers: [Int: any ShipController]`).
  Controller protocol is in `ShipController.swift` — three implementations:
  - `PlayerController` — input-driven; the legacy `controlShip()` body.
  - `AutopilotController` — vector-feedback port of `autopilot.c:auto_control`.
    Resolves `ship.targetID` from `world.others`; with `huntsForTargets=true`
    it picks the nearest other ship when no target is set.
  - `RemoteController` — applies the most recent network snapshot.
- `ShipKinematics.advance(...)` holds the `forward/up/right` integration
  from `adjust_vectors()`, shared by player + autopilot.
- `DStarGameState.step(_:)` drives every ship in the roster through its
  controller each frame, with `ShipWorld` giving controllers a read-only
  view of everyone else.

### Robots

- `b` key (and `⌘B` from the menu) spawns a local AI opponent:
  `DStarGameState.spawnRobot()` creates a `DStarObject` with
  `objectClass = .robot`, `flags |= robot`, and an `AutopilotController`
  with `huntsForTargets = true`. Robots get ids `1000+` so they don't
  collide with network-allocated peer ids (`1...maxPlayers`).
- The renderer iterates `gameState.others.values` and stamps the ported
  `FighterMesh.fighter1` at each ship's basis/position. `me` is not drawn
  (the camera *is* its cockpit).

### Fighter mesh

- `FighterMesh.swift` is auto-generated from `dstar-1.0/fighter1_bsp.h`
  by `tools/parse_fighter.py`. 26 polygons, with the `BSP_BACK_VIEW`
  flag preserved as `doubleSided`. Regenerate by re-running the script.

### Networking

- Wire vocabulary mirrors the legacy `netio.h` cases but uses Swift
  `Codable` (JSON v1, easy to inspect with tcpdump; flip to binary
  Codable later without touching call sites). See `NetMessage.swift`.
- `ShipState` (`NetMessage.swift`) is the on-wire snapshot for
  `NET_CURRENT_STATUS`; it lossy-round-trips a `DStarObject`.
- `NetTransport` (`NetTransport.swift`) is the swap point for GameKit
  later. The only implementation right now is
  `BonjourUDPTransport`: `NWListener` + `NWBrowser` over
  `_dstar._udp`, peers identified by their advertised service name.
  Inbound payloads come back on `onReceive`, peer-set changes on
  `onPeersChanged`. Symmetric topology (no master election in v1).
- `NetSession` (`NetSession.swift`) is the orchestrator:
  - `start()` brings the transport up and begins a 20 Hz status
    broadcast (every `1 / DStarGameParameters.statusBroadcastHz`).
  - Inbound `.status` calls `game.applyRemoteSnapshot(...)` which
    upserts the peer's ship and (re)installs a `RemoteController` for
    it.
  - `.leaving` and `.died` remove peers; other message types
    (missile / scoring / membership / relay) are accepted but not yet
    acted on — those land in the next slice when we introduce a host
    authority.

### App + HUD wiring

- `DStarSwiftApp` owns the `NetSession` as a `@StateObject`. When the
  Metal view's renderer is constructed it publishes its `DStarGameState`
  through `DStarHUDState.onGameStateReady`, which the app uses to call
  `net.attach(game:)`.
- New macOS menu items:
  - `Multiplayer ▸ Start / Stop Hosting (Bonjour)` — `⌘⇧H`.
  - `Multiplayer ▸ Spawn Robot` — `⌘B`.
  - The same menu surfaces the local Bonjour name and the list of
    currently-discovered peers.
- Status strip in `ContentView` shows a `net • N peers` badge whenever
  the session is running.

### What's deliberately not done yet

- Missile allocation (no `missileRequest` / `missileAssigned`).
- Scoring authority (no `scored`).
- Host election / master role — currently a flat mesh; OK for LAN
  testing, swap in once we decide on host-authoritative hit detection.
- GKMatch transport — protocol is in place for the future drop-in.

## Automated tests + Mac/visionOS LAN slice — September 2026

- Added the `DStarSwiftTests` macOS unit-test target. Coverage includes input
  state, pause/radar behavior, ship kinematics, robot creation and pursuit,
  remote dead-reckoning, Codable wire round-trips, peer identity, robot
  broadcasts, loopback rejection, and peer cleanup.
- Bonjour objects now use deterministic per-peer network namespaces instead
  of every device sending local object id `0`. Each process broadcasts both
  its player and its locally simulated robots, with owner metadata for clean
  removal when a peer leaves.
- Both app targets declare `_dstar._udp`, local-network usage, and incoming /
  outgoing network capability. Start/stop Bonjour and spawn-robot buttons are
  available in the visible UI on macOS and visionOS.
- The immersive RealityKit scene mirrors robot and remote fighter transforms.
  It defaults to full immersion and provides a 0…100% ambient slider; at zero,
  lit ringworld geometry is black while unlit stars and ships remain visible.
- Restored the legacy cockpit HUD as a responsive SwiftUI overlay: the red
  command card opens on first launch, the blue center sight is always present,
  score/missile/radar-lock status is live at lower left, and the lower-right
  wireframe HSI rotates from the player's actual forward/up/right basis.
- In full immersion, a RealityKit wireframe HSI is attached to a continuously
  tracked head anchor at a lower-right gaze offset. It follows the wearer while
  its internal globe continues to rotate from the player ship's attitude.
- Missile launch now creates a five-second homing roster object instead of only
  consuming ammunition. Metal renders the original red/yellow line glyph plus
  an extended tracer wake; RealityKit uses an unlit flare and tail. Flying
  missiles carry their object class over Bonjour and expire on remote peers.

## Sun-era world reconstruction — September 2026

- Added a renderer-independent `DStarLegacyWorld` boundary for scenery. It is
  deliberately separate from the player/robot/network roster, giving a future
  authored world or space-station setting one clean replacement point.
- Restored the two faceted gray planet meshes generated by the original
  `gen_sphere()` path (radii 100 and 50) and the exact 80 × 20 × 180 TMA-2
  mesh from `monolith_bsp.h`.
- Restored the 2004 Ringworld as a world body at its original `(4000, 0, 0)`
  position and original basis instead of baking its mesh at the origin.
- All four bodies use the legacy forward/up/right integration, including the
  planets' approximate orbits, TMA-2 motion, and the Ringworld's slow rotation.
- Metal and RealityKit now render the same world description. Immutable BSP
  geometry is shared between world instances; only transforms and clocks vary.
- `LegacyWorldTests` locks down body inventory, polygon counts, Ringworld
  placement, coordinate transforms, and orthonormal motion. This completes the
  continuity-preserving scenery pass before new world-building diverges from
  the historical DStar scene.
