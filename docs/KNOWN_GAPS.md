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

## 3D (Part II + Master Asset Directive) — see docs/ASSET_AUDIT.md for per-family grades
- **No asset is HERO grade.** Everything scripted is PROTOTYPE at best. The CR-X9 helmet is egg-shaped and the neck shows; vehicle surfaces are faceted; NPCs have no faces or hands detail. An artist sculpt/texture pass is required for showcase quality.
- **Gameplay systems are deliberately not implemented** (directive: assets first): no grappling physics beyond the existing pull, gliding, driving, combat or NPC AI. NPCs stand idle; vehicles are parked in the Citadel hangar; the gear is display/attachment only.
- **Held gear alignment** is derived from the idle pose per socket (`Hero.hold`). Two-handed weapons do not IK the off hand to `OffHand` yet.
- **Hero:** missing clips are listed in ANIMATION_MAP.md. No runtime cape simulation.
- **City:** a single downtown intersection sector with a LOD1 skyline ring. No streaming of further sectors, no interiors in the city buildings, and kit buildings are not enterable.
- **NPC crowd:** shares one skeleton, so body variety comes only from girth, clothing and accessories (no height or gender morph targets). Skinned NPCs use per-NPC mixers, which is fine at 34 NPCs but would need GPU-instanced animation for crowds.
- **Download size:** every small GLB embeds its own copies of the material PNGs (18 gear models = 7 MB, kit = 18 MB). Sharing external textures across GLBs is the next load-time win.
- **Physics note:** the ground slab is offset from the spawn after a fall-through bug at (0, 0); the root cause wasn't isolated (see systems/physics.ts).
