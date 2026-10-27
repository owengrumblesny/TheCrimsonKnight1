# CRIMSON KNIGHT: EARTH-RED — Audio Implementation

**From:** ChatGPT  
**To:** Claude Code  
**Project owner:** Owen Grumbles  
**Scope:** Make audio work in the existing Three.js / TypeScript / Vite game. **Do not** implement the Windows installer, GitHub updater, new story, or unrelated mechanics in this task.

## Mission

Build a working, maintainable audio foundation and connect it to existing game actions. Prioritize **audible, testable results** over collecting an enormous sound library. Reuse the project's existing sounds and architecture wherever possible. If audio files are absent, make a small set of original, synthesized placeholder sounds so the implementation is testable without downloading anything.

## 1. Inspect before changing files

1. Read `README_START_HERE.md`, the relevant `docs/` files, `package.json`, the Vite config, and the actual game source.
2. Find the entry point, scene/camera lifecycle, character controller, vehicles, UI, asset loader, and any existing sound/audio settings.
3. Inventory existing audio files and check their licensing metadata.
4. Record which intended audio triggers actually exist in gameplay. Do not invent integrations with nonexistent mechanics or claim that they work.
5. Preserve the current browser build. Work within the existing project layout and use its conventions.

## 2. Implement a reusable audio manager

Use the Web Audio API and/or Three.js `Audio`, `PositionalAudio`, and `AudioListener`, compatible with the installed Three.js version.

Requirements:

- A single shared audio manager, with **one listener attached to the active camera** (and correctly moved if the camera changes).
- A central event registry mapping game events to asset files or synthesized placeholders.
- Separate volume buses or equivalent controls for **master, music, ambience, SFX, vehicles, and UI**.
- Support looping, one-shots, fading, playback rate/pitch where appropriate, and simultaneous sound limits.
- For positional sounds, configurable reference distance, rolloff, maximum distance, and reasonable attenuation.
- Avoid recreating AudioContexts, listeners, or decoded buffers on every event.
- Preload/cache audio; handle loading errors and missing files without crashing gameplay.
- Pause, resume, and clean up audio resources correctly as the game state changes.
- Support a mute toggle and persistent volume preferences (use existing settings persistence if present; otherwise a small versioned localStorage setting).
- Keep implementation modular and typed; avoid hardcoding audio logic inside unrelated rendering functions.

**Browser policy:** Audio must be unlocked by a user gesture. Add an unobtrusive **Enable Audio** button or use the existing Play/Start interaction to call `AudioContext.resume()`; provide a visible mute state. Never assume autoplay works.

## 3. Wire up real triggers

Implement the events supported by the current build, and leave TODO mappings for systems not yet implemented:

| Event | Trigger | Behavior |
|---|---|---|
| `ui.click` | Menu/button clicks | Short non-spatial SFX |
| `ui.open` / `ui.close` | Opening/closing menus | Short non-spatial SFX |
| `armor.step` | Foot contacts ground during movement | Surface-aware variation if surfaces exist; otherwise rate-limited footsteps |
| `armor.jump` | Jump starts | One-shot |
| `armor.land` | Character touches down | One-shot, scaled by landing strength where available |
| `armor.activate` | Suit/equipment activation | Short mechanical cue |
| `gadget.deploy` | Existing equipment activation | One-shot; only if an actual event exists |
| `vehicle.enter` / `vehicle.exit` | Entering/exiting vehicle | One-shot |
| `vehicle.engine` | Vehicle moving/active | Loop that follows vehicle; smoothly respond to speed |
| `vehicle.summon` | Existing summon action | Short cue |
| `ambience.city` | Player in New Gotham | Cross-faded ambience loop |
| `ambience.citadel` | Player in Red Citadel | Cross-faded ambience loop |

Use animation events for footsteps **if clips and markers exist**; otherwise use distance-based cadence with grounded-state checks. Do not play footsteps while airborne or seated in a vehicle. If there's no usable vehicle physics yet, tie engine sound conservatively to actual available speed or control signals.

## 4. Organize assets

Prefer existing asset naming, otherwise use:

```text
public/assets/audio/
  ambience/
  armor/
  vehicles/
  gadgets/
  ui/
  music/
```

Add `config/audio_manifest.json` (or an equivalent typed manifest) with event ID, file path, category, loop flag, default gain, and optional positional settings. Provide an `AUDIO_CREDITS.md` listing source, creator, license, link, and any attribution requirements for **every third-party sound**. Use original synthesized WAV/OGG placeholder files if no licensed files are present; distinguish these from final production sounds.

Do not download files or rely on online CDNs at runtime. Do not include sounds ripped from Batman, Arkham, Star Wars, or other copyrighted games or films.

## 5. Build a sound test panel

Add a small debug panel available in development mode (or behind an explicit debug flag) with:

- Enable Audio / Mute
- Master, SFX, ambience, vehicle, music, UI volume sliders
- Test buttons for at least UI click, armor step, jump, landing, vehicle engine, city ambience, and Citadel ambience
- Status messages for audio enabled/disabled, file load failure, and currently playing loops

This lets Owen confirm audio works **before** the rest of the game is complete.

## 6. Verify in browser

1. Run the project's existing install/build/test scripts, and repair any errors caused by these changes.
2. Test audio unlock after a button click in Chrome.
3. Verify muted startup, volume changes, and refresh persistence.
4. Verify city/Citadel transitions do not stack ambience loops.
5. Verify rapid sound events do not cause clipping or runaway overlapping playback.
6. Verify positional vehicle sounds grow quieter at distance, if implemented.
7. Verify missing files don't crash the game.
8. State clearly which interactive events were tested in a browser and which were only statically checked. If interactive testing is unavailable, provide Owen with exact manual test steps.

## 7. Required deliverables

Make actual edits and leave the game working. Provide:

- Audio manager implementation and audio manifest.
- Initial audio files or playable original placeholders.
- Wired integrations for **existing** menu, movement, environment, and vehicle events.
- Development sound-test panel.
- `docs/AUDIO_SETUP.md`: architecture, how to replace files, how to add a sound event, and how to test.
- `AUDIO_CREDITS.md` and an accurate list of outstanding audio needs.
- Brief summary of changed files, build/test results, and any blockers.

**Definition of done:** Owen can launch the existing browser game, click Enable Audio, test sounds from the debug panel, hear sounds during supported gameplay actions, control volume/mute, and reload without losing audio preferences. Do not call this completed until these behaviors work or clearly document untested points.

**Begin by inspecting the existing project, then implement the smallest end-to-end working audio slice before expanding it.**
