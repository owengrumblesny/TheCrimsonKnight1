# CRIMSON KNIGHT — Earth-RED | Asset Foundation v0.1

**Owner / fictional setting:** Owen Grumbles — Owen Enterprises. Original crimson armored hero, vehicles, and New Gotham setting.

## Included

- `reference/concept_board.png`: visual reference sheet for hero, vehicles, environments and pose ideas.
- `reference/knight_*.png`: six cropped character angles extracted from the concept board. **Not six separately rendered orthographic projections**; use only as design references.
- `models/*.glb`: four importable GLB geometry blockouts: hero, Interceptor, Batcycle, Specter.
- `animation/animation_presets.json`: named animation specifications and timing ideas.
- `animation/preview_animator.js`: simple rigid-part motion preview for named meshes.
- `preview.html`: Three.js GLB viewer with orbit camera and procedural pose previews.
- `docs/asset_manifest.json`: machine-readable inventory for other AI coding tools.

## How to preview

From the directory containing this pack run `python -m http.server 8000` and visit `http://localhost:8000/crimson_knight_asset_pack/preview.html` (when the pack is in a directory of that name). Three.js is loaded from a CDN and requires internet.

## Important production status

These are **starter assets, not finished photorealistic game assets**. The GLBs are low-poly primitive blockouts without textures, skinning, collision meshes, PBR maps, IK, facial animation, or embedded animation clips. The preview animator rotates rigid mesh pieces around their local origins; it is a proof of concept and is not anatomical motion. The generated reference sheet is concept artwork, not a valid UV texture atlas.

## Suggested handoff to another AI / 3D artist

1. Retopologize each GLB to a coherent model; retain model file names and Y-up / -Z-forward coordinates.
2. Create a proper humanoid armature, parent all armor pieces to bones, and skin the undersuit.
3. Produce 17 character animations and vehicle transformation/flight animations named in `animation_presets.json`.
4. Export GLB with embedded `animations[]` and use Three.js `AnimationMixer` for actual clips.
5. Add PBR textures, LOD meshes, collider geometry, root-motion conventions, and animation events.
6. Validate animations and assets in `preview.html` before importing into the main sandbox.

**This package intentionally prioritizes asset interoperability and visual direction over new gameplay mechanics.**
