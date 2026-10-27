import { registry } from '../data/registry';
import type { AudioManager } from '../systems/audio';
import type { Vitals } from '../systems/vitals';
import { IconRegistry, keyLabel } from './IconRegistry';
import { ACTIONS, type ActionId, type Bindings } from './inputBindings';
import { InventoryPanel } from './InventoryPanel';
import { ITEMS } from './inventoryData';
import type { InventoryService, Quality, SaveData, Settings } from './uiState';

export type Screen = 'main' | 'pause' | 'inventory' | 'map' | 'loadout' | 'settings';

interface MapFeature { kind: 'building' | 'road' | 'portal' | 'billboard'; minX: number; minZ: number; maxX: number; maxZ: number }

/** Everything the menus can do to the game — each button maps to one of these real actions. */
export interface MenuHooks {
  inventory: InventoryService;
  bindings: Bindings;
  settings: Settings;
  vitals: Vitals;
  audio: AudioManager;
  readSave: () => SaveData | null;
  play: () => void;
  continueSave: () => void;
  newSandbox: () => void;
  saveNow: () => void;
  applySettings: () => void;
  captureKey: (cb: (code: string) => void) => void;
  selectSlot: (index: number) => void;
  quickVehicle: () => string;
  setQuickVehicle: (id: string) => void;
  notify: (text: string, icon?: string, kind?: 'info' | 'warn') => void;
  playerPose: () => { x: number; z: number; heading: number };
  mapFeatures: () => MapFeature[];
  onOpenChange: (open: boolean) => void;
}

const SCREEN_ICON: Record<Screen, string> = { main: 'home', pause: 'pause', inventory: 'inventory', map: 'map', loadout: 'loadout', settings: 'settings' };
const SCREEN_TITLE: Record<Screen, string> = { main: 'Main Menu', pause: 'Paused', inventory: 'Inventory', map: 'Map', loadout: 'Equipment Loadout', settings: 'Settings' };

/** Modal menu stack with focus trap, Escape-to-back and focus restore. */
export class MenuManager {
  private stack: { screen: Screen; el: HTMLElement; dispose?: () => void; returnFocus: Element | null }[] = [];
  private mapTimer = 0;

  constructor(private h: MenuHooks) {
    document.addEventListener('keydown', (e) => {
      // focus trap: Tab cycles inside the top modal (Tab is not the inventory key inside menus)
      const top = this.stack.at(-1);
      if (!top || e.key !== 'Tab' || top.screen === 'inventory') return;
      const f = [...top.el.querySelectorAll<HTMLElement>('button:not(:disabled), input, select, [tabindex="0"]')];
      if (!f.length) return;
      const i = f.indexOf(document.activeElement as HTMLElement);
      e.preventDefault();
      f[(i + (e.shiftKey ? -1 : 1) + f.length) % f.length].focus();
    }, true);
  }

  get open(): boolean {
    return this.stack.length > 0;
  }

  get top(): Screen | null {
    return this.stack.at(-1)?.screen ?? null;
  }

  /** Close the top screen (Escape / Back). The main menu can't be backed out of. */
  back(): void {
    const top = this.stack.at(-1);
    if (!top || top.screen === 'main') return;
    this.pop();
  }

  closeAll(): void {
    while (this.stack.length) this.pop(true);
    this.h.onOpenChange(false);
  }

  /** Toggle a screen from a hotkey (Tab inventory, M map). */
  toggle(screen: Screen): void {
    if (this.top === screen) this.back();
    else if (!this.stack.some((s) => s.screen === 'main')) this.show(screen);
  }

  private pop(silent = false): void {
    const s = this.stack.pop()!;
    s.dispose?.();
    s.el.remove();
    if (!silent) this.h.audio.play('ui.close');
    (s.returnFocus as HTMLElement | null)?.focus?.();
    if (!this.stack.length) this.h.onOpenChange(false);
  }

