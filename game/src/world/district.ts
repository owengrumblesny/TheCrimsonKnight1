import * as THREE from 'three';
import { registry, worldConfig } from '../data/registry';
import { mergeByMaterial } from '../render/batching';
import { pngMaterial } from '../render/materials';
import type { Physics } from '../systems/physics';
import type RAPIER from '@dimforge/rapier3d-compat';

interface Placement {
  x: number;
  z: number;
  rotY?: number;
  scale?: number;
}

/** Deterministic PRNG so the district layout is stable (seed from config/world.json). */
function rng(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

/**
 * First New Gotham test block, assembled from the manifest's placeholder GLBs:
 * two crossing avenues, building rows, street lights, furniture and physics props.
 * Repeating props are drawn with InstancedMesh; colliders are bounds boxes (to be replaced by
 * authored collision proxies as assets are upgraded).
 */
export class District {
  readonly dynamic: { body: RAPIER.RigidBody; obj: THREE.Object3D }[] = [];
  /** everything the city sector renders (hidden while the player is underground) */
  readonly group = new THREE.Group();
  /** every street-lamp head; offUntil > now = knocked out (EMP) */
  readonly lamps: { pos: THREE.Vector3; offUntil: number }[] = [];
  /** fixed-size pool of real point lights moved to the nearest working lamps (size per graphics preset) */
  private lightPool: THREE.PointLight[] = [];
  private poolTimer = 0;
  /** building footprints + road strips for the map screen (world XZ metres) */
  readonly mapFeatures: { kind: 'building' | 'road' | 'portal' | 'billboard'; minX: number; minZ: number; maxX: number; maxZ: number }[] = [];
  private rand = rng(worldConfig.seed);

  constructor(scene: THREE.Scene, private physics: Physics) {
    this.group.name = 'Sector_Downtown';
    scene.add(this.group);
  }

  async build(): Promise<void> {
    const asphalt = registry.texture('wet_asphalt').clone();
    asphalt.repeat.set(200, 200);
    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(400, 400),
      new THREE.MeshStandardMaterial({ map: asphalt, roughness: 0.28, metalness: 0.15 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    this.group.add(ground);
    this.physics.addGround(400);

    const roadTiles: Placement[] = [];
    const walks: Placement[] = [];
    for (let i = -10; i <= 10; i++) {
      roadTiles.push({ x: i * 6, z: 0 }, { x: 0, z: i * 6 });
      if (i !== 0) {
        for (const o of [-6, 6]) walks.push({ x: i * 6, z: o }, { x: o, z: i * 6 });
      }
    }
    await this.instanced('road_tile_v01', roadTiles, { collide: false, shadow: false });
    await this.instanced('sidewalk_tile_v01', walks, { collide: true, shadow: false });

    // building rows along both avenues, skipping the intersection corners' sidewalks
    const kinds = ['building_low_v01', 'building_mid_v01', 'building_high_v01', 'building_low_v02', 'building_mid_v02',
      'building_high_v02', 'tower_v01', 'building_mid_v03'];
    const lots = new Map<string, Placement[]>();
    for (let i = -9; i <= 9; i += 1.5) {
      if (Math.abs(i) < 2) continue;
      for (const side of [-1, 1]) {
        const k1 = kinds[Math.floor(this.rand() * kinds.length)];
        const k2 = kinds[Math.floor(this.rand() * kinds.length)];
        (lots.get(k1) ?? lots.set(k1, []).get(k1)!).push({ x: i * 6, z: side * 15, rotY: side > 0 ? Math.PI : 0 });
        (lots.get(k2) ?? lots.set(k2, []).get(k2)!).push({ x: side * 15, z: i * 6, rotY: side > 0 ? -Math.PI / 2 : Math.PI / 2 });
      }
    }
    for (const [id, list] of lots) await this.instanced(id, list, { collide: true, mapKind: 'building' });
    this.mapFeatures.push({ kind: 'road', minX: -63, maxX: 63, minZ: -3, maxZ: 3 }, { kind: 'road', minX: -3, maxX: 3, minZ: -63, maxZ: 63 });

    // street lights with real lights near the spawn
    const lamps: Placement[] = [];
    for (let i = -8; i <= 8; i += 2) {
      if (i === 0) continue;
      lamps.push({ x: i * 6, z: -7.5, rotY: Math.PI / 2 }, { x: 7.5, z: i * 6, rotY: Math.PI });
    }
    await this.instanced('street_light_v01', lamps, { collide: true });
    for (const l of lamps) this.lamps.push({ pos: new THREE.Vector3(l.x, 3.6, l.z), offUntil: 0 });

    const scatter = (ids: string[], n: number, r: number): Map<string, Placement[]> => {
      const out = new Map<string, Placement[]>();
      for (let i = 0; i < n; i++) {
        const along = (this.rand() - 0.5) * 2 * r;
        const side = this.rand() < 0.5 ? -1 : 1;
        const off = side * (4.6 + this.rand() * 2.4);
        const p = this.rand() < 0.5 ? { x: along, z: off } : { x: off, z: along };
        if (Math.hypot(p.x, p.z) < 6) continue;
        const id = ids[i % ids.length];
        (out.get(id) ?? out.set(id, []).get(id)!).push({ ...p, rotY: this.rand() * Math.PI * 2 });
      }
      return out;
    };
    for (const [id, list] of scatter(['trash_can_v01', 'fire_hydrant_v01', 'bench_v01', 'mailbox_v01', 'planter_v01',
      'parking_meter_v01', 'bollard_v01', 'bus_stop_v01', 'dumpster_v01'], 70, 55)) {
      await this.instanced(id, list, { collide: true });
    }
    const cars: Placement[] = [];
    for (let i = 0; i < 10; i++) {
      const along = (this.rand() - 0.5) * 100;
      if (Math.abs(along) < 10) continue;
      const lane = this.rand() < 0.5 ? -1.6 : 1.6;
      cars.push(i % 2 ? { x: along, z: lane, rotY: 0 } : { x: lane, z: along, rotY: Math.PI / 2 });
    }
    await this.instanced('car_prop_v01', cars, { collide: true });

    // physics playthings
    for (const [id, list] of scatter(['crate_v01', 'barrel_v01', 'traffic_cone_v01', 'pallet_v01'], 28, 30)) {
      for (const p of list) await this.dynamicProp(id, p);
    }

    await this.billboards();
    await this.citadelPortal();
  }

  /** Owen Enterprises billboards showing vehicle / city images cut from the concept boards. */
  private async billboards(): Promise<void> {
    // individual images cut from Owen's boards (config/image_catalog.json)
    const art = ['vehicles/x1_crx1_showcase', 'vehicles/b1_crb1_showcase', 'vehicles/a1_cra1_showcase', 'world/c_downtown_wide',
      'vehicles/x1_crx1_pursuit', 'world/c_citadel_main_hangar_wide', 'vehicles/a1_cra1_flight', 'world/c_rooftops_wide'];
    // [x, z, rotY]: above the sidewalks, facing the avenues
    const spots: [number, number, number][] = [
      [-21, -10.4, 0], [21, 10.4, Math.PI], [10.4, -27, -Math.PI / 2], [-10.4, 27, Math.PI / 2],
      [-45, 10.4, Math.PI], [45, -10.4, 0], [-10.4, -45, Math.PI / 2], [10.4, 45, -Math.PI / 2],
    ];
    const frameMat = pngMaterial('gunmetal', (t) => registry.texture(t));
    const trimMat = pngMaterial('red_emissive', (t) => registry.texture(t));
    await Promise.all(spots.map(async ([x, z, rot], i) => {
      const id = art[i % art.length];
      const tex = await registry.imageTexture(id);
      const img = tex.image as { width: number; height: number };
      const w = 9;
      const h = Math.min(6.5, (w * img.height) / img.width);
      const board = new THREE.Group();
      board.position.set(x, 0, z);
      board.rotation.y = rot;
      const face = new THREE.Mesh(
        new THREE.PlaneGeometry(w, h),
        new THREE.MeshStandardMaterial({ map: tex, emissiveMap: tex, emissive: 0xffffff, emissiveIntensity: 0.75, roughness: 0.6 }),
      );
      face.position.set(0, 7 + h / 2, 0.16);
      const back = new THREE.Mesh(new THREE.BoxGeometry(w + 0.5, h + 0.5, 0.25), frameMat);
      back.position.set(0, 7 + h / 2, 0);
      const trim = new THREE.Mesh(new THREE.BoxGeometry(w + 0.6, 0.12, 0.3), trimMat);
      trim.position.set(0, 6.8, 0.02);
      const post = new THREE.Mesh(new THREE.BoxGeometry(0.4, 7, 0.4), frameMat);
      post.position.set(0, 3.5, -0.2);
      for (const m of [back, post]) m.castShadow = true;
      board.add(face, back, trim, post);
      this.group.add(board);
      board.updateMatrixWorld(true);
      this.physics.addStaticBox(new THREE.Box3().setFromObject(post));
    }));
  }

  /** Red Citadel entrance marker at config/world.json redCitadelPortal (traversable Citadel is M4). */
  private async citadelPortal(): Promise<void> {
    const [x, , z] = worldConfig.redCitadelPortal;
    await this.instanced('landing_pad_v01', [{ x, z, scale: 2 }], { collide: true, texture: 'cavern_stone', mapKind: 'portal' });
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(4, 0.12, 12, 64),
      new THREE.MeshStandardMaterial({ color: '#330000', emissive: '#ff2020', emissiveIntensity: 3 }),
    );
    ring.position.set(x, 4.5, z);
    this.group.add(ring);
    const glow = new THREE.PointLight(0xff2020, 40, 30, 1.5);
    glow.position.set(x, 4, z);
    this.group.add(glow);
    // holo panels flanking the portal: Red Citadel images from the boards
    const panels: [string, number][] = [['world/c_citadel_entrance_wide', -1], ['world/c_citadel_command_center_wide', 1]];
    for (const [id, side] of panels) {
      const tex = await registry.imageTexture(id);
      const img = tex.image as { width: number; height: number };
      const w = 6, h = (w * img.height) / img.width;
      const panel = new THREE.Mesh(
        new THREE.PlaneGeometry(w, h),
        new THREE.MeshBasicMaterial({ map: tex, transparent: true, opacity: 0.85, side: THREE.DoubleSide, toneMapped: false }),
      );
      panel.position.set(x + side * 7.5, 3 + h / 2, z + 1);
      panel.rotation.y = -side * 0.35;
      this.group.add(panel);
    }
  }

  private matrixFor(p: Placement): THREE.Matrix4 {
    return new THREE.Matrix4().compose(
      new THREE.Vector3(p.x, 0, p.z),
      new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), p.rotY ?? 0),
      new THREE.Vector3().setScalar(p.scale ?? 1),
    );
  }

  /** One InstancedMesh per sub-mesh of the asset; optional static bounds colliders. */
  async instanced(id: string, list: Placement[], opts: { collide: boolean; shadow?: boolean; texture?: string; mapKind?: 'building' | 'portal' }): Promise<void> {
    if (!list.length) return;
    const proto = await registry.instance(id, opts.texture);
    const localBox = new THREE.Box3().setFromObject(proto);
    // one InstancedMesh per MATERIAL (sub-meshes merged), not per sub-mesh — keeps draw calls low
    for (const { geometry, material } of mergeByMaterial(proto)) {
      const inst = new THREE.InstancedMesh(geometry, material, list.length);
      list.forEach((p, i) => inst.setMatrixAt(i, this.matrixFor(p)));
      inst.castShadow = opts.shadow ?? true;
      inst.receiveShadow = true;
      inst.computeBoundingSphere();
      this.group.add(inst);
    }
    for (const p of list) {
      const box = localBox.clone().applyMatrix4(this.matrixFor(p));
      if (opts.collide) this.physics.addStaticBox(box);
      if (opts.mapKind) this.mapFeatures.push({ kind: opts.mapKind, minX: box.min.x, minZ: box.min.z, maxX: box.max.x, maxZ: box.max.z });
    }
  }

  private async dynamicProp(id: string, p: Placement): Promise<void> {
    const obj = await registry.instance(id);
    const box = new THREE.Box3().setFromObject(obj);
    const center = box.getCenter(new THREE.Vector3());
    // re-centre the visual on the collider origin
    obj.children[0].position.sub(center);
    const pivot = new THREE.Group();
    pivot.add(obj);
    obj.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) o.castShadow = o.receiveShadow = true;
    });
    const placed = box.clone().applyMatrix4(this.matrixFor({ ...p, rotY: 0 })); // body starts axis-aligned with its visual
    const body = this.physics.addDynamicBox(placed, id.startsWith('traffic_cone') ? 3 : 25);
    this.group.add(pivot);
    this.dynamic.push({ body, obj: pivot });
  }

  /** Resize the street-light pool (called when the graphics preset changes; causes one shader recompile). */
  setLightPool(n: number): void {
    for (const l of this.lightPool) l.removeFromParent();
    this.lightPool = Array.from({ length: n }, () => {
      const l = new THREE.PointLight(0xffb070, 18, 22, 1.6);
      this.group.add(l);
      return l;
    });
    this.poolTimer = 0;
  }

  /** Move pooled lights to the nearest working lamps (throttled). */
  updateLights(center: THREE.Vector3, now: number, dt: number): void {
    if ((this.poolTimer -= dt) > 0) return;
    this.poolTimer = 0.25;
    const live = this.lamps.filter((l) => l.offUntil <= now)
      .sort((a, b) => a.pos.distanceToSquared(center) - b.pos.distanceToSquared(center));
    this.lightPool.forEach((light, i) => {
      const lamp = live[i];
      light.intensity = lamp ? 18 : 0;
      if (lamp) light.position.copy(lamp.pos);
    });
  }

  /** Copy dynamic body transforms to their visuals. */
  sync(): void {
    for (const { body, obj } of this.dynamic) {
      obj.position.copy(body.translation() as THREE.Vector3Like);
      obj.quaternion.copy(body.rotation() as THREE.QuaternionLike);
    }
  }
}
