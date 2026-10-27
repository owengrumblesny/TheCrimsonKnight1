import type { Hero } from '../actors/hero';
import type { Player } from '../actors/player';
import { clipReferences, registry } from '../data/registry';

/** Icons are Owen's ui/icons PNGs; pictures are images cut from his concept boards (config/image_catalog.json). */
const icon = (id: string) => registry.iconUrl(id);
const pic = (id: string) => registry.imageUrl(id);

/** Gadget menu: id, label, image cut from the asset board. */
const GADGETS = [
  ['batarang', 'Batarang', 'gadgets/b_batarangs'], ['grapple', 'Grapnel Gun', 'gadgets/b_grapple_gun'],
  ['smoke', 'Smoke Pellet', 'gadgets/b_smoke_pellet'], ['flash', 'Flash Grenade', 'gadgets/b_flash_grenade'],
  ['emp', 'EMP Device', 'gadgets/b_emp_device'], ['sonic', 'Sonic Device', 'gadgets/b_sonic_device'],
  ['scanner', 'Holo Scanner', 'gadgets/b_holographic'], ['tablet', 'Tac Tablet', 'gadgets/b_tac_tablet'],
  ['visor', 'Thermal Visor', 'gadgets/b_thermal_visor'], ['zipline', 'Zip Line', 'gadgets/b_zip_line'],
  ['gel', 'Explosive Gel', 'gadgets/b_explosive_gel'], ['medkit', 'Medkit', 'gadgets/b_medkit'],
] as const;

/** Summon menu: showcase + mode images from the CR-X1 / CR-B1 / CR-A1 boards. */
const VEHICLES = [
  { id: 'interceptor', label: 'CR-X1 Crimson Interceptor', img: 'vehicles/x1_crx1_showcase',
    modes: [['Pursuit', 'vehicles/x1_crx1_pursuit'], ['Battle', 'vehicles/x1_crx1_battle'], ['Stealth', 'vehicles/x1_crx1_stealth']] },
  { id: 'batcycle', label: 'CR-B1 Crimson Batcycle', img: 'vehicles/b1_crb1_showcase',
    modes: [['Pursuit', 'vehicles/b1_crb1_pursuit'], ['Combat', 'vehicles/b1_crb1_combat'], ['Stealth', 'vehicles/b1_crb1_stealth']] },
  { id: 'specter', label: 'CR-A1 Crimson Specter', img: 'vehicles/a1_cra1_showcase',
    modes: [['Flight', 'vehicles/a1_cra1_flight'], ['VTOL', 'vehicles/a1_cra1_vtol'], ['Stealth', 'vehicles/a1_cra1_stealth']] },
] as const;

/** Suit viewer sections (hero/* board images). */
const SUIT: [string, string[]][] = [
  ['TURNAROUND', ['c_turnaround_front', 'c_turnaround_front_angle', 'c_turnaround_side', 'c_turnaround_back_angle', 'c_turnaround_back', 'c_turnaround_side_b']],
  ['HELMET', ['a_helmet_front', 'a_helmet_front_angle', 'a_helmet_side', 'a_helmet_back', 'a_helmet_top', 'a_helmet_left', 'a_helmet_right']],
  ['ARMOR', ['c_detail_helmet', 'c_detail_chest', 'c_detail_gauntlet', 'c_detail_belt', 'a_armor_shoulder', 'a_armor_leg', 'a_armor_boots', 'a_armor_emblem']],
  ['DISPLAY', ['scene_war_suit_display']],
];

const CONTROLS = [
  ['walk', 'WASD', 'Move'], ['mouse', 'Mouse', 'Look (click to capture)'], ['sprint', 'Shift', 'Sprint'], ['run', 'CapsLock', 'Walk / run toggle'],
  ['crouch', 'C', 'Crouch'], ['jump', 'Space', 'Jump'], ['glide', 'Space (air)', 'Hold to glide'], ['grapple', 'G', 'Aim grapnel'],
  ['equipment', 'Q', 'Gadget menu'], ['summon', 'V', 'Summon vehicle'], ['interact', 'E', 'Interact'],
  ['pause', 'Esc', 'Pause menu'], ['hud', '`', 'Animation debug'], ['gamepad', 'Gamepad', 'Standard layout'],
] as const;

/** "b_citadel_command_center" -> "command center" */
const pretty = (label: string) => label.replace(/^[a-z0-9]+_/, '').replace(/^scene_/, '').replace(/_wide$/, '')
  .replace(/^citadel_/, '').replace(/^(turnaround|helmet|armor|detail)_/, '').replace(/_/g, ' ');

