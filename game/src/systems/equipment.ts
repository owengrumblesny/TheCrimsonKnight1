import * as THREE from 'three';
import type { Hero } from '../actors/hero';
import type { Player } from '../actors/player';
import { registry } from '../data/registry';
import type { Effects } from '../render/effects';
import type { InventoryService } from '../ui/uiState';
import type { District } from '../world/district';
import type { AudioManager } from './audio';
import { RAPIER, type Physics } from './physics';
import type { Vitals } from './vitals';

export type Notify = (text: string, iconId?: string, kind?: 'info' | 'warn') => void;

interface Timed {
  until: number;
  update?: (now: number, dt: number) => void;
  end: () => void;
}

interface Projectile {
  mesh: THREE.Object3D;
  vel: THREE.Vector3;
  travelled: number;
}

/**
 * Uses the hotbar's selected item. Selection itself never triggers this; only the primary action does.
 * Every effect here is real gameplay; items marked unavailable in the catalog are refused with their reason.
 */
export class Equipment {
  private timed: Timed[] = [];
  private projectiles: Projectile[] = [];
  private beacons: THREE.Object3D[] = [];
  private lamp: THREE.SpotLight | null = null;
  private grappleLine: THREE.Line | null = null;
  photoMode = false;

  constructor(
    private ctx: {
      scene: THREE.Scene; camera: THREE.PerspectiveCamera; physics: Physics; player: Player; hero: Hero;
      district: District; effects: Effects; inventory: InventoryService; vitals: Vitals; audio: AudioManager; notify: Notify;
      setPhotoMode: (on: boolean) => void;
    },
  ) {}

  /** Try to use the selected item. Returns true if something happened. */
  useSelected(now: number): boolean {
    const { inventory, vitals, notify, audio } = this.ctx;
    const id = inventory.selectedItemId;
    if (!id) {
      notify('Nothing selected — press 1–8 or open the inventory (Tab)', 'inventory', 'warn');
      return false;
    }
    const def = inventory.def(id)!;
    const deny = (msg: string) => {
      notify(msg, def.iconId, 'warn');
      audio.play('ui.deny');
      return false;
    };
    if (def.unavailableReason) return deny(`${def.displayName}: ${def.unavailableReason}`);
    if (!inventory.has(id)) return deny(`${def.displayName}: none left (restocks over time)`);
    const cd = inventory.cooldownRemaining(id, now);
    if (cd > 0) return deny(`${def.displayName} recharging (${(cd / 1000).toFixed(1)} s)`);
    if (def.energyCost && vitals.energy < def.energyCost) return deny(`Not enough energy for ${def.displayName} (${def.energyCost} needed)`);
    const handler = this.handlers[id];
    if (!handler) return deny(`${def.displayName}: no effect wired`);
    if (!handler(now)) return false;
    if (def.energyCost) vitals.spend(def.energyCost);
    inventory.consume(id);
    inventory.startCooldown(id, now);
    if (def.useClip && id !== 'grapple') this.ctx.player.act(def.useClip, 0.35);
    return true;
  }

  private get feet(): THREE.Vector3 {
    return this.ctx.hero.root.position.clone();
  }

  private aimRay(): { origin: THREE.Vector3; dir: THREE.Vector3 } {
    const dir = new THREE.Vector3();
    this.ctx.camera.getWorldDirection(dir);
    return { origin: this.ctx.camera.position.clone(), dir };
  }

  /** Rapier ray cast that ignores the player capsule. */
  private cast(origin: THREE.Vector3, dir: THREE.Vector3, max: number) {
    const ray = new RAPIER.Ray(origin, dir);
    const hit = this.ctx.physics.world.castRay(ray, max, true, undefined, undefined, this.ctx.player.collider);
    if (!hit) return null;
    const toi = (hit as unknown as { timeOfImpact?: number; toi?: number }).timeOfImpact ?? (hit as unknown as { toi: number }).toi;
    return { point: origin.clone().addScaledVector(dir, toi), collider: hit.collider, distance: toi };
  }

  private addTimed(ms: number, now: number, end: () => void, update?: Timed['update']): void {
    this.timed.push({ until: now + ms, end, update });
  }

