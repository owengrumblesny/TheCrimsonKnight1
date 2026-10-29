# The Crimson Knight

**An open-world armored-vigilante sandbox, built almost entirely by AI.**

You are Owen Grumbles, the Crimson Knight. You pilot the CR-X9, a strength-enhancing exoskeleton built by Owen Enterprises, through the rainy night streets of New Gotham. You can:
- grapple to rooftops, boost over the edge and glide across the city;
- fight crowds with free-flow melee;
- call in your vehicles: the CR-X1 Interceptor, the CR-B1 Cycle and the CR-A1 Specter jet;
- talk to **R.E.D.**, a sassy AI who lives in your helmet.

The game runs on **Godot 4.7** (GDScript, Jolt physics) as a native Windows and Linux game. The earlier Three.js web version has been retired and removed.

---

## ⚠️ Full disclosure: this game is AI-generated

I'm Owen, and I'm not a game developer. I can't write a game engine, rig a character or model a car. This whole project is an experiment: **how far can AI go at making a real 3D game when one person just describes what they want?**

Almost everything here was produced by AI:

| What | Made by |
|---|---|
| Concept art, reference sheets, UI icons, the first asset pack and design docs | **ChatGPT** (OpenAI) |
| The game code, Godot port, gameplay systems, shaders, tests and docs | **Claude** (Anthropic), via Claude Code |
| 3D models: the CR-X9 hero mesh and rig, all 34 animation clips, the vehicles and their mode transforms, the city kit | Generated **procedurally by Claude**, which wrote Python scripts for headless Blender (`tools/blender/`). No hand modelling. |
| The sound effects | Synthesized in code (oscillators and filtered noise), with no recorded audio |
| R.E.D.'s brain, ears and voice | Open-source local AI models running on your own PC (see below) |

My part was the ideas, the design direction ("make the grapple feel like Arkham", "make R.E.D. sassy", "I want him lying down on the bike"), testing, and a lot of "that's broken, fix it".

**What this project is testing:**
- whether an AI can hold a large codebase in its head and keep it working over hundreds of changes;
- whether it can make 3D assets with no artist: meshes, skinning, animation and LODs, all from code;
- whether it can grade its own work honestly instead of claiming it's finished.

It is **not** AAA, and the docs say so plainly: see `docs/EXPERIENCE_SPEC_GAPS.md` for what works, what's partial and what's missing.

---

## The game

### What's in it
- **Traversal:** walking, running and sprinting with weight; vaults, ledge grab, shimmy and climb; a sprint-slide; a camera-aimed grapple with real line tension, grapple boost, and glide physics (lift, drag, dive and stall).
- **Combat:**
  - Free-flow melee: light and heavy strikes, counters on telegraphed attacks, dodges, and a hold-to-block that staggers attackers.
  - Combos, takedowns and hit-stop.
  - Enemies take turns, circle the fight and **adapt to how you fight**: they block jab spam, feint against counter spam, and bring riot shields if you rely on guns.
- **The utility belt:** every gadget is on the bar at once, on number keys 1–0 and the mouse wheel, and every one does something:
  - batarang and grapnel;
  - three fictional energy weapons, with aim assist and lock-on;
  - smoke, shield, scanner, EMP, sonic, cloak, decoy and holoprojector;
  - a **piloted recon drone** that tags enemies through walls;
  - plus a few more.
- **Vehicles:**
  - **CR-X1 Interceptor:**
    - Pursuit, Battle and Stealth modes, with animated transforms.
    - Battle-mode autocannon and missiles.
    - Launches the CR-B1 Cycle out of its body.
    - A damage model.
  - **CR-B1 Cycle:** a lean-into-turns motorcycle with a pulse blaster in Battle mode.
  - **CR-A1 Specter:** a jet with flight, VTOL and stealth modes. When summoned, it flies in dark and lands on the nearest rooftop you can see.
  - Summoned vehicles drive or fly to you; they never pop into existence.
  - Four driving cameras: chase, close, hood and cockpit.
