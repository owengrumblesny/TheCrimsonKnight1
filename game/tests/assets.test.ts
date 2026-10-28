import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import manifest from '../../config/asset_manifest.json';
import gearConfig from '../../config/gadget_assets.json';
import npcConfig from '../../config/npc_assets.json';
import { ITEMS } from '../src/ui/inventoryData';

const ROOT = path.resolve(__dirname, '../..');
const byId = new Map(manifest.assets.map((a) => [a.id, a]));

describe('3D asset library links', () => {
  it('every gadget / fictional-weapon item links to a built gear_<itemId> model', () => {
    const gear = ITEMS.filter((i) => i.category === 'gadget' || i.category === 'fictional_weapon');
    expect(gear.length).toBe(18);
    for (const item of gear) {
      expect(item.modelId).toBe(`gear_${item.id}`);
      const entry = byId.get(item.modelId!);
      expect(entry, item.id).toBeDefined();
      expect(fs.existsSync(path.join(ROOT, entry!.file)), entry!.file).toBe(true);
    }
  });

  it('every gear model declares a socket and its clips', () => {
    for (const g of gearConfig.gear) {
      expect(['Socket_Hand_R', 'Socket_Hand_L', 'Socket_Belt_R', 'Socket_Belt_L', 'Socket_Back', 'ground']).toContain(g.attach);
      expect(g.clips.length).toBeGreaterThan(0);
    }
  });

  it('every item modelId resolves in the asset manifest', () => {
    for (const item of ITEMS) if (item.modelId && !/^CR[XBA]1_/.test(item.modelId)) expect(byId.has(item.modelId), item.modelId).toBe(true);
  });

  it('NPC families are registered, on disk, within the crowd budget, and share the clip set', () => {
    expect(npcConfig.npcs.length).toBe(15);
    for (const n of npcConfig.npcs) {
      const entry = byId.get(n.id);
      expect(entry, n.id).toBeDefined();
      expect(fs.existsSync(path.join(ROOT, n.file))).toBe(true);
      expect(n.triangles).toBeLessThan(4000);
      if (n.id !== 'npc_patrol_drone') expect(n.clips).toEqual(['NPC_Idle', 'NPC_Walk', 'NPC_Alert', 'NPC_Cower', 'NPC_Talk']);
    }
  });
});
