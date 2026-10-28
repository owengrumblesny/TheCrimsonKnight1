# Performance (target: Owen's laptop: Ryzen 5 7520U, Radeon 610M, 16 GB, 720p, 30 FPS)

Measured with the in-game harness (`game/src/testing/benchmark.ts`): six scenes, four presets, internal resolution 1280x720. GPU string: `ANGLE (AMD, AMD Radeon(TM) Graphics (0x00001506) Direct3D11 vs_5_0 ps_5_0, D3D11)`. Raw reports are in `docs/benchmarks/*.json`.

## Last measured run (before the city kit, NPCs and the `_COL`-skipping batch fix)
| Scene | LOW fps (draws) | MEDIUM fps (draws) | HIGH fps (draws) | ULTRA fps (draws) |
|---|---|---|---|---|
| CR-X9 character close-up | 31.5 (484) | 26.2 (541) | 30.4 (563) | 25.5 (566) |
| Red Citadel command center | skipped | skipped | skipped | skipped |
| Red Citadel vehicle hangar | skipped | skipped | skipped | skipped |
| New Gotham street | 34.4 (519) | 30.1 (539) | 34.9 (605) | 26.5 (614) |
| New Gotham rooftop | 37.7 (542) | 33.2 (581) | 33.6 (603) | 25.7 (607) |
| Dense city intersection | 47.7 (530) | 34.3 (559) | 29.9 (584) | 8.6 (589) |

The two Red Citadel scenes were skipped in that run because the Citadel did not exist yet. The re-run covers all six.

Reading: the scene is **draw-call bound**. ULTRA at the intersection collapses. LOW and HIGH hold about 30 fps in the close-up and street scenes. The rooftop and intersection scenes clear 30 fps on LOW.

## Changes since that run (NOT yet re-measured)
- Batching skips `*_COL` proxies, so invisible collider meshes no longer add draw calls or triangles.
- Kit buildings and props are instanced per material: one draw per material per asset type, whatever the instance count. Far buildings and the skyline use the merged LOD1 versions.
- NPCs: one skinned mesh and one material each (34 NPCs, about 34 draws plus the shadow pass), culled beyond 90 m, animation skipped beyond 60 m and throttled beyond 18 m.
- Dev-pane spot check (not a benchmark: the pane is hidden and throttled): the intersection view now issues about 460 draws and about 0.9M triangles per frame **including the shadow pass**. The kit raised the triangle load considerably. If the re-run shows HIGH below 30 fps, the first levers are no shadows on far LOD1 buildings and a smaller full-detail radius.

## Re-running the benchmark (needs a visible, unlocked window)
With the dev server running (`cd game && npm run dev`), run in PowerShell:

```powershell
Start-Process -FilePath 'C:\Program Files\Google\Chrome\Application\chrome.exe' -ArgumentList '--user-data-dir=C:\Users\oweng\AppData\Local\Temp\ck-bench-profile','--no-first-run','--window-size=1296,759','--app=http://localhost:5173/?nolock&bench&quality=low&then=medium,high,ultra'
```

Leave the window in front for about 3 minutes. Each preset's report is saved to `docs/benchmarks/`. A locked screen or a minimised window pauses rendering, and those numbers are invalid.
