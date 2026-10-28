import * as THREE from 'three';
import { registry, worldConfig } from '../data/registry';
import { mergeByMaterial } from '../render/batching';
import { pngMaterial } from '../render/materials';
import type { Physics } from '../systems/physics';
import type RAPIER from '@dimforge/rapier3d-compat';

interface Placement {
  x: number;
  z: number;
  y?: number;
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

    // ---- building rows: kit buildings placed facade-to-facade along both avenues ----
    // footprints (width along the street, depth) from config/citykit.json; facades sit 11 m from the road centre
    const FOOT: Record<string, [number, number]> = {
      kit_gothic_tower: [16, 16], kit_office_tower: [17, 17], kit_apartment: [14, 13], kit_warehouse: [24, 20], kit_shopfront: [10, 12],
    };
    const kinds = ['kit_apartment', 'kit_shopfront', 'kit_office_tower', 'kit_apartment', 'kit_warehouse', 'kit_shopfront', 'kit_gothic_tower'];
    const lots = new Map<string, Placement[]>();
    const add = (id: string, p: Placement) => (lots.get(id) ?? lots.set(id, []).get(id)!).push(p);
    for (const axis of ['x', 'z'] as const) {
      for (const side of [-1, 1]) {
        for (const dir of [-1, 1]) {
          let cursor = 12;
          while (cursor < 116) {
            const kind = kinds[Math.floor(this.rand() * kinds.length)];
            const [w, d] = FOOT[kind];
            if (cursor + w > 120) break;
            const along = dir * (cursor + w / 2);
            const off = side * (11 + d / 2);
            // near the intersection: full detail; further out: the merged LOD1 version (static distance split)
            const id = Math.abs(along) < 64 ? kind : `${kind}_lod1`;
            if (axis === 'x') add(id, { x: along, z: off, rotY: side > 0 ? Math.PI : 0 });
            else add(id, { x: off, z: along, rotY: side > 0 ? -Math.PI / 2 : Math.PI / 2 });
            cursor += w + 1.5;
          }
        }
      }
    }
    for (const [id, list] of lots) await this.instanced(id, list, { collide: true, mapKind: 'building' });
    // simplified distant skyline (LOD1 only, no collision): fills the horizon cheaply
    const sky = new Map<string, Placement[]>();
    for (let i = 0; i < 48; i++) {
      const a = (i / 48) * Math.PI * 2 + this.rand() * 0.05;
      const r = 150 + this.rand() * 70;
      const kind = ['kit_office_tower', 'kit_gothic_tower', 'kit_apartment'][i % 3];
      (sky.get(kind) ?? sky.set(kind, []).get(kind)!).push({ x: Math.cos(a) * r, z: Math.sin(a) * r, rotY: -a - Math.PI / 2, scale: 1 + this.rand() * 0.9 });
    }
    for (const [kind, list] of sky) await this.instanced(`${kind}_lod1`, list, { collide: false, shadow: false });
    this.mapFeatures.push({ kind: 'road', minX: -63, maxX: 63, minZ: -3, maxZ: 3 }, { kind: 'road', minX: -3, maxX: 3, minZ: -63, maxZ: 63 });

    // ---- street lights (arm over the road); the real light pool follows the lamp heads ----
    const lamps: Placement[] = [];
    for (let i = -9; i <= 9; i += 2) {
      if (Math.abs(i) < 2) continue;
      lamps.push({ x: i * 6, z: -3.7, rotY: -Math.PI / 2 }, { x: i * 6 + 6, z: 3.7, rotY: Math.PI / 2 });
      lamps.push({ x: 3.7, z: i * 6, rotY: Math.PI }, { x: -3.7, z: i * 6 + 6, rotY: 0 });
    }
    await this.instanced('kit_streetlight', lamps, { collide: true });
    for (const l of lamps) {
      const head = new THREE.Vector3(1.75, 6.55, 0).applyAxisAngle(new THREE.Vector3(0, 1, 0), l.rotY ?? 0);
      this.lamps.push({ pos: new THREE.Vector3(l.x, 0, l.z).add(head), offUntil: 0 });
    }

