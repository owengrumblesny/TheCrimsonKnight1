# Godot port performance (target: Owen's laptop, Ryzen 5 7520U, Radeon 610M, 720p, 30 fps on LOW)

Measured on the target laptop itself with the in-game harness (`godot/scripts/testing/benchmark.gd`). It runs the same six scenes as the web harness, with V-Sync off, 1.5 s of warm-up (4.5 s for the first scene, which absorbs pipeline compilation) and 5 s measured per scene. The window was 1280×720 and GPU reported as "AMD Radeon(TM) Graphics" (Vulkan). Raw reports are in `docs/benchmarks/godot-*.json`.

```
godot --path . --resolution 1280x720 -- --bench --quality=low
godot --rendering-method mobile --path . --resolution 1280x720 -- --bench --quality=low
```

Caveats: the runs were made while the PC may have been in use (the test window sits off-screen and real input is ignored), the battery and power state are unknown, and run-to-run noise is roughly ±10–15 %. Treat these as comparisons, not lab numbers.

## Final presets (2026-10-28), Forward+, average fps (1 % low frame time)
| Scene | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| CR-X9 close-up | **40.7** (32 ms) | 29.2 (45 ms) | 11.1 | 2.9 |
| Citadel command | **75.2** (24 ms) | 59.7 (24 ms) | 31.5 | 1.7 |
| Citadel hangar | **95.8** (16 ms) | 64.5 (18 ms) | 33.2 | 1.8 |
| New Gotham street | **50.5** (27 ms) | 38.2 (36 ms) | 13.0 | 1.9 |
| New Gotham rooftop | **65.5** (25 ms) | 35.5 (49 ms) | 12.5 | 1.7 |
| Dense intersection | **44.6** (34 ms) | 29.8 (48 ms) | 11.1 | 2.4 |

The HIGH and ULTRA columns were measured before the MEDIUM retune, with the same district optimisations. Those two presets weren't changed afterwards.

- **LOW meets the 30 fps laptop target in every scene, with a 41 fps minimum.** It beats the web build's best LOW run (13.5 / 59.7 / 60.0 / 31.6 / 26.8 / 34.3 fps, `docs/PERFORMANCE.md`) in every scene.
- **MEDIUM is the "average laptop" preset:** glow, FXAA, 2-split shadows, 4 street lights and the LOD1 hero. It is about 30 fps on the 610M, so a laptop with a faster iGPU or an entry dGPU should run it comfortably. That last point is inferred, not measured.
- **HIGH and ULTRA are desktop presets.** ULTRA's SDFGI/SSIL/TAA are unplayable on an integrated GPU, as expected. Auto-detect keeps integrated GPUs on LOW.

## Forward+ vs Mobile renderer, LOW
| Scene | Forward+ | Mobile |
|---|---|---|
| CR-X9 close-up | 40.7 | 20.2 |
| Citadel command | 75.2 | 47.3 |
| Citadel hangar | 95.8 | 59.8 |
| New Gotham street | 50.5 | 41.0 |
| New Gotham rooftop | 65.5 | 38.5 |
| Dense intersection | 44.6 | 40.1 |

Forward+ is faster on the Radeon 610M in every scene, even though Mobile issues fewer draw calls (about 300 against 750–950). **Forward+ stays the default.**

## What changed between the first and final LOW runs
| Scene | First port run | After merge | After chunking, final |
|---|---|---|---|
| CR-X9 close-up | 29.1 | 30.3 | 40.7 |
| Citadel command | 61.3 | 74.0 | 75.2 |
| Citadel hangar | 74.4 | 93.5 | 95.8 |
| New Gotham street | 29.6 (3016 draws) | 45.8 (753) | 50.5 |
| New Gotham rooftop | 38.3 | 57.3 | 65.5 |
| Dense intersection | 17.9 (1888 draws) | 39.5 (606) | 44.6 |

1. **Merging by material** (`district.gd` `_merge`): each kit asset's sub-meshes are combined into one mesh with one surface per material, plus generated LODs, before instancing. The first port drew every part as its own MultiMesh (an apartment block has 200+ parts), which made the city draw-call bound. Draw calls fell about 4×.
2. **Chunking every repeated asset** (48 m by default) so off-screen props are culled in both the main and shadow passes.
3. **Longer first-scene warm-up** in the harness. The first close-up run's 104 ms 1 % lows were shader pipeline compilation, not steady-state cost.
4. **MEDIUM retune:** MSAA → FXAA, SSAO off, hard shadow filter, LOD1 hero, 4 street lights.
