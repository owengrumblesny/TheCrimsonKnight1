# Known gaps (honest status)

## UI (Part I) — implemented and tested; remaining gaps
- No Electron/desktop packaging exists yet, so "Quit" is disabled and packaged-build icon loading is untested.
- Gamepad: in-game bindings exist, but menu navigation with a gamepad is not implemented. Not tested on real hardware.
- Inventory drag-and-drop is not implemented; assignment uses buttons or keys 1–8.
- Subtitles toggle is disabled (there is no dialogue).
- The minimap is the full-screen Map only; there is no corner minimap widget.
- Health, armor and energy are real but simple (fall damage, regeneration, gadget costs). There is no combat damage.

## Items without an in-game effect yet
Hologram decoy, holoprojector, O.E. comms, forensics kit, all fictional weapons (no combat), and all three vehicles (not drivable). Each shows an N/A badge and its reason.

## Audio (docs/CRIMSON_KNIGHT_AUDIO_SETUP_FOR_CLAUDE.md) — partial
Done:
- One AudioContext with master + music / ambience / sfx / vehicles / ui buses.
- Volume + mute settings, persisted.
- Unlocks on the Play click or "Enable audio".
- Original synthesized placeholder sounds for: UI click/open/close/select/deny, footsteps, jump, landing (scaled by impact), gadget deploy/throw/pulse, armor activate, vehicle call, rain ambience.

Not done:
- Sound test panel, `config/audio_manifest.json`, `docs/AUDIO_SETUP.md`.
- Positional audio, music, vehicle engine loop, Citadel ambience.

No third-party audio is used, so no credits are owed yet.

## 3D (Part II) — see docs/ASSET_AUDIT.md for per-family status
- **Hero:** procedural rigged model with 22 clips. Missing clips are listed in ANIMATION_MAP.md. No cloth or spring cape.
- **Vehicles:** blockouts only; no pivots, interiors or driving.
- **City:** cube/cylinder placeholders re-textured with Owen's material PNGs; bounding-box colliders; no LODs.
- **NPCs / enemies:** blockouts only; no rigs or AI.
- **Red Citadel:** concept art + portal marker only.
- **Physics note:** the ground slab is offset from the spawn after a fall-through bug at (0, 0); the root cause wasn't isolated (see systems/physics.ts).