    // ---- intersection: traffic lights, crosswalks, signs; road furniture ----
    await this.instanced('kit_traffic_light', [
      { x: 4.4, z: 4.4, rotY: Math.PI }, { x: -4.4, z: -4.4, rotY: 0 }, { x: -4.4, z: 4.4, rotY: Math.PI / 2 }, { x: 4.4, z: -4.4, rotY: -Math.PI / 2 },
    ], { collide: true });
    await this.instanced('kit_crosswalk', [{ x: 7.5, z: 0, rotY: 0 }, { x: -7.5, z: 0, rotY: 0 }, { x: 0, z: 7.5, rotY: Math.PI / 2 }, { x: 0, z: -7.5, rotY: Math.PI / 2 }],
      { collide: false, shadow: false });
    await this.instanced('kit_street_sign', [{ x: 5.5, z: -5.5, rotY: 0.3 }, { x: -5.5, z: 5.5, rotY: Math.PI + 0.3 }], { collide: true });
    const covers: Placement[] = [];
    const drains: Placement[] = [];
    for (let i = -8; i <= 8; i++) {
      if (Math.abs(i) < 2) continue;
      covers.push({ x: i * 7.3, z: 0.9 * (i % 2 ? 1 : -1) }, { x: 0.9 * (i % 2 ? -1 : 1), z: i * 7.3 });
      drains.push({ x: i * 6.5 + 2, z: 2.75 }, { x: 2.75, z: i * 6.5 + 2, rotY: Math.PI / 2 });
    }
    await this.instanced('kit_manhole', covers, { collide: false, shadow: false });
    await this.instanced('kit_drain', drains, { collide: false, shadow: false });
    const trees: Placement[] = [];
    for (let i = -8; i <= 8; i++) {
      if (Math.abs(i) < 2) continue;
      trees.push({ x: i * 7 + 3, z: 8.2, rotY: i }, { x: i * 7 + 3, z: -8.2, rotY: i * 2 }, { x: 8.2, z: i * 7 + 3, rotY: i * 3 }, { x: -8.2, z: i * 7 + 3, rotY: i });
    }
    await this.instanced('kit_street_tree', trees, { collide: true });

    // ---- sidewalk props ----
    const scatter = (ids: string[], n: number, r: number): Map<string, Placement[]> => {
      const out = new Map<string, Placement[]>();
      for (let i = 0; i < n; i++) {
        const along = (this.rand() - 0.5) * 2 * r;
        const side = this.rand() < 0.5 ? -1 : 1;
        const off = side * (4.9 + this.rand() * 2.0);
        const p = this.rand() < 0.5 ? { x: along, z: off } : { x: off, z: along };
        if (Math.hypot(p.x, p.z) < 9) continue;
        const id = ids[i % ids.length];
        (out.get(id) ?? out.set(id, []).get(id)!).push({ ...p, rotY: this.rand() * Math.PI * 2 });
      }
      return out;
    };
    for (const [id, list] of scatter(['kit_trash_can', 'kit_hydrant', 'kit_bench', 'kit_mailbox', 'kit_recycling_bin', 'kit_vending_machine',
      'kit_utility_cabinet', 'kit_garbage_bag', 'kit_bus_shelter', 'kit_dumpster', 'kit_bush'], 80, 60)) {
      await this.instanced(id, list, { collide: id !== 'kit_garbage_bag' && id !== 'kit_bush' });
    }
    // dumpster alley + an industrial corner (containers, generator, fencing, barriers)
    await this.instanced('kit_dumpster', [{ x: -40, z: 9.4, rotY: Math.PI }, { x: -37.5, z: 9.4, rotY: Math.PI }], { collide: true });
    await this.instanced('kit_shipping_container', [{ x: 92, z: -7, rotY: 0 }, { x: 92, z: -7, rotY: 0, y: 2.6 }, { x: 99, z: 7, rotY: 0.2 }],
      { collide: true });
    await this.instanced('kit_generator', [{ x: 84, z: 6.5, rotY: 0 }], { collide: true });
    await this.instanced('kit_fence', [{ x: 88, z: 10.2, rotY: 0 }, { x: 94, z: 10.2, rotY: 0 }], { collide: true });
    await this.instanced('kit_jersey_barrier', [{ x: -30, z: -1.6, rotY: 0 }, { x: -26.8, z: -1.6, rotY: 0 }, { x: 30, z: 1.6, rotY: 0 }], { collide: true });
    const cars: Placement[] = [];
    for (let i = 0; i < 10; i++) {
      const along = (this.rand() - 0.5) * 100;
      if (Math.abs(along) < 12) continue;
      const lane = this.rand() < 0.5 ? -1.6 : 1.6;
      cars.push(i % 2 ? { x: along, z: lane, rotY: 0 } : { x: lane, z: along, rotY: Math.PI / 2 });
    }
    await this.instanced('car_prop_v01', cars, { collide: true });

    // ---- physics playthings (kit boxes, cones, pallets + the barrels) ----
    for (const [id, list] of scatter(['kit_cardboard_box', 'barrel_v01', 'kit_traffic_cone', 'kit_pallet', 'kit_toolbox'], 30, 34)) {
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
      new THREE.Vector3(p.x, p.y ?? 0, p.z),
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
    // physics from the asset's own *_COL proxies (e.g. a stepped tower gets stepped colliders); else its bounds
    const cols: THREE.Box3[] = [];
    proto.traverse((o) => {
      if (o.name.endsWith('_COL')) cols.push(new THREE.Box3().setFromObject(o));
    });
    for (const p of list) {
      const box = localBox.clone().applyMatrix4(this.matrixFor(p));
      if (opts.collide) {
        if (cols.length) for (const c of cols) this.physics.addStaticBox(c.clone().applyMatrix4(this.matrixFor(p)));
        else this.physics.addStaticBox(box);
      }
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
      if (o.name.endsWith('_COL')) o.visible = false;
      else if ((o as THREE.Mesh).isMesh) o.castShadow = o.receiveShadow = true;
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