type Menu = 'gadget' | 'summon' | 'pause' | 'controls' | 'suit' | 'map' | null;
interface Item { id: string; label: string; img: string }

/** HUD, action bar, menus and the animation debug panel. */
export class Hud {
  debugClip: string | null = null;
  menu: Menu = null;
  private status!: HTMLDivElement;
  private panel!: HTMLDivElement;
  private slots = new Map<string, HTMLDivElement>();
  private menuEl!: HTMLDivElement;
  private toastEl!: HTMLDivElement;
  private toastTimer = 0;
  private compass!: HTMLSpanElement;
  private energyBar!: HTMLDivElement;
  private energy = 1;
  private wasLocked = false;
  private refEl!: HTMLDivElement;
  private refImg!: HTMLImageElement;
  private refFrames: string[] = [];
  private refT = 0;

  constructor(private hero: Hero, private player: Player, private canvas: HTMLCanvasElement) {
    this.style();
    this.build();
    document.addEventListener('pointerlockchange', () => {
      // Esc while the mouse is captured releases pointer lock instead of sending keydown
      if (!document.pointerLockElement && !this.menu && !this.debugClip && this.wasLocked) this.open('pause');
      this.wasLocked = !!document.pointerLockElement;
    });
  }

  private style(): void {
    const css = document.createElement('style');
    css.textContent = `
      .ck{position:fixed;font:12px/1.4 system-ui,sans-serif;color:#eadede;text-shadow:0 1px 2px #000;z-index:5}
      .ck-brand{left:16px;top:12px;letter-spacing:.18em;font-weight:700;color:#ff3030}
      .ck-brand small{display:block;letter-spacing:.08em;font-weight:400;color:#c9b9b9}
      .ck-meters{left:16px;top:52px;display:flex;gap:8px;align-items:flex-start}
      .ck-portrait{width:68px;height:68px;object-fit:cover;border:1px solid #8a1010;border-radius:6px}
      .ck-meter{display:flex;align-items:center;gap:6px;margin-bottom:2px}
      .ck-meter img{width:24px;height:24px}
      .ck-meter .bar{width:140px;height:7px;background:#2a1418;border:1px solid #5a1a1a;border-radius:4px;overflow:hidden}
      .ck-meter .fill{height:100%;background:linear-gradient(90deg,#8a0c17,#f5182a)}
      .ck-top{right:16px;top:12px;display:flex;align-items:center;gap:6px;font-family:ui-monospace,monospace}
      .ck-top img{width:34px;height:34px}
      .ck-status{right:16px;top:54px;font-family:ui-monospace,monospace;opacity:.75}
      .ck-bar{left:50%;bottom:14px;transform:translateX(-50%);display:flex;gap:6px}
      .ck-slot{position:relative;width:58px;height:58px;opacity:.45;transition:opacity .15s,transform .15s,filter .15s}
      .ck-slot img{width:100%;height:100%;object-fit:cover;border-radius:8px}
      .ck-slot.on{opacity:1;transform:translateY(-4px);filter:drop-shadow(0 0 8px #ff2030)}
      .ck-slot b{position:absolute;right:3px;top:2px;font:600 10px ui-monospace,monospace;color:#fff;background:#000a;padding:0 3px;border-radius:3px}
      .ck-menu{inset:0;display:none;align-items:center;justify-content:center;background:#05050acc;backdrop-filter:blur(3px);z-index:10}
      .ck-menu.open{display:flex}
      .ck-menu .box{background:#0d0b10ee;border:1px solid #6a1212;border-radius:10px;padding:18px 22px;width:min(900px,92vw);max-height:86vh;overflow:auto;box-sizing:border-box}
      .ck-menu h2{margin:0 0 12px;font:700 14px system-ui;letter-spacing:.2em;color:#ff3030}
      .ck-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(110px,1fr));gap:10px}
      .ck-item{display:flex;flex-direction:column;align-items:center;gap:4px;padding:6px;border:1px solid transparent;border-radius:8px;
        cursor:pointer;background:none;color:inherit;font:inherit}
      .ck-item:hover,.ck-item.on{border-color:#ff2030;background:#2a0a0e}
      .ck-item img{width:76px;height:76px}
      .ck-item.pic img{width:104px;height:80px;object-fit:contain;background:#000;border-radius:4px}
      .ck-item small{opacity:.7}
      .ck-cards{display:flex;flex-direction:column;gap:10px}
      .ck-card{display:grid;grid-template-columns:300px 1fr;gap:12px;align-items:center;padding:8px;border:1px solid #3a1010;
        border-radius:8px;cursor:pointer;background:#120c0f;color:inherit;font:inherit;text-align:left}
      .ck-card:hover{border-color:#ff2030;background:#2a0a0e}
      .ck-card>img{width:300px;height:130px;object-fit:cover;border-radius:4px}
      .ck-card .modes{display:flex;gap:6px;margin-top:6px}
      .ck-card figure{margin:0;text-align:center;font-size:11px;opacity:.85}
      .ck-card figure img{width:120px;height:54px;object-fit:cover;border-radius:3px}
      .ck-gallery h3{margin:12px 0 6px;font:700 11px system-ui;letter-spacing:.2em;color:#ff6060}
      .ck-gallery .row{display:flex;flex-wrap:wrap;gap:8px}
      .ck-gallery figure{margin:0;text-align:center;font-size:11px;opacity:.9;text-transform:capitalize}
      .ck-gallery img{height:140px;max-width:320px;object-fit:contain;background:#000;border-radius:4px;display:block}
      .ck-gallery.locs img{height:96px;width:170px;object-fit:cover}
      .ck-rows{display:grid;grid-template-columns:auto auto 1fr;gap:6px 14px;align-items:center}
      .ck-rows img{width:36px;height:36px}
      .ck-rows kbd{font:600 12px ui-monospace,monospace;background:#241418;border:1px solid #5a1a1a;border-radius:4px;padding:2px 6px}
      .ck-toast{left:50%;top:16%;transform:translateX(-50%);display:none;align-items:center;gap:10px;background:#0d0b10ee;
        border:1px solid #6a1212;border-radius:8px;padding:8px 14px}
      .ck-toast img{height:56px;max-width:140px;object-fit:contain;border-radius:4px}
      .ck-panel{right:16px;top:80px;display:none;flex-direction:column;gap:3px;background:#0d0d12d0;border:1px solid #661111;
        padding:8px;border-radius:6px;max-height:60vh;overflow:auto}
      .ck-panel button{font:12px system-ui;background:#1a1114;color:#f3dede;border:1px solid #441414;border-radius:4px;padding:3px 8px;
        text-align:left;cursor:pointer}
      .ck-panel button:hover,.ck-panel button.on{background:#7a0e0e}
      .ck-ref{right:200px;top:80px;display:none;background:#0d0d12e0;border:1px solid #661111;border-radius:6px;padding:6px;text-align:center}
      .ck-ref img{height:170px;max-width:320px;object-fit:contain;display:block;margin-bottom:4px}`;
    document.head.appendChild(css);
  }

