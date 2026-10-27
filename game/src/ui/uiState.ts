import { DEFAULT_HOTBAR, STARTING_OWNED, itemById } from './inventoryData';
import type { HotbarSlot, InventoryState, ItemDefinition, ItemId } from './inventoryTypes';

/**
 * InventoryService: the ONE source of truth for owned items, hotbar assignments and the selected
 * slot. Hotbar, inventory panel, loadout, HUD and gameplay (equipment.ts) all read and write here.
 */
export class InventoryService {
  state: InventoryState;
  /** per-item next-allowed-use time and cooldown length (ms, performance.now clock) */
  private cooldownUntil = new Map<ItemId, number>();
  private restockAt = new Map<ItemId, number>();
  private listeners = new Set<() => void>();

  constructor(saved?: Partial<InventoryState>) {
    this.state = InventoryService.fresh();
    if (saved) this.load(saved);
  }

  static fresh(): InventoryState {
    return {
      owned: Object.fromEntries(Object.entries(STARTING_OWNED).map(([itemId, quantity]) => [itemId, { itemId, quantity }])),
      hotbar: DEFAULT_HOTBAR.map((s, index) => ({ index, itemId: s.itemId, keyCode: s.keyCode })),
      selectedSlot: 0,
    };
  }

  /** Apply saved data, dropping unknown item ids (items removed in an update) instead of crashing. */
  load(saved: Partial<InventoryState>): void {
    if (saved.owned && typeof saved.owned === 'object') {
      for (const [id, stack] of Object.entries(saved.owned)) {
        const def = itemById.get(id);
        if (!def || !stack || typeof stack.quantity !== 'number') continue;
        this.state.owned[id] = { itemId: id, quantity: Math.max(0, Math.min(def.maxStack, Math.floor(stack.quantity))) };
      }
    }
    if (Array.isArray(saved.hotbar)) {
      saved.hotbar.slice(0, 8).forEach((s, i) => {
        const id = s?.itemId ?? null;
        this.state.hotbar[i].itemId = id && itemById.get(id)?.canEquip ? id : null;
      });
    }
    if (typeof saved.selectedSlot === 'number' && saved.selectedSlot >= 0 && saved.selectedSlot < 8) {
      this.state.selectedSlot = Math.floor(saved.selectedSlot);
    }
    this.emit();
  }

  onChange(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private emit(): void {
    this.listeners.forEach((l) => l());
  }

  def(id: ItemId): ItemDefinition | undefined {
    return itemById.get(id);
  }

  quantity(id: ItemId): number {
    return this.state.owned[id]?.quantity ?? 0;
  }

  has(id: ItemId): boolean {
    return this.quantity(id) > 0;
  }

  slot(index: number): HotbarSlot | undefined {
    return this.state.hotbar[index];
  }

  get selectedItemId(): ItemId | null {
    return this.state.hotbar[this.state.selectedSlot]?.itemId ?? null;
  }

  /**
   * Select a hotbar slot. Selecting never uses the item. Returns a reason string when the slot
   * cannot be selected (empty / item not owned), so the UI can give feedback.
   */
  selectSlot(index: number): string | null {
    const slot = this.state.hotbar[index];
    if (!slot) return 'No such slot';
    if (!slot.itemId) return `Slot ${index + 1} is empty — assign an item from the inventory (Tab)`;
    if (!this.has(slot.itemId)) return `${this.def(slot.itemId)?.displayName ?? 'Item'}: none left`;
    if (this.state.selectedSlot !== index) {
      this.state.selectedSlot = index;
      this.emit();
    }
    return null;
  }

  /** Step selection to the next/previous non-empty slot. */
  cycle(dir: 1 | -1): void {
    for (let i = 1; i <= 8; i++) {
      const idx = (this.state.selectedSlot + dir * i + 8) % 8;
      if (this.state.hotbar[idx].itemId) {
        this.selectSlot(idx);
        return;
      }
    }
  }

  /** Put an item in a hotbar slot (an item lives in at most one slot; the old slot is cleared). */
  assign(itemId: ItemId | null, index: number): string | null {
    if (index < 0 || index > 7) return 'No such slot';
    if (itemId) {
      const d = this.def(itemId);
      if (!d) return 'Unknown item';
      if (!d.canEquip) return `${d.displayName} cannot be placed on the hotbar`;
      for (const s of this.state.hotbar) if (s.itemId === itemId) s.itemId = null;
    }
    this.state.hotbar[index].itemId = itemId;
    this.emit();
    return null;
  }

  // ---- cooldowns & consumption (driven by real game time) ----
  cooldownRemaining(id: ItemId, now: number): number {
    return Math.max(0, (this.cooldownUntil.get(id) ?? 0) - now);
  }

  cooldownFraction(id: ItemId, now: number): number {
    const total = this.def(id)?.cooldownMs ?? 0;
    return total ? this.cooldownRemaining(id, now) / total : 0;
  }

  startCooldown(id: ItemId, now: number): void {
    const ms = this.def(id)?.cooldownMs ?? 0;
    if (ms) this.cooldownUntil.set(id, now + ms);
  }

  consume(id: ItemId, n = 1): boolean {
    const d = this.def(id);
    const s = this.state.owned[id];
    if (!d || !s || s.quantity < n) return false;
    if (d.stackable) {
      s.quantity -= n;
      this.emit();
    }
    return true;
  }

  /** Consumables refill slowly over time (sandbox: no shop, no paywall). */
  tick(now: number): void {
    let changed = false;
    for (const [id, stack] of Object.entries(this.state.owned)) {
      const d = this.def(id);
      if (!d?.restockMs || stack.quantity >= d.maxStack) {
        this.restockAt.delete(id);
        continue;
      }
      const at = this.restockAt.get(id);
      if (at === undefined) this.restockAt.set(id, now + d.restockMs);
      else if (now >= at) {
        stack.quantity++;
        this.restockAt.delete(id);
        changed = true;
      }
    }
    if (changed) this.emit();
  }

  /** Persistable snapshot (game state only, no catalog data). */
  snapshot(): InventoryState {
    return {
      owned: Object.fromEntries(Object.entries(this.state.owned).map(([k, v]) => [k, { itemId: k, quantity: v.quantity }])),
      hotbar: this.state.hotbar.map((s) => ({ ...s })),
      selectedSlot: this.state.selectedSlot,
    };
  }
}

export type Quality = 'low' | 'medium' | 'high';

export interface Settings {
  uiScale: number;
  hudVisible: boolean;
  reduceMotion: boolean;
  quality: Quality;
  volumes: { master: number; music: number; ambience: number; sfx: number; vehicles: number; ui: number };
  muted: boolean;
}

export const DEFAULT_SETTINGS: Settings = {
  uiScale: 1, hudVisible: true, reduceMotion: false, quality: 'high',
  volumes: { master: 0.8, music: 0.6, ambience: 0.6, sfx: 0.8, vehicles: 0.8, ui: 0.6 }, muted: false,
};

export interface SaveData {
  version: number;
  savedAt: string;
  inventory: InventoryState;
  bindings: Record<string, string>;
  settings: Settings;
  player?: { position: [number, number, number]; heading: number };
  /** item id of the vehicle the call key summons */
  quickVehicle?: string;
}

export const SAVE_VERSION = 1;
const SAVE_KEY = 'crimson-knight.save';
const SETTINGS_KEY = 'crimson-knight.settings';

interface KV {
  getItem(k: string): string | null;
  setItem(k: string, v: string): void;
  removeItem(k: string): void;
}

/** Versioned save/load (localStorage). Settings persist separately so they survive "New Sandbox". */
export class SaveService {
  constructor(private store: KV | null = typeof localStorage !== 'undefined' ? localStorage : null) {}

