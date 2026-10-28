# Handoff prompt: remake Crimson Knight: Earth-RED in Godot 4

Paste everything below the line into a new Claude Code chat opened in `C:\Users\oweng\OneDrive\Desktop\Crimson Knight 1`.

---

You are taking over **Crimson Knight: Earth-RED**, an open-world superhero sandbox by Owen Grumbles (Owen Enterprises). It currently runs in the browser on Three.js + TypeScript + Vite (`game/`). **Your job is to remake it as a native Godot 4 game** for better performance and graphics, reusing the existing asset library. Work in tested stages and commit locally after each milestone.

## Hard rules (from Owen, keep them)
- **Commit locally only. Never push.** Use `git -c user.name="Owen Grumbles" -c user.email="owengrumblesny@gmail.com" commit ...`. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Ask Owen before downloading anything**, including Godot itself. Godot is **not installed**. `winget` is available (`winget install GodotEngine.GodotEngine`, the latest stable 4.x). Say what and how big before downloading. GDScript needs no other SDK. C# would need the .NET SDK plus the Godot .NET build, so prefer **GDScript**.
- **Never upload Owen's art** (PNGs, boards, models) to third-party services.
- **Original IP only:** don't copy Batman or other existing assets, names or designs. "Arkham Knight style" means realism and quality, not copying.
- **Don't change system or security settings.** PowerShell's execution policy blocks `npm.ps1`, so use `npm.cmd`. Never enter or bypass the Windows PIN or lock screen. If the screen is locked, wait for Owen.
- **Keep the web version** (`game/`) working and unmodified as the reference implementation. Don't delete it.
- **Grade honestly:** BLOCKOUT / PROTOTYPE / GAME-READY / HERO, only after looking at real renders or screenshots. Benchmark before claiming performance.
- **Gameplay scope:** there is no grappling, gliding, driving, combat or AI yet. Port what exists first; new gameplay comes later and only when Owen asks.

## Targets
- **Laptop (must run):** Ryzen 5 7520U, Radeon 610M iGPU, 16 GB, 720p, **30 FPS on the LOW preset**.
- **Desktop (should look great):** realism-first presets (Owen chose "realism first, laptop LOD").
- Godot renderer: use **Forward+** with quality presets that scale on the laptop (3D render scale with FSR, shadow size and distance, SSAO/SSIL/SDFGI/volumetric fog off on LOW, MSAA off on LOW). Benchmark the **Mobile** renderer too (`--rendering-method mobile`) and report which is faster on the 610M.

