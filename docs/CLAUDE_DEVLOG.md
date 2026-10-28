# Crimson Knight: Earth-RED — Claude development log

Project creator: Owen Grumbles · Original asset pack: ChatGPT · Development: Claude

---

## Milestone M0 + M1 (+ start of M2) — 2026-10-27

### Audit findings (see `ASSET_AUDIT.md`, regenerate with `python tools/audit_glb.py`)
- 245 unique GLBs in `assets/models` + 64 in `legacy_v03/models`; all parse. **0 had a rig, animation clip, UV set, normals or glTF material** — all are trimesh exports with vertex colours only.
- The manifest claimed 257 assets but listed 12 character files twice (245 unique). Fixed (schema 1.1); original kept as `config/asset_manifest.v0.4_original.json`.
- Up-axis is mixed: procedural placeholders are **Z-up**, the CR-X9 and vehicle blockouts are **Y-up**. Every manifest entry now has an explicit `up_axis`.
- The original CR-X9 blockout is 24 eight-vertex boxes, ~4.3 m tall (helmet top), facing −Z. Used as a proportion/part reference only; it is untouched and imported beside the new model in the `.blend`.
- `assets/materials/*.png` are ~1.9 KB solid-colour cards, not PBR maps; the hero uses PBR material factors instead.

### What was built
| Area | Files |
|---|---|
| CR-X9 builder (Blender 5.2, scripted, reproducible) | `tools/blender/ck_build_crx9.py` |
| Rigged + animated hero GLB | `assets/models/characters/crimson_knight_CRX9_rigged.glb` (2.6 MB, ~19k tris, 41 bones, 22 clips) |
| Editable source | `assets/source/blender/crimson_knight_CRX9_rigged.blend` |
| Clip metadata (duration, loop, refSpeed) | `config/crx9_clips.json` |
| True six-view renders + clip frame sheets | `tools/blender/ck_render_views.py`, `tools/make_contact_sheet.py` → `references/renders/crx9/` |
| GLB auditor | `tools/audit_glb.py` → `ASSET_AUDIT.md/.json` |
| Game (Three.js + Rapier + Vite, strict TS) | `game/src/{core,data,render,actors,systems,world,ui,testing}` |

**Hero model:** skinned black undersuit (Skin-modifier body, bone-heat weights, 0 unweighted verts), rigid crimson armor plates each weighted 100% to one bone (plates rotate, never bend), long-eared helmet with narrow red emissive eyes, Owen Enterprises chest emblem with emissive core, forearm fins, wrist module, belt, skinned cape on 5×4 cape bones. Height 1.95 m to the helmet crown (ears to 2.08 m), feet at y=0, faces +Z in Three.js.

**Clips (22, all `CK_*`):** Idle, Walk, Run, Sprint, StrafeLeft/Right, CrouchIdle, CrouchWalk, JumpStart, Airborne, LandSoft, LandHard (three-point hero landing), GrappleAim, GrapplePull, Glide, GadgetDraw/Stow, Summon, VehicleEnter/Exit, Drive, Interact. Locomotion uses planted-foot leg IK solved in Python and baked to FK, with heel-strike / toe-off foot roll; the game sets playback rate = speed ÷ `refSpeed` to keep feet planted.

**Game slice:** rainy night New Gotham crossroads built from manifest placeholders (instanced roads, sidewalks, building rows, street lights with real point lights, street furniture, parked cars, 28 dynamic crates/barrels/cones you can shove), Red Citadel portal marker at `world.json` coordinates, third-person camera, Rapier kinematic character controller at fixed 60 Hz with interpolation, and an animation state machine covering every clip above. Controls are from `config/controls.json` (added `crouch`=C and `walkToggle`=CapsLock); a gamepad works too.

### Verified (actually run)
- Blender build runs headless in ~16 s; the exported GLB re-imports cleanly and renders all 22 clips (`references/renders/crx9/contact_clips_*.png`).
- `npm run build` (tsc strict + Vite) passes.
- `?test=assets` loads **246/246** manifest assets through the game registry in both `npm run dev` and the production build; the hero has SkinnedMesh + 41 bones + all 22 expected clips.
- In-browser state test via `__CK__.advance()`: idle → run (6.7 m/s) → sprint (9.2 m/s); jump → air → land; 14 m fall → LandHard → recover; 4 m drop → LandSoft; glide at 8.9 m/s with slowed fall; crouch/crouch-walk; summon; gadget draw; aim, aim-strafe and backpedal; walk toggle. No console errors.