  show(screen: Screen): void {
    const returnFocus = document.activeElement;
    if (!this.stack.length) this.h.onOpenChange(true);
    this.h.audio.play('ui.open');
    if (screen === 'main') return this.mainMenu(returnFocus);
    const modal = document.createElement('div');
    modal.className = 'ck-modal ck-ui' + (this.h.settings.reduceMotion ? '' : ' ck-blur');
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-label', SCREEN_TITLE[screen]);
    const win = document.createElement('div');
    win.className = 'ck-window' + (screen === 'pause' ? ' narrow' : '');
    win.innerHTML = `<div class="ck-head"><img alt="" src="${IconRegistry.url(SCREEN_ICON[screen])}"><h2>${SCREEN_TITLE[screen]}</h2>
      <button class="ck-btn ghost close" type="button" aria-label="Close"><img alt="" src="${IconRegistry.url('back')}">Back</button></div>`;
    win.querySelector('.close')!.addEventListener('click', () => this.back());
    modal.addEventListener('mousedown', (e) => {
      if (e.target === modal) this.back();
    });
    modal.appendChild(win);
    document.body.appendChild(modal);
    const entry: (typeof this.stack)[number] = { screen, el: modal, returnFocus };
    this.stack.push(entry);
    const body = document.createElement('div');
    body.className = 'ck-body';
    if (screen === 'inventory') {
      const panel = new InventoryPanel(this.h.inventory, {
        notify: this.h.notify, click: () => this.h.audio.play('ui.click'), selectSlot: this.h.selectSlot,
        quickVehicle: this.h.quickVehicle, setQuickVehicle: this.h.setQuickVehicle,
      });
      win.appendChild(panel.el);
      entry.dispose = () => panel.dispose();
      panel.focusFirst();
      return;
    }
    win.appendChild(body);
    if (screen === 'pause') this.pauseMenu(body);
    else if (screen === 'map') entry.dispose = this.mapScreen(body);
    else if (screen === 'loadout') this.loadout(body);
    else if (screen === 'settings') this.settingsScreen(body);
    (body.querySelector('button:not(:disabled), input, select') as HTMLElement | null)?.focus();
  }

  private btn(label: string, icon: string, onClick: (() => void) | null, note = '', cls = ''): HTMLButtonElement {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = `ck-btn ${cls}`;
    b.innerHTML = `<img alt="" src="${IconRegistry.url(icon)}"><span></span>${note ? `<small>${note}</small>` : ''}`;
    b.querySelector('span')!.textContent = label;
    if (onClick) {
      b.addEventListener('click', () => {
        this.h.audio.play('ui.click');
        onClick();
      });
    } else {
      b.disabled = true;
      b.title = note || 'Coming later';
    }
    return b;
  }

  // ---------------- main menu ----------------
  private mainMenu(returnFocus: Element | null): void {
    const el = document.createElement('div');
    el.className = 'ck-main ck-ui';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-label', 'Main menu');
    el.style.backgroundImage = `url("${registry.imageUrl('world/c_downtown_wide')}")`;
    const save = this.h.readSave();
    el.innerHTML = `<div class="ck-col"><p class="ck-title">CRIMSON KNIGHT</p><div class="ck-sub">EARTH-RED · OWEN ENTERPRISES</div><div class="ck-menu-list"></div>
      <p style="color:var(--ck-muted);font-size:12px;margin-top:16px">Open-world sandbox · no required story · created by Owen Grumbles</p></div>`;
    const list = el.querySelector('.ck-menu-list')!;
    const go = (fn: () => void) => () => {
      void this.h.audio.unlock(); // user gesture: unlock Web Audio
      this.closeAll();
      fn();
    };
    list.append(
      this.btn('Play', 'play', go(this.h.play), 'resume current session', 'primary'),
      this.btn('Continue', 'load', save ? go(this.h.continueSave) : null, save ? new Date(save.savedAt).toLocaleString() : 'No save yet'),
      this.btn('New Sandbox', 'sandbox', go(this.h.newSandbox), 'fresh inventory & spawn'),
      this.btn('Settings', 'settings', () => this.show('settings')),
      this.btn('Controls', 'controls', () => this.show('settings')),
      this.btn('Quit', 'quit', null, 'Desktop build only'),
    );
    document.body.appendChild(el);
    this.stack.push({ screen: 'main', el, returnFocus });
    (list.querySelector('button') as HTMLElement).focus();
  }

  // ---------------- pause ----------------
  private pauseMenu(body: HTMLElement): void {
    const list = document.createElement('div');
    list.className = 'ck-menu-list';
    list.append(
      this.btn('Resume', 'play', () => this.closeAll(), 'Esc', 'primary'),
      this.btn('Inventory', 'inventory', () => this.show('inventory'), keyLabel(this.h.bindings.get('inventory'))),
      this.btn('Map', 'map', () => this.show('map'), keyLabel(this.h.bindings.get('map'))),
      this.btn('Equipment Loadout', 'loadout', () => this.show('loadout')),
      this.btn('Settings', 'settings', () => this.show('settings')),
      this.btn('Save', 'save', () => this.h.saveNow()),
      this.btn('Exit to Main Menu', 'home', () => {
        this.h.saveNow();
        while (this.stack.length) this.pop(true);
        this.show('main');
      }),
    );
    body.appendChild(list);
  }

