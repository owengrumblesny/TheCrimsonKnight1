import type { Hero } from '../actors/hero';
import { clipReferences, registry } from '../data/registry';

/** Animation debug (backtick): play any CK_* clip and compare it with the board's key-pose frames. */
export class AnimDebug {
  readonly el: HTMLElement;
  clip: string | null = null;
  private refImg: HTMLImageElement;
  private refBox: HTMLElement;
  private frames: string[] = [];
  private t = 0;

  constructor(private hero: Hero) {
    this.el = document.createElement('div');
    this.el.className = 'ck-anim ck-ui ck-hidden';
    this.el.innerHTML = '<div class="ref ck-hidden"><img alt=""><small style="color:var(--ck-muted)">board reference</small></div><div class="list"></div>';
    this.refBox = this.el.querySelector('.ref')!;
    this.refImg = this.refBox.querySelector('img')!;
    const list = this.el.querySelector('.list')!;
    for (const name of [null, ...hero.clipNames]) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'ck-btn';
      b.textContent = name ?? '▶ gameplay control';
      b.title = name ? hero.meta.get(name)?.description ?? '' : '';
      b.addEventListener('click', () => this.select(name));
      list.appendChild(b);
    }
    document.body.appendChild(this.el);
  }

  get visible(): boolean {
    return !this.el.classList.contains('ck-hidden');
  }

  toggle(): void {
    this.el.classList.toggle('ck-hidden');
    if (!this.visible) this.select(null);
    else document.exitPointerLock?.();
  }

  select(name: string | null): void {
    this.clip = name;
    for (const b of this.el.querySelectorAll('.list .ck-btn')) b.classList.toggle('on', b.textContent === name);
    this.frames = name ? (clipReferences[name] ?? []).flatMap((id) => registry.imageFrames(id)) : [];
    this.refBox.classList.toggle('ck-hidden', !this.frames.length);
    this.t = 0;
    if (name) this.hero.play(name, { fade: 0.2, restart: true });
  }

  update(dt: number): void {
    if (!this.frames.length) return;
    this.t += dt;
    const src = this.frames[Math.floor(this.t * 8) % this.frames.length];
    if (this.refImg.getAttribute('src') !== src) this.refImg.setAttribute('src', src);
  }
}