  private el(cls: string, html = '', parent: HTMLElement = document.body): HTMLDivElement {
    const d = document.createElement('div');
    d.className = cls;
    d.innerHTML = html;
    parent.appendChild(d);
    return d;
  }

  private build(): void {
    this.el('ck ck-brand', 'OWEN ENTERPRISES · CRIMSON KNIGHT: EARTH-RED<small>New Gotham sandbox</small>');
    const meters = this.el('ck ck-meters', `<img class="ck-portrait" src="${pic('hero/a_helmet_front')}" alt="CR-X9">`);
    const bars = this.el('', '', meters);
    for (const id of ['health', 'armor', 'energy']) {
      const m = this.el('ck-meter', `<img src="${icon(id)}" alt="${id}"><div class="bar"><div class="fill" style="width:100%"></div></div>`, bars);
      if (id === 'energy') this.energyBar = m.querySelector('.fill')!;
    }
    const top = this.el('ck ck-top', `<img src="${icon('night')}" alt="night"><img src="${icon('rain')}" alt="rain"><img src="${icon('compass')}" alt="compass">`);
    this.compass = document.createElement('span');
    top.appendChild(this.compass);
    this.status = this.el('ck ck-status');

    const bar = this.el('ck ck-bar');
    for (const [id, key] of [['run', 'Caps'], ['sprint', 'Shift'], ['crouch', 'C'], ['jump', 'Spc'], ['glide', 'Spc'],
      ['grapple', 'G'], ['equipment', 'Q'], ['summon', 'V'], ['interact', 'E']] as const) {
      this.slots.set(id, this.el('ck-slot', `<img src="${icon(id)}" alt="${id}"><b>${key}</b>`, bar));
    }

    this.menuEl = this.el('ck ck-menu');
    this.menuEl.addEventListener('click', (e) => {
      if (e.target === this.menuEl) this.close();
    });
    this.toastEl = this.el('ck ck-toast');

    // animation debug: clip list + reference key-pose flipbook from the boards
    this.refEl = this.el('ck ck-ref', '<img alt=""><small>board reference</small>');
    this.refImg = this.refEl.querySelector('img')!;
    this.panel = this.el('ck ck-panel');
    const off = document.createElement('button');
    off.textContent = '▶ gameplay control';
    off.onclick = () => this.selectClip(null);
    this.panel.appendChild(off);
    for (const name of this.hero.clipNames) {
      const b = document.createElement('button');
      b.textContent = name;
      b.title = this.hero.meta.get(name)?.description ?? '';
      b.onclick = () => this.selectClip(name);
      this.panel.appendChild(b);
    }
  }

