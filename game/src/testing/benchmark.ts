import * as THREE from 'three';
import { FrameStats } from '../ui/PerfOverlay';

export interface BenchScene {
  name: string;
  /** null when the scene can run; otherwise why it is skipped (never faked) */
  unavailable: string | null;
  camera: [number, number, number];
  target: [number, number, number];
  hero?: [number, number, number];
}

/** The six benchmark scenes from the asset directive. Citadel scenes activate once the Citadel exists. */
export const BENCH_SCENES: BenchScene[] = [
  { name: 'CR-X9 character close-up', unavailable: null, hero: [4, 0, 4], camera: [5.6, 1.7, 6.3], target: [4, 1.2, 4] },
  { name: 'Red Citadel command center', unavailable: 'Red Citadel not built yet', camera: [0, 0, 0], target: [0, 0, 1] },
  { name: 'Red Citadel vehicle hangar', unavailable: 'Red Citadel not built yet', camera: [0, 0, 0], target: [0, 0, 1] },
  { name: 'New Gotham street', unavailable: null, hero: [30, 0, 1.5], camera: [33, 1.9, 3.5], target: [-20, 3, 0] },
  { name: 'New Gotham rooftop', unavailable: null, hero: [0, 0, 0], camera: [22, 34, 22], target: [-10, 8, -10] },
  { name: 'Dense city intersection', unavailable: null, hero: [0, 0, 0], camera: [9, 5, 9], target: [0, 1.5, 0] },
];

export interface BenchResult {
  scene: string;
  skipped?: string;
  frames?: number;
  avgFps?: number;
  avgMs?: number;
  worst1pctMs?: number;
  drawCalls?: number;
  trianglesK?: number;
}

export interface BenchReport {
  when: string;
  quality: string;
  gpu: string;
  internalResolution: string;
  pageVisible: boolean;
  results: BenchResult[];
}

/**
 * Real-time benchmark: each scene warms up 1.5 s then measures 5 s of actual frames.
 * Results are only meaningful with the window visible and focused (hidden tabs are throttled).
 */
export class Benchmark {
  active = false;
  private i = -1;
  private t = 0;
  private warm = true;
  private stats = new FrameStats();
  private calls = 0;
  private tris = 0;
  private results: BenchResult[] = [];
  private hiddenSeen = false;

  constructor(
    private camera: THREE.PerspectiveCamera,
    private renderer: THREE.WebGLRenderer,
    private hooks: { placeHero: (p: THREE.Vector3) => void; info: () => { quality: string; gpu: string }; done: (r: BenchReport) => void },
  ) {}

  start(): void {
    this.active = true;
    this.results = [];
    this.hiddenSeen = false;
    this.i = -1;
    this.next();
  }

  private next(): void {
    this.i++;
    while (this.i < BENCH_SCENES.length && BENCH_SCENES[this.i].unavailable) {
      this.results.push({ scene: BENCH_SCENES[this.i].name, skipped: BENCH_SCENES[this.i].unavailable! });
      this.i++;
    }
    if (this.i >= BENCH_SCENES.length) return this.finish();
    const s = BENCH_SCENES[this.i];
    if (s.hero) this.hooks.placeHero(new THREE.Vector3(...s.hero));
    this.t = 0;
    this.warm = true;
    this.stats.reset();
    this.calls = this.tris = 0;
  }

  get sceneName(): string {
    return BENCH_SCENES[this.i]?.name ?? '';
  }

  /** Call every rendered frame (after render) with the real frame time in ms. */
  frame(ms: number): void {
    if (!this.active) return;
    if (document.hidden) this.hiddenSeen = true;
    const s = BENCH_SCENES[this.i];
    this.camera.position.set(...s.camera);
    this.camera.lookAt(...s.target);
    this.t += ms / 1000;
    if (this.warm) {
      if (this.t > 1.5) {
        this.warm = false;
        this.t = 0;
      }
      return;
    }
    this.stats.push(ms);
    this.calls += this.renderer.info.render.calls;
    this.tris += this.renderer.info.render.triangles;
    if (this.t >= 5) {
      const n = this.stats.count;
      this.results.push({
        scene: s.name, frames: n, avgFps: +this.stats.fps.toFixed(1), avgMs: +this.stats.avgMs.toFixed(2),
        worst1pctMs: +this.stats.p99Ms.toFixed(2), drawCalls: Math.round(this.calls / n), trianglesK: +(this.tris / n / 1000).toFixed(1),
      });
      this.next();
    }
  }

  private finish(): void {
    this.active = false;
    const info = this.hooks.info();
    const report: BenchReport = {
      when: new Date().toISOString(), quality: info.quality, gpu: info.gpu,
      internalResolution: `${this.renderer.domElement.width}x${this.renderer.domElement.height}`,
      pageVisible: !this.hiddenSeen, results: this.results,
    };
    (window as unknown as { __CK_BENCH__: BenchReport }).__CK_BENCH__ = report;
    if (import.meta.env.DEV) void fetch('/__bench', { method: 'POST', body: JSON.stringify(report) }).catch(() => undefined);
    this.hooks.done(report);
  }
}

/** Result panel with copy/download so Owen can share numbers from his laptop. */
export function showBenchReport(r: BenchReport, onClose: () => void): void {
  const el = document.createElement('div');
  el.className = 'ck-modal ck-ui';
  el.setAttribute('role', 'dialog');
  el.setAttribute('aria-label', 'Benchmark results');
  const rows = r.results.map((x) => x.skipped
    ? `<tr><td>${x.scene}</td><td colspan="5" style="color:var(--ck-muted)">skipped — ${x.skipped}</td></tr>`
    : `<tr><td>${x.scene}</td><td><b style="color:${x.avgFps! >= 30 ? '#7ddc8a' : '#ff8a8a'}">${x.avgFps}</b></td><td>${x.avgMs}</td><td>${x.worst1pctMs}</td><td>${x.drawCalls}</td><td>${x.trianglesK}k</td></tr>`).join('');
  el.innerHTML = `<div class="ck-window"><div class="ck-head"><h2>Benchmark — ${r.quality.toUpperCase()}</h2></div><div class="ck-body">
    <p style="color:var(--ck-muted)">GPU: ${r.gpu}<br>Internal resolution: ${r.internalResolution} · ${r.when}${r.pageVisible ? '' : '<br><b style="color:#ffb020">The window was hidden during the run — numbers are throttled and not valid.</b>'}</p>
    <table class="ck-bench"><thead><tr><th>Scene</th><th>Avg FPS</th><th>Avg ms</th><th>1% worst ms</th><th>Draw calls</th><th>Triangles</th></tr></thead><tbody>${rows}</tbody></table>
    <div style="display:flex;gap:8px;margin-top:14px"><button class="ck-btn primary" data-a="copy" type="button">Copy results</button>
    <button class="ck-btn" data-a="save" type="button">Save as JSON</button><button class="ck-btn ghost" data-a="close" type="button">Close</button></div></div></div>`;
  const json = JSON.stringify(r, null, 2);
  el.querySelector('[data-a="copy"]')!.addEventListener('click', () => void navigator.clipboard?.writeText(json));
  el.querySelector('[data-a="save"]')!.addEventListener('click', () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
    a.download = `crimson-knight-benchmark-${r.quality}.json`;
    a.click();
  });
  el.querySelector('[data-a="close"]')!.addEventListener('click', () => {
    el.remove();
    onClose();
  });
  document.body.appendChild(el);
}
