# Godot 4 port: status and parity checklist

The Godot port lives beside the web build. `project.godot` sits at the repo root so `res://assets/...` and `res://config/...` resolve in place; Godot code is in `godot/`. The web reference build in `game/` is untouched and ignored by Godot (`game/.gdignore`).

- Engine: **Godot 4.7.2 stable** (standard build, GDScript only), installed with winget as a portable app under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*`.
- Renderer: Forward+. Physics: Jolt (built in), 60 Hz, physics interpolation on.
- **Performance:** measured on the target laptop in `docs/PERFORMANCE_GODOT.md`. LOW holds 41–96 fps across the six benchmark scenes (target 30); MEDIUM is about 30.

## Where it stands (2026-10-28)
| Milestone | Status | Grade |
|---|---|---|
| M0 project + import pipeline | Done (`cbfcf11`) | n/a (all 326 GLBs import with 0 errors) |
| M1 CR-X9 in the district | Done (`8713445`) | PROTOTYPE |
| M2 Red Citadel + transitions | Done (`63e9771`) | PROTOTYPE |
| M3 NPCs, gear sockets, gadgets, hotbar | Done (`c2f1719`) | PROTOTYPE |
| M4 UI pack | Done (`59dd70d`) | PROTOTYPE |
| M3.5 guns + drivable vehicles | Done (`87d64d7`, `9571842`) | PROTOTYPE |
| M5 benchmark harness + laptop optimisation | Done; see `docs/PERFORMANCE_GODOT.md` | LOW meets target |
| M6 desktop graphics | Done (`c063c08`) | PROTOTYPE |
| Audio | Done (`904ce35`) | PROTOTYPE (not listened to) |

Everything in the handoff is ported, along with guns and drivable vehicles, which Owen added on top. Nobody has played the port by hand yet; every check so far was scripted (`--hold`/`--press`) or headless.

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
| NPC crowd: 34 NPCs + patrol drone, idle-family loops (no AI), hidden > 90 m, anim off > 60 m, ~10 Hz > 18 m, shadows < 30 m | `godot/scripts/world/npcs.gd` (same mulberry32 layout as the web) | **Done (M3)** |
| Inventory / hotbar state, restock, cooldowns, save snapshot | `godot/scripts/systems/inventory.gd`, catalog in `godot/data/items.json` | Done (M3) |
| Hotbar selection: 1-8, Q/R, wheel; equip clip and gear on the socket | `main.gd` `select_slot()`, `hero.hold()` | Done (M3). Grapnel verified at `Socket_Hand_R` |
| Gadgets: batarang, grapnel, scanner, drone, smoke, shield, cloak, beacon, EMP, sonic, helmet lamp, power cell, med kit, repair, photo mode | `godot/scripts/systems/equipment.gd` | Done (M3). Scripted use of batarang, scanner (16 props found), shield and drone, plus the cooldown refusal |
| Vitals (health/armour/energy, impact damage, regen, critical recall) | `godot/scripts/systems/vitals.gd` | Done (M3) |
| Landing / gadget effects from the board sprites, radial tile-border mask | `godot/scripts/render/effects.gd`, `godot/shaders/effect_sprite.gdshader` | Done |
| Shove props (E), keycard check on the Citadel portal, vehicle call message | `main.gd` `_interact()`, `_gameplay_input()` | Done (M3) |
| HUD: vitals with helmet portrait, compass, notifications (max 4, fade), selected-item card, crosshair (aiming / batarang / grapnel), interact prompt with UI-pack keycaps | `godot/scripts/ui/hud.gd` | **Done (M4)** |
| Hotbar: 8 slots, circle icons, live key labels, quantities, N/A badges, cooldown sweeps, click to select, flash on key | `hud.gd` | Done (M4) |
| Main menu, pause, inventory (tabs, search, sort, cards, detail, Equip, assign 1-8), map (district geometry + locations gallery), equipment loadout, settings | `godot/scripts/ui/menus.gd`, `map_view.gd`, theme in `ck_ui.gd` | Done (M4). Menus pause the tree |
| Settings: quality preset, fullscreen, audio levels (saved), UI scale, Show HUD, reduce motion, key rebinding with swap, reset | `menus.gd` | Done (M4). Reduce motion is saved but has no effect yet (the web used it for CSS transitions) |
| Save / Continue / New Sandbox / autosave every 30 s; settings + bindings saved separately | `godot/scripts/systems/save_service.gd` (user://, same JSON shape as the web) | Done (M4) |
| Perf overlay (F3) | `main.gd` | Done (M4), as a plain readout of fps, draws and primitives. Not a benchmark |
| Loading screen: cycling board art, step label, progress bar, idle key-pose flipbook | `godot/scripts/ui/loading_screen.gd` | Done |
| Animation debug panel (`): loop any CK_* clip on the Knight beside its board key-pose flipbook | `godot/scripts/ui/anim_debug.gd` | Done |
| Desktop graphics (M6): wet streets with puddles (near-mirror roughness) and animated ripples; SSR, volumetric fog (lamp halos), glow on HIGH/ULTRA; SDFGI + SSIL + TAA on ULTRA | `godot/shaders/wet_asphalt.gdshader`, `quality.gd`, `stage.gd` | **Done (M6).** LOW keeps the puddle mask with ripples off and no SSAO/SSR/SDFGI/volumetric fog/MSAA |
| Guns (Godot only, Owen's request): sidearm and carbine (hitscan), launcher and cannon (splash projectiles), blade (melee); muzzle flash, tracers, decals, recoil, ammo/reload (T), RMB over-the-shoulder aim, hit marker, 6 target dummies | `godot/scripts/systems/weapons.gd`, `godot/data/weapons.json`, `world/targets.gd` | **Done (M3.5a).** Each weapon tested against dummies |
| Drivable vehicles (Godot only): CR-X1 car and CR-B1 bike (VehicleBody3D, bike auto-balance and lean), CR-A1 jet (arcade flight + VTOL); V summon, E/F enter and exit, first-person default with head-bob and FOV kick, V chase cam, B modes (car pursuit/battle/stealth, bike pursuit/stealth, jet flight/vtol/stealth: clips, top speed, emissives, engine volume), engine sound | `godot/scripts/vehicles/vehicle.gd`, `drive_controller.gd`, `godot/data/vehicles.json` | **Done (M3.5b).** Car reached its 224 km/h cap; bike stays upright turning at 120 km/h; jet takes off and climbs in VTOL. Per-mode GLB/material swaps read from config, ready for the vehicle-modes models |
| Benchmark harness (6 scenes × 4 presets), Forward+ vs Mobile | `godot/scripts/testing/benchmark.gd` (`--bench`) | **Done (M5).** Forward+ beats Mobile on the 610M; district meshes merged by material and chunked (draws about 4× lower) |
| Audio: the 13 synthesized placeholder sounds, rain ambience loop ducked under menus, per-category buses following the volume settings, footsteps | `godot/scripts/systems/audio.gd` (pre-rendered AudioStreamWAV, same recipes as the web) | Done. Checked headlessly (every event non-silent, buses exist); not listened to |

## Decisions
- **Godot's name-suffix import hints are off** (`nodes/use_name_suffixes=false`), because Godot would otherwise turn `*_COL` into visible trimesh colliders. The post-import script makes box colliders instead, matching the web build.
- **Embedded GLB textures are extracted** next to each GLB on import (Godot's default). They are VRAM-compressed with mipmaps, but they are generated copies, so they are git-ignored (`assets/models/**/*.png`, about 38 MB) and recreated on the first import.
- Owen's material PNGs (`assets/materials`) import VRAM-compressed with mipmaps. `config/asset_manifest.csv` is set to "keep", so Godot doesn't treat it as a translation table.
- Three files on disk differ in case from the manifest (`CRX1_interceptor.glb` and others). `CKData.model_path()` resolves the on-disk spelling, because exported builds are case-sensitive.
- Brightness factors in the material PNGs were lowered for Godot's lighting: concrete went from 1.6 to 0.9 and gunmetal from 1.3 to 1.1. At the web values, sidewalks rendered almost white.
- Godot has no auto-step like Rapier's character controller. The capsule rides over the sidewalk curbs anyway (tested). Higher steps would need a step-up pass.
- The player node's origin is at the feet (the web build used the capsule centre). The capsule shape is offset by half its height.
- The rain is a GPUParticles3D field of 6000 streaks (scaled by the preset), following the player.

- **Citadel asset fixes, now in the asset:** `tools/blender/ck_build_citadel.py` skips the two hub ring-wall colliders that blocked the tunnel mouths, and adds colliders to the elevator shaft walls (the arrival walk north used to fall into the void). The GLB was rebuilt, so `citadel.gd` no longer patches either at runtime. The rebuild also picked up the current CR-X9 v3 for the hub's armour statue. That raised the Citadel from 118.5k to 143.8k triangles and the GLB from 7.6 MB to 22 MB. The Citadel benchmark scenes still run 64–73 fps on LOW. The web build loads the same GLB, so its download is larger too.
- The district ground collider is a 400 × 400 m slab. A WorldBoundaryShape3D is a half-space and pushed the Citadel (y −120) back up to street level.
- The Citadel light pool uses Blender light watts ÷ 8 as Godot energy, and underground uses a flat warm ambient. Both were tuned by eye.

- The item catalog is exported from `game/src/ui/inventoryData.ts` to `godot/data/items.json` with the web build's own esbuild (`godot/tools/export_web_data.sh`), so both builds share the same values. `icon_manifest.json`, `hotbar_layout.json` and `menu_spec.json` are copied the same way.
- **Stray input in test runs (explained):** windowed test runs pop up and take keyboard focus, so someone typing on the PC was typing into the game. Logged move vectors showed W/A/D input, and one ULTRA screenshot showed a drone launch and a slot-7 refusal that the script never sent. Since M6, scripted runs (`--frames`) unbind every real key, button and pad (`--hold` and `--press` drive actions directly), and test windows are opened at `--position 3000,2000`. The earlier "phantom drift" in M2/M3 was this, not a game bug.

- The UI is built in code from Control nodes with one shared Theme (`CKUI.theme()`) whose colours come from `game/src/ui/ui.css`. Icons load from `CRIMSON_KNIGHT_UI_PACK/`, which is identical to the web build's `public/ui`.
- Godot 4 gotcha: `set_anchors_preset()` keeps a zero-size control at zero size. UI code uses `CKUI.place()` (explicit anchors and offsets) or `set_anchors_and_offsets_preset()`.
- Logic tests: `godot --headless --path . --script res://godot/tools/test_logic.gd` covers inventory, vitals, rebinding and the item → icon/model/art links (99 checks pass, including the synthesized sounds).
- Scripted `--press` now sends real InputEventActions, so menu hotkeys can be tested too. They take effect on the next frame.

- The Knight's head pokes through the CR-X1 roof in the chase cam (the placeholder cabin is low); first person hides the hero anyway. The Specter lands on the open plaza north of the Citadel entrance, because its 28.7 m wingspan doesn't fit the 22 m avenues. The world is a 400 m slab, so flying or driving past ±200 m leaves the ground.

## Proof screenshots
`docs/godot_shots/`: `m1_high.png` (HIGH, LOD0 hero by the Night Owl Diner billboard) and `m1_low_run.png` (LOW, running north on the avenue), `m2_citadel_hub.png` (Citadel hub with the armour statue) `m2_training_door.png` (corridor door into the Training room), `m3_npcs_intersection.png` (police officer and civilians, vertex-coloured NPCs) and `m3_grapnel_front.png` (grapnel selected), `m4_*.png` (main menu, in-game HUD, portal prompt, inventory, settings, map, loadout), and `m6_{low,high,ultra}_wet_street.png` (the same viewpoint on three presets).
