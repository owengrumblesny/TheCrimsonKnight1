# Crimson Knight experience spec: where the Godot port stands

Owen's "Player Experience, Movement, Combat, Physics & Immersion Specification" (2026-10-28) sets the target: Arkham-Knight-level feel, built as an original Crimson Knight game. This file grades the Godot port against each section. It is honest by design: **"Have" means it works in game today; "Partial" means a real but simpler version exists; "Missing" means not built.** Nothing here is AAA-equivalent yet. The spec itself says that takes extensive asset, animation and engineering work.

Legend: ✅ Have · 🟡 Partial · ❌ Missing · 🔨 being built in the current pass

| § | Spec item | Status | Notes / next step |
|---|---|---|---|
| 1 | Weighty walk/run/sprint, acceleration, deceleration | 🟡 | Velocity eases in and out (14/s on the ground); clip rate tracks speed so the feet stay planted. No lean-into-acceleration or turn-in-place clip yet |
| 1 | Cape reacts to movement and wind | 🟡 | The cape is skinned on 5×4 bones and animated per clip (lift and wave). No physics simulation |
| 1 | Head look-at toward objects | ❌ | Needs a head-bone look-at modifier |
| 1 | Heavy mechanical footsteps | 🟡 | Synth footsteps, one surface |
| 2 | Over-the-shoulder camera, free mouse orbit, collision | ✅ | SpringArm3D with collision. Sensitivity is a code constant; 🔨 settings slider |
| 2 | Dynamic camera (sprint pulls back, glide far, combat framing) | 🔨 | Activity-based distance and FOV |
| 3 | Walk, jog, sprint, crouch, jump, land | ✅ | |
| 3 | Vault, ledge grab/hang/climb, drop, slide | 🔨 | New CK_Vault / LedgeHang / LedgeClimb / Slide clips in the CR-X9 builder, plus geometry-tested traversal |
| 3 | Climbing walls | ❌ | After ledges |
| 4 | Grapple: camera-aimed targeting indicator, visible cable, momentum reel, cancel, boost, glide out | 🔨 | Was a gadget reel in a straight line at a fixed speed. Being rebuilt as a physics reel with a target indicator, boost and glide chaining |
| 5 | Glide with lift, drag, dive, pull-up, stall | 🔨 | Was a clamped fall speed. Being rebuilt as a flight model |
| 6 | Light/heavy attacks, counters, dodges, blocks, multi-enemy, takedowns | 🔨 | Takedown (E) and weapons exist. Free-flow melee is being added with new CK_PunchL/R, HeavyStrike, Counter, Dodge, Guard clips |
| 6 | Enemies surround, coordinate, telegraph | 🔨 | Enemies chase, shoot and strike. Adding an attack token (two attackers at a time), circling and counter-able telegraphs |
| 7 | Hotbar with circular icons and shortcuts; every gadget functional | ✅ | All 21 equippable items have a real effect |
| 7 | Recon drone alternate camera | ❌ | The drone orbits the Knight; no drone camera yet |
| 8 | CR-X1: summon, enter, drive, modes, collisions | ✅ | VehicleBody3D, three modes with mechanical clips and per-mode models, bike eject |
| 8 | Summoned vehicle drives in (no teleport) | 🔨 | Vehicles currently appear in front of the Knight |
| 8 | Hood / close chase cameras; vehicle damage | 🟡 | Cockpit and chase cameras only. No damage model |
| 9 | CR-B1 lean, suspension, mount | ✅ | Visual lean and auto-balance. No mount clip of its own (it uses the generic enter) |
| 10 | CR-A1 takeoff, landing, throttle, pitch, roll, yaw, VTOL | ✅ | Arcade model |
| 11 | Red Citadel: explorable, statue, hangars | ✅ | |
| 11 | Citadel interactions (suit display, computer, enter parked vehicles, training) | ❌ | Next pass: terminals that open the map, loadout and missions |
| 11 | Drive out of the Citadel | ❌ | The Citadel is a separate level reached by elevator; a road tunnel needs new geometry |
| 12 | Roads, sidewalks, buildings, lights, signals, traffic, pedestrians, props, rain | ✅ | 7×7 grid of 4-lane avenues |
| 12 | Bridges, tunnels, industrial district, interiors | ❌ | Kit assets don't exist yet |
| 12 | Day/night cycle, weather changes | ❌ | Fixed rainy night |
| 12 | Pedestrians react; traffic follows roads | 🟡 | Pedestrians cower at gunfire; traffic follows lanes and turns. No traffic lights or obeying rules |
| 13 | Gravity, momentum, collision, slopes, landing reactions | ✅ | |
| 13 | IK foot placement and hand alignment | ❌ | The clips use baked leg IK; no runtime IK |
| 13 | Ragdolls | ❌ | Knocked-down enemies topple with a tween |
| 14 | Surface-based footsteps, suit servos, city ambience, tunnel echo | 🟡 | Synth placeholder sounds and a rain loop only |
| 15 | Suit HUD, prompts, objective markers, minimap, vehicle info | ✅ | 🔨 grapple target indicator |
| 16 | Free sandbox from the start | ✅ | Missions are optional (they start on Play but never gate anything) |
| 17 | LOD, culling, instancing, presets, pooling | ✅ | LOW on the 610M: 55–102 fps in the six benchmark scenes |
| 17 | Per-setting graphics options (shadows, draw distance, reflections…) | 🟡 | Four presets only |
| 20 | Acceptance run: Citadel → drive out → grapple → boost → glide → land | 🟡 | Drive-out is missing; the grapple/boost/glide chain is being built now |