### Changed config values
- `physics.json` `player.walkSpeed` 3.2 → 1.8 (3.2 m/s is a jog and made the walk cycle slide). Added `glideFallSpeed`, `hardLandingSpeed`.
- `animation_graph.json`: `clipsStatus` now points at the baked GLB; added `clipMap` from graph names to `CK_*` clips.
- `missing_production_assets.json`: rigged + animated CR-X9 moved to `produced_by_claude_m1`, with caveats.

### Honest limitations
- The hero is **procedural hard-surface art**, a big step up from the boxes but not photoreal. It has no texture maps yet (box-projected UVs are in place for them).
- Clips are hand-authored procedural keyframes, **not motion capture**. They're good for gameplay testing; hero moments (landing, summon) would benefit from manual polish in Blender.
- The cape is bone-animated per clip. There's no runtime cloth or spring sim yet (M2), and it can clip the legs during sprint and seated poses.
- Vehicle enter/exit are generic clips; vehicles aren't drivable yet (M5). Grapple has animation but no line/pull physics yet.
- City colliders are bounding boxes; buildings are untextured placeholders.

### How to run
```
blender -b --factory-startup --python tools/blender/ck_build_crx9.py      # rebuild hero GLB + .blend + clip json
blender -b --factory-startup --python tools/blender/ck_render_views.py    # six views + clip frames
python tools/make_contact_sheet.py && python tools/audit_glb.py
cd game && npm install && npm run dev                                      # http://localhost:5173  (?test=assets for the load test)
```

### Next concrete tasks
1. **Runtime cape:** spring-chain secondary motion on the `Cape_*` bones layered over clips, plus collision spheres for legs and hips.
2. **Hero polish pass in Blender:** sculpted helmet/cowl shape, armor panel lines via normal map, real undersuit texture; author `CK_TurnInPlace` and run-stop/start transitions.
3. **Grapple:** raycast target, rope line, pull along a spline using GrappleAim → GrapplePull → Airborne.
4. **M5 vehicles:** rebuild Interceptor/Batcycle/Specter with named wheel pivots and `seat_attach`/`entry_anchor`/`exit_anchor` empties (same scripted Blender approach), then a Rapier raycast vehicle.
5. **M3/M4:** replace bounding-box building colliders; first traversable Red Citadel interior.

---

## Using Owen's PNGs — 2026-10-27

**Concept boards are asset sheets.** `tools/slice_boards.py` cuts every labelled panel out of the boards in `references/original_images` at native resolution, using the crop spec in `config/board_slices.json`. It writes **423 images (+ animation frames)** to `assets/images/{hero,animations,vehicles,gadgets,world,npcs,props,effects,textures,ui}` and catalogs them in `config/image_catalog.json`. Crop boxes are drawn on each board in `references/renders/board_overlays/` for checking. (The `v03_*` boards are byte-identical copies, so they were not sliced twice.)

