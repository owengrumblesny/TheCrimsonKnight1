import * as THREE from 'three';
import { registry } from '../data/registry';

interface Particle {
  sprite: THREE.Sprite;
  vel: THREE.Vector3;
  life: number;
  max: number;
  grow: number;
}

/**
 * Sprite bursts using the effect images cut from the boards (effects/b_*). The source images sit
 * on near-black backgrounds, so additive blending makes the background disappear.
 */
export class Effects {
  private mats = new Map<string, THREE.SpriteMaterial>();
  private live: Particle[] = [];

  constructor(private scene: THREE.Scene) {}

  async load(): Promise<void> {
    // radial fade hides the tile borders that come with each cut-out
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const g = c.getContext('2d')!;
    const grad = g.createRadialGradient(64, 64, 4, 64, 64, 60);
    grad.addColorStop(0, '#fff');
    grad.addColorStop(0.55, '#888');
    grad.addColorStop(1, '#000');
    g.fillStyle = grad;
    g.fillRect(0, 0, 128, 128);
    const mask = new THREE.CanvasTexture(c);
    await Promise.all(['sparks', 'smoke', 'debris', 'electrical'].map(async (k) => {
      const tex = await registry.imageTexture(`effects/b_${k}`);
      this.mats.set(k, new THREE.SpriteMaterial({
        map: tex, alphaMap: mask, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, toneMapped: false,
        color: new THREE.Color().setScalar(0.8),
      }));
    }));
  }

  burst(kind: string, at: THREE.Vector3, count: number, speed: number, size: number, life: number): void {
    const base = this.mats.get(kind);
    if (!base) return;
    for (let i = 0; i < count; i++) {
      const sprite = new THREE.Sprite(base.clone());
      sprite.position.copy(at).add(new THREE.Vector3((Math.random() - 0.5) * 0.4, 0.1, (Math.random() - 0.5) * 0.4));
      sprite.scale.setScalar(size * (0.6 + Math.random() * 0.6));
      const a = Math.random() * Math.PI * 2;
      const vel = new THREE.Vector3(Math.cos(a), 0.4 + Math.random() * 0.8, Math.sin(a)).multiplyScalar(speed * (0.5 + Math.random()));
      this.scene.add(sprite);
      this.live.push({ sprite, vel, life: life, max: life, grow: kind === 'smoke' ? 1.6 : 0.2 });
    }
  }

  /** Hero landing impact; hard landings throw sparks, debris and smoke. */
  landing(at: THREE.Vector3, hard: boolean): void {
    if (hard) {
      this.burst('sparks', at, 10, 3.5, 0.9, 0.5);
      this.burst('debris', at, 8, 2.5, 0.6, 0.8);
      this.burst('smoke', at, 8, 1.2, 1.6, 1.4);
      this.burst('electrical', at, 2, 0.5, 1.4, 0.35);
    } else {
      this.burst('smoke', at, 3, 0.6, 0.9, 0.8);
    }
  }

  update(dt: number): void {
    for (let i = this.live.length - 1; i >= 0; i--) {
      const p = this.live[i];
      p.life -= dt;
      p.vel.y -= 4 * dt;
      p.sprite.position.addScaledVector(p.vel, dt);
      p.sprite.scale.multiplyScalar(1 + p.grow * dt);
      (p.sprite.material as THREE.SpriteMaterial).opacity = Math.max(0, p.life / p.max);
      if (p.life <= 0) {
        this.scene.remove(p.sprite);
        p.sprite.material.dispose();
        this.live.splice(i, 1);
      }
    }
  }
}
