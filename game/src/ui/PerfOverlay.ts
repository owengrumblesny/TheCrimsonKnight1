import * as THREE from 'three';

/** Rolling frame statistics shared by the overlay and the benchmark. */
export class FrameStats {
  private times: number[] = [];

  push(ms: number): void {
    this.times.push(ms);
    if (this.times.length > 240) this.times.shift();
  }

  reset(): void {
    this.times = [];
  }

  get count(): number {
    return this.times.length;
  }

  get avgMs(): number {
    return this.times.length ? this.times.reduce((a, b) => a + b, 0) / this.times.length : 0;
  }

  /** frame time exceeded by only the worst 1% of frames */
  get p99Ms(): number {
    if (!this.times.length) return 0;
    const s = [...this.times].sort((a, b) => a - b);
    return s[Math.min(s.length - 1, Math.floor(s.length * 0.99))];
  }

  get fps(): number {
    return this.avgMs ? 1000 / this.avgMs : 0;
  }
}

/** Estimated GPU memory of all textures used by scene materials (RGBA8 + mips; compressed formats not detected). */
export function estimateTextureMB(scene: THREE.Scene): number {
  const seen = new Set<THREE.Texture>();
  scene.traverse((o) => {
    const mats = (o as THREE.Mesh).material;
    if (!mats) return;
    for (const m of Array.isArray(mats) ? mats : [mats]) {
      for (const v of Object.values(m)) if ((v as THREE.Texture)?.isTexture) seen.add(v as THREE.Texture);
    }
  });
  if (scene.environment) seen.add(scene.environment);
  let bytes = 0;
  for (const t of seen) {
    const img = t.image as { width?: number; height?: number } | undefined;
    if (img?.width && img?.height) bytes += img.width * img.height * 4 * 1.33;
  }
  return bytes / (1024 * 1024);
}

/** Developer overlay (F3): FPS, frame time, draw calls, triangles, objects, sectors, texture estimate. */
export class PerfOverlay {
  readonly el: HTMLElement;
  readonly stats = new FrameStats();
  private visibleObjects = 0;
  private texMB = 0;
  private slowTimer = 0;

  constructor(private renderer: THREE.WebGLRenderer, private scene: THREE.Scene, private info: () => { quality: string; gpu: string; sectors: string }) {
    this.el = document.createElement('pre');
    this.el.className = 'ck-perf ck-ui ck-hidden';
    this.el.setAttribute('aria-label', 'Performance overlay');
    document.body.appendChild(this.el);
  }

  get visible(): boolean {
    return !this.el.classList.contains('ck-hidden');
  }

  toggle(): void {
    this.el.classList.toggle('ck-hidden');
  }

  /** Call once per frame with the real frame delta (ms). */
  frame(ms: number): void {
    this.stats.push(ms);
    if (!this.visible) return;
    if ((this.slowTimer -= ms) <= 0) {
      // expensive counts only twice a second
      this.slowTimer = 500;
      let n = 0;
      this.scene.traverseVisible(() => n++);
      this.visibleObjects = n;
      this.texMB = estimateTextureMB(this.scene);
    }
    const r = this.renderer.info;
    const i = this.info();
    const fps = this.stats.fps;
    this.el.textContent =
      `FPS ${fps.toFixed(0).padStart(3)}   ${this.stats.avgMs.toFixed(1)} ms avg   ${this.stats.p99Ms.toFixed(1)} ms 1% worst\n` +
      `draw calls ${r.render.calls}   triangles ${(r.render.triangles / 1000).toFixed(1)}k\n` +
      `visible objects ${this.visibleObjects}   geometries ${r.memory.geometries}   textures ${r.memory.textures} (~${this.texMB.toFixed(0)} MB est.)\n` +
      `programs ${r.programs?.length ?? 0}   sectors ${i.sectors}\n` +
      `preset ${i.quality.toUpperCase()}   ${this.renderer.domElement.width}×${this.renderer.domElement.height} internal\n` +
      `GPU ${i.gpu}`;
    this.el.dataset.fps = fps.toFixed(1);
  }
}
