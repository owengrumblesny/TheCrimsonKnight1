# CLAUDE MASTER BUILD PROMPT — CRIMSON KNIGHT: EARTH-RED

You are the lead Three.js game engineer, technical artist, and gameplay systems developer. Build an original, playable third-person open-world sandbox called **Crimson Knight: Earth-RED**, starring fictional Owen Grumbles in the CR-X9 armored suit. The user wants **free roaming, not a compulsory story**. The tone is dark military sci-fi; avoid copying copyrighted Batman character meshes, branding, or game assets. Use Owen Enterprises / Crimson Knight original IP.

## READ FIRST
Read `docs/ASSET_STATUS.md`, `docs/expanded_asset_manifest.json`, `docs/WORLD_AND_ART_BIBLE.md`, and `animation/complete_animation_contract.json`. Existing GLBs are low-poly static blockouts. They are NOT rigged, NOT photorealistic, and have NO authored animation clips. Do not claim otherwise. Keep replacement assets swappable through a stable asset registry.

## PRIMARY GOAL
Ship a working, playable browser game rather than a demo screen or static scene. Use Vite + TypeScript + Three.js, and a lightweight physics solution such as Rapier. Work in incremental runnable milestones; never claim an unfinished feature works.

## REQUIRED SYSTEMS (in order)
1. Project scaffold, asset registry, scene streaming/chunks, debug UI, performance profiler, persistent settings.
2. Third-person controller with grounded physics, slope/step handling, sprint, jump, camera collision, camera shoulder switch, crouch, and interact prompts.
3. Animation graph using named states in animation contract, blending, procedural fallbacks, root motion compatibility, cape secondary motion. Until rigged animations exist, explicitly label procedural animation as provisional.
4. Build a coherent explorable district of New Gotham from the supplied modular assets, with roads, rooftops, lighting, weather, fog, NPC pedestrians, basic traffic and navigation. Expand via chunk streaming and instancing.
5. Accessible Red Citadel base: suit display, armory display, command terminal, hangars, equipment case, armor customization, save/load.
6. Enter/exit and summon CR-X1, CR-B1 and CR-A1. Implement physically plausible *game-feel* vehicle controllers, camera transitions, wheels/suspension or equivalent, aircraft lift/hover, collisions, and recovery. Fictional weapon and gadget systems must be non-instructional and suitable for a game.
7. Gadget UI: equip/holster, scan, deploy/recall drone, grapnel traversal, visual-only energy props; animation-driven timing and cooldowns.
8. Sandbox menu: spawn and recall vehicles, teleport to unlocked locations, weather/time, photo mode, HUD toggle, reset, equipment customization.
9. Optional emergent encounters and non-graphic combat with simple AI, detection, pathfinding, hit reactions, and a resettable training arena. No required main quest.
10. Optimize: LOD, GPU instancing, pooled objects, occlusion approximations, adaptive graphics presets, asset loading indicators, browser memory safeguards.

## REQUIRED CONTROLS
WASD movement; mouse orbit/look; Shift sprint/boost; Space jump/ascend; Ctrl crouch/descend; E interact/enter/exit; G grapnel; Q gadget wheel; V summon menu; Tab sandbox menu; C camera; Esc pause. Rebindable in settings.

## ENGINEERING CONTRACT
- Never treat static GLB blockouts as skeletal animation clips.
- Separate data from rendering and gameplay logic.
- Use a central typed asset manifest and scene/entity interfaces.
- Keep controls keyboard/mouse first and provide gamepad mapping if feasible.
- Do not make users install licensed commercial assets.
- All assets must load locally; avoid CDN-only runtime dependencies except npm-installed libraries.
- Provide tests or scripted checks for asset loading, save migration, and core controller behavior.
- Keep a `STATUS.md` with working, partial, missing, and known bugs.
- Include `npm install`, `npm run dev`, `npm run build` instructions.

## DELIVERY STYLE
Implement code and files directly, not just a plan. Start with a vertical slice that launches and is fun to move around in. After each milestone, give changed files, how to run, actual tests performed, remaining limitations, and the next milestone. Do not invent completed work.

## ASSET IMPROVEMENT REQUEST
Prioritize high-quality art and animation: create an original humanoid rig specification, consistent pivots, blend tree, movement transitions, procedural cape, animation timing, six-view reference guide, PBR material rules, collision proxies, and LOD conventions. If you cannot produce photorealistic production assets directly, document that clearly and create the best functioning placeholders plus a replacement workflow.

## START NOW
Inspect the provided files and implement Milestone 1 + a playable Milestone 2. Preserve all existing files unless intentionally replacing them, and explain each replacement.