- **New Gotham:**
  - A 7×7 grid of four-lane avenues, with traffic and pedestrians.
  - Street crimes, heat stars and story missions (all optional).
  - A day/night cycle and changing weather: drizzle, rain, storms with lightning, and clear nights.
- **The Red Citadel:** the underground HQ, with waterfalls, hangars and the statue.
- **HUD:** a minimap, waypoints, context control hints, a live reticle and a combo counter.
- **Performance:** tuned to run on a budget laptop (Radeon 610M). Four graphics presets, with LODs and instancing.

### R.E.D., the suit AI
R.E.D. is a sarcastic, helpful voice in your helmet, and **she runs 100% locally**: no cloud, no account, no internet.
- **Hold Y** and talk, or **press Enter** and type. For example: *"summon the Batmobile"*, *"I need more strength"*, *"lose the cops"*, *"find me a crime"*, *"equip the batarang"*, or just *"tell me a joke"*.
- She can call your vehicles and boost your suit: overdrive strength, armor boost, repair and shield. She can also scan for enemies, set waypoints, jam the police and switch your gear.
- She calls out ambushes, low health, heat and new crimes, and gives tips.
- The engines behind her:
  - llama.cpp running **Qwen2.5-1.5B-Instruct** for conversation;
  - **whisper.cpp** (base.en) for speech recognition;
  - **Piper** (en_US-amy-low), put through a robot filter, for her voice.
- Game actions go through a deterministic command parser, because small models are bad at picking actions. The LLM only does the talking.

The models are about 1.3 GB, so they aren't in this repo. See [`docs/RED_AI.md`](docs/RED_AI.md) for what to download and where to put it. Without them, R.E.D. still works for commands, with text and scripted lines.

---

## Running it

1. Install **Godot 4.7.x** (standard, not .NET).
2. Clone this repo and open `project.godot` in the repo root with Godot.
3. Press **F5**. (The first open imports the assets, which takes a few minutes.)

### Controls (default)
| | |
|---|---|
| WASD / Shift / Space / C | Move / sprint / jump (hold in the air to glide) / crouch (while sprinting: slide) |
| G | Grapple to the gold marker (Space near the top: boost) |
| LMB / RMB | Use item or strike / aim and lock on (in a fight: heavy strike) |
| E | Interact, counter (when an enemy flashes red), takedown; hold to block |
| 1–0, mouse wheel, Q/R | Utility belt |
| V | Call a vehicle (while driving: change camera) |
| B / X / F | Vehicle mode / launch the Cycle from the Interceptor / exit |
| Y (hold) / Enter | Talk to R.E.D. / type to R.E.D. |
| Tab / M / Esc | Inventory / map / pause and settings |

Everything can be rebound in Settings, and gamepads work.

---

## Repo layout
| Path | What |
|---|---|
| `project.godot`, `godot/` | **The game** (Godot 4): scripts, shaders, data, tools and tests |
| `assets/` | Models (GLB), textures and source `.blend` files |
| `tools/blender/` | Python scripts that generate the hero, the vehicles and the rig/animation clips in Blender |
| `config/` | Game data shared by both builds (vehicles, physics, assets, controls) |
| `docs/` | Design specs, status reports, the dev log, and the honest gap list |
| `references/`, `CRIMSON_KNIGHT_UI_PACK/`, `ui/` | The ChatGPT-made reference art and UI icon pack |

Tests: `godot --headless --path . --script godot/tools/test_logic.gd`

---

## Legal
- Code and original assets: [MIT License](LICENSE) © 2026 Owen J Grumbles.
- The Crimson Knight, R.E.D., New Gotham and Owen Enterprises are original creations for this project. The game takes inspiration from the feel of the *Batman: Arkham* games, but it is **not affiliated with, endorsed by or derived from DC, Warner Bros. or Rocksteady**, and it uses none of their assets. All weapons are fictional.
- R.E.D.'s optional third-party models keep their own licenses: Qwen2.5 (Apache-2.0), whisper.cpp and llama.cpp (MIT), Piper and its voices (MIT, with voice-specific licenses).
