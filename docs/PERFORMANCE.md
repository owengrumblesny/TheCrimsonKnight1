# Performance (target: Owen's laptop: Ryzen 5 7520U, Radeon 610M, 16 GB, 720p, 30 FPS)

Measured with the in-game harness (`game/src/testing/benchmark.ts`): six scenes, four presets, internal resolution 1280x720. GPU string: `ANGLE (AMD, AMD Radeon(TM) Graphics (0x00001506) Direct3D11 vs_5_0 ps_5_0, D3D11)`. Raw reports are in `docs/benchmarks/*.json`.

## Earlier run (before the city kit, NPCs and the `_COL`-skipping batch fix)
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

## 2026-10-28 runs (city kit, NPCs, gear in place)
Both runs were made with a YouTube video playing in another Chrome window, and Chrome's occluded-window throttling was disabled (`--disable-backgrounding-occluded-windows`), so they read low. Use them for comparison, not as absolute numbers.

**Before the culling fix:** about 900k triangles per frame. Every kit building type was one district-wide `InstancedMesh`, so it was never culled in either the main or the shadow pass. All 34 NPCs had `frustumCulled = false` and cast shadows.

| Scene | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| CR-X9 close-up | 13.2 | 11.4 | 11.3 | 9.5 |
| Citadel command | 47.5 | 32.9 | 27.9 | 24.6 |
| Citadel hangar | 58.5 | 46.2 | 55.3 | 47.2 |
| New Gotham street | 18.8 | 15.0 | 17.3 | 14.6 |
| New Gotham rooftop | 19.7 | 14.5 | 16.2 | 11.7 |
| Dense intersection | 24.5 | 23.1 | 21.7 | 16.8 |

**After the fix:** about 520–690k triangles. Changes:
- Instancing is split into 40 m chunks (150 m for the skyline), so frustum culling works.
- Far LOD1 lots cast no shadows.
- NPCs use a posed, padded cull sphere and cast shadows only within 30 m.

| Scene | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| CR-X9 close-up | 13.5 | 17.5 | 14.7 | 11.7 |
| Citadel command | 59.7 | 53.1 | 42.8 | 48.1 |
| Citadel hangar | 60.0 | 60.0 | 49.5 | 43.0 |
| New Gotham street | 31.6 | 21.5 | 19.9 | 15.6 |
| New Gotham rooftop | 26.8 | 17.4 | 14.2 | 12.8 |
| Dense intersection | 34.3 | 24.1 | 21.6 | 13.5 |

(The after-fix ULTRA column is `bench-ultra-1793200020794.json`. `bench-ultra-1793199817889.json` came from a page that hot-reloaded mid-run, so it is not used.)

CR-X9 v3 (2026-10-28) raised the hero to 132.7k / 47.4k / 14.3k triangles (LOD0/1/2) with 2K baked maps. LOW now caps the hero at LOD1 (`heroMinLod`). Not re-benchmarked: Owen asked for fewer benchmark runs, and the Godot port (`docs/GODOT_PORT_HANDOFF.md`) will re-measure.

LOW now meets 30 fps in the street and intersection scenes, and the Citadel meets it on every preset. The CR-X9 close-up and the rooftop scene are still below target.

## Re-running the benchmark (needs a visible, unlocked window)
With the dev server running (`cd game && npm run dev`), run in PowerShell:

```powershell
Start-Process -FilePath 'C:\Program Files\Google\Chrome\Application\chrome.exe' -ArgumentList '--user-data-dir=C:\Users\oweng\AppData\Local\Temp\ck-bench-profile','--no-first-run','--window-size=1296,759','--app=http://localhost:5173/?nolock&bench&quality=low&then=medium,high,ultra'
```

Leave the window in front for about 3 minutes. Each preset's report is saved to `docs/benchmarks/`. A locked screen or a minimised window pauses rendering, and those numbers are invalid.