  // ---------------- map ----------------
  private mapScreen(body: HTMLElement): () => void {
    body.innerHTML = `<div class="ck-tabs" style="padding:0;margin:-6px 0 12px"><button class="ck-tab" data-t="map" aria-selected="true">District map</button>
      <button class="ck-tab" data-t="loc" aria-selected="false">Locations</button></div><div class="pane"></div>`;
    const pane = body.querySelector<HTMLElement>('.pane')!;
    const drawMap = () => {
      pane.innerHTML = `<div class="ck-map"><canvas width="1280" height="800" aria-label="Top-down map of the explored district"></canvas></div>
        <p style="color:var(--ck-muted);font-size:12px">Built from the loaded district geometry. North is up. Red triangle = you. Only the explored test district exists so far.</p>`;
      const c = pane.querySelector('canvas')!;
      const g = c.getContext('2d')!;
      const draw = () => {
        const S = 3, cx = c.width / 2, cy = c.height / 2 + 120; // 3 px per metre; shifted so the Citadel entrance (z -120) fits
        g.fillStyle = '#0b0a10';
        g.fillRect(0, 0, c.width, c.height);
        for (const f of this.h.mapFeatures()) {
          g.fillStyle = f.kind === 'road' ? '#1e1d26' : f.kind === 'portal' ? '#7a1020' : '#3a2a33';
          g.fillRect(cx + f.minX * S, cy + f.minZ * S, (f.maxX - f.minX) * S, (f.maxZ - f.minZ) * S);
          if (f.kind === 'portal') {
            g.fillStyle = '#ff405d';
            g.font = '600 20px system-ui';
            g.fillText('RED CITADEL ENTRANCE', cx + f.maxX * S + 8, cy + ((f.minZ + f.maxZ) / 2) * S + 6);
          }
        }
        const p = this.h.playerPose();
        g.save();
        g.translate(cx + p.x * S, cy + p.z * S);
        g.rotate(-p.heading + Math.PI);
        g.fillStyle = '#ff405d';
        g.beginPath();
        g.moveTo(0, -14);
        g.lineTo(9, 10);
        g.lineTo(-9, 10);
        g.closePath();
        g.fill();
        g.restore();
        g.fillStyle = '#b9a9b0';
        g.font = '700 22px system-ui';
        g.fillText('N', cx - 7, 30);
      };
      draw();
      this.mapTimer = window.setInterval(draw, 250);
    };
    const drawLocs = () => {
      clearInterval(this.mapTimer);
      const world = registry.boardImages.filter((i) => i.category === 'world');
      const gotham = world.filter((i) => i.id.startsWith('world/b_') && !i.label?.startsWith('citadel')).map((i) => i.id);
      const citadel = world.filter((i) => /^world\/[ab]_citadel/.test(i.id)).map((i) => i.id);
      pane.innerHTML = '';
      for (const [title, ids] of [['New Gotham', gotham], ['Red Citadel', ['world/scene_red_citadel_overview', ...citadel]]] as const) {
        pane.insertAdjacentHTML('beforeend', `<div class="ck-section">${title}</div>`);
        const gal = document.createElement('div');
        gal.className = 'ck-gallery locs';
        for (const id of ids) gal.insertAdjacentHTML('beforeend', `<figure><img alt="" src="${registry.imageUrl(id)}"><figcaption>${pretty(id)}</figcaption></figure>`);
        pane.appendChild(gal);
      }
      pane.insertAdjacentHTML('beforeend', '<p style="color:var(--ck-muted);font-size:12px">Concept locations from the Earth-RED boards — most are not built as playable areas yet.</p>');
    };
    for (const t of body.querySelectorAll<HTMLElement>('.ck-tab')) {
      t.addEventListener('click', () => {
        for (const x of body.querySelectorAll('.ck-tab')) x.setAttribute('aria-selected', String(x === t));
        if (t.dataset.t === 'map') drawMap();
        else drawLocs();
      });
    }
    drawMap();
    return () => clearInterval(this.mapTimer);
  }

