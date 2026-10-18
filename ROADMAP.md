# DStarSwift Roadmap

These are proposed priorities, not release commitments or a list of completed
features. They draw on Ed Falk's original README and the current Swift code.
See [USER_MANUAL.md](USER_MANUAL.md) for the present user-facing behavior and
[PORTING_PLAN.md](PORTING_PLAN.md) for implementation details.

## 1. Finish the flight and combat loop

- Validate manual steering, aiming, target selection, and autopilot together.
- Make normal and aggressive autopilot behavior explicit and distinct.
- Complete and test laser hits, missile impacts, destruction, scoring, and respawn.
- Decide missile lifetime, active limits, and ammunition replenishment deliberately;
  document any differences from the original game.
- Revisit automatic radar acquisition, range limits, lock retention, and warnings.

## 2. Validate multiplayer play

- Exercise two Mac clients, Mac plus visionOS, and multiple simulator instances.
- Verify discovery, peer departure, reconnects, robot ownership, and missile cleanup.
- Define authority for hits, scores, deaths, and respawns before competitive play.
- Test stale packets, duplicate identities, packet loss, and session teardown.

The original master/submaster/slave hierarchy, hostname joining, and subnet
broadcast relays are historical reference material. Their inclusion would
require an explicit design decision; today's Bonjour transport uses symmetric peers.

## 3. Make immersive flight playable

- Add and document visionOS flight input appropriate to available devices.
- Validate immersive scene placement, ship-relative movement, and HUD readability.
- Provide accessible in-space controls for flight, targeting, pause, and exit.
- Check comfort and performance on physical Vision Pro hardware.

## 4. Improve onboarding and distribution

- Keep the manual and on-screen help aligned with actual controls.
- Add screenshots and a short first-flight walkthrough after gameplay validation.
- Document a reproducible release build and device installation process.
- Review inherited source provenance and preserve applicable original notices.

## Historical reference

Ed Falk's README describes the original multiplayer space game, flight and
weapons controls, a separate robot executable, pursuit tactics, and the old
UDP protocol and C source layout. Those implementation details are useful for
porting research, but are not instructions for running the Swift application.
The local `README-Orig.text` reference is intentionally excluded from Git.
