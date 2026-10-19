# Coordinate architecture

DStar has three coordinate layers. Apple spatial UI conversion complements the
universe model; it does not replace the universe's precision representation.
The visionOS baseline is now 27.0. macOS remains 26.2 or later.

## Universal addresses

`WorldPosition` stores an Int64 sector address on each axis and a bounded Double
offset in metres. Sectors span exactly 2^32 metres; offsets are normalized into
[-2^31, 2^31). The address range exceeds four trillion light-years in either
direction. Local offset resolution stays below one micrometre throughout a
sector, independent of distance from the universal origin.

Construct distant positions using integer sector addresses, then add local metre
offsets. Do not build a giant Double metre value and expect conversion to recover
fractional detail that was already lost. Values are checked for nonfinite input
and address overflow. Int64 sector subtraction happens before converting the
relative distance to Double. Very distant relative vectors are approximate;
nearby relative vectors retain local precision, including across sector boundaries.

This is independently written Swift code. Celestia's high-precision-before-local
conversion informed the design; its source is not incorporated.

## Reference frames

Only root `WorldFrame`s may carry universal anchors. Each child has a local metre
translation, orientation, and optional spin. Snapshot resolution carries a
`WorldPosition` through the hierarchy rather than flattening into one absolute
Double. Call `snapshot(at:relativeTo:)` with an observer's universal address;
returned draw-item poses are observer-relative, with global-axis orientations.

`WorldLocation` names a frame and a local metre offset.
`displacement(from:to:at:)` resolves related locations through their lowest shared
ancestor and returns the vector in the source frame's axes. Large ancestor
translations do not enter the nearby calculation. Separate-root locations use
universal address subtraction. This distinction matters for docking ports,
ships, and terrain inside the same distant habitat.

Local frames should stay local. Divide a vast structure into smaller frames
instead of giving a single mesh or local offset astronomical dimensions.
The model supports rigid transforms, not nonuniform simulation scale or relativistic
cosmology. Distances are Euclidean coordinates; a cosmological address does not
implement cosmic expansion, light-time effects, or physically realistic travel.

## Rendering and spatial input

Metal requests observer-relative habitat snapshots before expanding vertices.
RealityKit does the same before assigning entity translations. The habitat lives
under its own camera-relative root, avoiding cancellation between large Float
entity translations. Both keep geometry assets in local coordinates.

The explicit game-to-renderer boundary still converts DStar +Z-forward into the
renderers' -Z-forward convention. This is a simulation convention, not a SwiftUI
layout conversion; it remains deliberate and separate.

On visionOS, the navigation globe obtains its local `CoordinateSpace3D` from
`GeometryReader3D`, and its drag requests values in that space. Apple handles the
spatial conversion into local view coordinates even for a RealityKit attachment.
The control uses local x/y displacement and ignores depth. macOS retains a local
2D drag. No raw eye tracking, hand skeleton, or enterprise entitlement is needed.

## Current integration limits

The legacy player, network packets, planets, and starfield still use the original
local Float simulation. They are not an interstellar physics/network system.
The active demonstration region is near universal zero; the new world model can
address distant regions, but moving the player between regions is future work.
An active-region address should accompany local simulation and network locations
when that feature is added. UI and renderer coordinates must never become the
persistent universe database.

Tests cover millimetre and light-microsecond separations at approximately
46 billion light-years, sector crossings, range errors, observer rebasing,
common-ancestor calculations, separate-root rotations, and existing frame/geometry
behavior. Device testing remains necessary for spatial gesture feel and comfort.
