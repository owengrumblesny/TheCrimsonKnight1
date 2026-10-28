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

## NPC clips (`tools/blender/ck_build_npcs.py`, shared by all 14 humanoids)
| Clip | Frames | Use |
|---|---|---|
| NPC_Idle | 72 loop | default; random start phase per NPC |
| NPC_Walk | 32 loop, 1.4 m/s | authored for later AI (not used yet) |
| NPC_Alert | 60 loop | enemies on guard |
| NPC_Cower | 48 loop | civilian reaction (not triggered yet) |
| NPC_Talk | 60 loop | conversation pairs |
| NPC_DroneHover / NPC_DroneScan | 48 / 80 | patrol drone rotors + gimbal sweep |

## Gear clips (`tools/blender/ck_build_gear.py`)
`Gear_Deploy` (unfold / ignite / extend), `Gear_Fire` (recoil, claw spread, dish pulse, barrel spin), `Gear_Idle` (rotors, batarang spin, EMP cap). Each model's clips and pivots are listed in `config/gadget_assets.json`. The hero still plays `CK_GadgetDraw` / `CK_Interact` per item, and the gear clips are ready for the gadget systems.
