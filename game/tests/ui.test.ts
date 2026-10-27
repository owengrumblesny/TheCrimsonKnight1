import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import catalog from '../../config/image_catalog.json';
import hotbarLayout from '../src/ui/data/hotbar_layout.json';
import iconManifest from '../src/ui/data/icon_manifest.json';
import { IconRegistry, keyLabel } from '../src/ui/IconRegistry';
import { ACTIONS, Bindings, DEFAULT_BINDINGS, isTypingTarget } from '../src/ui/inputBindings';
import { DEFAULT_HOTBAR, ITEMS, itemById } from '../src/ui/inventoryData';
import { DEFAULT_SETTINGS, InventoryService, SAVE_VERSION, SaveService } from '../src/ui/uiState';

const PUBLIC_UI = path.resolve(__dirname, '../public/ui');
const ROOT = path.resolve(__dirname, '../..');

describe('icon assets', () => {
  it('ships every PNG/SVG referenced by icon_manifest.json (67 icons + 26 keycaps)', () => {
    const icons = iconManifest.icons as Record<string, unknown>[];
    expect(icons.filter((i) => i.category !== 'keycap')).toHaveLength(67);
    expect(icons.filter((i) => i.category === 'keycap')).toHaveLength(26);
    const missing: string[] = [];
    for (const icon of icons) {
      for (const key of ['glyphPNG', 'circlePNG', 'glyphSVG', 'circleSVG']) {
        const rel = icon[key];
        if (typeof rel === 'string' && !fs.existsSync(path.join(PUBLIC_UI, rel))) missing.push(rel);
      }
    }
    expect(missing).toEqual([]);
  });

  it('resolves hotbar circles vs inventory glyphs to different files under BASE_URL', () => {
    expect(IconRegistry.url('grapple', 'circle')).toMatch(/ui\/assets\/gadget\/circle\/grapple\.png$/);
    expect(IconRegistry.url('grapple', 'glyph')).toMatch(/ui\/assets\/gadget\/glyph\/grapple\.png$/);
    expect(IconRegistry.url('grapple')).toMatch(new RegExp(`^${import.meta.env.BASE_URL}`));
  });

  it('falls back to a neutral icon instead of throwing for unknown ids', () => {
    expect(() => IconRegistry.url('does_not_exist')).not.toThrow();
    expect(IconRegistry.get('does_not_exist').id).toBe('notification');
  });

  it('maps key codes to keycap art and labels', () => {
    expect(IconRegistry.keycap('Digit3')).toMatch(/keycaps\/3\.png$/);
    expect(IconRegistry.keycap('KeyE')).toMatch(/keycaps\/e\.png$/);
    expect(IconRegistry.keycap('KeyZ')).toBeNull();
    expect(keyLabel('Digit1')).toBe('1');
    expect(keyLabel('KeyQ')).toBe('Q');
  });

  it('every item links to an existing icon id, board image and asset model', () => {
    const imageIds = new Set(catalog.images.map((i) => i.id));
    const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'config/asset_manifest.json'), 'utf8'));
    const modelIds = new Set(manifest.assets.map((a: { id: string }) => a.id));
    for (const item of ITEMS) {
      expect(IconRegistry.has(item.iconId), `${item.id} icon ${item.iconId}`).toBe(true);
      if (item.artId) expect(imageIds.has(item.artId), `${item.id} art ${item.artId}`).toBe(true);
      if (item.modelId) expect(modelIds.has(item.modelId), `${item.id} model ${item.modelId}`).toBe(true);
    }
  });
});

describe('key bindings', () => {
  it('uses hotbar_layout Digit1..8 defaults and keeps E as Interact (next slot moves to R)', () => {
    expect(DEFAULT_HOTBAR.map((s) => s.keyCode)).toEqual(['Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5', 'Digit6', 'Digit7', 'Digit8']);
    expect(DEFAULT_HOTBAR.map((s) => s.itemId)).toEqual(['batarang', 'grapple', 'scanner', 'drone', 'smoke', 'shield', 'phantom_sidearm', 'crimson_carbine']);
    expect(hotbarLayout.input.KeyE).toBe('next_slot'); // the pack suggested E...
    expect(DEFAULT_BINDINGS.interact).toBe('KeyE'); // ...but E stays Interact
    expect(DEFAULT_BINDINGS.slotNext).toBe('KeyR');
    expect(DEFAULT_BINDINGS.inventory).toBe('Tab');
    expect(DEFAULT_BINDINGS.map).toBe('KeyM');
  });

  it('has no duplicate default bindings', () => {
    const codes = Object.values(DEFAULT_BINDINGS);
    expect(new Set(codes).size).toBe(codes.length);
  });

  it('detects conflicts and swaps on rebind so nothing is left unbound', () => {
    const b = new Bindings();
    expect(b.conflicts('slotNext', 'KeyE')).toEqual(['interact']);
    expect(b.rebind('slotNext', 'KeyE')).toBe('interact');
    expect(b.get('slotNext')).toBe('KeyE');
    expect(b.get('interact')).toBe('KeyR');
    expect(b.overrides()).toEqual({ slotNext: 'KeyE', interact: 'KeyR' });
    b.reset();
    expect(b.overrides()).toEqual({});
  });

  it('refuses to rebind fixed actions and ignores junk overrides', () => {
    const b = new Bindings({ pause: 'KeyP', notAnAction: 'KeyX', jump: 42 as unknown as string });
    expect(b.get('jump')).toBe('Space');
    expect(b.rebind('pause', 'KeyP')).toBeNull();
    expect(b.get('pause')).toBe('Escape');
    expect(ACTIONS.find((a) => a.id === 'pause')?.fixed).toBe(true);
  });

  it('treats text fields as typing targets', () => {
    expect(isTypingTarget({ tagName: 'INPUT' } as Element)).toBe(true);
    expect(isTypingTarget({ tagName: 'TEXTAREA' } as Element)).toBe(true);
    expect(isTypingTarget({ tagName: 'CANVAS', isContentEditable: false } as unknown as Element)).toBe(false);
    expect(isTypingTarget(null)).toBe(false);
  });
});

