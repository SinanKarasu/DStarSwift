# Axial docking-core prototype

This is an original, deliberately simple 120 m × 30 m microgravity station,
with a rectangular axial entrance, a continuous docking passage, approach
lights and a green berth target. It is a starting point for an O’Neill station;
it does not yet include a rotating landscape or life-support engineering.
The existing demonstration habitat remains nearby.

## Try it on Mac or Vision Pro

1. Build the appropriate DStarSwift or DStarSwiftVision scheme. Xcode resolves
   SwiftGLTF from GitHub. On Vision Pro, enter immersive mode.
2. In the globe panel, choose **Visit Docking Core**. This places the stopped
   ship on axis, 140 m outside the entrance, looking toward the berth.
3. Choose **Match Station Roll**, then **Approach**. This is a 2 m/s flight;
   the first complete approach takes about two minutes. Look around using
   the globe's Look mode; Steer changes the flight direction.
4. The green berth captures the ship within 3 m, at no more than 2.5 m/s,
   with heading and roll errors no greater than 5°. Capture fixes the ship
   to the rotating berth. **Undock** releases it to a stopped position
   20 m outside the entrance.

For a manual trial, release roll matching and use the two 5° roll buttons.
**Stop Station Spin** freezes the current station phase without stopping the
rest of the world; **Stop** stops the ship. **Visit Docking Core** resets the
approach if you miss. Range, axis offset, heading error and roll error appear
in the panel. Speed remains visible in the main flight status.

Roll matching is an assistance mode: it continuously aligns the ship's roll
plane with the station while leaving heading under pilot control. It is not
a simulated thruster controller. The station rotates at 0.08 rad/s, approximately
0.76 rpm. The central axis has essentially no rotational artificial gravity.

## Asset pipeline

We adopt [Jonathan Wight's SwiftGLTF](https://github.com/schwa/SwiftGLTF), pinned
at `529cf3a40fbe7fcf9990f42f0a8a39487d3aebcc`, under BSD-3-Clause.
`DStarStationAsset` uses its Container, scene hierarchy, resource resolution and
accessor decoding to build renderer-independent WorldGeometry. Both Metal and
RealityKit therefore display the same imported asset. We do not maintain a
separate glTF parser or duplicate the asset using RealityKit's generator.

The initial adapter supports static triangle meshes, hierarchy transforms and
untextured KHR_materials_unlit colors. It rejects skins, morph targets and
textured/lit materials. It is not yet a general glTF viewer; animations and
richer PBR rendering remain future work. A model-loading failure is reported
in the globe panel rather than silently presented as a successfully loaded core.

`DStarSwift/Assets/DockingCore.gltf` is an original DStar asset under this
repository's MIT license. Reproduce it using:

```sh
python3 Tools/generate_station.py
```

The model uses metres and +Y along the station. Its world frame rotates that
axis into DStar's +Z. Universal placement stays in WorldPosition; geometry
stays local. The station has its own simulation clock so stopping its spin
keeps the visible model, alignment indicators and captured ship synchronized.

## Deliberate prototype limits

Docking uses a capture envelope, not contact mechanics. Hull and tunnel walls
are currently visual geometry: they do not block a missed approach. There is
no automatic translation/heading guidance, docking sound, airlock operation,
station network authority or persistence. Remote players still receive the
normal ship pose rather than a station-relative docking attachment.

Next useful additions are swept hull collision, a proper entry vestibule and
larger berthing chamber, approach guidance, and modular habitat construction.
