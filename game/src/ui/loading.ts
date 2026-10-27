import { registry } from '../data/registry';

/** Loading screen: board-cut scenes cycling behind real progress, with the idle key-pose frames as a flipbook. */
export class LoadingScreen {
  private root: HTMLDivElement;
  private fill: HTMLDivElement;
  private label: HTMLDivElement;
  private done = 0;
  private total = 0;
  private timers: number[] = [];
  private static BACKDROPS = ['world/c_downtown_wide', 'world/scene_red_citadel_overview', 'hero/scene_war_suit_display', 'world/c_rooftops_wide'];

  constructor() {
    this.root = document.createElement('div');
    this.root.style.cssText = `position:fixed;inset:0;z-index:20;display:flex;flex-direction:column;justify-content:flex-end;
      padding:48px;background:#050508 url("${registry.imageUrl(LoadingScreen.BACKDROPS[0])}") center/cover no-repeat;
      font:13px system-ui,sans-serif;color:#eadede;transition:opacity .6s`;
    this.root.innerHTML = `
      <div style="position:absolute;inset:0;background:linear-gradient(0deg,#050508f2 0%,#05050888 45%,#05050833 100%)"></div>
      <div style="position:relative;display:flex;align-items:center;gap:14px">
        <img data-flip style="height:96px;border-radius:4px" alt="">
        <img src="${registry.iconUrl('red_citadel')}" style="width:64px;height:64px" alt="">
        <div><div style="font:700 22px system-ui;letter-spacing:.22em;color:#ff3030">CRIMSON KNIGHT: EARTH-RED</div>
        <div style="letter-spacing:.12em;opacity:.8">OWEN ENTERPRISES · NEW GOTHAM</div></div>
      </div>
      <div style="position:relative;margin-top:18px;width:min(520px,80vw);height:6px;background:#2a1418;border-radius:3px;overflow:hidden">
        <div data-fill style="height:100%;width:0;background:linear-gradient(90deg,#8a0c17,#f5182a);transition:width .2s"></div></div>
      <div data-label style="position:relative;margin-top:6px;opacity:.7">Loading…</div>`;
    document.body.appendChild(this.root);
    this.fill = this.root.querySelector('[data-fill]')!;
    this.label = this.root.querySelector('[data-label]')!;
    const flip = this.root.querySelector<HTMLImageElement>('[data-flip]')!;
    const frames = registry.imageFrames('animations/a_idle');
    let f = 0, b = 0;
    flip.src = frames[0];
    this.timers.push(window.setInterval(() => (flip.src = frames[++f % frames.length]), 160));
    this.timers.push(window.setInterval(() => {
      b = (b + 1) % LoadingScreen.BACKDROPS.length;
      this.root.style.backgroundImage = `url("${registry.imageUrl(LoadingScreen.BACKDROPS[b])}")`;
    }, 2500));
  }

  /** Wraps a promise so it counts toward the progress bar. */
  track<T>(label: string, p: Promise<T>): Promise<T> {
    this.total++;
    return p.finally(() => {
      this.done++;
      this.fill.style.width = `${(this.done / this.total) * 100}%`;
      this.label.textContent = `Loaded ${label} (${this.done}/${this.total})`;
    });
  }

  hide(): void {
    this.timers.forEach((t) => clearInterval(t));
    this.root.style.opacity = '0';
    setTimeout(() => this.root.remove(), 700);
  }
}
