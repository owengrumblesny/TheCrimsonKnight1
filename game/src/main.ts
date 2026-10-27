import * as THREE from 'three';
import { Hero } from './actors/hero';
import { Player } from './actors/player';
import { Input } from './core/input';
import { worldConfig } from './data/registry';
import { FollowCamera } from './render/followCamera';
import { Stage } from './render/stage';
import { Effects } from './render/effects';
import { Physics } from './systems/physics';
import { runAssetLoadTest } from './testing/assetLoadTest';
import { Hud } from './ui/hud';
import { LoadingScreen } from './ui/loading';
import { District } from './world/district';

async function startGame(): Promise<void> {
  const stage = new Stage();
  const input = new Input(stage.renderer.domElement);
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
  const player = new Player(physics, hero, new THREE.Vector3(sx, sy - 2, sz));
  player.onLand = (hard, feet) => effects.landing(feet, hard);
  const cam = new FollowCamera(stage.camera);
  const hud = new Hud(hero, player, stage.renderer.domElement);
  loading.hide();

  const clock = new THREE.Clock();
  let acc = 0;
  const frame = (dt: number) => {
    input.poll();
    if (input.hit('sandboxMenu')) hud.togglePanel();
    if (hud.menu) {
      if (input.hit('pause')) hud.close();
      for (let i = 0; i < 9; i++) if (input.hitCode(`Digit${i + 1}`)) hud.pickIndex(i);
    } else if (input.hit('pause')) hud.open('pause');
    else if (input.hit('gadgetMenu')) hud.open('gadget');
    else if (input.hit('summonMenu')) hud.open('summon');
    const live = !hud.menu; // menus pause the simulation
    if (live && !hud.debugClip) player.handleInput(input);
    if (live) {
      acc += dt;
      while (acc >= physics.dt) {
        if (!hud.debugClip) player.fixedUpdate(physics.dt, input, cam.yaw, input.held('jump'));
        physics.step();
        acc -= physics.dt;
      }
      district.sync();
      if (!hud.debugClip) player.update(dt, acc / physics.dt);
      hero.update(dt);
      effects.update(dt);
    }
    cam.update(dt, input, player.position, input.held('grapple'));
    stage.follow(player.position);
    if (live) stage.updateRain(dt);
    hud.update(dt);
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
      player,
      hero,
      hud,
      teleport: (x: number, y: number, z: number) => player.teleport(new THREE.Vector3(x, y, z)),
      advance: (seconds: number) => {
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
