import * as THREE from 'three';
import { registry } from '../data/registry';
import { mergeByMaterial } from '../render/batching';
import type { Physics } from '../systems/physics';

/** The Citadel sits far below New Gotham; the portal/elevator teleports between them. */
export const CITADEL_OFFSET = new THREE.Vector3(0, -120, -420);

interface Room {
  name: string;
  group: THREE.Group;
  box: THREE.Box3;
}

interface LightPoint {
  pos: THREE.Vector3;
  color: THREE.Color;
  intensity: number;
  range: number;
  room: string;
}

interface Door {
  obj: THREE.Object3D;
  closedY: number;
  open: number;
}

/**
 * Red Citadel runtime: physics from *_COL boxes, per-room merged meshes (one draw per material per room),
 * room-based visibility (only rooms near the player render), a fixed-size light pool fed by the room
 * light points, proximity doors, and the three vehicles parked at their hangar anchors with LOD.
 */
export class Citadel {
  readonly root = new THREE.Group();
  readonly bounds = new THREE.Box3();
  private rooms: Room[] = [];
  private lightPoints: LightPoint[] = [];
  private pool: THREE.PointLight[] = [];
  private doors: Door[] = [];
  private anchors = new Map<string, THREE.Vector3>();
  private timer = 0;
  visibleRooms = 0;

  constructor(private scene: THREE.Scene, private physics: Physics) {
    this.root.name = 'RedCitadel';
  }

  anchor(name: string): THREE.Vector3 {
    return (this.anchors.get(name) ?? CITADEL_OFFSET).clone();
  }

  contains(p: THREE.Vector3): boolean {
    return this.bounds.containsPoint(p);
  }

  async build(): Promise<void> {
    const gltf = await registry.gltf('red_citadel');
    const model = gltf.scene;
    model.position.copy(CITADEL_OFFSET);
    this.scene.add(this.root);
    this.root.add(model);
    model.updateMatrixWorld(true);

    const remove: THREE.Object3D[] = [];
    model.traverse((o) => {
      if (o.name.endsWith('_COL')) {
        this.physics.addStaticBox(new THREE.Box3().setFromObject(o));
        remove.push(o);
      } else if (o.name.startsWith('Anchor_')) {
        this.anchors.set(o.name, o.getWorldPosition(new THREE.Vector3()));
      } else if (o.name.startsWith('Light_')) {
        const u = o.userData as { color?: number[]; intensity?: number; range?: number };
        this.lightPoints.push({
          pos: o.getWorldPosition(new THREE.Vector3()), color: new THREE.Color(...((u.color ?? [1, 0.3, 0.25]) as [number, number, number])),
          intensity: u.intensity ?? 30, range: u.range ?? 18, room: o.parent?.name.replace('Room_', '') ?? '',
        });
      } else if (o.name.startsWith('Door_') || o.name === 'Elevator_Platform') {
        if (o.name.startsWith('Door_')) this.doors.push({ obj: o, closedY: o.position.y, open: 0 });
      }
    });
    for (const o of remove) o.removeFromParent();

    // merge each room's static meshes per material; rooms become the unit of visibility
    for (const child of [...model.children]) {
      if (!child.name.startsWith('Room_')) continue;
      const group = new THREE.Group();
      group.name = child.name;
      for (const { geometry, material } of mergeByMaterial(child)) {
        const mesh = new THREE.Mesh(geometry, material);
        mesh.receiveShadow = true;
        group.add(mesh);
      }
      const box = new THREE.Box3().setFromObject(group);
      this.rooms.push({ name: child.name.slice(5), group, box });
      this.root.add(group);
      child.removeFromParent();
      this.bounds.union(box);
    }
    this.bounds.expandByScalar(4);

    // vehicles in their bays (articulated model near, merged LOD1 far)
    const park = async (id: string, anchor: string, rotY: number) => {
      const near = await registry.instance(id);
      const far = await registry.instance(`${id}_lod1`);
      for (const o of [near, far]) {
        o.traverse((m) => {
          if (m.name.endsWith('_COL')) m.visible = false;
          if ((m as THREE.Mesh).isMesh) m.castShadow = m.receiveShadow = true;
        });
      }
      const lod = new THREE.LOD();
      lod.addLevel(near, 0);
      lod.addLevel(far, 40);
      lod.position.copy(this.anchor(anchor));
      lod.rotation.y = rotY;
      this.root.add(lod);
      lod.updateMatrixWorld(true);
      near.traverse((m) => {
        if (m.name.endsWith('_COL')) this.physics.addStaticBox(new THREE.Box3().setFromObject(m));
      });
    };
    await Promise.all([park('crx1_interceptor', 'Anchor_CRX1', Math.PI), park('crb1_batcycle', 'Anchor_CRB1', Math.PI),
      park('cra1_specter', 'Anchor_CRA1', Math.PI)]);
  }

  /** Fixed number of real lights, moved to the nearest light points in visible rooms (size per preset). */
  setLightPool(n: number): void {
    for (const l of this.pool) l.removeFromParent();
    this.pool = Array.from({ length: n }, () => {
      const l = new THREE.PointLight(0xff4040, 0, 20, 1.6);
      this.root.add(l);
      return l;
    });
    this.timer = 0;
  }

  /** Room visibility, lights and doors. Returns whether the player is inside the Citadel. */
  update(player: THREE.Vector3, dt: number, activeHint = false): boolean {
    const inside = activeHint || this.contains(player);
    this.root.visible = inside;
    if (!inside) return false;
    for (const d of this.doors) {
      const p = d.obj.getWorldPosition(new THREE.Vector3());
      const want = p.distanceTo(player) < 5 ? 1 : 0;
      d.open += (want - d.open) * Math.min(1, dt * 3);
      d.obj.position.y = d.closedY + d.open * 3.4;
    }
    if ((this.timer -= dt) > 0) return true;
    this.timer = 0.25;
    let visible = 0;
    const near = new Set<string>();
    for (const r of this.rooms) {
      const show = r.box.distanceToPoint(player) < 30;
      r.group.visible = show;
      if (show) {
        visible++;
        near.add(r.name);
      }
    }
    this.visibleRooms = visible;
    const pts = this.lightPoints.filter((l) => near.has(l.room)).sort((a, b) => a.pos.distanceToSquared(player) - b.pos.distanceToSquared(player));
    this.pool.forEach((light, i) => {
      const p = pts[i];
      light.intensity = p ? p.intensity * 1.8 : 0; // Blender light-point values -> three.js candela
      if (p) {
        light.position.copy(p.pos);
        light.color.copy(p.color);
        light.distance = p.range * 1.5;
      }
    });
    return true;
  }
}
