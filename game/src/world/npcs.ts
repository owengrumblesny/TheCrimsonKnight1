import * as THREE from 'three';
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';
import npcConfig from '../../../config/npc_assets.json';
import { registry } from '../data/registry';
import type { Physics } from '../systems/physics';

interface NpcSpot {
  id: string;
  x: number;
  z: number;
  rotY: number;
  clip: string;
}

interface Npc {
  root: THREE.Object3D;
  mixer: THREE.AnimationMixer | null;
  /** accumulated time not yet fed to the mixer (far NPCs animate at a lower rate) */
  pending: number;
  spin: THREE.Object3D[];
  meshes: THREE.Mesh[];
  shadow: boolean;
}

/** NPCs cast shadows only this close to the focus (the moon's shadow frustum is ≤45 m anyway). */
const SHADOW_DIST = 30;

const scaleOf = new Map<string, number>(npcConfig.npcs.map((n) => [n.id, (n as { scale?: number }).scale ?? 1]));

/**
 * Ambient NPC / enemy population. Directive: assets before gameplay, so there is NO AI here -- each NPC
 * stands at a fixed spot playing an idle-family loop (idle, talk, alert, cower). Budget: one skinned mesh
 * and one material per NPC; mixers are skipped beyond 60 m and updated at ~10 Hz beyond 18 m.
 */
export class NpcCrowd {
  readonly group = new THREE.Group();
  readonly npcs: Npc[] = [];
  private rand = mulberry(0x5eed);

  constructor(private scene: THREE.Scene, private physics: Physics) {
    this.group.name = 'NPCs';
  }

  async build(): Promise<void> {
    this.scene.add(this.group);
    for (const s of this.layout()) await this.spawn(s);
    // patrol drone hovering over the intersection (rigid model, rotor clip)
    const drone = await registry.instance('npc_patrol_drone');
    drone.position.set(6, 6.5, -6);
    this.group.add(drone);
    const gltf = await registry.gltf('npc_patrol_drone');
    const mixer = new THREE.AnimationMixer(drone);
    for (const clip of gltf.animations) mixer.clipAction(clip).play();
    this.npcs.push({ root: drone, mixer, pending: 0, spin: [], meshes: [], shadow: true });
  }

  private layout(): NpcSpot[] {
    const civ = ['npc_civilian_a', 'npc_civilian_b', 'npc_office_worker', 'npc_scientist', 'npc_mechanic', 'npc_construction_worker'];
    const out: NpcSpot[] = [];
    // civilians along the sidewalks (some in talking pairs)
    for (let i = 0; i < 14; i++) {
      const along = (this.rand() < 0.5 ? -1 : 1) * (12 + this.rand() * 48);
      const side = this.rand() < 0.5 ? -1 : 1;
      const off = side * (5.2 + this.rand() * 1.2);
      const xAxis = this.rand() < 0.5;
      const x = xAxis ? along : off;
      const z = xAxis ? off : along;
      const id = civ[i % civ.length];
      if (i % 4 === 0) {
        const dx = xAxis ? 0.9 : 0;
        const dz = xAxis ? 0 : 0.9;
        const face = Math.atan2(dx, dz);
        out.push({ id, x, z, rotY: face, clip: 'NPC_Talk' }, { id: civ[(i + 1) % civ.length], x: x + dx, z: z + dz, rotY: face + Math.PI, clip: 'NPC_Idle' });
      } else out.push({ id, x, z, rotY: this.rand() * Math.PI * 2, clip: 'NPC_Idle' });
    }
    // law enforcement at the intersection corners and the Owen Enterprises frontage
    out.push({ id: 'npc_police_officer', x: 6.2, z: 5.6, rotY: -2.4, clip: 'NPC_Idle' },
      { id: 'npc_police_officer', x: -6.0, z: -6.4, rotY: 0.7, clip: 'NPC_Idle' },
      { id: 'npc_security_guard', x: -18, z: -6.0, rotY: 0, clip: 'NPC_Idle' },
      { id: 'npc_security_guard', x: -21, z: -6.0, rotY: 0, clip: 'NPC_Idle' });
    // enemy groups: thugs in the dumpster alley, a merc squad in the industrial yard
    out.push({ id: 'npc_criminal_thug', x: -41.5, z: 7.6, rotY: 0.4, clip: 'NPC_Alert' },
      { id: 'npc_criminal_thug', x: -38.8, z: 7.2, rotY: -0.5, clip: 'NPC_Talk' },
      { id: 'npc_criminal_thug', x: -40.2, z: 6.2, rotY: Math.PI, clip: 'NPC_Idle' },
      { id: 'npc_mercenary', x: 88, z: -4.5, rotY: -1.2, clip: 'NPC_Alert' },
      { id: 'npc_mercenary', x: 90.5, z: -3.4, rotY: Math.PI, clip: 'NPC_Alert' },
      { id: 'npc_enforcer', x: 95, z: -2.5, rotY: Math.PI * 0.9, clip: 'NPC_Alert' },
      { id: 'npc_riot_trooper', x: 84, z: -1.8, rotY: -Math.PI / 2, clip: 'NPC_Alert' },
      { id: 'npc_riot_trooper', x: 84, z: 0.6, rotY: -Math.PI / 2, clip: 'NPC_Alert' },
      { id: 'npc_stealth_operative', x: 97.5, z: 3.5, rotY: -2.2, clip: 'NPC_Alert' },
      { id: 'npc_security_robot', x: 80, z: -5.5, rotY: -Math.PI / 2, clip: 'NPC_Alert' },
      { id: 'npc_security_robot', x: -24, z: -6.0, rotY: 0, clip: 'NPC_Idle' });
    return out;
  }

