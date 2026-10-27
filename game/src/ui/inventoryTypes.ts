export type Category = 'gadget' | 'fictional_weapon' | 'vehicle' | 'tool' | 'quest_item';
export type ItemId = string;

/**
 * Static catalog record. itemId, iconId, modelId and animation names are linked explicitly so the
 * hotbar, inventory, HUD and gameplay never rely on matching strings by accident.
 */
export interface ItemDefinition {
  id: ItemId;
  displayName: string;
  category: Category;
  /** id in src/ui/data/icon_manifest.json */
  iconId: string;
  /** optional board image (config/image_catalog.json) shown in the detail panel */
  artId?: string;
  /** optional 3D model id in config/asset_manifest.json */
  modelId?: string;
  /** hero clip played on use */
  useClip?: string;
  stackable: boolean;
  maxStack: number;
  description: string;
  canEquip: boolean;
  cooldownMs?: number;
  energyCost?: number;
  /** consumables restock one unit every N ms up to maxStack (no shop, no microtransactions) */
  restockMs?: number;
  /** null when the item's in-game effect is implemented; otherwise the honest reason it can't be used yet */
  unavailableReason?: string;
}

export interface OwnedStack {
  itemId: ItemId;
  quantity: number;
  isNew?: boolean;
}

export interface HotbarSlot {
  index: number;
  itemId: ItemId | null;
  keyCode: string;
}

export interface InventoryState {
  owned: Record<ItemId, OwnedStack>;
  hotbar: HotbarSlot[];
  selectedSlot: number;
}