  private items(list: Item[], onPick: (id: string) => void, active?: string | null, cls = ''): HTMLDivElement {
    const grid = document.createElement('div');
    grid.className = 'ck-grid';
    list.forEach(({ id, label, img }, i) => {
      const b = document.createElement('button');
      b.className = `ck-item ${cls}` + (id === active ? ' on' : '');
      b.innerHTML = `<img src="${img}" alt="${id}"><span>${label}</span><small>${i < 9 ? i + 1 : ''}</small>`;
      b.onclick = () => onPick(id);
      grid.appendChild(b);
    });
    return grid;
  }

  private gallery(sections: [string, string[]][], cls = ''): HTMLDivElement {
    const g = document.createElement('div');
    g.className = 'ck-gallery ' + cls;
    for (const [title, ids] of sections) {
      g.insertAdjacentHTML('beforeend', `<h3>${title}</h3>`);
      const row = this.el('row', '', g);
      for (const id of ids) {
        row.insertAdjacentHTML('beforeend', `<figure><img src="${pic(id)}" alt=""><figcaption>${pretty(id.split('/')[1])}</figcaption></figure>`);
      }
    }
    return g;
  }

  open(menu: Exclude<Menu, null>): void {
    this.menu = menu;
    document.exitPointerLock?.();
    const box = document.createElement('div');
    box.className = 'box';
    if (menu === 'gadget') {
      box.innerHTML = '<h2>EQUIPMENT</h2>';
      const list: Item[] = GADGETS.map(([id, label, img]) => ({ id, label, img: pic(img) }));
      if (this.player.state.gadget) list.push({ id: 'stow', label: 'Stow', img: icon('equipment') });
      box.appendChild(this.items(list, (id) => this.pickGadget(id), this.player.state.gadget, 'pic'));
    } else if (menu === 'summon') {
      box.innerHTML = '<h2>SUMMON VEHICLE</h2>';
      const cards = this.el('ck-cards', '', box);
      VEHICLES.forEach((v, i) => {
        const c = document.createElement('button');
        c.className = 'ck-card ck-item';
        c.innerHTML = `<img src="${pic(v.img)}" alt=""><div><b>${i + 1}. ${v.label}</b><div class="modes">` +
          v.modes.map(([m, img]) => `<figure><img src="${pic(img)}" alt=""><figcaption>${m}</figcaption></figure>`).join('') + '</div></div>';
        c.onclick = () => this.pickVehicle(v.id);
        cards.appendChild(c);
      });
    } else if (menu === 'pause') {
      box.innerHTML = '<h2>PAUSED</h2>';
      const opts: [string, string, string][] = [['resume', 'Resume', 'resume'], ['suit', 'CR-X9 Suit', 'armor'],
        ['map', 'Locations', 'map'], ['controls', 'Controls', 'controls'], ['settings', 'Settings', 'settings'],
        ['save', 'Save', 'save'], ['photo_mode', 'Photo mode', 'photo_mode']];
      box.appendChild(this.items(opts.map(([id, label, ic]) => ({ id, label, img: icon(ic) })), (id) => this.pickPause(id)));
    } else if (menu === 'suit') {
      box.innerHTML = '<h2>CR-X9 CRIMSON KNIGHT — SUIT</h2>';
      box.appendChild(this.gallery(SUIT.map(([t, ids]) => [t, ids.map((i) => 'hero/' + i)])));
    } else if (menu === 'map') {
      box.innerHTML = '<h2>LOCATIONS — EARTH-RED</h2>';
      const world = registry.boardImages.filter((i) => i.category === 'world');
      const gotham = world.filter((i) => i.id.startsWith('world/b_') && !i.label?.startsWith('citadel')).map((i) => i.id);
      const citadel = world.filter((i) => /^world\/[ab]_citadel/.test(i.id)).map((i) => i.id);
      box.appendChild(this.gallery([['NEW GOTHAM', gotham], ['RED CITADEL', ['world/scene_red_citadel_overview', ...citadel]]], 'locs'));
    } else {
      box.innerHTML = '<h2>CONTROLS</h2>';
      const rows = this.el('ck-rows', '', box);
      for (const [id, key, what] of CONTROLS) rows.insertAdjacentHTML('beforeend', `<img src="${icon(id)}" alt=""><kbd>${key}</kbd><span>${what}</span>`);
    }
    this.menuEl.replaceChildren(box);
    this.menuEl.classList.add('open');
  }

