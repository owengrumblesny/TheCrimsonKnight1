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

## Decisions
- **Godot's name-suffix import hints are off** (`nodes/use_name_suffixes=false`), because Godot would otherwise turn `*_COL` into visible trimesh colliders. The post-import script makes box colliders instead, matching the web build.
- **Embedded GLB textures are extracted** next to each GLB on import (Godot's default). They are VRAM-compressed with mipmaps, but they are generated copies, so they are git-ignored (`assets/models/**/*.png`, about 38 MB) and recreated on the first import.
- Owen's material PNGs (`assets/materials`) import VRAM-compressed with mipmaps. `config/asset_manifest.csv` is set to "keep", so Godot doesn't treat it as a translation table.
- Three files on disk differ in case from the manifest (`CRX1_interceptor.glb` and others). `CKData.model_path()` resolves the on-disk spelling, because exported builds are case-sensitive.
- Brightness factors in the material PNGs were lowered for Godot's lighting: concrete went from 1.6 to 0.9 and gunmetal from 1.3 to 1.1. At the web values, sidewalks rendered almost white.
