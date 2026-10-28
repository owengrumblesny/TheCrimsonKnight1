# Asset pipeline

All steps are scripted and reproducible from the project root (Blender 5.2 at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`).

| Step | Command | Output |
|---|---|---|
| Audit every GLB | `python tools/audit_glb.py` | `ASSET_AUDIT.md`, `ASSET_AUDIT.json` |
| Build the rigged CR-X9 | `blender -b --factory-startup --python tools/blender/ck_build_crx9.py` | hero GLB, `.blend`, `config/crx9_clips.json` |
| True six views + clip frames | `blender -b --factory-startup --python tools/blender/ck_render_views.py` then `python tools/make_contact_sheet.py` | `references/renders/crx9/` |
| Build CR-X9 v2 (current hero) | `blender -b --factory-startup --python tools/blender/ck_build_crx9_v2.py` | hero GLB with LOD0-2, sockets, finger bones |
| Build vehicles | `blender -b --factory-startup --python tools/blender/ck_build_vehicles.py` | `assets/models/vehicles/*`, `config/vehicle_assets.json` |
| Build the Red Citadel | `blender -b --factory-startup --python tools/blender/ck_build_citadel.py` | `red_citadel.glb`, `config/citadel_layout.json` |
| Build the city kit | `blender -b --factory-startup --python tools/blender/ck_build_citykit.py` | `assets/models/kit/*`, `config/citykit.json` |
| Build NPCs / enemies | `blender -b --factory-startup --python tools/blender/ck_build_npcs.py [-- type ...]` | `assets/models/npcs/*`, `config/npc_assets.json` |
| Build gadgets / weapons | `blender -b --factory-startup --python tools/blender/ck_build_gear.py [-- id ...]` | `assets/models/gear/*`, `config/gadget_assets.json` |
| Register built assets | `python tools/manifest_add.py config/npc_assets.json npcs npcs "<changelog line>"` (same for `gadget_assets.json gear gear`) | `config/asset_manifest.json` |
| Review renders | `ck_render_asset.py -- in.glb outdir` (6 views + hero shot); `ck_render_lineup.py -- out.png spacing clip|- a.glb b.glb …` | `references/renders/**` |
| Laptop benchmark | open `/?nolock&bench&quality=low&then=medium,high,ultra` in a visible window (dev server saves `docs/benchmarks/*.json`) | see `docs/PERFORMANCE.md` |
| Slice concept boards | `python tools/slice_boards.py` (spec: `config/board_slices.json`) | `assets/images/**`, `config/image_catalog.json`, overlays |
| Run the game | `cd game && npm install && npm run dev` | http://localhost:5173 |
| Unit tests | `cd game && npm test` | vitest |
| Production build | `cd game && npm run build && npm run preview` | `game/dist` (copies models, materials, images, icons) |
| Asset load test | open `/?test=assets` | `window.__CK_TEST__` (models + every PNG) |
| Scripted gameplay test | open `/?nolock`, drive `window.__CK__` (`advance`, `selectSlot`, `use`, `teleport`, `menus`) | — |

Conventions:
- Blender is Z-up with the character facing −Y; glTF export converts this to Y-up facing +Z.
- The asset manifest's `up_axis` tells the game which placeholders need a −90° X rotation.
- Every runtime asset id resolves through `config/asset_manifest.json` (models, textures, artwork) or `game/src/ui/data/icon_manifest.json` (UI icons).
- URLs are built from Vite's `BASE_URL`.
