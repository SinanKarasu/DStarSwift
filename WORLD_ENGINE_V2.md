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

## O'Neill cylinder design direction

Build the cylinder as a parametric structure, furnish it with modular assets,
and use RealityKit to inspect and experience the result. Maintain one versioned
station specification with stable IDs, radius, length, rotation, section layout,
terrain seeds and asset references. Blender assets and Swift-generated structure
must follow this specification rather than becoming independent station models.
The specification is planned work; the current habitat is defined in Swift.

### Responsibilities and asset workflow

| Component | Responsibility |
| --- | --- |
| DStar world engine | Station dimensions, universal placement, reference frames, rotation, docking state and habitat physics. |
| Blender | Terrain sections, buildings, structural details, UVs and textures. Evaluate Geometry Nodes for generating repeated structures from the station dimensions. |
| glTF and SwiftGLTF | Transfer authored local geometry into DStar's shared asset layer. The current adapter supports static triangles and untextured unlit colors; textured and physically based materials require further implementation. |
| RealityKit | Immersive rendering, spatial entities and interaction, with local collision and physics facilities where appropriate. |
| AR and visionOS | Head tracking, spatial input and placement of a tabletop inspection model or an immersive experience around the wearer. |

Keep astronomical positions in WorldPosition and mesh coordinates local in
metres. DStar owns rotating reference frames and habitat-scale motion; native
scene transforms serve presentation and local interaction. Interior effective
gravity points toward the cylindrical surface, so a single fixed scene-wide
gravity direction is insufficient. Moving objects also require rotating-frame
effects such as Coriolis acceleration; visual rotation alone is not a gravity
simulation.

The first imported asset is the axial docking core, documented in
[Station Prototype](STATION_PROTOTYPE.md). It provides the initial model-loading,
approach and capture workflow. Its walls are currently visual-only and it is a
microgravity facility. Incorporating it into the cylinder's frame hierarchy,
including the choice of rotating versus stationary docking structure, remains
a design task.

### First inhabited section

Extend the docking-core foundation with a rotating shell and one inhabited
section before furnishing the entire circumference:

- A visible interior floor with terrain, a few buildings, trees and recognizable
  human-scale references.
- Structural ribs and window sections around the shell.
- A planned connection from the axial docking area to the inhabited surface.
- Reusable assets and section boundaries suitable for instancing, visibility
  culling and later levels of detail.

Validate this section's scale, lighting, navigation and rendering cost before
repeating it around the cylinder. This is a visual and interaction prototype,
not a complete habitat engineering or life-support design.

### Three views of the same station

1. **Tabletop inspection:** a reduced model that can be rotated and cut away to
   inspect the structure and select destinations.
2. **Exterior flight:** approach and dock with the station at full apparent scale.
3. **Interior exploration:** a standing viewpoint on the inhabited surface,
   looking across and upward at the opposite landscape.

All three views must derive from the same station definition. Inspection scale
and cutaways are presentation choices; they must not change simulation dimensions
or duplicate station state. Full apparent scale and standing interior exploration
are planned modes: the current immersive renderer still uses its 0.001 display
scale.

### Next milestone and acceptance checks

Build **one furnished interior section, visible in both a cutaway inspection
model and a standing viewpoint inside**.

- Both views use the same dimensions, assets and section IDs.
- Human-scale landmarks make cylinder curvature and distances understandable.
- The section's connection toward the axial core is recognizable.
- Transitions between views preserve a clear sense of location and orientation.
- Evaluate lighting, material readability, frame pacing and comfort on physical
  Vision Pro hardware; measure performance before choosing detail budgets.
- Have a first-time user try inspection, destination selection and entering the
  interior without coaching; record hesitation, unclear modes and missing feedback.

Confirm current Blender export and RealityKit material/interaction workflows
before selecting the detailed authoring tools. The first slice does not depend
on a complete city, landscape ecosystem or universal glTF material support.

## Next slices

1. Validate the existing docking-core approach, capture controls and exit on M5 Vision Pro.
2. Define the shared station specification and the relationship between docking-core and habitat frames.
3. Build and validate the first inhabited section in cutaway and standing interior views.
4. Add shared textured/material support and lighting as needed for that section.
5. Add hull collision, bounds-based visibility, Metal asset caching and detail selection.
6. Unify legacy body snapshots with the new frame model while preserving legacy motion.
7. Implement and test rotating-frame motion and interior gravity before enabling physical surface exploration.