  close(): void {
    this.menu = null;
    this.menuEl.classList.remove('open');
    this.canvas.requestPointerLock?.();
  }

  /** Number keys pick the n-th item of an open menu. */
  pickIndex(i: number): void {
    this.menuEl.querySelectorAll<HTMLButtonElement>('.ck-item')[i]?.click();
  }

  private pickGadget(id: string): void {
    const g = GADGETS.find(([k]) => k === id);
    if (this.player.setGadget(g ? id : null)) {
      if (g) this.toastPic(pic(g[2]), `${g[1]} ready (fictional prop)`);
      else this.toastPic(icon('equipment'), 'Gadget stowed');
    }
    this.close();
  }

  private pickVehicle(id: string): void {
    const v = VEHICLES.find((x) => x.id === id)!;
    if (this.player.summon()) this.toastPic(pic(v.img), `${v.label} called — drivable vehicles arrive in milestone M5`);
    this.close();
  }

  private pickPause(id: string): void {
    if (id === 'resume') this.close();
    else if (id === 'controls' || id === 'suit' || id === 'map') this.open(id);
    else this.toastPic(icon(id), 'Not built yet — planned for a later milestone');
  }

  toastPic(src: string, text: string): void {
    this.toastEl.innerHTML = `<img src="${src}" alt=""><span>${text}</span>`;
    this.toastEl.style.display = 'flex';
    this.toastTimer = 3;
  }

  private selectClip(name: string | null): void {
    this.debugClip = name;
    for (const b of this.panel.querySelectorAll('button')) b.classList.toggle('on', b.textContent === name);
    this.refFrames = name ? (clipReferences[name] ?? []).flatMap((id) => registry.imageFrames(id)) : [];
    this.refEl.style.display = this.refFrames.length ? 'block' : 'none';
    this.refT = 0;
    if (name) this.hero.play(name, { fade: 0.2, restart: true });
  }

  togglePanel(): void {
    const show = this.panel.style.display !== 'flex';
    this.panel.style.display = show ? 'flex' : 'none';
    if (!show) this.refEl.style.display = 'none';
    if (show) document.exitPointerLock?.();
  }

  update(dt: number): void {
    const s = this.player.state;
    const on = (id: string, v: boolean) => this.slots.get(id)?.classList.toggle('on', v);
    on('run', s.mode === 'ground' && s.speed > 0.2 && !s.sprinting && !s.crouched);
    on('sprint', s.sprinting);
    on('crouch', s.crouched);
    on('jump', s.mode === 'air');
    on('glide', s.mode === 'glide');
    on('grapple', s.aiming);
    on('equipment', !!s.gadget);
    on('summon', this.hero.current === 'CK_Summon');
    on('interact', this.hero.current === 'CK_Interact');
    // equipped gadget shows its board image in the slot
    const eq = this.slots.get('equipment')!.querySelector('img')!;
    const g = GADGETS.find(([k]) => k === s.gadget);
    const want = g ? pic(g[2]) : icon('equipment');
    if (eq.getAttribute('src') !== want) eq.setAttribute('src', want);
    // suit energy: drains while sprinting or gliding, recharges otherwise (display only for now)
    this.energy = Math.min(1, Math.max(0, this.energy + dt * (s.sprinting || s.mode === 'glide' ? -0.08 : 0.15)));
    this.energyBar.style.width = `${this.energy * 100}%`;
    const deg = ((((Math.PI - s.heading) * 180) / Math.PI) % 360 + 360) % 360;
    this.compass.textContent = `${['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][Math.round(deg / 45) % 8]} ${deg.toFixed(0).padStart(3, '0')}°`;
    this.status.textContent = this.debugClip ? `debug clip: ${this.debugClip}` : this.player.status;
    if (this.toastTimer > 0 && (this.toastTimer -= dt) <= 0) this.toastEl.style.display = 'none';
    if (this.refFrames.length) {
      this.refT += dt;
      const src = this.refFrames[Math.floor(this.refT * 8) % this.refFrames.length];
      if (this.refImg.getAttribute('src') !== src) this.refImg.setAttribute('src', src);
    }
  }
}
