# IMAGE TO 3D: HONEST PRODUCTION PIPELINE

## What these files are
The images are **concept/reference sheets** and key-pose illustrations, NOT aligned camera captures, not actual animation frames, and not riggable 3D assets. Crops of a sheet are not new independent views. Image labels and proportions may be inconsistent. Do not generate frame-by-frame motion by naively playing these images as sprites. The existing GLBs are static blockouts, not skinned production meshes.

## Recommended production workflow
1. **Lock model design.** Choose one canonical CR-X9 front/side/back reference. Manually redraw orthographic front, rear, left, right, top and 3/4 views on a neutral background with identical silhouette and proportions. Define character height (e.g. 2.0 game meters), bone proportions, armor boundaries, cape anchors.
2. **Create geometry.** Use Blender or a 3D generation tool that supports multi-view reference. Prefer manually modeled clean topology for a hero asset. Generated meshes must be retopologized. Separate rigid armor plates from deforming undersuit, eyes, cape, helmet and accessories. Use these concept sheets for *visual guidance*, not photogrammetry.
3. **UV + PBR.** Bake high-poly details to normal maps, author baseColor, metallicRoughness, normal, emissive and AO maps; verify in neutral light. Target a desktop hero asset around 30k-80k triangles initially and LODs at ~50%, 25%, 10%. These are adjustable budgets.
4. **Rig.** In Blender build a humanoid skeleton: root, pelvis, spine_01-03, neck, head, clavicles, upper/lower arms, hands, individual fingers, thighs, calves, feet, toes. Use separate bones/constraints for rigid armor, cape anchors and optional helmet fins. Bind undersuit with weights, rigid armor plates to bones or near-rigid vertex groups. Test shoulder, knee, hip and neck ranges; avoid plate clipping.
5. **Animate.** Create actual timeline clips in Blender or with retargeted motion capture that permits redistribution. Start with idle, walk, run, sprint, jump start/loop/land, crouch, turn, aim, gadget draw/holster, summon, car enter/exit, motorcycle mount/dismount, aircraft enter/exit. Add attack/block/hit animations later. Use a common skeleton and consistent rest pose. Separate in-place and root-motion clips explicitly.
6. **Cape.** Use skinned cape bones plus spring simulation, or cloth simulation with stable attachment and collision capsules. Bake cinematic simulations if runtime cost is excessive.
7. **Export.** glTF 2.0 binary GLB with named clips, meter units, Y-up at runtime, predictable facing direction (-Z recommended for Three.js), material textures embedded or properly referenced. Blender exporter should include skinning and animations.
8. **Validate.** Load GLBs with Three.js GLTFLoader; verify skinnedMesh, skeleton bones, AnimationClip names, PBR textures, no missing assets, scale and root orientation. Test animation transitions using AnimationMixer crossFadeTo.
9. **Vehicle rigs.** Keep wheels separate with pivot nodes; steering and suspension transforms for CR-X1, fork and leaning pivots for CR-B1, control surfaces/landing gear/VTOL thrusters for CR-A1. Model deployable fictional props as cosmetic mesh groups with authored animations.
10. **World.** Modular facades, road segments, sidewalk, roofs, signage, interiors, hangar modules, Citadel stations. Author collision proxy meshes, navmesh data, occlusion and LODs separately.

## Quality gates
- Character silhouette matches canonical front/side/back views.
- All rigged animations play without broken skinning or armor intersections.
- All clips start/end with documented pose and root displacement.
- Car wheels turn and suspension responds; bike leans; aircraft controls articulate.
- Load and render on Windows Chrome with npm local dependencies, without external asset services.
- Target 60fps at 1080p on a defined test GPU; offer low-quality preset.

## Tool limitations
Claude can write Blender Python scripts, model specifications, Three.js integration and rig tests, but text alone does not convert reference images into production-grade models. A Blender modeling workflow or external 3D reconstruction tool, artist QA, and actual animation authoring are necessary. Avoid claiming generated screenshots are motion capture or multi-view calibrated photographs.
