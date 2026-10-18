# DStarSwift

A Swift port of the legacy DStar space game, using SwiftUI and Metal, with a
RealityKit immersive scene on visionOS.

Features include the legacy world and starfield, ship controls, radar and HUD,
missiles, robot opponents, and Bonjour multiplayer discovery.

## Origins and credits

**DStar was originally written by Ed Falk.** The original game used Sun's XGL
graphics library. Ed later ported DStar to OpenGL for Linux, bringing the game
from its Sun/XGL roots to Linux systems.

DStarSwift continues that lineage: **XGL → OpenGL on Linux → Swift and Metal**.
This port adapts the legacy C/OpenGL game to Swift, SwiftUI, and Metal, with
RealityKit providing the visionOS immersive scene. It carries forward the
original game's world, ship models, controls, and gameplay concepts.

Credit for the original DStar game and its Linux OpenGL port belongs to
**Ed Falk**. The Swift/Metal port is by **Sinan Karasu**.

## Run

Open `DStarSwift.xcodeproj` in Xcode with the macOS and visionOS SDKs installed.

- For macOS, select the `DStarSwift` scheme and My Mac.
- For visionOS, select `DStarSwiftVision` and an Apple Vision Pro simulator or
  device. Click **Enter Immersive** to open the immersive scene.
- Use the on-screen help for controls. Bonjour multiplayer requires local
  network access.

The project currently targets macOS 26.2 and visionOS 26.2 or later.
The scene manifest in `DStarSwift/Info.plist` enables multiple scenes, which
visionOS requires to open the immersive space alongside the main window.

## Tests

```sh
xcodebuild -project DStarSwift.xcodeproj -scheme DStarSwift \
  -destination 'platform=macOS' test
```

Tests cover game state, networking, and the legacy world.
See [PORTING_PLAN.md](PORTING_PLAN.md) for implementation notes and remaining work.

## License

Licensed under the [MIT License](LICENSE). See the origins and credits above
for attribution to Ed Falk, creator of the original DStar and its Linux OpenGL port.