  private async spawn(s: NpcSpot): Promise<void> {
    const gltf = await registry.gltf(s.id);
    const root = cloneSkinned(gltf.scene);
    const meshes: THREE.Mesh[] = [];
    root.traverse((o) => {
      const mesh = o as THREE.SkinnedMesh;
      if (mesh.isMesh) {
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        meshes.push(mesh);
      }
    });
    root.position.set(s.x, 0, s.z);
    root.rotation.y = s.rotY;
    root.scale.setScalar(scaleOf.get(s.id) ?? 1);
    this.group.add(root);
    const mixer = new THREE.AnimationMixer(root);
    const clip = gltf.animations.find((c) => c.name === s.clip) ?? gltf.animations.find((c) => c.name === 'NPC_Idle');
    if (clip) {
      const action = mixer.clipAction(clip);
      action.time = this.rand() * clip.duration; // desync identical idles
      action.play();
    }
    // NPCs stay in place playing idle-family loops, so a posed bounding sphere with margin is a safe cull volume
    // (frustum culling off made every NPC render in both the main and shadow pass)
    mixer.update(0);
    root.updateMatrixWorld(true);
    for (const m of meshes) {
      const sk = m as THREE.SkinnedMesh;
      if (sk.isSkinnedMesh) {
        sk.computeBoundingSphere();
        sk.boundingSphere!.radius *= 1.4;
      }
    }
    this.npcs.push({ root, mixer, pending: 0, spin: [], meshes, shadow: true });
    const r = 0.28;
    this.physics.addStaticBox(new THREE.Box3(new THREE.Vector3(s.x - r, 0, s.z - r), new THREE.Vector3(s.x + r, 1.8, s.z + r)));
  }

  update(focus: THREE.Vector3, dt: number): void {
    for (const n of this.npcs) {
      const d = n.root.position.distanceTo(focus);
      n.root.visible = d < 90;
      const shadow = d < SHADOW_DIST;
      if (shadow !== n.shadow) {
        n.shadow = shadow;
        for (const m of n.meshes) m.castShadow = shadow;
      }
      if (!n.mixer || d > 60) continue;
      n.pending += dt;
      if (d > 18 && n.pending < 0.1) continue;
      n.mixer.update(n.pending);
      n.pending = 0;
    }
  }
}

function mulberry(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