## What already exists (read these first)
| Area | Where |
|---|---|
| Status and truth | `docs/PRODUCTION_TRUTH_AND_STATUS.md`, `docs/ASSET_AUDIT.md`, `docs/KNOWN_GAPS.md`, `docs/CLAUDE_DEVLOG.md` |
| Performance history | `docs/PERFORMANCE.md`, `docs/benchmarks/*.json` (Three.js numbers to beat) |
| Asset manifest | `config/asset_manifest.json`, 327 assets with ids, files, triangles, clips and sockets |
| 3D models (GLB, Y-up, metres, +Z forward in Three.js) | `assets/models/{characters,vehicles,citadel,kit,npcs,gear,props,architecture,furniture,gadgets}` |
| Materials / 2D art | `assets/materials/*.png` (Owen's PNGs), `assets/images/*` (board cut-outs), UI icons in `game/public/ui/assets` |
| Blender sources | `tools/blender/ck_build_*.py`, headless Blender 5.2 at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`. Rebuild models there, never by hand. |
| Game data | `config/{controls,physics,graphics,world,citadel_layout,citykit,npc_assets,gadget_assets,vehicle_assets,vehicle_specs,crx9_clips,animation_graph}.json` |

**Hero:** `assets/models/characters/crimson_knight_CRX9_rigged.glb` is **CR-X9 v3**, the realistic pass. It is a sculpted anatomy body with armour plates cut from it and baked 2K PBR maps.
- Skeleton: 68 bones, including fingers, a cape chain, and non-deforming sockets `Socket_Hand_R/L`, `Socket_Belt_R/L`, `Socket_Back` and `Socket_Head`.
- Clips: 22 `CK_*` clips. Loop flags and speeds are in `config/crx9_clips.json`.
- LODs: meshes named `*_LOD0/1/2`, switched by camera distance (9 m / 26 m). **LOD1 is the laptop LOD.** The LOW preset never shows LOD0.

## TypeScript systems to port (`game/src`, about 5k lines)
| TS file | Behaviour to reproduce in Godot |
|---|---|
| `actors/player.ts` (311) | Third-person character controller: walk, run, sprint, jump, airborne, hard landing, crouch. Values come from `config/physics.json`. Use `CharacterBody3D`. |
| `render/followCamera.ts` | Over-the-shoulder follow camera with collision. Use `SpringArm3D` + `Camera3D`. |
| `actors/hero.ts` (146) | Clip state machine over the `CK_*` clips (`config/animation_graph.json`) and LOD switching. `hold(modelId)` attaches `gear_*` models to the socket named in the GLB root extra `attach`. Alignment is `socketWorldQ⁻¹ * rootWorldQ`, cached per socket, so the muzzle points forward. Use `BoneAttachment3D`. |
| `world/district.ts` (356) | The New Gotham district: 2 avenues, kit buildings facade-to-facade at 11 m, LOD1 beyond 64 m, a skyline ring, street lights whose light pool follows the lamp heads, and street props. **Port as chunked `MultiMeshInstance3D` (about 40 m chunks so culling works).** Static colliders come from each asset's `*_COL` boxes. |
| `world/citadel.ts` (174) | The Red Citadel underground base: 22 `Room_*` groups, 16 door pivots, an elevator, and room-based visibility. |
| `world/npcs.ts` (162) | 34 ambient NPCs plus a patrol drone, idle-family clips only (**no AI**). Hidden beyond 90 m, animation off beyond 60 m and throttled beyond 18 m, shadows only within 30 m. |
| `systems/equipment.ts` (341) | Gadgets: batarang-style projectile `gear_batarang`, recon drone `gear_drone`, beacon `gear_beacon`, and so on. |
| `ui/*` (~1.5k) | HUD, hotbar, inventory, menus, settings, keybindings, vitals, loading screen and perf overlay, using the PNG UI pack in `game/public/ui/assets`. Rebuild with Godot `Control` scenes and themes. |
| `systems/audio.ts` | The audio is synthesized placeholders. Use `AudioStreamGenerator` or simple samples, following `docs/CRIMSON_KNIGHT_AUDIO_SETUP_FOR_CLAUDE.md`. |
| `render/quality.ts`, `render/stage.ts` | LOW/MEDIUM/HIGH/ULTRA presets (moon shadow range 16/26/34/45 m, rain, fog, light pool size), with auto-LOW on integrated GPUs. Night city lighting with a moon, sky and fog. |
| `testing/benchmark.ts` | Six scenes (CR-X9 close-up, Citadel command centre, Citadel hangar, street, rooftop, dense intersection) on 4 presets. Writes JSON reports to `docs/benchmarks/`. **Port this first-class.** It's how you prove Godot is faster. |

## Godot import gotchas (handle these in an `EditorScenePostImport` script)
- **Colliders:** `*_COL` meshes are collision proxies. Godot only auto-detects `-col` suffixes, so convert `*_COL` into `StaticBody3D` + `BoxShape3D` and hide them.
- **NPC vertex colours:** NPC GLBs (`npc_*`) store their colours as vertex colours. Enable `vertex_color_use_as_albedo` on their materials.
- **Animation loops:** set the loop mode per clip from `config/crx9_clips.json` (CR-X9) and the NPC and gear configs.
- **Gear sockets:** gear GLB roots carry an `attach` extra (glTF extras). Read it with `_import_scene` metadata, or fall back to `config/gadget_assets.json`.
- **Project layout:** put `project.godot` at the **repo root** so `res://assets/...` resolves without copying 226 MB. Add `.gdignore` files to `game/` (contains `node_modules`), `tools/`, `references/` and `docs/`.

## Milestones (commit after each, with a screenshot or benchmark as proof)
1. **M0:** Ask Owen to install Godot 4 stable. Create the project skeleton, import settings and the post-import script. All GLBs must import without errors, as checked by a headless import run.
2. **M1:** The CR-X9 walks, runs and jumps through the district with the follow camera, clips and LOD. Night lighting and fog.
3. **M2:** The Red Citadel is explorable (doors, elevator, room visibility), with district ↔ Citadel transitions.
4. **M3:** NPC crowd, gear on sockets, equipment gadgets, hotbar selection.
5. **M4:** The full UI pack: HUD, hotbar, inventory, menus, settings, keybindings, vitals.
6. **M5:** Quality presets plus the benchmark harness. Run all 6 scenes × 4 presets on the laptop (Forward+ and Mobile), compare with `docs/PERFORMANCE.md`, and record the results in a new `docs/PERFORMANCE_GODOT.md`.
7. **M6:** Graphics pass, desktop presets only: SDFGI or VoxelGI, SSR, volumetric fog, glow, wet streets. LOW keeps the 30 fps laptop target.

Keep a parity checklist (web feature → Godot status) in `docs/GODOT_PORT_STATUS.md`. Update `docs/CLAUDE_DEVLOG.md` at each milestone.