  private handlers: Record<string, (now: number) => boolean> = {
    batarang: () => {
      const { dir } = this.aimRay();
      const start = this.feet.add(new THREE.Vector3(0, 1.4, 0)).addScaledVector(dir, 0.6);
      void registry.instance('gear_batarang').then((m) => {
        m.scale.setScalar(1.6);
        m.position.copy(start);
        this.ctx.scene.add(m);
        this.projectiles.push({ mesh: m, vel: dir.clone().multiplyScalar(32), travelled: 0 });
      });
      this.ctx.audio.play('gadget.throw');
      return true;
    },
    grapple: () => {
      const { origin, dir } = this.aimRay();
      const hit = this.cast(origin, dir, 55);
      const chest = this.feet.add(new THREE.Vector3(0, 1.4, 0));
      if (!hit || hit.point.distanceTo(chest) > 45) {
        this.ctx.notify('Grapnel: no surface in range (45 m) — aim at a building or prop', 'grapple', 'warn');
        this.ctx.audio.play('ui.deny');
        return false;
      }
      if (hit.point.y < this.feet.y + 1.2) {
        this.ctx.notify('Grapnel: aim higher — the anchor must be above you', 'grapple', 'warn');
        this.ctx.audio.play('ui.deny');
        return false;
      }
      this.ctx.player.grappleTo(hit.point);
      this.ctx.audio.play('gadget.throw');
      return true;
    },
    scanner: (now) => {
      const p = this.feet;
      const found = this.ctx.district.dynamic.filter(({ obj }) => obj.position.distanceTo(p) < 30);
      for (const { obj } of found) {
        const helper = new THREE.BoxHelper(obj, 0xff405d);
        this.ctx.scene.add(helper);
        this.addTimed(4000, now, () => this.ctx.scene.remove(helper), () => helper.update());
      }
      const ring = this.ring(p, 0xff405d);
      this.addTimed(900, now, () => this.ctx.scene.remove(ring), (t) => this.grow(ring, t, now, 900, 30));
      this.ctx.audio.play('gadget.pulse');
      this.ctx.notify(`Scan complete: ${found.length} movable object${found.length === 1 ? '' : 's'} within 30 m`, 'scanner');
      return true;
    },
    drone: (now) => {
      void registry.instance('gear_drone').then((drone) => {
        const light = new THREE.SpotLight(0xffffff, 40, 25, 0.5, 0.6);
        drone.add(light, light.target);
        light.target.position.set(0, -5, 0);
        this.ctx.scene.add(drone);
        this.addTimed(20000, now, () => this.ctx.scene.remove(drone), (t) => {
          const a = t / 1200;
          drone.position.copy(this.feet).add(new THREE.Vector3(Math.cos(a) * 3.5, 4.2 + Math.sin(a * 2) * 0.3, Math.sin(a) * 3.5));
          drone.rotation.y = -a;
        });
      });
      this.ctx.audio.play('gadget.deploy');
      this.ctx.notify('Recon drone launched (20 s)', 'drone');
      return true;
    },
    smoke: () => {
      this.ctx.effects.burst('smoke', this.feet, 16, 1.6, 2.4, 3.2);
      this.ctx.audio.play('gadget.deploy');
      return true;
    },
    shield: (now) => {
      this.ctx.vitals.shieldUntil = now + 6000;
      const dome = new THREE.Mesh(
        new THREE.SphereGeometry(1.5, 32, 16),
        new THREE.MeshBasicMaterial({ color: 0xff405d, transparent: true, opacity: 0.18, depthWrite: false, side: THREE.DoubleSide }),
      );
      this.ctx.scene.add(dome);
      this.addTimed(6000, now, () => this.ctx.scene.remove(dome), (t) => {
        dome.position.copy(this.feet).add(new THREE.Vector3(0, 1, 0));
        (dome.material as THREE.MeshBasicMaterial).opacity = 0.12 + 0.06 * Math.sin(t / 120);
      });
      this.ctx.audio.play('armor.activate');
      this.ctx.notify('Energy shield up — impact damage blocked (6 s)', 'shield');
      return true;
    },
    cloak: (now) => {
      const mats: THREE.Material[] = [];
      this.ctx.hero.root.traverse((o) => {
        const m = (o as THREE.Mesh).material;
        if (m) for (const mat of Array.isArray(m) ? m : [m]) mats.push(mat);
      });
      for (const m of mats) {
        m.transparent = true;
        m.opacity = 0.12;
        m.needsUpdate = true;
      }
      this.addTimed(8000, now, () => {
        for (const m of mats) {
          m.opacity = 1;
          m.transparent = false;
          m.needsUpdate = true;
        }
        this.ctx.notify('Optical cloak disengaged', 'cloak');
      });
      this.ctx.audio.play('armor.activate');
      this.ctx.notify('Optical cloak engaged (8 s)', 'cloak');
      return true;
    },
    beacon: () => {
      const at = this.feet;
      void registry.instance('gear_beacon').then((b) => {
        b.position.copy(at);
        const light = new THREE.PointLight(0xff2030, 10, 12, 1.5);
        light.position.y = 0.8;
        b.add(light);
        this.ctx.scene.add(b);
        this.beacons.push(b);
        if (this.beacons.length > 3) this.ctx.scene.remove(this.beacons.shift()!);
      });
      this.ctx.audio.play('gadget.deploy');
      this.ctx.notify('Tracking beacon planted', 'beacon');
      return true;
    },
    emp: (now) => {
      const p = this.feet;
      const hit = this.ctx.district.lamps.filter((l) => l.pos.distanceTo(p) < 25);
      for (const l of hit) l.offUntil = now + 6000;
      this.ctx.district.updateLights(p, now, 1); // apply immediately
      this.ctx.effects.burst('electrical', p.clone().setY(1), 6, 2, 1.8, 0.6);
      const ring = this.ring(p, 0x6aa8ff);
      this.addTimed(700, now, () => this.ctx.scene.remove(ring), (t) => this.grow(ring, t, now, 700, 25));
      this.ctx.audio.play('gadget.pulse');
      this.ctx.notify(`EMP: ${hit.length} street light${hit.length === 1 ? '' : 's'} knocked out for 6 s`, 'emp');
      return true;
    },
    sonic: (now) => {
      const p = this.feet;
      let pushed = 0;
      for (const { body, obj } of this.ctx.district.dynamic) {
        const d = obj.position.clone().sub(p);
        const dist = d.length();
        if (dist > 9) continue;
        d.setY(0).normalize().multiplyScalar((9 - dist) * 1.6 * body.mass()).setY(body.mass() * 3);
        body.applyImpulse(d, true);
        pushed++;
      }
      const ring = this.ring(p, 0xffffff);
      this.addTimed(500, now, () => this.ctx.scene.remove(ring), (t) => this.grow(ring, t, now, 500, 9));
      this.ctx.audio.play('gadget.pulse');
      this.ctx.notify(`Sonic burst pushed ${pushed} object${pushed === 1 ? '' : 's'}`, 'sonic');
      return true;
    },
    flashlight: () => {
      if (this.lamp) {
        this.ctx.hero.root.remove(this.lamp, this.lamp.target);
        this.lamp = null;
      } else {
        this.lamp = new THREE.SpotLight(0xfff4e8, 60, 40, 0.42, 0.5, 1.2);
        this.lamp.position.set(0, 1.75, 0.15);
        this.lamp.target.position.set(0, 0.6, 12);
        this.ctx.hero.root.add(this.lamp, this.lamp.target);
      }
      this.ctx.audio.play('ui.click');
      return true;
    },
    power_cell: () => this.heal('energy', 60, 'power_cell'),
    first_aid: () => this.heal('health', 50, 'first_aid'),
    repair: () => this.heal('armor', 40, 'repair'),
    photo_camera: () => {
      this.photoMode = !this.photoMode;
      this.ctx.setPhotoMode(this.photoMode);
      this.ctx.notify(this.photoMode ? 'Photo mode on — HUD hidden (use the camera again to exit)' : 'Photo mode off', 'camera');
      return true;
    },
  };

