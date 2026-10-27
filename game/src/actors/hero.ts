import * as THREE from 'three';
import { HERO_ID, heroClips, registry, type ClipMeta } from '../data/registry';

interface PlayOptions {
  fade?: number;
  timeScale?: number;
  restart?: boolean;
}

/** The CR-X9 visual: skinned GLB + AnimationMixer with cross-faded CK_* clips. */
export class Hero {
  readonly root = new THREE.Group();
  readonly meta = new Map<string, ClipMeta>(heroClips.map((c) => [c.name, c]));
  private mixer!: THREE.AnimationMixer;
  private actions = new Map<string, THREE.AnimationAction>();
  current = '';
  /** meshes per level of detail (v2 GLB: *_LOD0 / *_LOD1 / *_LOD2); empty for single-LOD models */
  private lods: THREE.Object3D[][] = [[], [], []];
  lodLevel = 0;
  private finishedCb: ((name: string) => void) | null = null;

  static async load(): Promise<Hero> {
    const hero = new Hero();
    const gltf = await registry.gltf(HERO_ID);
    const model = gltf.scene;
    model.traverse((o) => {
      const mesh = o as THREE.Mesh;
      if (mesh.isMesh) {
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        mesh.frustumCulled = false; // skinned bounds don't follow animation
      }
    });
    model.traverse((o) => {
      // a multi-material mesh is a group named *_LODn whose children are the primitives
      const m = /_LOD(\d)$/.exec(o.name);
      if (m) hero.lods[Number(m[1])].push(o);
    });
    hero.setLod(0);
    hero.root.add(model);
    hero.mixer = new THREE.AnimationMixer(model);
    for (const clip of gltf.animations) {
      const action = hero.mixer.clipAction(clip);
      const meta = hero.meta.get(clip.name);
      if (meta && !meta.loop) {
        action.setLoop(THREE.LoopOnce, 1);
        action.clampWhenFinished = true;
      }
      hero.actions.set(clip.name, action);
    }
    hero.mixer.addEventListener('finished', (e) => {
      const name = (e.action as THREE.AnimationAction).getClip().name;
      hero.finishedCb?.(name);
    });
    hero.play('CK_Idle', { fade: 0 });
    return hero;
  }

  get clipNames(): string[] {
    return [...this.actions.keys()].sort();
  }

  onFinished(cb: (name: string) => void): void {
    this.finishedCb = cb;
  }

  play(name: string, { fade = 0.22, timeScale = 1, restart = false }: PlayOptions = {}): void {
    const next = this.actions.get(name);
    if (!next) return;
    next.timeScale = timeScale;
    if (name === this.current && !restart) return;
    const prev = this.actions.get(this.current);
    next.reset();
    next.setEffectiveWeight(1);
    next.play();
    if (prev && prev !== next && fade > 0) prev.crossFadeTo(next, fade, false);
    else if (prev && prev !== next) prev.stop();
    this.current = name;
  }

  setTimeScale(scale: number): void {
    const a = this.actions.get(this.current);
    if (a) a.timeScale = scale;
  }

  /** Playback rate that keeps feet planted for a locomotion clip at the given ground speed. */
  rateFor(name: string, speed: number): number {
    const ref = this.meta.get(name)?.refSpeed;
    return ref ? THREE.MathUtils.clamp(speed / ref, 0.55, 1.8) : 1;
  }

  /** Show one level of detail. */
  setLod(level: number): void {
    if (!this.lods[1].length) return;
    this.lodLevel = level;
    this.lods.forEach((objs, i) => objs.forEach((o) => (o.visible = i === level)));
  }

  /** Pick LOD from camera distance; lodScale comes from the graphics preset (lower = switch sooner). */
  updateLod(cameraDistance: number, lodScale: number): void {
    const d = cameraDistance / lodScale;
    const level = d < 9 ? 0 : d < 26 ? 1 : 2;
    if (level !== this.lodLevel) this.setLod(level);
  }

  update(dt: number): void {
    this.mixer.update(dt);
  }
}
