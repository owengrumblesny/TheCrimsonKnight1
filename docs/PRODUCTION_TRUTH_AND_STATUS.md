# Verified production status — ChatGPT

- **257** GLB files listed in `config/asset_manifest.json` (majority programmatically generated LOW-POLY placeholders).
- **95** separate UI icon PNG files (simple generated icon cards, not bespoke professional icons).
- **9** full-resolution original image-generation outputs discovered in the current workspace, copied without recreating them.
- **25** individually saved cropped/reference PNGs, several cut from composite concept boards.
- Four earlier character/vehicle GLB blockouts copied; no rigging/animation is implied.
- No real motion-capture animations, no final vehicle simulations, and no photorealistic meshes are claimed.
- Existing original images may contain imprecise technical typography, and multiple camera views may not be geometrically consistent.

**Do not advertise these files as the finished game or as hundreds of independently drawn character frames.**

## Update — Claude, M0/M1 (2026-10-27)
- Manifest corrected to **246** unique entries (245 original files + new `crimson_knight_CRX9_rigged`); the "257" count included 12 duplicates.
- **Now exists and is verified:** a rigged, skinned CR-X9 GLB with 22 baked `CK_*` animation clips, true six-view orthographic renders of that one mesh (`references/renders/crx9/`), and a playable Three.js/Rapier slice in `game/`. Details, tests and limitations: `docs/CLAUDE_DEVLOG.md`.
- Still true: no photoreal meshes, no motion capture, no cloth sim, no drivable vehicles yet.
