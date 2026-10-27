import * as THREE from 'three';
import { Hero } from './actors/hero';
import { Player } from './actors/player';
import { Input, lockPointer } from './core/input';
import { physicsConfig, worldConfig } from './data/registry';
import { Effects } from './render/effects';
import { FollowCamera } from './render/followCamera';
import { Stage } from './render/stage';
import { AudioManager } from './systems/audio';
import { Equipment } from './systems/equipment';
import { Physics } from './systems/physics';
import { Vitals } from './systems/vitals';
import { runAssetLoadTest } from './testing/assetLoadTest';
import { AnimDebug } from './ui/AnimDebug';
import { Hotbar } from './ui/Hotbar';
import { HudWidgets } from './ui/HudWidgets';
import { Bindings, SLOT_ACTIONS } from './ui/inputBindings';
import { LoadingScreen } from './ui/loading';
import { MenuManager } from './ui/MenuManager';
import { InventoryService, SaveService } from './ui/uiState';
import './ui/ui.css';
import { District } from './world/district';

/** ?nolock: automated tests — no automatic pointer lock and no pause-on-lock-loss. */
const TEST_NO_LOCK = new URLSearchParams(location.search).has('nolock');

async function startGame(): Promise<void> {
  // ---- persistent state: settings/bindings survive "New Sandbox"; the save holds the session ----
  const saves = new SaveService();
  const prefs = saves.readSettings();
  const settings = prefs.settings;
  const bindings = new Bindings(prefs.bindings);
  const inventory = new InventoryService();
  let quickVehicle = 'crx1_interceptor';

  const stage = new Stage();
  const input = new Input(stage.renderer.domElement, bindings);
  const audio = new AudioManager(settings);
  const loading = new LoadingScreen();
  const physics = await loading.track('Rapier physics', Physics.create());
  const district = new District(stage.scene, physics);
  const effects = new Effects(stage.scene);
  const [hero] = await Promise.all([
    loading.track('CR-X9 Crimson Knight', Hero.load()),
    loading.track('New Gotham district', district.build()),
    loading.track('effect sprites', effects.load()),
  ]);
  stage.scene.add(hero.root);
  if (worldConfig.weather === 'rain') stage.enableRain();

  const [sx, sy, sz] = worldConfig.spawn;
  const spawn = new THREE.Vector3(sx, sy - 2, sz);
  const player = new Player(physics, hero, spawn);
  const cam = new FollowCamera(stage.camera);
  const vitals = new Vitals();

  // ---- UI ----
  const hud = new HudWidgets(inventory, vitals);
  document.body.appendChild(hud.root);
  const notify = (text: string, icon?: string, kind?: 'info' | 'warn') => hud.notify(text, icon, kind);
  const selectSlot = (i: number) => {
    const err = inventory.selectSlot(i);
    hotbar.flash(i);
    if (err) {
      notify(err, 'inventory', 'warn');
      audio.play('ui.deny');
      return;
    }
    audio.play('ui.select');
    player.setGadget(inventory.selectedItemId); // equip animation only — never uses the item
  };
  const hotbar = new Hotbar(inventory, bindings, selectSlot);
  hud.root.appendChild(hotbar.el);
  const animDebug = new AnimDebug(hero);
  const equipment = new Equipment({
    scene: stage.scene, camera: stage.camera, physics, player, hero, district, effects, inventory, vitals, audio, notify,
    setPhotoMode: (on) => document.body.classList.toggle('ck-hud-off', on || !settings.hudVisible),
  });

  const applySettings = () => {
    document.documentElement.style.setProperty('--ck-scale', String(settings.uiScale));
    document.body.classList.toggle('ck-reduce-motion', settings.reduceMotion);
    document.body.classList.toggle('ck-hud-off', !settings.hudVisible || equipment.photoMode);
    stage.applyQuality(settings.quality);
    audio.applySettings(settings);
    saves.writeSettings(settings, bindings.overrides());
  };
  applySettings();

  const snapshot = () => ({
    inventory: inventory.snapshot(), bindings: bindings.overrides(), settings, quickVehicle,
    player: { position: player.position.toArray() as [number, number, number], heading: player.heading },
  });
  const saveNow = () => {
    saves.write(snapshot());
    notify('Game saved', 'save');
  };
  const loadSave = () => {
    const s = saves.read();
    if (!s) return;
    inventory.load(s.inventory);
    if (s.quickVehicle) quickVehicle = s.quickVehicle;
    if (s.player) {
      player.teleport(new THREE.Vector3(...s.player.position).setY(s.player.position[1] + 0.05));
      player.heading = s.player.heading;
    }
    notify('Save loaded', 'load');
  };

  let started = false;
  const menus = new MenuManager({
    inventory, bindings, settings, vitals, audio,
    readSave: () => saves.read(),
    play: () => {
      started = true;
    },
    continueSave: () => {
      loadSave();
      started = true;
    },
    newSandbox: () => {
      saves.clear();
      inventory.load(InventoryService.fresh());
      vitals.reset();
      player.respawn(spawn.clone().setY(spawn.y + 1));
      started = true;
      notify('New sandbox started — explore freely', 'sandbox');
    },
    saveNow,
    applySettings,
    captureKey: (cb) => {
      input.capture = cb;
    },
    selectSlot,
    quickVehicle: () => quickVehicle,
    setQuickVehicle: (id) => {
      quickVehicle = id;
    },
    notify,
    playerPose: () => ({ x: player.position.x, z: player.position.z, heading: player.heading }),
    mapFeatures: () => district.mapFeatures,
    onOpenChange: (open) => {
      input.clear(); // nothing stays held across a menu
      audio.setPaused(open);
      if (open) document.exitPointerLock?.();
      else if (!TEST_NO_LOCK) lockPointer(stage.renderer.domElement); // closing is always a user action
    },
  });
  // Esc while the mouse is captured only releases pointer lock (no keydown) — treat that as "pause"
  document.addEventListener('pointerlockchange', () => {
    if (!document.pointerLockElement && started && !menus.open && !animDebug.visible && !TEST_NO_LOCK) menus.show('pause');
  });

  player.onLand = (vy, hard, feet) => {
    effects.landing(feet, hard);
    audio.play('armor.land', Math.min(1, -vy / 20));
    const dmg = vitals.impact(vy, performance.now(), physicsConfig.player.hardLandingSpeed);
    if (dmg > 0) notify(`Impact damage −${Math.round(dmg)} health`, 'health', 'warn');
  };

  loading.hide();
  menus.show('main');

  // ---- interactables (real): shove loose props, Citadel entrance ----
  const [px, , pz] = worldConfig.redCitadelPortal;
  const portal = new THREE.Vector3(px, 0, pz);
  const nearestProp = () => {
    let best: (typeof district.dynamic)[number] | null = null;
    let bestD = 2.6;
    for (const d of district.dynamic) {
      const dist = d.obj.position.distanceTo(player.position.clone().setY(d.obj.position.y));
      if (dist < bestD) {
        bestD = dist;
        best = d;
      }
    }
    return best;
  };

  const clock = new THREE.Clock();
  let acc = 0;
  let stepDist = 0;
  let autosave = 0;
  const lastPos = new THREE.Vector3();
  const frame = (dt: number) => {
    const now = performance.now();
    input.poll();
    if (input.hit('sandboxMenu') && !menus.open) animDebug.toggle();

    // ---- menu hotkeys (Esc / Tab / M) ----
    if (menus.open) {
      if (input.hit('pause')) menus.back();
      else if (input.hit('inventory') && menus.top === 'inventory') menus.back();
      else if (input.hit('map') && menus.top === 'map') menus.back();
    } else if (started) {
      if (input.hit('pause')) menus.show('pause');
      else if (input.hit('inventory')) menus.show('inventory');
      else if (input.hit('map')) menus.show('map');
    }
    const live = !menus.open; // menus pause the simulation and block gameplay binds

    if (live && !animDebug.clip) {
      // ---- hotbar: 1–8 select (never use), Q/R or wheel cycle, primary action uses ----
      SLOT_ACTIONS.forEach((a, i) => {
        if (input.hit(a)) selectSlot(i);
      });
      if (input.hit('slotPrev') || input.wheel < 0) inventory.cycle(-1);
      if (input.hit('slotNext') || input.wheel > 0) inventory.cycle(1);
      if (input.hit('primaryAction')) equipment.useSelected(now);
      if (input.hit('summonMenu')) {
        const v = inventory.def(quickVehicle)!;
        player.act('CK_Summon');
        audio.play('vehicle.summon');
        notify(`${v.displayName}: ${v.unavailableReason ?? 'on the way'}`, v.iconId, 'warn');
      }
      const prop = nearestProp();
      const nearPortal = player.position.distanceTo(portal) < 9;
      if (input.hit('interact')) {
        if (prop) {
          const dir = prop.obj.position.clone().sub(player.position).setY(0.4).normalize();
          prop.body.applyImpulse(dir.multiplyScalar(5 * prop.body.mass()), true);
          audio.play('armor.step');
        } else if (nearPortal) {
          notify(inventory.has('citadel_keycard') ? 'Keycard accepted — the Red Citadel interior is still under construction' : 'Access denied', 'citadel');
        }
      }
      if (input.hit('jump') && player.state.mode === 'ground') audio.play('armor.jump');
      player.handleInput(input);
      hud.setPrompt(prop ? bindings.get('interact') : nearPortal ? bindings.get('interact') : null,
        prop ? 'Shove' : 'Red Citadel entrance');
    } else hud.setPrompt(null);

    if (live) {
      acc += dt;
      player.canExert = vitals.energy > 1;
      while (acc >= physics.dt) {
        if (!animDebug.clip) player.fixedUpdate(physics.dt, input, cam.yaw, input.held('jump'));
        physics.step();
        acc -= physics.dt;
      }
      district.sync();
      if (!animDebug.clip) player.update(dt, acc / physics.dt);
      hero.update(dt);
      effects.update(dt);
      equipment.update(dt, now);
      inventory.tick(now);
      const st = player.state;
      vitals.update(dt, now, st.sprinting ? 'sprint' : st.mode === 'glide' ? 'glide' : null);
      if (vitals.critical) {
        notify('CR-X9 suit critical — emergency recall to spawn', 'health', 'warn');
        vitals.reset();
        player.respawn(spawn.clone().setY(spawn.y + 1));
      }
      // distance-based footsteps while grounded and moving
      const moved = player.position.distanceTo(lastPos);
      lastPos.copy(player.position);
      if (st.mode === 'ground' && st.grounded && moved < 1) {
        stepDist += moved;
        if (stepDist > (st.speed > 6 ? 1.6 : st.speed > 3 ? 1.25 : 0.8)) {
          stepDist = 0;
          audio.play('armor.step');
        }
      }
      if (started && (autosave += dt) > 30) {
        autosave = 0;
        saves.write(snapshot());
      }
    }
    animDebug.update(dt);
    cam.update(dt, input, player.position, input.held('grapple'));
    stage.follow(player.position);
    if (live) stage.updateRain(dt);
    const sel = inventory.selectedItemId;
    hud.update(now, player.heading, player.state.aiming || ((sel === 'grapple' || sel === 'batarang') && input.locked), bindings.get('primaryAction'));
    hotbar.update(now);
    stage.render();
    input.endFrame();
  };
  const loop = () => {
    frame(Math.min(clock.getDelta(), 0.1));
    requestAnimationFrame(loop);
  };
  loop();
  // test/debug handle: __CK__.advance(seconds) steps the game synchronously at 60 fps
  Object.assign(window, {
    __CK__: {
      player, hero, inventory, bindings, menus, equipment, vitals, settings, audio, cam,
      selectSlot,
      start: () => menus.closeAll(),
      teleport: (x: number, y: number, z: number) => player.teleport(new THREE.Vector3(x, y, z)),
      use: () => equipment.useSelected(performance.now()),
      advance: (seconds: number) => {
        started = true;
        for (let t = 0; t < seconds; t += 1 / 60) frame(1 / 60);
        clock.getDelta();
        return player.status;
      },
    },
  });
}

const params = new URLSearchParams(location.search);
(params.get('test') === 'assets' ? runAssetLoadTest() : startGame()).catch((e) => {
  console.error('[CK] fatal', e);
  document.body.insertAdjacentHTML('beforeend', `<pre style="color:#f55;padding:20px">${String(e?.stack ?? e)}</pre>`);
});