  /** Migrates older versions forward; returns null for missing/corrupt saves. */
  static migrate(raw: unknown): SaveData | null {
    if (!raw || typeof raw !== 'object') return null;
    const d = raw as Partial<SaveData> & { version?: number };
    if (typeof d.version !== 'number' || d.version > SAVE_VERSION) return null;
    // v1 is the first format; future versions add steps here (v1 -> v2 ...)
    return {
      version: SAVE_VERSION,
      savedAt: typeof d.savedAt === 'string' ? d.savedAt : '',
      inventory: (d.inventory ?? InventoryService.fresh()) as InventoryState,
      bindings: d.bindings && typeof d.bindings === 'object' ? d.bindings : {},
      settings: SaveService.cleanSettings(d.settings),
      player: SaveService.cleanPlayer(d.player),
      quickVehicle: typeof d.quickVehicle === 'string' && itemById.get(d.quickVehicle)?.category === 'vehicle' ? d.quickVehicle : undefined,
    };
  }

  static cleanSettings(s: unknown): Settings {
    const out: Settings = structuredClone(DEFAULT_SETTINGS);
    if (!s || typeof s !== 'object') return out;
    const v = s as Partial<Settings>;
    if (typeof v.uiScale === 'number') out.uiScale = Math.min(1.5, Math.max(0.7, v.uiScale));
    if (typeof v.hudVisible === 'boolean') out.hudVisible = v.hudVisible;
    if (typeof v.reduceMotion === 'boolean') out.reduceMotion = v.reduceMotion;
    if (v.quality === 'low' || v.quality === 'medium' || v.quality === 'high') out.quality = v.quality;
    if (typeof v.muted === 'boolean') out.muted = v.muted;
    if (v.volumes && typeof v.volumes === 'object') {
      for (const k of Object.keys(out.volumes) as (keyof Settings['volumes'])[]) {
        const x = (v.volumes as Record<string, unknown>)[k];
        if (typeof x === 'number') out.volumes[k] = Math.min(1, Math.max(0, x));
      }
    }
    return out;
  }

  private static cleanPlayer(p: unknown): SaveData['player'] {
    if (!p || typeof p !== 'object') return undefined;
    const v = p as SaveData['player'];
    const ok = Array.isArray(v?.position) && v!.position.length === 3 && v!.position.every((n) => Number.isFinite(n));
    return ok ? { position: v!.position, heading: Number.isFinite(v!.heading) ? v!.heading : 0 } : undefined;
  }

  read(): SaveData | null {
    try {
      return SaveService.migrate(JSON.parse(this.store?.getItem(SAVE_KEY) ?? 'null'));
    } catch {
      return null;
    }
  }

  write(data: Omit<SaveData, 'version' | 'savedAt'>): void {
    const full: SaveData = { version: SAVE_VERSION, savedAt: new Date().toISOString(), ...data };
    this.store?.setItem(SAVE_KEY, JSON.stringify(full));
    this.writeSettings(data.settings, data.bindings);
  }

  clear(): void {
    this.store?.removeItem(SAVE_KEY);
  }

  readSettings(): { settings: Settings; bindings: Record<string, string> } {
    try {
      const raw = JSON.parse(this.store?.getItem(SETTINGS_KEY) ?? 'null');
      return { settings: SaveService.cleanSettings(raw?.settings), bindings: raw?.bindings && typeof raw.bindings === 'object' ? raw.bindings : {} };
    } catch {
      return { settings: structuredClone(DEFAULT_SETTINGS), bindings: {} };
    }
  }

  writeSettings(settings: Settings, bindings: Record<string, string>): void {
    this.store?.setItem(SETTINGS_KEY, JSON.stringify({ version: SAVE_VERSION, settings, bindings }));
  }
}

