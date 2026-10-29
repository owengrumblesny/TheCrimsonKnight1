# Villains, landmarks and local AI voice conversations

Ten persistent villains live in New Gotham. Walk up to one, press **E**, hold **V** and talk, then let go. He hears you, thinks, and answers in his own voice. Everything runs on your machine: no cloud, no accounts, no internet.

## Controls (in a conversation)
| Key | Does |
|---|---|
| **E** | Talk to the villain in front of you (the prompt shows within 3.2 m) |
| **V** (hold) | Speak. The microphone is open only while V is held; a pulsing **● REC** meter shows it |
| **T** | Type instead (Enter sends, Esc cancels) |
| **Esc** | Leave the conversation |

The microphone is never opened unless you hold V. Turning off **R.E.D. voice commands** in Settings turns the microphone off for villains too (whisper never starts); typing still works. Outside a conversation, V still calls your vehicle and T still reloads, because on-foot controls pause while you talk.

## The pipeline
1. **Ears**: push-to-talk audio is downsampled to 16 kHz and sent to the whisper.cpp `whisper-server` (base.en) that R.E.D. already runs (port 8090).
2. **Brain**: one shared model for everyone, R.E.D.'s `llama-server` (Qwen2.5-1.5B-Instruct Q4_K_M, CPU, 3 threads, 2k context, port 8089). Ten villains means ten prompts, not ten models.
   - The fixed prefix is the personality file (`assets/ai/personalities/*.txt`, your text), rules (he is speaking to Crimson Knight, stay in character, never mention AI, one to three sentences, may refuse or lie) and the villain's example exchanges. llama.cpp's prompt cache keeps it warm, and it is pre-warmed as you approach within 25 m.
   - Each turn adds the scene: location and description, time and weather, what he is doing (schedule), attitude, objective, your reputation, and **YOUR MEMORY OF HIM** (a compact summary, not the transcript).
   - Output is grammar-constrained (GBNF) to `(emotion) words [action]`. The emotion and action can only be values this villain is allowed. JSON took about twice the tokens (~10 s vs ~3 s per reply standalone), so the format is compact.
3. **Validation**: the model only *requests* an action. `VillainActions.validate` checks it against the villain's permitted actions, what he actually knows, the relationship and the world before anything happens:
   - `reveal_location` needs earned trust (or respect, or a deal). A lead sets your waypoint.
   - The Pale Harlequin may "reveal" without trust, but then it's a false lead.
   - `give_clue` adds evidence. `call_guards` needs high hostility and fewer than 4 enemies around (spawns 2).
   - `flee` moves him to another place on his schedule. `cooperate` needs trust ≥ 0.3. `offer_deal` lets you say yes or back out (a betrayal).
   - Anything invalid becomes `none`: the line is spoken and nothing happens.
4. **Voice**: one long-running Piper process with the multi-speaker `en_US-libritts_r-medium` model (904 voices, 78 MB). Each villain has his own speaker, picked by measured pitch, pace and intonation range, plus a playback rate, a pitch-preserving tempo correction and an effect bus:
   - Iron Sovereign: metallic chorus and grit.
   - Doctor Hollow: soft low-pass.
   - Lord Umbra: low shelf and long reverb.
   - Cipher King: thin and phased.
   - The others: hall, theatre or room reverb.

   The voice plays positionally (AudioStreamPlayer3D) from his head.
5. **Body**: the emotion tag maps to an allowed clip, speed and posture (`Villain.EMOTE`). A `VillainPose` SkeletonModifier3D layers head tracking (±70° yaw, ±35° pitch), chest lean, head tilt, chin and a talking nod or laugh on top of the clip.
   - Angry: forward lean and +3.5 dB.
   - Confused: head tilt and a 0.7 s pause before speaking.
   - Amused: lean back and a laugh bounce.
   - Suspicious: still, staring, slow.
6. **Memory**: `user://villain_memory.json`, one compact record per villain. It holds trust, respect and hostility, plus capped lists of promises, deals, betrayals, insults, threats, questions, revealed leads and world news. When you leave, the model writes a one-line summary in the villain's voice for next time. It survives restarts.

The game never waits on any of this. Requests are async HTTP and Piper is a separate process. Without the engines it falls back: no LLM means scripted lines, no Piper means subtitles only, no whisper means typing.