describe('inventory / hotbar sync', () => {
  it('selecting a slot changes the selected item and never consumes it', () => {
    const inv = new InventoryService();
    const before = inv.quantity('batarang');
    expect(inv.selectSlot(1)).toBeNull();
    expect(inv.selectedItemId).toBe('grapple');
    expect(inv.selectSlot(0)).toBeNull();
    expect(inv.selectedItemId).toBe('batarang');
    expect(inv.quantity('batarang')).toBe(before);
  });

  it('gives feedback (not an exception) for empty or exhausted slots', () => {
    const inv = new InventoryService();
    inv.assign(null, 2);
    expect(inv.selectSlot(2)).toMatch(/empty/);
    inv.state.owned.smoke.quantity = 0;
    expect(inv.selectSlot(4)).toMatch(/none left/);
    expect(inv.selectSlot(99)).toBe('No such slot');
  });

  it('assigning moves an item between slots and notifies listeners', () => {
    const inv = new InventoryService();
    let changes = 0;
    inv.onChange(() => changes++);
    expect(inv.assign('batarang', 5)).toBeNull();
    expect(inv.slot(5)?.itemId).toBe('batarang');
    expect(inv.slot(0)?.itemId).toBeNull(); // an item lives in one slot
    expect(changes).toBeGreaterThan(0);
    expect(inv.assign('crx1_interceptor', 1)).toMatch(/cannot be placed/);
    expect(inv.assign('nope', 1)).toBe('Unknown item');
  });

  it('cycles past empty slots', () => {
    const inv = new InventoryService();
    inv.assign(null, 1);
    inv.selectSlot(0);
    inv.cycle(1);
    expect(inv.state.selectedSlot).toBe(2);
    inv.cycle(-1);
    expect(inv.state.selectedSlot).toBe(0);
  });

  it('runs cooldowns and restocks from real timestamps', () => {
    const inv = new InventoryService();
    inv.startCooldown('batarang', 1000);
    expect(inv.cooldownRemaining('batarang', 1100)).toBe(itemById.get('batarang')!.cooldownMs! - 100);
    expect(inv.cooldownFraction('batarang', 1000)).toBe(1);
    expect(inv.consume('batarang')).toBe(true);
    const q = inv.quantity('batarang');
    inv.tick(0); // schedules restock
    inv.tick(itemById.get('batarang')!.restockMs! + 1);
    expect(inv.quantity('batarang')).toBe(q + 1);
  });

  it('load() drops removed item ids and clamps quantities', () => {
    const inv = new InventoryService();
    inv.load({
      owned: { batarang: { itemId: 'batarang', quantity: 999 }, removed_item: { itemId: 'removed_item', quantity: 3 } },
      hotbar: [{ index: 0, itemId: 'removed_item', keyCode: 'Digit1' }, { index: 1, itemId: 'cloak', keyCode: 'Digit2' }],
      selectedSlot: 1,
    });
    expect(inv.quantity('batarang')).toBe(itemById.get('batarang')!.maxStack);
    expect(inv.state.owned.removed_item).toBeUndefined();
    expect(inv.slot(0)?.itemId).toBeNull();
    expect(inv.slot(1)?.itemId).toBe('cloak');
    expect(inv.selectedItemId).toBe('cloak');
  });
});

describe('save service', () => {
  const memory = () => {
    const m = new Map<string, string>();
    return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) };
  };

  it('round-trips a versioned save', () => {
    const s = new SaveService(memory());
    const inv = new InventoryService();
    inv.assign('cloak', 7);
    s.write({ inventory: inv.snapshot(), bindings: { slotNext: 'KeyT' }, settings: DEFAULT_SETTINGS, quickVehicle: 'crb1_batcycle' });
    const back = s.read()!;
    expect(back.version).toBe(SAVE_VERSION);
    expect(back.inventory.hotbar[7].itemId).toBe('cloak');
    expect(back.quickVehicle).toBe('crb1_batcycle');
    expect(s.readSettings().bindings).toEqual({ slotNext: 'KeyT' });
  });

  it('rejects corrupt and future-version saves, and sanitises settings', () => {
    expect(SaveService.migrate('garbage')).toBeNull();
    expect(SaveService.migrate({ version: SAVE_VERSION + 1 })).toBeNull();
    const m = SaveService.migrate({ version: 1, settings: { uiScale: 9, quality: 'ultra', volumes: { master: -3 } }, quickVehicle: 'batarang' })!;
    expect(m.settings.uiScale).toBe(1.5);
    expect(m.settings.quality).toBe('high');
    expect(m.settings.volumes.master).toBe(0);
    expect(m.quickVehicle).toBeUndefined(); // not a vehicle
  });
});
