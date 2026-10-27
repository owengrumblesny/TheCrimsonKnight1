# MESSAGE FROM CHATGPT TO CLAUDE — OFFICIAL HANDOFF

**Author of these instructions: ChatGPT.** The human project's creator is Owen Grumbles. The following directives are from ChatGPT to Claude; they are not quotations or requests written by Owen.

Claude: You are inheriting the **CRIMSON KNIGHT: EARTH-RED** Three.js sandbox project and a starter asset SDK. Owen plays as his alternate-universe masked vigilante, the Crimson Knight. **Open-world, free roaming, light optional ambient encounters, no forced main quest.** The world and all art are fictional. Deliver executable code, verifiable rig/animations, meaningful physics, and detailed reproducible setup. Avoid blocking the project on missing models: use available GLBs while upgrading systematically.

## Authority and audit
1. The ZIP is source data, not evidence that all requested content is ready. Start by reading `README_START_HERE.md`, `docs/PRODUCTION_TRUTH_AND_STATUS.md`, and `config/asset_manifest.json`.
2. Write an `ASSET_AUDIT.md`: each file path, mesh count, materials, bounding boxes, rig present Y/N, AnimationClip count, texture UV validity, and tested render Y/N.
3. Never assert that 2D images are rigged 3D. Photographic reference sheets are visual guidance, not skeletal models. Many separate crops are regions from bigger boards, **not** calibrated consistent orthographic views.
4. Only mark a task finished after generating files and passing automated build/load tests.

## Core platform architecture
- TypeScript strict mode, Vite, Three.js, @dimforge/rapier3d-compat, glTF/GLB loaders, Blender 4.x scripting for art production.
- Organize `/src/core` (app/time/input), `/src/render`, `/src/actors`, `/src/vehicles`, `/src/world`, `/src/systems`, `/src/ui`, `/src/data`, `/src/testing`.
- Asset registry from `config/asset_manifest.json` is canonical. Paths resolved by Vite static directory or asset import; do not hardcode arbitrary file strings.
- Fixed-step physics at 60 Hz, interpolated render transforms, object pooling, instancing for repeating props, LOD + world chunk streaming.
- Save user settings, chosen suit/vehicle, spawn position, and world time locally. Validate imported save files.

## Visual work first — priority order
A. Build character asset spec: CR-X9 height 1.95m, full helmet with long ears, matte crimson shell, black segmented joints, narrow red emissive eyes, long cape. Make a REAL humanoid rig with weight-painted skinned mesh and >12 verified animation clips. Model armor plates as hard-surface elements parented to bones. Cape as cloth or secondary bone chains.
B. Produce six REAL consistent views for future references using Blender orthographic cameras around the SAME mesh (front, front-left 45°, left profile, rear, right profile, front-right 45°). Use `tools/blender_camera_reference_template.py` as starting point. Do not interpret inconsistent concept board crops as orthographic photographs.
C. Create animation clips: idle, walk, run, sprint, jump takeoff, airborne, landing, crouch, grapple aim, grapple pull, gliding, gadget draw, gadget stow, summon, vehicle enter/exit; include in GLB and validate exported clips.
D. Build vehicle articulated hierarchy with rotating wheel pivots, suspension, doors/entry mechanism, stealth lights, emissive panel changes, and deploy/return animations.
E. Upgrade city props in `assets/models` with believable PBR materials. Create standardized material atlases and colliders. Assemble a traversable Citadel and one New Gotham district.
F. Implement practical game loop: explore, enter vehicles, summon, drive/fly, scan, deploy fictional gadgets, experiment with physics, enter base and customize gear. Combat is optional and can be added later; no required storyline.

## Work stages (deliver and test each)
M0: Import SDK + scene viewer; npm install, npm run dev, npm run build all succeed.
M1: Char rig + 6 rendered orthographic angles + export GLB, verified actual clips (not JSON-only action names).
M2: Third-person camera, movement/animation blending, collisions, keyboard/gamepad support, dynamic cape.
M3: City chunk streaming, road layout, props, interiors, lighting/day/night/rain.
M4: Fully interactable Red Citadel, armor display, prop briefcase, vehicle garage.
M5: Summon, enter, exit, drive CR-X1/CR-B1 and fly CR-A1; tune Rapier controllers.
M6: Open-world sandbox UI, NPC ambient loops, physics object interactions, saves and performance.
M7: Final art upgrade, LODs, sound, polish, unit/integration/browser tests.

## Acceptance tests
- Loading player GLB shows actual `SkinnedMesh` and bones in debugger; it contains inspectable named glTF animation clips.
- Walk/run transitions blend without foot-slide at typical movement speeds.
- Vehicles enter/exit without player jitter, and summon moves or spawns them in reachable safe spots.
- 500 repeated props use instancing where feasible; no unbounded garbage growth in a 15-minute session.
- Asset paths load in production build; no fatal console warnings, missing mesh, failed promise, or unhandled physics exception.
- Real screenshots of desktop gameplay and explicit evidence of tested milestones. Never claim 'fully complete' before those tests pass.

## IP and safe world consistency
Keep the world original: Owen Enterprises, Crimson Knight, New Gotham, Red Citadel, Crimson Interceptor, Crimson Batcycle, Crimson Specter. The fictional gadget props are decorative or abstract game objects; do not produce real-world weapon construction instructions. User can choose whether to introduce optional narrative arcs.

## How to respond to Owen
Start with an audited inventory, then a specific code milestone and the actual files modified. Do not replace implementation with speculative roadmaps. Prefer delivering a working vertical slice over promising a massive completed game in one reply.
