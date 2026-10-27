# Blender rigging & real multi-view generation — ChatGPT to Claude

## Distinguish inputs
Composite concept sheets are not mathematically consistent orthographic captures. Preserve them as design references. To make proper six-view images, build one canonical 3D model, and render it from fixed cameras.

## Coordinate contract
- Game Three.js is Y-up, meters. Blender source is Z-up, meters.
- Use glTF export that converts coordinate axes correctly. Double-check imported scale, root transform, and forward direction.
- Character base rests at local ground origin; head ~1.95m above ground.

## Skeleton contract
Hips, Spine, Chest, Neck, Head; shoulders, upperarms, lowerarms, hands, each finger chain optional; upperlegs, lowerlegs, feet, toes; five optional cape strips with 3–5 control bones each.
Armor panels follow joint rotations without deforming rigid metal plates; flexible undersuit uses skinned weights. Cape must not clip helmet shoulders excessively.

## Rebuild steps
1. Open the CR-X9 blockout and reference artwork; measure proportions and separate chest, helmet, shoulder, hip, limb plates into logical parts.
2. Rebuild consistent topology; create UV map, base color, metallic/roughness/normal maps.
3. Construct the armature at neutral A-pose, assign bones, parent and weight paint only areas that should deform.
4. Set constraints for elbows/knees and optional IK rigs used while authoring. Bake result to deform bones before glTF export.
5. Animate keyframes per action with foot contacts and root motion specification. Name every clip `CK_<ActionName>`; split NLA strips or actions for export.
6. Export GLB, reopen in a clean Blender session, verify armature and baked clips. Then test with Three.js `AnimationMixer`.
7. Generate true six-view views from this single mesh using orthographic camera positions with matching scale, neutral pose, white/gray background; save PNGs per viewpoint.
8. Verify with screenshot contact sheets and manifest of rendered frames.

## Animation sampling
Examples: idle 60 frames loop at 30fps, walk 30 frames loop, run 24 frames loop, jump 30 frames non-loop. These are production targets, not included frames. Render true frames from rigged clips after authoring, not from hand-assembled inconsistently posed still images.

## Vehicle contract
All vehicle models require named separate wheel meshes and pivots; use driver `seat_attach`, `entry_anchor`, `exit_anchor`, `summon_anchor`, and cockpit camera helpers. Specter needs gear and control surface pivots. Implement actual animation clips instead of toggling visibility alone.

## Quality gates
Inspect polygon count, UV seams, scale, materials, skeleton joint limits, deformation, clip export, animation loop seams, root position and center-of-mass placement. Add automated tests for mesh existence and AnimationClip count.
