# UI integration — CRIMSON_KNIGHT_UI_PACK (Part I)

Implements `CRIMSON_KNIGHT_UI_PACK/CLAUDE_CODE_READ_THIS_FIRST.txt` Part I inside the existing Three.js / TypeScript / Vite game. The Three.js canvas keeps running underneath an HTML/CSS overlay; no icon is a 3D mesh.

## Installed files

```text
game/public/ui/assets/               <- copied from CRIMSON_KNIGHT_UI_PACK/assets (294 files; previews NOT copied)
  action/ fictional_weapon/ gadget/ hud/ menu/ vehicle/   {glyph,circle}/<id>.{png,svg}
  keycaps/<key>.png
game/src/ui/data/                    <- copied configs, imported as typed JSON
  icon_manifest.json  hotbar_layout.json  menu_spec.json
game/src/ui/
  IconRegistry.ts    manifest lookup; uiUrl() prefixes import.meta.env.BASE_URL; unknown ids fall back to the notification glyph
  inventoryTypes.ts  Category / ItemDefinition / OwnedStack / HotbarSlot / InventoryState
  inventoryData.ts   item catalog: itemId -> iconId -> artId (board image) -> modelId -> useClip
  inputBindings.ts   one binding table (controls.json + hotbar_layout.json + saved overrides), conflict detection, typing guard
  uiState.ts         InventoryService (single source of truth), Settings, versioned SaveService
  Hotbar.ts          bottom-center 8-slot bar
  HudWidgets.ts      vitals, compass, notifications, selected item, crosshair, contextual prompt
  InventoryPanel.ts  tabs, search, sort, glyph cards, detail panel, equip / assign 1–8
  MenuManager.ts     main, pause, inventory, map, loadout, settings (graphics/audio/interface/controls)
  AnimDebug.ts       animation debug panel (backtick) with board key-pose flipbooks
  ui.css             theme tokens from the directive (--ck-red #d42a40, --ck-bright #ff405d, ...)
game/src/systems/
  equipment.ts       what "use selected item" actually does
  vitals.ts          health / armor / energy that gameplay really changes
  audio.ts           Web Audio buses + original synthesized placeholder sounds
game/tests/ui.test.ts  18 unit tests (icon paths, bindings, inventory/hotbar sync, saves)
```

Icon roles follow the directive: **circle PNG** only inside hotbar slots; **glyph PNG** on inventory cards, tabs, menus, HUD; **glyph SVG** in the inventory detail panel; **keycaps** for world prompts (textual tags elsewhere, never both stacked).

## Bindings (default; all rebindable except Esc)

