import { registry } from '../data/registry';
import type { Vitals } from '../systems/vitals';
import { IconRegistry, keyLabel } from './IconRegistry';
import type { InventoryService } from './uiState';

const CARD = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/** Top-left vitals, top-center compass, top-right notifications, bottom-right selection, crosshair, prompts. */
export class HudWidgets {
  readonly root: HTMLElement;
  private meters = {} as Record<'health' | 'armor' | 'energy', { fill: HTMLElement; num: HTMLElement; el: HTMLElement }>;
  private strip!: HTMLElement;
  private notes!: HTMLElement;
  private selected!: HTMLElement;
  private crosshair!: HTMLImageElement;
  private prompt!: HTMLElement;
  private promptKey = '';

  constructor(private inventory: InventoryService, private vitals: Vitals) {
    this.root = document.createElement('div');
    this.root.className = 'ck-layer ck-ui';
    const status = this.add('ck-status ck-hud-widget',
      `<img class="ck-portrait" alt="CR-X9 helmet" src="${registry.imageUrl('hero/a_helmet_front')}"><div class="m"><div class="ck-brand">CR-X9 · OWEN ENTERPRISES</div></div>`);
    const m = status.querySelector('.m')!;
    for (const [k, label] of [['health', 'Health'], ['armor', 'Armor integrity'], ['energy', 'Fusion energy']] as const) {
      const row = document.createElement('div');
      row.className = `ck-meter ${k}`;
      row.setAttribute('role', 'meter');
      row.setAttribute('aria-label', label);
      row.innerHTML = `<img alt="" src="${IconRegistry.url(k)}"><div class="bar"><div class="fill"></div></div><span class="num"></span>`;
      m.appendChild(row);
      this.meters[k] = { el: row, fill: row.querySelector('.fill')!, num: row.querySelector('.num')! };
    }
    const compass = this.add('ck-compass ck-hud-widget', `<img alt="" src="${IconRegistry.url('compass')}"><div class="strip"></div><div class="needle"></div>`);
    compass.setAttribute('aria-hidden', 'true');
    this.strip = compass.querySelector('.strip')!;
    // three repeats of 8 cardinal marks (45 px each) so the strip can scroll seamlessly
    this.strip.innerHTML = Array.from({ length: 24 }, (_, i) => `<span class="${i % 2 ? '' : 'card'}">${CARD[i % 8]}</span>`).join('');
    this.notes = this.add('ck-notes');
    this.notes.setAttribute('role', 'status');
    this.notes.setAttribute('aria-live', 'polite');
    this.selected = this.add('ck-selected ck-hud-widget');
    this.crosshair = document.createElement('img');
    this.crosshair.className = 'ck-crosshair ck-hud-widget ck-hidden';
    this.crosshair.alt = '';
    this.crosshair.src = IconRegistry.url('crosshair');
    this.root.appendChild(this.crosshair);
    this.prompt = this.add('ck-prompt ck-hud-widget ck-hidden');
  }

  private add(cls: string, html = ''): HTMLElement {
    const d = document.createElement('div');
    d.className = cls;
    d.innerHTML = html;
    this.root.appendChild(d);
    return d;
  }

  /** Top-right queue: max 4 visible, each fades after ~4 s. */
  notify(text: string, iconId = 'notification', kind: 'info' | 'warn' = 'info'): void {
    const n = document.createElement('div');
    n.className = `ck-note ${kind}`;
    n.innerHTML = `<img alt="" src="${IconRegistry.url(iconId)}"><span></span>`;
    n.querySelector('span')!.textContent = text;
    this.notes.prepend(n);
    while (this.notes.children.length > 4) this.notes.lastElementChild!.remove();
    setTimeout(() => n.classList.add('out'), 3800);
    setTimeout(() => n.remove(), 4300);
  }

  /** Contextual prompt from real bindings, e.g. ('KeyE', 'Shove crate'); null hides it. */
  setPrompt(code: string | null, text = ''): void {
    if (!code) {
      this.prompt.classList.add('ck-hidden');
      this.promptKey = '';
      return;
    }
    const key = `${code}|${text}`;
    if (key === this.promptKey) return;
    this.promptKey = key;
    const cap = IconRegistry.keycap(code);
    this.prompt.innerHTML = (cap ? `<img alt="${keyLabel(code)}" src="${cap}">` : `<kbd>${keyLabel(code)}</kbd>`) + `<span></span>`;
    this.prompt.querySelector('span')!.textContent = text;
    this.prompt.classList.remove('ck-hidden');
  }

  update(now: number, headingRad: number, showCrosshair: boolean, useKey: string): void {
    for (const k of ['health', 'armor', 'energy'] as const) {
      const v = this.vitals[k];
      const m = this.meters[k];
      m.fill.style.width = `${v}%`;
      m.num.textContent = String(Math.round(v));
      m.el.setAttribute('aria-valuenow', String(Math.round(v)));
    }
    // compass: heading 0 = facing +Z (south in map terms, where north is -Z)
    const deg = (((180 - (headingRad * 180) / Math.PI) % 360) + 360) % 360;
    this.strip.style.left = `${180 - (deg / 45) * 45 - 360 - 22.5}px`;
    const id = this.inventory.selectedItemId;
    const def = id ? this.inventory.def(id) : undefined;
    if (!def) this.selected.innerHTML = '<b>No item selected</b><small>Press 1–8 or open the inventory</small>';
    else {
      const cd = this.inventory.cooldownRemaining(def.id, now);
      const parts = [
        def.stackable ? `${this.inventory.quantity(def.id)} / ${def.maxStack}` : '',
        def.energyCost ? `${def.energyCost} energy` : '',
        cd > 0 ? `recharging ${(cd / 1000).toFixed(1)} s` : def.unavailableReason ? 'unavailable' : `${keyLabel(useKey)} to use`,
      ].filter(Boolean);
      this.selected.innerHTML = `<b></b><small>${parts.join(' · ')}</small>`;
      this.selected.querySelector('b')!.textContent = def.displayName;
    }
    this.crosshair.classList.toggle('ck-hidden', !showCrosshair);
  }
}
