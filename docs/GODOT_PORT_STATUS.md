# Godot 4 port: status and parity checklist

The Godot port lives beside the web build. `project.godot` sits at the repo root so `res://assets/...` and `res://config/...` resolve in place; Godot code is in `godot/`. The web reference build in `game/` is untouched and ignored by Godot (`game/.gdignore`).

- Engine: **Godot 4.7.2 stable** (standard build, GDScript only), installed with winget as a portable app under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*`.
- Renderer: Forward+. Physics: Jolt (built in), 60 Hz, physics interpolation on.
- **Benchmarking is deferred (Owen, 2026-10-28).** No performance numbers are claimed here; the FPS counter in test logs is not a benchmark.

## How to run
```
godot --path .                                   # play (Esc frees the mouse)
godot --headless --path . --import               # (re)import assets
godot --headless --path . --script res://godot/tools/verify_import.gd   # import rules check
godot --path . -- --frames=120 --quality=low --shot=out.png --log       # scripted run + screenshot
```
Test arguments (after `--`): `--quality=low|medium|high|ultra`, `--at=x,y,z`, `--yaw=r`, `--hold=moveForward,sprint`, `--press=jump@60`, `--frames=N`, `--shot=path.png`, `--log`.

## Parity checklist
| Web feature (game/src) | Godot | Status |
|---|---|---|
| Asset import, all 327 manifest GLBs | `godot/import/ck_post_import.gd` | **Done (M0).** Headless import: 0 errors; `verify_import.gd`: 0 failures |
| Z-up placeholders turned Y-up | post-import | Done |
| `*_COL` proxies → hidden StaticBody3D + BoxShape3D | post-import | Done (164 bodies) |
| Placeholder vertex colours → Owen's material PNGs (`render/materials.ts` rules) | post-import + `godot/materials/png_*.tres` (triplanar, 1 tile / 2 m) | Done |
| NPC vertex colours | post-import (`vertex_color_use_as_albedo`) | Done |
| Clip loop modes (CK_*, NPC_*, Gear_*) | post-import | Done |
| Gear `attach` extra | post-import → root meta `attach` (fallback `gadget_assets.json`) | Done |
| Input bindings (KeyboardEvent.code table, gamepad) | `godot/scripts/core/ck_input.gd` (autoload `CKInput`) | Done (M1); rebinding UI is M4 |
| Third-person controller: walk/run/sprint/jump/air/hard landing/crouch/glide/grapple-reel | `godot/scripts/actors/player.gd` (CharacterBody3D, feet origin) | **Done (M1).** Scripted test: run 6.7 m/s, jump, land, facade stop at 11.56 m, curb step-up |
| CR-X9 clip state machine, rate = speed / refSpeed, LOD switch (9 m / 26 m, LOW pinned to LOD1) | `godot/scripts/actors/hero.gd` | Done (M1) |
| Gear on sockets (`hold`), per-socket alignment cache | `hero.gd` `hold()` + BoneAttachment3D | Code ported; wired in M3 |
| Over-the-shoulder camera with collision | `godot/scripts/render/follow_camera.gd` (SpringArm3D) | Done (M1) |
| District: avenues, kit buildings (LOD1 > 64 m), skyline ring, street props, billboards, Citadel portal | `godot/scripts/world/district.gd` (chunked MultiMeshInstance3D, 40 m chunks) | Done (M1) |
| Street-light pool following the nearest working lamps | `district.gd` `update_lights()` | Done (M1) |
| Dynamic props (boxes, barrels, cones, pallets) | `district.gd` RigidBody3D | Done (M1); shove interaction is M3 |
| Night lighting, moon shadows, fog, rain, hero key light | `godot/scripts/render/stage.gd` | Done (M1) |
| LOW/MEDIUM/HIGH/ULTRA presets, auto-LOW on integrated GPUs | `godot/scripts/render/quality.gd` + `stage.apply_quality()` | Done (M1); settings menu is M4 |
| Red Citadel: *_COL physics, room visibility (30 m), Light_* pool from glTF extras, sliding doors, parked vehicles with far LOD | `godot/scripts/world/citadel.gd` | **Done (M2).** Walked elevator → corridor → Training door, and tunnel → hub |
| District ↔ Citadel transitions (portal E → Anchor_Arrival; Anchor_Exit E → portal), underground lighting, city hidden underground | `main.gd` `_interact()`, `stage.set_underground()` | Done (M2). The keycard check arrives with the inventory (M3) |

## Decisions
- **Godot's name-suffix import hints are off** (`nodes/use_name_suffixes=false`), because Godot would otherwise turn `*_COL` into visible trimesh colliders. The post-import script makes box colliders instead, matching the web build.
- **Embedded GLB textures are extracted** next to each GLB on import (Godot's default). They are VRAM-compressed with mipmaps, but they are generated copies, so they are git-ignored (`assets/models/**/*.png`, about 38 MB) and recreated on the first import.
- Owen's material PNGs (`assets/materials`) import VRAM-compressed with mipmaps. `config/asset_manifest.csv` is set to "keep", so Godot doesn't treat it as a translation table.
- Three files on disk differ in case from the manifest (`CRX1_interceptor.glb` and others). `CKData.model_path()` resolves the on-disk spelling, because exported builds are case-sensitive.
- Brightness factors in the material PNGs were lowered for Godot's lighting: concrete went from 1.6 to 0.9 and gunmetal from 1.3 to 1.1. At the web values, sidewalks rendered almost white.
- Godot has no auto-step like Rapier's character controller. The capsule rides over the sidewalk curbs anyway (tested). Higher steps would need a step-up pass.
- The player node's origin is at the feet (the web build used the capsule centre). The capsule shape is offset by half its height.
- The rain is a GPUParticles3D field of 6000 streaks (scaled by the preset), following the player.

- **Citadel asset fixes, applied at runtime in Godot:**
  - The hub's 16-segment wall-collider ring blocked both tunnel mouths (segments 4 and 12). `citadel.gd` drops those two colliders, and `tools/blender/ck_build_citadel.py` now skips them. The GLB has not been rebuilt yet.
  - The elevator shaft walls had no `*_COL`, so walking north from the arrival point fell into the void. `citadel.gd` adds box colliders for them.
  - Both bugs are also in the web build, which was left unmodified.
- The district ground collider is a 400 × 400 m slab. A WorldBoundaryShape3D is a half-space and pushed the Citadel (y −120) back up to street level.
- The Citadel light pool uses Blender light watts ÷ 8 as Godot energy, and underground uses a flat warm ambient. Both were tuned by eye.

## Proof screenshots
`docs/godot_shots/`: `m1_high.png` (HIGH, LOD0 hero by the Night Owl Diner billboard) and `m1_low_run.png` (LOW, running north on the avenue), `m2_citadel_hub.png` (Citadel hub with the armour statue) and `m2_training_door.png` (corridor door into the Training room).
