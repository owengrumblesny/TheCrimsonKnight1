# Asset audit & status (Part II, section A)

Per-file GLB numbers (meshes, triangles, UVs, rigs, clips, bounds) are generated into `ASSET_AUDIT.md` / `ASSET_AUDIT.json` at the project root by `python tools/audit_glb.py`. This table is the human status view. Quality levels: **concept** (2D art only) · **blockout** (primitive placeholder) · **procedural** (scripted model with real materials) · **rigged** · **game-ready**.

| Asset / family | Reference art | Existing model | Quality | Textures | Rig | Animations | Collider | LOD | Next action |
|---|---|---|---|---|---|---|---|---|---|
| CR-X9 Crimson Knight | boards A/B/C hero, helmet, armor (`assets/images/hero`) | `crimson_knight_CRX9_rigged.glb` (+ original 24-box blockout) | procedural, **rigged** | material PNGs as base colour + emissive | 41 bones incl. 5×4 cape | 22 `CK_*` clips (see ANIMATION_MAP) | capsule (physics.json) | none | Sculpt helmet/cowl to match boards; add the Part II clips listed as missing |
| CR-X1 Interceptor | X1 board, A/C vehicle crops | `CRX1_interceptor.glb` (10 boxes, named wheels) | blockout | none | n/a | none | none | none | M5: rebuild in Blender with wheel/steer/suspension pivots, door, modes |
| CR-B1 Batcycle | B1 board | `CRB1_batcycle.glb` (6 parts) | blockout | none | n/a | none | none | none | M5 |
| CR-A1 Specter | A1 board | `CRA1_specter.glb` (10 parts) | blockout | none | n/a | none | none | none | M5 |
| Gadget props (batarang, grapnel, scanner, drone, smoke, shield, beacon, power cell, medkit, projector, comms, wrist module, blade) | board gadget crops | `assets/models/gadgets/*_v01/v02.glb` | blockout | material PNGs by palette colour | n/a | none (equip uses hero clips) | box (dynamic where spawned) | none | Detailed display models + equip/inspect events |
| Fictional weapon props | board weapon crops | `energy_sidearm_prop`, `energy_blaster_prop`, `rocket_pod_prop` | blockout | palette PNGs | n/a | none | none | none | Display-only models; no combat planned yet |
| City architecture (buildings, roads, sidewalks, stairs, bridges…) | board environment crops | 63 `assets/models/architecture/*` | blockout | concrete / glass / asphalt PNGs | n/a | none | bounding boxes | none | M3 city kit: modular walls/windows/fire escapes, real colliders |
| Street props (75) & furniture (51) | board props crops | `assets/models/props|furniture/*` | blockout (cube/cylinder only) | palette PNGs | n/a | none | boxes; crates/barrels/cones/pallets dynamic | none | Rebuild with thickness/cavities (e.g. dumpster lid pivot) |
| NPC / enemy families | board NPC crops (15) | `civilian_dummy`, `security_bot`, `police_drone`, `training_dummy` + legacy v0.3 characters | blockout | palette PNGs | none | none | none | none | M6: shared humanoid rig + library |
| Red Citadel | Citadel overview/hangar/command/armory scenes | portal pad + ring in the district only | concept | cavern_stone on pad | n/a | none | pad box | none | M4: traversable cavern level |
| UI icons (67 + 26 keycaps) | — | `game/public/ui/assets` | **game-ready (2D)** | — | — | — | — | — | done (Part I) |
| Board cut-outs (423 + frames) | 9 boards | `assets/images/*` | 2D reference / UI art | — | — | — | — | — | done; re-slice if boards change |
| Audio | — | synthesized in `systems/audio.ts` | placeholder | — | — | — | — | — | Replace with licensed/original recordings |

Sources and licences: the 3D blockouts, material PNGs, boards and UI pack were supplied by Owen (generated with ChatGPT). Everything else is original procedural work in this repo. No third-party downloads are used.
