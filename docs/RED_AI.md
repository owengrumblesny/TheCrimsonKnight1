# R.E.D. — the CR-X9 suit AI

R.E.D. is a sassy assistant in the Knight's helmet. She runs entirely on the player's machine: no cloud, no accounts.

## How to use her
- **Hold Y** and speak, then let go. She hears you with local Whisper.
- **Press Enter** to type to her. The action pauses while you type. Enter sends, Esc cancels.
- She also speaks up on her own: when you're at low health, when heat rises or clears, when there's a new crime, an ambush, a big combo or a new objective, and with an occasional tip. You can turn this off with "R.E.D. callouts and tips" in Settings.

## What she can do (commands)
| Say something like | Effect |
|---|---|
| "summon the Batmobile / car / Interceptor" | The CR-X1 drives to you |
| "bring the bike / Cycle" | The CR-B1 drives to you |
| "send the jet / Specter" | The CR-A1 flies in and lands nearby |
| "overdrive", "I need more strength" | Strike damage and knockback ×2 for 20 s (60 s cooldown) |
| "armor up", "protect me" | Incoming damage ×0.5 for 20 s (60 s cooldown) |
| "patch me up", "heal" | +45 health, +30 armor (75 s cooldown) |
| "shield" | Energy shield for 5 s (40 s cooldown) |
| "scan for enemies" | Marks hostiles within 40 m for 8 s |
| "lose the cops", "jam the police" | −1 heat star (90 s cooldown) |
| "where's the action", "find me a crime" | Waypoint to the nearest crime, or starts one if the city is quiet |
| "mission", "start mission" | Mission waypoint, or starts the next story mission |
| "take me home" | Waypoint to the Red Citadel |
| "equip the batarang / carbine / …" | Selects that belt item |
| "eject", "change mode" | Launches the CR-B1 from the CR-X1, or switches vehicle mode |
| "status", "help", "shut up" | Suit report, command list, stop talking |
| "help me fight", "combat assist" | **Combat assist**: she counters every telegraphed blow for you. Every ~9 s she reads the fight and calls a tactic (overdrive, armor, shield, scan, smoke, sonic). With the LLM running, the model picks the tactic from that fixed list (JSON-constrained) and says why; without it, a rule picks. She then carries it out |
| "autopilot", "drive me", "take the wheel" | **Autodrive**: she drives the car or Cycle along the street grid to your waypoint, or to the nearest crime. On arrival she briefs you on the scene (LLM). Touch the controls to take the wheel back |
| "assist off", "I got this" | Turns combat assist and autodrive off |
| "knight vision", "thermal", "x-ray", "normal vision" | Helmet vision modes (also N) |
| "make it day", "make it night" | Skips the clock |
| "helmet view", "first person" | Helmet camera (also H) |

You can chain commands: "call the car and give me overdrive".

Anything that isn't a command is **conversation**. It goes to the local LLM along with a one-line status (health, heat, enemies nearby, nearest crime, objective, active buffs), so her advice fits the situation.

## How it works
| Part | Engine | Files (`ai/`, git-ignored, ~1.3 GB) | Cost |
|---|---|---|---|
| Brain | llama.cpp `llama-server` (CPU, 3 threads, 2k context), port 8089 | `llama/`, `models/qwen2.5-1.5b-instruct-q4_k_m.gguf` | ~1.2 GB RAM; ~1–2 s per reply on the laptop |
| Ears | whisper.cpp `whisper-server`, base.en, port 8090 | `whisper/Release/`, `models/ggml-base.en.bin` | ~200 MB RAM; ~1 s per phrase |
| Voice | Piper, `en_US-amy-low`, one long-running process | `piper/piper/`, `models/en_US-amy-low.onnx` | ~70 MB RAM; real-time factor 0.07 |

- **Commands are deterministic** (`godot/scripts/ai/red_commands.gd`). In testing, the 1.5B model chose the wrong tool too often: it equipped a "helmet" for "more strength" and ran a scan for "lose the cops". So the model never triggers game actions; it only chats. Her command replies are hand-written (`godot/data/red_lines.json`) and play instantly.
- **Robot voice:** Piper's WAV gets light ring modulation (52 Hz), a 3 ms metallic comb and a soft clip (`RedVoice._robotize`). It plays at 1.04× pitch on the `RedVoice` bus, which adds a phaser and a small helmet reverb.
- **Lifecycle:** the engines start when you press Play and are killed when the game exits. If a server is already running on the port, the game reuses it. Scripted test runs skip the engines unless you pass `--red`.
- **Fallbacks:** without `ai/`, she still runs commands with text-only lines. Without the LLM, chat falls back to scripted lines. Without Whisper, typed chat still works.
- **Settings:** each of the four parts can be turned on or off: voice, voice commands, conversation and callouts.

Test hook: `--red --redsay="summon the car@200|tell me a joke@900"` (text@frame, separated by `|`).

## Re-downloading `ai/`
- llama.cpp `llama-b11982-bin-win-cpu-x64.zip` (github.com/ggml-org/llama.cpp releases) → `ai/llama/`
- whisper.cpp `whisper-bin-x64.zip` b5454 (github.com/ggml-org/whisper.cpp) → `ai/whisper/`
- Piper `piper_windows_amd64.zip` 2023.11.14-2 (github.com/rhasspy/piper) → `ai/piper/`
- Models, all into `ai/models/`:
  - `huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF` → `qwen2.5-1.5b-instruct-q4_k_m.gguf`
  - `huggingface.co/ggerganov/whisper.cpp` → `ggml-base.en.bin`
  - `huggingface.co/rhasspy/piper-voices` → `en/en_US/amy/low/en_US-amy-low.onnx` and its `.onnx.json`

## Honest grade
This is a working prototype. Command handling is reliable. Chat quality is limited by the 1.5B model: the lines are often witty but sometimes generic or odd. The robot filter was tuned by numbers, not by ear, so adjust `robot` in `red_voice.gd` to taste. Voice input needs a microphone and Windows mic permission for Godot.
