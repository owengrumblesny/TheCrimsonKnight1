# Animation map

Clips live in `assets/models/characters/crimson_knight_CRX9_rigged.glb`, built by `tools/blender/ck_build_crx9.py`. Their metadata (frames, loop, refSpeed) is in `config/crx9_clips.json`, and the mapping from graph names to clips is in `config/animation_graph.json` → `clipMap`. All clips are procedural keyframes, not motion capture.

| Part II requirement | Clip | Status |
|---|---|---|
| idle | CK_Idle | ✔ |
| walk forward / back | CK_Walk (played at negative rate for backpedal while aiming) | ✔ (no dedicated back clip) |
| strafe | CK_StrafeLeft / CK_StrafeRight | ✔ |
| run / sprint | CK_Run / CK_Sprint | ✔ (speed-matched playback) |
| turn | — | ✘ missing (turn-in-place) |
| crouch / crouch walk | CK_CrouchIdle / CK_CrouchWalk | ✔ |
| jump start / loop / land | CK_JumpStart / CK_Airborne / CK_LandSoft, CK_LandHard | ✔ |
| dodge | — | ✘ missing |
| climb | — | ✘ missing (no climbable geometry yet) |
| grapple aim / launch / travel | CK_GrappleAim / CK_GrapplePull | ◐ no separate launch clip |
| glide start / loop / land | CK_Glide | ◐ loop only; uses LandSoft/LandHard |
| scan | CK_Interact (scanner use) | ◐ no dedicated scan clip |
| equip / holster | CK_GadgetDraw / CK_GadgetStow | ✔ (played on hotbar selection) |
| gadget deploy | CK_GadgetDraw / CK_Interact per item (`inventoryData.ts` useClip) | ◐ |
| vehicle call | CK_Summon | ✔ |
| armor activation / shutdown | — | ✘ missing |
| enter / exit car, mount / dismount cycle, enter / exit aircraft | CK_VehicleEnter / CK_VehicleExit / CK_Drive (generic) | ◐ one generic pair for all vehicles |

Footsteps: distance-based cadence while grounded (no clip markers yet). Cape: bone-animated per clip, with no runtime secondary motion yet.
