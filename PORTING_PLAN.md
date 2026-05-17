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

- Build smoke-test: `xcodebuild -project DStarSwift.xcodeproj
  -scheme DStarSwift -destination 'platform=macOS' build`.
- Manual: launch the macOS app, confirm:
  - star field has visible depth (parallax when moving),
  - `h` and `⌘?` both show the help panel,
  - `f`, `Esc`, and `⌘.` all toggle freeze,
  - HUD speed label updates with `0/1/2/+/-`.
