# DStarSwift

A Swift port of the legacy DStar space game, using SwiftUI and Metal, with a
RealityKit immersive scene on visionOS.

Features include the legacy world and starfield, ship controls, radar and HUD,
missiles, robot opponents, and Bonjour multiplayer discovery.

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
