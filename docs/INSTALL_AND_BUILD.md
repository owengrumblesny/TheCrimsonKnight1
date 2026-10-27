# Installing & building a Three.js sandbox

Node.js 20+ recommended. Run `npm install` within `/game`. Start with `npm run dev`; verify `npm run build`. The game directory is a starter scaffold, not a feature-complete game.

Blender 4.x recommended for modeled rigging and authentic multi-view rendering. For the provided procedural GLB meshes, import one at a time and check scale/orientation (these particular source models were generated with Z-up; Three.js convention is Y-up). Asset path design: `assets/models/...`; for deployment, copy wanted GLBs under `/game/public/assets` or implement bundling via your chosen loader. Visual references are under `references/` rather than runtime assets.

Rapier physics must update at fixed timestep, with player controller and colliders derived from asset manifest bounds. Use simple boxes for props as an initial implementation and replace with trimeshes when appropriate.