  private heal(kind: 'health' | 'armor' | 'energy', amount: number, icon: string): boolean {
    const got = this.ctx.vitals.restore(kind, amount);
    if (got <= 0) {
      this.ctx.notify(`${kind[0].toUpperCase() + kind.slice(1)} already full`, icon, 'warn');
      return false;
    }
    this.ctx.audio.play('armor.activate');
    this.ctx.notify(`+${Math.round(got)} ${kind}`, icon);
    return true;
  }

  private ring(at: THREE.Vector3, color: number): THREE.Mesh {
    const m = new THREE.Mesh(
      new THREE.RingGeometry(0.9, 1, 64),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.8, side: THREE.DoubleSide, depthWrite: false }),
    );
    m.rotation.x = -Math.PI / 2;
    m.position.copy(at).setY(at.y + 0.1);
    this.ctx.scene.add(m);
    return m;
  }

  private grow(m: THREE.Mesh, t: number, start: number, ms: number, radius: number): void {
    const k = Math.min(1, (t - start) / ms);
    m.scale.setScalar(0.5 + k * radius);
    (m.material as THREE.MeshBasicMaterial).opacity = 0.8 * (1 - k);
  }

  /** Per-frame: projectiles, timed effects, grapple line. dt seconds, now ms. */
  update(dt: number, now: number): void {
    for (let i = this.timed.length - 1; i >= 0; i--) {
      const e = this.timed[i];
      if (now >= e.until) {
        e.end();
        this.timed.splice(i, 1);
      } else e.update?.(now, dt);
    }
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      const step = p.vel.length() * dt;
      const dir = p.vel.clone().normalize();
      const hit = this.cast(p.mesh.position, dir, step);
      p.mesh.rotation.y += dt * 25;
      if (hit) {
        const body = hit.collider.parent();
        if (body && body.isDynamic()) body.applyImpulse(dir.multiplyScalar(6 * body.mass()), true);
        this.ctx.effects.burst('sparks', hit.point, 6, 2.5, 0.5, 0.4);
        this.ctx.audio.play('armor.step');
      }
      p.mesh.position.addScaledVector(p.vel, dt);
      p.vel.y -= 2 * dt;
      p.travelled += step;
      if (hit || p.travelled > 45) {
        this.ctx.scene.remove(p.mesh);
        this.projectiles.splice(i, 1);
      }
    }
    // grapple line from the hand to the anchor while reeling in
    const anchor = this.ctx.player.grappleAnchor;
    if (anchor) {
      const from = this.feet.add(new THREE.Vector3(0, 1.5, 0));
      if (!this.grappleLine) {
        this.grappleLine = new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color: 0x222222 }));
        this.ctx.scene.add(this.grappleLine);
      }
      this.grappleLine.geometry.setFromPoints([from, anchor]);
    } else if (this.grappleLine) {
      this.ctx.scene.remove(this.grappleLine);
      this.grappleLine = null;
    }
  }
}