| Where | PNGs used |
|---|---|
| Hero GLB | `assets/materials` crimson_metal / black_rubber / gunmetal / red_emissive embedded as base-colour (+ emissive) maps |
| City | every placeholder mesh re-materialled with the material PNG matching its palette colour (concrete, glass, gunmetal, crimson_metal, red_emissive, black_rubber); wet_asphalt ground; cavern_stone at the Red Citadel portal |
| HUD | `ui/icons` meters, compass, weather and action bar; helmet portrait from the board |
| Gadget menu (Q) | 12 gadget cut-outs; the equipped gadget shows in the Q slot |
| Summon menu (V) | CR-X1 / CR-B1 / CR-A1 showcase + 3 mode images each |
| Pause → Suit | turnaround, helmet views, armor close-ups, suit display scene |
| Pause → Locations | 15 New Gotham + Red Citadel images |
| Billboards / portal | vehicle and city cut-outs; Citadel entrance + command centre holo panels |
| Loading screen | cycling city/Citadel/suit scenes + idle key-pose flipbook |
| Animation debug (`) | each CK_* clip shows its board key-pose frames as a flipbook (`animation_graph.json` → `referenceImages`) |
| Effects | sparks / debris / smoke / electrical sprites on landings |

Verified: `?test=assets` loads 246/246 models and 613/613 images in dev and production builds; menus, flipbook, gadget equip and landing effects checked in the browser.

Limits: board cut-outs are small (gadgets ~60 px, key-pose frames ~25×60 px, environment tiles 100–350 px), so they work as UI, billboard and reference art but are too small to serve as 3D texture maps. That includes the "texture maps" swatches (~50 px). NPC and prop cut-outs are catalogued for when those models are built.

---

## Master Asset Directive, priorities 4–6 — 2026-10-27

- **New Gotham city kit in the district** (`world/district.ts`): kit buildings facade-to-facade on both avenues, LOD1 beyond 64 m and a 48-building LOD1 skyline ring. Kit street lights, with the light pool following the rotated lamp heads; traffic lights, crosswalks, signs, manholes, drains, trees, sidewalk props, a dumpster alley, an industrial yard (a stacked container uses the new `Placement.y`), and dynamic kit boxes, cones, pallets and toolboxes. Static physics now comes from each asset's `*_COL` proxies.
- **NPC / enemy families** (`tools/blender/ck_build_npcs.py`): 14 humanoids on the CR-X9 skeleton (cape chain removed) plus a patrol drone. Each NPC is one skinned mesh with one vertex-colour material (palette baked from slot colours), 2.0–3.4k tris, with clips NPC_Idle/Walk/Alert/Cower/Talk. `world/npcs.ts` places 34 of them plus the drone, idle only (**no AI**, per the directive), with distance-throttled mixers. Lineup review: `references/renders/npcs/lineup.png`. Fixed after review: heads enlarged, hair region widened.
- **Gadgets & fictional weapons** (`tools/blender/ck_build_gear.py`): 18 models `gear_<itemId>` with grip origins, a socket `attach` extra, Muzzle/Emitter/OffHand/Tip anchors, moving-part pivots and Gear_Deploy/Fire/Idle clips. Inventory `modelId`s are re-linked to them. `Hero.hold()` shows the selected item on its CR-X9 v2 socket bone, with alignment derived per socket from the idle pose. Review: `references/renders/gear/`.
- **Tooling:** `tools/manifest_add.py` (registers build configs into the manifest, now 327 assets), `tools/blender/ck_render_lineup.py` (side-by-side review sheets).
- **Tests:** `tests/assets.test.ts` checks the item→model links, the gear sockets, and NPC registration/budget (22 tests pass); `tsc` and `npm run build` are clean.
- **Not done:** the laptop re-benchmark with the kit, NPCs and batching fix. The run was started, but Windows was on its lock screen, which pauses the page's rendering. See `docs/PERFORMANCE.md` for the command.


## 2026-10-28: culling fix, CR-X9 v3 realistic pass, Godot handoff
- Benchmark (Radeon 610M): city scenes regressed to ~900k triangles per frame (district-wide InstancedMeshes were never culled, and NPC frustum culling was off). Fixed with chunked instancing, no far-LOD shadows, and NPC cull spheres plus distance shadows. LOW street/intersection now 31.6/34.3 fps. See PERFORMANCE.md.
- Owen asked for Arkham Knight-style realistic assets, starting with the hero, realism first with a laptop LOD. `tools/blender/ck_build_crx9_v3.py`: anatomy built from about 70 muscle volumes (voxel union plus a morphological closing), armour plates cut from that surface with real thickness, relaxed outlines and bevelled rims, a sculpted cowl with carved eye sockets and raked blade fins (kept clear of bat ears) and a crest, and a projected chest emblem. Cycles bakes AO, edge, grime, scratch and normal passes, combined in numpy into 2K base/MR/normal maps. Same skeleton and clips. Build time is about 6 minutes.
- Game: `heroMinLod` preset field; LOW pins the hero to LOD1.
- Owen wants the game remade in Godot 4 for native performance. The handoff prompt is in `docs/GODOT_PORT_HANDOFF.md`.
