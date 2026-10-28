# Asset audit & status (Part II + Master Asset Directive)

Per-file GLB numbers (meshes, triangles, UVs, rigs, clips, bounds) are generated into `ASSET_AUDIT.md` / `ASSET_AUDIT.json` at the project root by `python tools/audit_glb.py`. This table is the human status view.

Grades follow the directive and were given **after visual review of the renders** in `references/renders/**`:
**BLOCKOUT** (primitive placeholder) · **PROTOTYPE** (scripted model, real materials, pivots/clips, reads correctly in-game, but not artist-finished) · **GAME-READY** (final for shipping at this art style) · **HERO** (sculpted, hand-textured showcase quality).

Nothing in this repository is graded HERO. Arkham-level hero quality needs an artist sculpt/texture pass (ZBrush/Substance or equivalent), and procedural Blender scripting does not reach it. The scripted models are built so that pass can replace meshes without touching the game: same names, pivots, sockets, anchors and clips.

| Priority | Asset / family | Files | Tris (LOD0) | Rig / pivots | Clips | Collision | LOD | Grade | Review render |
|---|---|---|---|---|---|---|---|---|---|
| 1 | CR-X9 Crimson Knight **v3 (realistic pass)** | `characters/crimson_knight_CRX9_rigged.glb` (v2 kept as `_v2`, v1 as `_v1`); 26.8 MB with embedded 2K maps | 132.7k | same 68-bone v2 skeleton, 6 sockets | 22 `CK_*` | capsule (physics.json) | LOD0/1/2 132.7k/47.4k/14.3k; LOD1 is the laptop LOD (LOW never shows LOD0) | PROTOTYPE+ (sculpted anatomy, plates cut from it, baked oxblood paint, edge wear and grime, padded kevlar undersuit; the cowl face is still crude, the cape is a flat sheet with folds, and there is no artist sculpt) | build preview via `ck_build_crx9_v3.py -- --preview` |
| 2 | CR-X1 Interceptor | `vehicles/crx1_interceptor.glb` + `_lod1` | see `config/vehicle_assets.json` | wheel/steer/suspension pivots, doors, canopy, battle panels, turret; seat/entry/exit/camera/summon anchors | 5 `CRX1_*` | `*_COL` boxes | LOD1 | PROTOTYPE | `references/renders/crx1_interceptor/`, `vehicles_v2.png` |
| 2 | CR-B1 Batcycle | `vehicles/crb1_batcycle.glb` + `_lod1` | ″ | steer, swingarm, kickstand, wheels | 4 `CRB1_*` | `*_COL` | LOD1 | PROTOTYPE | `references/renders/crb1_batcycle/` |
| 2 | CR-A1 Specter | `vehicles/cra1_specter.glb` + `_lod1` | ″ | elevons, rudders, VTOL pods, gear | 5 `CRA1_*` | `*_COL` | LOD1 | PROTOTYPE | `references/renders/cra1_specter/` |
| 3 | Red Citadel | `environment/red_citadel.glb` | 118.6k | 22 `Room_*` groups, 16 door pivots, elevator, light points, anchors, founder statue | — (runtime doors) | `*_COL` boxes | room visibility | PROTOTYPE (functional explorable level) | in-game review (`window.__CK__.citadel`) |
| 4 | New Gotham city kit (36) | `kit/kit_*.glb`; buildings + `_lod1` | towers 4.8–11.8k; props 80–3.8k | dumpster lid pivot | `DumpsterLidOpen` | `*_COL` per asset (used as physics) | buildings LOD1 + skyline ring | PROTOTYPE (buildings, containers); GAME-READY at this stylised level for small street props | `references/renders/kit/` |
| 5 | NPC / enemy families (14 humanoids) | `npcs/npc_*.glb` | 2.0–3.4k | CR-X9 skeleton (no cape), sockets via hand/head bones | `NPC_Idle/Walk/Alert/Cower/Talk` | static box in world | single (1 draw call each) | PROTOTYPE (stylised mannequins with uniforms; no faces) | `references/renders/npcs/lineup.png` |
| 5 | Patrol drone | `npcs/npc_patrol_drone.glb` | 2.1k | 4 rotor pivots, camera gimbal | `NPC_DroneHover/Scan` | none | — | PROTOTYPE | — |
| 6 | Gadgets (13) + fictional energy weapons (5) | `gear/gear_<itemId>.glb` | 112–1,420 | grip origin, `attach` socket extra, Muzzle/Emitter/OffHand/Tip anchors, moving-part pivots | `Gear_Deploy/Fire/Idle` | none (visual) | — | PROTOTYPE | `references/renders/gear/` |
| 7 | Legacy ChatGPT blockouts (architecture, props, furniture, v0.3 characters) | `assets/models/{architecture,props,furniture,…}` | — | — | — | bounds | — | BLOCKOUT (kept for reference; the district now uses the kit) | — |
| — | UI icons (67 + 26 keycaps) | `game/public/ui/assets` | — | — | — | — | — | GAME-READY (2D) | — |
| — | Board cut-outs (423 + frames) | `assets/images/*` | — | — | — | — | — | 2D reference / UI art | — |
| — | Audio | synthesized in `systems/audio.ts` | — | — | — | — | — | placeholder | — |

In-game hookups:
- **District:** the kit buildings sit facade-to-facade on both avenues, using LOD1 beyond 64 m plus a LOD1 skyline ring. It also has kit street lights (the light pool follows the lamp heads), traffic lights, crosswalks, manholes and drains, trees, sidewalk props, a dumpster alley, an industrial yard, and dynamic boxes, cones, pallets and toolboxes.
- **NPCs:** `game/src/world/npcs.ts` places 34 NPCs plus the drone, idle only, with **no AI** (per the directive). Their mixers are skipped beyond 60 m and throttled to 10 Hz beyond 18 m.
- **Gear:** every gadget and weapon item's `modelId` in `inventoryData.ts` is now `gear_<itemId>`. Selecting a hotbar slot shows the model on its CR-X9 socket (`Hero.hold`). The batarang projectile, recon drone and beacon use the new models.

Sources and licences: the material PNGs, boards, UI pack and original blockouts were supplied by Owen (generated with ChatGPT). Everything else is original procedural work in this repo. No third-party downloads are used, and nothing copies Batman or any other existing IP.
