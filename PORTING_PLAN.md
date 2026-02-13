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
- `/Volumes/GitHubDeveloper/Projects/DStar/DStar/dstar/dstar.c`
  -> `GameLoop` Swift type:
  - Holds `Dtime`, timers, and high-level state transitions.
  - Calls update and network polling each frame.

- `/Volumes/GitHubDeveloper/Projects/DStar/DStar/dstar/graphics_gl.c`
  -> `Renderer` + input layer:
  - Replace fixed-function GL draw calls with Metal buffers/pipelines.
  - Replace GLUT callbacks with SwiftUI/AppKit event handling.

- `/Volumes/GitHubDeveloper/Projects/DStar/DStar/dstar/draw_starfield_gl.c`
  -> `StarfieldSystem`:
  - Keep star generation and color partitioning.
  - Draw as Metal point primitives.

- `/Volumes/GitHubDeveloper/Projects/DStar/DStar/dstar/draw_bsp_gl.c`
  -> `BSPMeshRenderer`:
  - Convert BSP-generated polygons into indexed triangle/line buffers.
  - Render with one fill pipeline + one wireframe/overlay pipeline.

- `/Volumes/GitHubDeveloper/Projects/DStar/DStar/dstar/control*.c`
  -> `InputSystem` and gameplay systems:
  - Convert key/button state bitfields to Swift structs.
  - Keep gameplay math and rule behavior equivalent.

## Next implementation slices
1. Add culling parity details (per-node backface rules + trim lines where used by other objects).
2. Port object update loop (`normal_action`, missile/fire, autopilot behavior parity).
3. Port additional BSP assets (fighters/monolith) from legacy headers/data.