| Key | Action | Note |
|---|---|---|
| 1–8 | Select hotbar slot (never uses the item) | `KeyboardEvent.code`, auto-repeat ignored |
| Left mouse | Use selected item | only while the mouse is captured |
| Q / R, mouse wheel | Previous / next slot | **Changed from the pack's Q/E**: E is the game's Interact, so it stays Interact and next-slot moved to R |
| Tab | Inventory (Tab again closes it) | |
| M | Map | |
| Esc | Pause / back | fixed; losing pointer lock while playing also opens Pause |
| E | Interact (shove props, Citadel entrance) | unchanged |
| V | Call quick-select vehicle | plays the call; vehicles are not drivable yet |
| G | Aim | unchanged |
| WASD, Shift, Space, C, CapsLock, ` | unchanged movement / debug | |

Gamepad (standard): A jump · B crouch · X interact · Y inventory · LB/RB prev/next slot · LT aim · RT use · L3 sprint · Start pause · Back map · D-pad up call vehicle. Menu navigation by gamepad is **not** implemented.

Rebinding a key that is in use swaps the two actions and shows a warning, so nothing is left unbound.

## What each visible control does

Every button performs a real action or is visibly disabled with its reason:

- **Main menu:** Play · Continue (disabled until a save exists) · New Sandbox · Settings · Controls · Quit (disabled: "Desktop build only").
- **Pause:** Resume · Inventory · Map · Equipment Loadout · Settings · Save · Exit to Main Menu (saves first).
- **Inventory:** five tabs (Gadgets default). Equip / Assign 1–8 / Remove write `InventoryService`. Vehicles are blueprints you can set as the quick-call vehicle.
- **Map:** top-down map drawn from the loaded district geometry, with a live player marker and the Red Citadel entrance. The Locations tab shows the board's concept images, labelled as not built yet.
- **Loadout:** suit panel (board art + live vitals), the 8 slots, vehicle quick-select.
- **Settings:**
  - Quality preset (resolution, shadows, rain), fullscreen.
  - Enable audio / mute / six volume buses.
  - UI scale, show HUD, reduce motion.
  - Subtitles: disabled, "Coming later".
  - Full key rebinding + reset.

Item effects (`equipment.ts`):
- Batarang: physics projectile, knocks props over.
- Grapnel: Rapier ray to a surface above you, reels you in.
- Scanner: highlights movable objects within 30 m.
- Recon drone: orbiting spotlight drone.
- Smoke: smoke sprites.
- Shield: 6 s dome that blocks fall damage.
- Cloak: 8 s near-invisibility.
- Beacons: up to 3, glowing.
- EMP: street lights within 25 m off for 6 s.
- Sonic: shoves props within 9 m.
- Helmet lamp: toggles a spotlight.
- Power cell / med kit / repair kit: restore energy / health / armor.
- Photo camera: hides the HUD.

Items with no effect yet (decoy, holoprojector, comms, forensics, all fictional weapons, vehicles) show an **N/A** badge and say why when used.

Vitals are real:
- Fall impacts above 11 m/s cost armor first, then health.
- Health regenerates after 6 s without damage.
- Energy drains while sprinting, gliding and using powered gadgets.
- At 0 energy you can't sprint or glide.
- At 0 health the suit recalls you to spawn.

## Saves

- `localStorage["crimson-knight.save"]` (version 1) holds the inventory, hotbar, selected slot, binding overrides, settings, quick vehicle and player position.
- `localStorage["crimson-knight.settings"]` holds settings and bindings, kept separately so they survive "New Sandbox".
- `SaveService.migrate` rejects corrupt or future versions, drops item ids that no longer exist, and clamps values.
- Autosave runs every 30 s while playing; there is also manual Save and save-on-exit.

## Tests actually run (2026-10-27)

- `npm test` (vitest): **18/18 pass**.
  - Coverage: all 93 manifest paths exist, roles and fallback, keycaps, item→icon/art/model links, default bindings and no duplicates, conflict swap, fixed keys, typing guard, select/assign/cycle/cooldown/restock/load sync, and save round-trip and migration.
  - A real bug was caught and fixed: saved overrides could rebind the fixed Esc key.
- `npm run build`: passes. The production preview loads 246/246 models and 613/613 images, serves the pack's PNG and SVG icons locally, and all 8 hotbar icons decode at 256 px.
- In the browser (dev, 1280×720 and 1920×1080, driven by `window.__CK__` with `?nolock`):
  - Hotbar and menu keys: 1–8 each select exactly one slot, and the UI, `InventoryService` and the player's equipped gadget agree. Selecting never consumed an item. Q/R cycle; Tab opens the inventory, Esc closes it, and Esc with no menu opens Pause.
  - Inventory assignment updates the hotbar icon.
  - Every implemented item was used, with real energy, quantity and cooldown changes. Unavailable items are refused with their reason.
  - Grapple: refuses anchors below you and pulls toward a street lamp.
  - Fall damage → repair kit worked. E shoves props, and V explains the vehicle is unavailable.
  - Map, loadout and settings screens all checked.
  - Rebinding with a conflict swaps the two keys and warns.
  - Settings, the hotbar and position persist across a page reload, and Continue loads them.
- **Not tested:**
  - Electron packaging: there is no Electron app in the project yet.
  - Real gamepad hardware.
  - Screen-reader output.
  - Audio audibility: sounds are wired, but I can't listen in this environment.
