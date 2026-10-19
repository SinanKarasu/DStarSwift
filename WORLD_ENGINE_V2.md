# World engine v2 — first implementation

Branch: `codex/world-engine-v2`.

This first slice adds an independently written Swift world/frame model and a
procedural O'Neill cylinder alongside the existing legacy scenery. Celestia's
separation of geometry, frames, and rendering informed the architecture; no
Celestia source or assets are included.

## Shared model

`DStarWorld.swift` defines immutable world frames, geometry assets, instances,
and evaluated draw items. Frames have stable string IDs, optional parents,
double-precision translations and quaternions, and a spin rate around local Y.
A snapshot resolves the complete hierarchy at one simulation time and rejects
duplicate IDs, missing parents, cycles, and nonfinite time. Evaluating time
again, including backwards, does not accumulate integration error.

Conventions are metres, seconds, +Y up, and DStar's +Z forward. The v2 region
uses one metre per legacy game unit for this first integration. The existing
legacy simulation retains its original units and single-precision state.
Universal frame positions now use integer sector addresses plus bounded local
offsets. Snapshots subtract the observer address before producing local Double
poses and Float vertices. See [Coordinate Architecture](COORDINATE_ARCHITECTURE.md). Metal uses the player's position as that origin for habitat geometry;
legacy triangles and lines are also shifted into the resulting nearby render
space. The player simulation itself is still Float, so this is a foundation
for large worlds, not a completed astronomical-scale flight system.

Both renderers evaluate the same definition at the HUD/game simulation time.
Metal expands the shared indexed triangles into its existing vertex stream.
RealityKit uploads shared geometry once and updates entity poses on subsequent
snapshots. Its current 0.001 world display scale is retained, so 1,000 game units
span one metre of immersive scene. Immersive rendering now applies the inverse ship/view pose, with +Z converted
to RealityKit -Z. The navigation panel remains outside that world transform.

## First destination

The habitat center is at `(350, 0, 1300)`, in the arrival region (the legacy player spawn remains random). It is 360 metres across and 600 metres long, with its axis
along Y. Three green land bands alternate with three opaque blue window
placeholders. Silver end bands surround open axial entrances. A narrow gold
axial hub extends beyond the ends. The shell spins at 0.08 radians per second;
the hub remains fixed in the habitat frame.

Surfaces contain explicit triangles for both sides, allowing views from inside
and outside. Geometry is generated once in the static world definition.
This is an initial visual model: windows are not transparent, the hub has no
caps or docking behavior, and there are no collisions, gravity, surface cities,
LOD transitions, or physically based habitat lighting yet. RealityKit uses
unlit habitat materials to match the flat-colored Metal first pass. The ambient
slider continues to affect legacy scenery rather than these unlit materials.

## Run and validation

Use `DStarSwift` on My Mac or `DStarSwiftVision` on a visionOS simulator/device.
On Mac, choose **Visit Cylinder** to stop at a known viewpoint facing the habitat,
then use `1` for a half-speed approach. Left-click enables mouse steering; `f` pauses rotation
and the local flight simulation.

Tests in `WorldEngineTests.swift` cover parent rotation and child translation,
stationary hub versus rotating shell, rewind determinism, origin subtraction
at large coordinates, invalid frame graphs, and finite nondegenerate geometry.
Existing game/network/legacy-world tests continue to cover the preserved game.
Physical Vision Pro visual quality, comfort, frame pacing, and the placement
of the new destination still require headset validation.

## Next slices

1. Validate scale and approach on M5 Vision Pro; add an explicit arrival viewpoint.
2. Add hull ribs, axial approach beacons, and a recognizable docking interface.
3. Add transparent window materials and interior landmarks through shared material definitions.
4. Unify legacy body snapshots with the new frame model while preserving legacy motion.
5. Add bounds-based visibility, asset caching in Metal, and detail selection.
6. Design docked/local flight frames and collision behavior before artificial gravity.