  // ---------------- loadout ----------------
  private loadout(body: HTMLElement): void {
    const v = this.h.vitals;
    body.innerHTML = `<div class="ck-loadout"><div>
        <div class="ck-section" style="margin-top:0">CR-X9 War Suit</div>
        <img alt="CR-X9 turnaround" src="${registry.imageUrl('hero/c_turnaround_front')}" style="height:260px;display:block;margin:0 auto;border-radius:8px;background:#000">
        <p class="meta" style="color:var(--ck-muted)">Health ${Math.round(v.health)} · Armor ${Math.round(v.armor)} · Energy ${Math.round(v.energy)}</p>
        <div class="ck-gallery suit"></div></div>
      <div><div class="ck-section" style="margin-top:0">Gadget slots</div><div class="ck-grid slots" style="padding:0;max-height:none"></div>
        <div class="ck-section">Vehicle quick select</div><div class="ck-veh"></div>
        <p style="color:var(--ck-muted);font-size:12px">Drivable vehicles arrive in milestone M5; the call key plays the wrist-module call until then.</p></div></div>`;
    const suit = body.querySelector('.suit')!;
    for (const id of ['a_helmet_front', 'a_helmet_side', 'c_detail_chest', 'c_detail_gauntlet', 'c_detail_belt', 'a_armor_boots']) {
      suit.insertAdjacentHTML('beforeend', `<figure><img alt="" style="height:70px" src="${registry.imageUrl('hero/' + id)}"><figcaption>${pretty(id)}</figcaption></figure>`);
    }
    const slots = body.querySelector('.slots')!;
    this.h.inventory.state.hotbar.forEach((s, i) => {
      const d = s.itemId ? this.h.inventory.def(s.itemId) : undefined;
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'ck-card' + (i === this.h.inventory.state.selectedSlot ? ' sel' : '') + (d?.unavailableReason ? ' na' : '');
      b.innerHTML = `<span class="slotno">${keyLabel(this.h.bindings.get(`slot${i + 1}` as ActionId))}</span>
        <img alt="" src="${d ? IconRegistry.url(d.iconId) : IconRegistry.url('key_prompt')}"><span class="t">${d?.displayName ?? 'Empty'}</span>
        <span class="s">${d ? (d.unavailableReason ? 'not usable yet' : 'ready') : 'assign in inventory'}</span>`;
      b.addEventListener('click', () => this.show('inventory'));
      slots.appendChild(b);
    });
    const veh = body.querySelector('.ck-veh')!;
    for (const d of ITEMS.filter((i) => i.category === 'vehicle')) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'ck-card' + (this.h.quickVehicle() === d.id ? ' sel' : '');
      b.innerHTML = `<img alt="" src="${registry.imageUrl(d.artId!)}"><span class="t">${d.displayName}</span><span class="s">${this.h.quickVehicle() === d.id ? 'Quick-call ✓' : 'Set quick-call'} · unavailable</span>`;
      b.addEventListener('click', () => {
        this.h.setQuickVehicle(d.id);
        this.h.audio.play('ui.select');
        this.loadout(body);
      });
      veh.appendChild(b);
    }
  }

  // ---------------- settings ----------------
  private settingsScreen(body: HTMLElement): void {
    const s = this.h.settings;
    const row = (label: string, control: HTMLElement, extra = '') => {
      const r = document.createElement('div');
      r.className = 'ck-row';
      r.innerHTML = `<label></label><div></div><span style="color:var(--ck-muted);font-size:12px">${extra}</span>`;
      r.querySelector('label')!.textContent = label;
      r.children[1].appendChild(control);
      return r;
    };
    const section = (t: string) => body.insertAdjacentHTML('beforeend', `<div class="ck-section">${t}</div>`);
    const apply = () => this.h.applySettings();

    section('Graphics');
    const q = document.createElement('select');
    q.className = 'ck-select';
    q.innerHTML = '<option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option>';
    q.value = s.quality;
    q.addEventListener('change', () => {
      s.quality = q.value as Quality;
      apply();
    });
    body.appendChild(row('Quality preset', q, 'shadows · resolution · rain'));
    const fs = this.btn(document.fullscreenElement ? 'Exit fullscreen' : 'Enter fullscreen', 'graphics',
      document.fullscreenEnabled ? () => {
        if (document.fullscreenElement) void document.exitFullscreen();
        else void document.documentElement.requestFullscreen();
      } : null, document.fullscreenEnabled ? '' : 'Not available here');
    body.appendChild(row('Fullscreen', fs));

    section('Audio');
    const en = this.btn(this.h.audio.unlocked ? 'Audio enabled' : 'Enable audio', 'audio', () => {
      void this.h.audio.unlock().then(() => {
        this.h.audio.play('ui.select');
        en.querySelector('span')!.textContent = 'Audio enabled';
      });
    });
    body.appendChild(row('Sound', en, 'synthesized placeholder sounds'));
    const mute = document.createElement('input');
    mute.type = 'checkbox';
    mute.checked = s.muted;
    mute.addEventListener('change', () => {
      s.muted = mute.checked;
      apply();
    });
    body.appendChild(row('Mute all', mute));
    for (const [k, label] of [['master', 'Master'], ['sfx', 'Effects'], ['music', 'Music'], ['ambience', 'Ambience'], ['vehicles', 'Vehicles'], ['ui', 'Interface']] as const) {
      const r = document.createElement('input');
      r.type = 'range';
      r.min = '0';
      r.max = '1';
      r.step = '0.05';
      r.value = String(s.volumes[k]);
      r.setAttribute('aria-label', `${label} volume`);
      const pct = () => `${Math.round(s.volumes[k] * 100)}%`;
      const rowEl = row(`${label} volume`, r, pct());
      r.addEventListener('input', () => {
        s.volumes[k] = Number(r.value);
        (rowEl.lastElementChild as HTMLElement).textContent = pct();
        apply();
      });
      r.addEventListener('change', () => this.h.audio.play(k === 'ui' ? 'ui.click' : 'armor.step'));
      body.appendChild(rowEl);
    }
    body.insertAdjacentHTML('beforeend', '<p style="color:var(--ck-muted);font-size:12px">There is no music or vehicle audio yet; those sliders take effect when it is added.</p>');

    section('Interface');
    const sc = document.createElement('input');
    sc.type = 'range';
    sc.min = '0.7';
    sc.max = '1.5';
    sc.step = '0.05';
    sc.value = String(s.uiScale);
    sc.setAttribute('aria-label', 'UI scale');
    const scRow = row('UI scale', sc, `${Math.round(s.uiScale * 100)}%`);
    sc.addEventListener('input', () => {
      s.uiScale = Number(sc.value);
      (scRow.lastElementChild as HTMLElement).textContent = `${Math.round(s.uiScale * 100)}%`;
      apply();
    });
    body.appendChild(scRow);
    for (const [k, label] of [['hudVisible', 'Show HUD'], ['reduceMotion', 'Reduce motion']] as const) {
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = s[k];
      cb.addEventListener('change', () => {
        s[k] = cb.checked;
        apply();
      });
      body.appendChild(row(label, cb));
    }
    const sub = document.createElement('input');
    sub.type = 'checkbox';
    sub.disabled = true;
    body.appendChild(row('Subtitles', sub, 'Coming later (no dialogue yet)'));

    section('Controls');
    body.insertAdjacentHTML('beforeend', '<p style="color:var(--ck-muted);font-size:12px">Click a key, then press the new key. If it is already used, the two actions swap. Esc cancels.</p>');
    const keys = document.createElement('div');
    keys.className = 'ck-keys';
    const renderKeys = () => {
      keys.innerHTML = '';
      for (const a of ACTIONS) {
        const l = document.createElement('span');
        l.textContent = `${a.group} · ${a.label}`;
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'ck-btn';
        b.textContent = keyLabel(this.h.bindings.get(a.id));
        if (a.fixed) {
          b.disabled = true;
          b.title = 'Fixed';
        } else {
          b.addEventListener('click', () => {
            b.classList.add('listening');
            b.textContent = 'Press a key…';
            this.h.captureKey((code) => {
              if (code !== 'Escape') {
                const swapped = this.h.bindings.rebind(a.id, code);
                if (swapped) this.h.notify(`${keyLabel(code)} was used by "${ACTIONS.find((x) => x.id === swapped)?.label}" — swapped`, 'controls', 'warn');
                apply();
              }
              renderKeys();
            });
          });
        }
        keys.append(l, b);
      }
    };
    renderKeys();
    body.appendChild(keys);
    const reset = this.btn('Reset all controls to defaults', 'back', () => {
      this.h.bindings.reset();
      apply();
      renderKeys();
    });
    reset.style.marginTop = '10px';
    body.appendChild(reset);
    body.insertAdjacentHTML('beforeend', '<p style="color:var(--ck-muted);font-size:12px">Gamepad (standard layout): A jump · B crouch · X interact · Y inventory · LB/RB previous/next slot · LT aim · RT use item · L3 sprint · Start pause · Back map · D-pad up call vehicle.</p>');
  }
}

/** "c_detail_chest" / "world/b_citadel_command_center" -> readable caption */
function pretty(id: string): string {
  return id.split('/').pop()!.replace(/^[a-z0-9]+_/, '').replace(/^scene_/, '').replace(/_wide$/, '')
    .replace(/^citadel_/, '').replace(/^(turnaround|helmet|armor|detail)_/, '').replace(/_/g, ' ');
}