## The ten villains
| Villain | Home | Schedule elsewhere | Voice |
|---|---|---|---|
| Professor Paradox | Northbridge University (lab) | Shattered Crown Museum 02-06 | speaker 688, measured, hall |
| The Laughing Wraith | Crimson Theater | Deadlight Pier 04-18 | 760 (most expressive), theatre |
| The Iron Sovereign | The Rustworks | (always) | 296 (deepest), metal |
| Doctor Hollow | Blackthorn Asylum | (always) | 232 (flattest, slow), soft |
| The Cipher King | Vesper Tower | Northbridge 05-19 | 264, fast, digital |
| Lady Nocturne | The Meridian Hotel | Museum 03-08, Gilded Ace 08-21 | 184 (female, calm), room |
| The Ashen Judge | City Hall | Grimstone 06-18 | 720, slow, hall |
| Black Viper | Ironhaven Docks | Gilded Ace 05-22 | 552, fast, low |
| The Pale Harlequin | Deadlight Pier | Crimson Theater 03-17 | 0 (female), theatre |
| Lord Umbra | Obsidian Plaza | Saint Mourne 04-09, Meridian 09-20 | 496, slow, deep |

Schedules run on the game clock. A villain only moves when you are more than 120 m away. Data: `godot/data/villains.json`.

## The 20 locations
Nineteen are built procedurally in the open belt around the downtown grid; the Red Citadel is the existing underground base. Each has a silhouette, an enterable interior, an accent light, a facade floodlight, a synthesized positional ambience loop and NPCs. "Underground" places (Gilded Ace, Ravencrest crypt, Nightfall Subway) are halls under a raised plinth: stairs go up, then down through a stairwell.

The harbour east of the docks and pier, and the asylum's moat, are visual water only (you wade). Invisible walls now close the edge of the world slab. Data: `godot/data/locations.json`; builders in `godot/scripts/villains/landmarks.gd`.

## Measured on the target laptop (Ryzen 5 7520U, 16 GB, game running, LOW)
| Step | Time |
|---|---|
| Whisper, 4.7 s question | 2.2-3.7 s |
| LLM reply, warm | 5-8 s (1-4 s with the game closed) |
| LLM first reply, cold prefix | 12-22 s (pre-warming on approach is meant to hide this; not timed separately) |
| Piper, after the reply | 0.3-1 s |
| Model cold start (if R.E.D.'s server isn't up yet) | about 25 s |

Extra memory: one more Piper process with a 78 MB voice model (its RAM use was not measured), on top of R.E.D.'s stack. The LLM is shared.

## Testing
- Unit tests: `godot --headless --path . --script res://godot/tools/test_villains.gd` (267 checks: data links, parsing, validation, memory, prompt shape, ambience).
- End to end, offline, without a microphone. The WAV goes to whisper exactly as releasing V would:

  `godot --path . -- --frames=4200 --log --red --nomissions --villain=professor_paradox --villaintalk=300 --villainmem=user://vtest.json "--villainscript=wav:question.wav|You're putting innocent people in danger.|end"`

  - `--villain=<id>` puts you in front of him.
  - `--villaintalk=<frame>` presses E (waits for the model).
  - `--villainscript` items run one per turn: `wav:<file>`, plain text, or `end`.
  - `--nomic` disables the microphone; `--novillainvoice` turns off Piper.

## Honest grade
A working local prototype of the whole loop. It is not Arkham-quality characters.
- **Works**: offline voice in, model, validated actions, positional voice out; memory across restarts; schedules; the fallbacks.
- **Dialogue quality** is the 1.5B model's ceiling. Lines are usually in character and on topic, but sometimes generic, and recall of memory is hit and miss. A villain addressing the Knight by the villain's own name is rewritten in code. A 3B model would be better and roughly twice as slow on this CPU.
- **Latency** of 5-8 s per turn in-game is noticeable. A "thinking" status shows meanwhile.
- **Bodies** are tinted stand-in NPC models with five clips plus procedural posture: no faces, no lip sync, no bespoke villain models.
- **Voices** were picked by measured pitch and pace, not by ear.
- **Landmarks** are blockouts built from boxes and kit pieces. They are dim at night from a distance, and interiors are single rooms (plus a lab or crypt).
- **Not done**:
  - map labels for the landmarks (they show as blocks only);
  - villains have no combat or arrest;
  - only Professor Paradox (voice in, memory across a restart) and the Iron Sovereign (typed) have had live conversations in-game. The other eight share the same code path and pass the data and grammar tests.
  - the model chooses actions conservatively: in testing it never called guards or revealed a lead unprompted, and the validator rightly refused an unearned reveal.
