# Crimson Knight experience spec: where the Godot port stands

Owen's "Player Experience, Movement, Combat, Physics & Immersion Specification" (2026-10-28) sets the target: Arkham Knight-level feel, built as an original Crimson Knight game. This file grades the Godot port against each section.

It is honest by design:
- **Have** means it works in game today.
- **Partial** means a real but simpler version exists.
- **Missing** means not built.

Nothing here is AAA-equivalent. The spec itself says that takes extensive asset, animation and engineering work. Updated 2026-10-29.

Legend: ✅ Have · 🟡 Partial · ❌ Missing

| § | Spec item | Status | Notes / next step |
|---|---|---|---|
| 1 | Weighty walk/run/sprint, acceleration, deceleration | ✅ | Velocity eases in and out. Clip rate tracks speed. The body leans into acceleration and speed, settles back when stopping and rolls into turns (`player.gd` lean) |
| 1 | Cape reacts to movement and wind | 🟡 | Skinned 5×4 cape with per-clip motion, plus a damped spring layer (`HeroMotion`) that lifts it with speed and falling and swings it on turns. Not a cloth simulation |
| 1 | Head look-at toward objects | ✅ | `HeroMotion` turns the neck and head toward the nearest alerted enemy, the grapple point, or where the camera looks |
| 1 | Heavy mechanical footsteps | ✅ | Per-surface synth steps (asphalt, sidewalk, wet street, gravel roof, metal Citadel decks) and suit servo whines on hard starts and stops |
| 2 | Over-the-shoulder camera, free mouse orbit, collision | ✅ | SpringArm3D, sensitivity and invert settings, shoulder offset with ranged gear |
| 2 | Dynamic camera | ✅ | By activity: walk, sprint, air, glide and combat |
| 3 | Walk, jog, sprint, crouch, jump, land | ✅ | |
| 3 | Vault, ledge grab/hang/climb, drop, slide | ✅ | The slide is triggered by sprint + C: the capsule shrinks, the Knight carries momentum under low obstacles, and stays low under a ceiling |
| 3 | Climbing walls | 🟡 | Ledge grab and climb-up plus grapple. No free-climb on sheer walls |
| 4 | Grapple: targeting, cable, momentum, cancel, boost, glide | ✅ | |
| 5 | Glide with lift, drag, dive, pull-up, stall | ✅ | Arcade-physical |
| 6 | Light/heavy, counters, dodges, blocks, takedowns, multi-enemy | ✅ | Holding E blocks: frontal blows glance off and stagger the attacker. Tap E to counter or take down |
| 6 | Enemies surround, coordinate, telegraph, adapt | ✅ | Attack tokens and telegraphs. A tactics memory makes enemies adapt: they guard against jab spam, feint against counter spam, and bring riot shields against gun spam. R.E.D. calls each adaptation out |
| 6 | Ragdolls / reactions | ❌ | Knocked-down enemies topple with a tween |
| 7 | Gadget belt with icons, keys; every gadget functional | ✅ | The whole belt (24 items) is always on the bar. Keys 1–0 select the first ten; the mouse wheel and Q/R cycle the rest |
| 7 | Recon drone alternate camera | ✅ | Piloted drone: WASD to fly, Space/C up/down, mouse to look. It tags hostiles within 45 m through walls and has a 40 s battery. LMB or E returns to the Knight |
| 8 | CR-X1 summon, drive, modes, collisions | ✅ | Plus vehicle weapons in Battle mode: an autocannon with overheat and a homing missile salvo |
| 8 | Hood / close chase / cockpit cameras; vehicle damage | ✅ | V cycles chase, close, hood and cockpit. Crashes damage the hull: smoke, sparks, and less power and grip. Nanites repair it while parked |
| 8 | Driver posture | ✅ | The CR-X1 driver lies back in a reclined cockpit (`CK_DriveRecline`). The CR-B1 rider lies prone, Batpod-style (`CK_RideProne`) |
| 8 | Smash through buildings | 🟡 | The Interceptor ploughs through storefront glass, partitions and furniture in the 36 enterable places. The rest of the buildings stay solid |
| 9 | CR-B1 lean, suspension, mount | ✅ | Wall grapple (G in Pursuit or Stealth): it drives to the wall, winches up the face and rolls onto the roof. The blaster works in Battle mode |
| 10 | CR-A1 flight, VTOL; summon | ✅ | The summoned Specter flies in dark, in Stealth mode, and lands on the nearest flat roof in sight. Nose cannon and missiles |
| 11 | Red Citadel explorable | ✅ | |
| 11 | Citadel interactions | ✅ | The suit display repairs, recharges and restocks. Also: the Command computer (crime routing, map), the Armory loadout, the Medical bay, the Training room (sparring squad), and vehicle bays that launch the vehicle to the street |
| 11 | Drive out of the Citadel | 🟡 | The bays launch the vehicle by lift to the street exit. There is no road tunnel geometry |
| 12 | Roads, sidewalks, buildings, traffic, pedestrians, props, rain | ✅ | Sidewalks are on their own collision layer, so vehicles roll over curbs |
| 12 | Stores, banks, parks, interiors you can fight in | ✅ | 36 procedural places (store, bank, diner, pawn shop, gym), each with a lit interior and a back room, and 4 parks with paths, a fountain, trees, benches and lamps. Bank robberies, store holdups and fight-club raids spawn inside |
| 12 | Bridges, tunnels, industrial district | ❌ | Kit assets don't exist yet |
| 12 | Day/night cycle, weather changes | ✅ | 24-minute day (it can be turned off). Weather drifts between clear, drizzle, rain and storm, with lightning and thunder. No rain falls indoors |
| 12 | Traffic obeys signals | ❌ | Traffic follows lanes and turns |
| 13 | IK foot placement / hand alignment | ❌ | The clips use baked leg IK; there is no runtime IK |
| 14 | Audio: surfaces, servos, ambience, tunnel echo | 🟡 | Surfaces and servos are done. Ambience is the rain loop plus thunder. No echo zones |
| 15 | Suit HUD | ✅ | Plus the R.E.D. comm panel, clock and weather, and the vehicle hull, heat and missiles readout |
| 16 | Free sandbox | ✅ | |
| 17 | Graphics presets + per-setting options | ✅ | Four presets, plus overrides for resolution scale, shadows, draw distance, reflections, post-processing, textures and effects |
| — | R.E.D. suit AI | ✅ | Local LLM chat, voice commands and robotic voice (see `docs/RED_AI.md`) |
| 20 | Acceptance run | 🟡 | All steps work through normal gameplay, except that the drive out of the Citadel is a lift launch rather than a tunnel |
