import hotbarLayout from './data/hotbar_layout.json';
import type { Category, ItemDefinition } from './inventoryTypes';

const NOT_BUILT = 'Effect not built yet — planned for a later milestone';
const NO_COMBAT = 'Fictional prop — combat systems are not built yet';
const NO_VEHICLE = 'Drivable vehicle not built yet (milestone M5)';

/**
 * The item catalog: itemId -> iconId (UI pack) -> artId (board image) -> modelId (asset manifest) -> useClip.
 * Items without `unavailableReason` have a real in-game effect in src/systems/equipment.ts.
 */
export const ITEMS: ItemDefinition[] = [
  // ---- gadgets ----
  { id: 'batarang', displayName: 'Crimson Batarang', category: 'gadget', iconId: 'batarang', artId: 'gadgets/b_batarangs',
    modelId: 'gear_batarang', useClip: 'CK_GadgetDraw', stackable: true, maxStack: 12, canEquip: true, cooldownMs: 450, restockMs: 4000,
    description: 'Throwable crimson batarang. Flies where you aim and knocks loose objects over.' },
  { id: 'grapple', displayName: 'Grapnel Gun', category: 'gadget', iconId: 'grapple', artId: 'gadgets/b_grapple_gun',
    modelId: 'gear_grapple', useClip: 'CK_GrapplePull', stackable: false, maxStack: 1, canEquip: true, cooldownMs: 900,
    description: 'Fires a line at a surface up to 45 m away and reels the Knight in. Aim with G for precision.' },
  { id: 'scanner', displayName: 'Tactical Scanner', category: 'gadget', iconId: 'scanner', artId: 'gadgets/b_holographic',
    modelId: 'gear_scanner', useClip: 'CK_Interact', stackable: false, maxStack: 1, canEquip: true, cooldownMs: 4000, energyCost: 15,
    description: 'Pulses the area within 30 m and highlights every movable object it finds.' },
  { id: 'drone', displayName: 'Recon Drone', category: 'gadget', iconId: 'drone', artId: 'gadgets/a_recon_drone',
    modelId: 'gear_drone', useClip: 'CK_Interact', stackable: false, maxStack: 1, canEquip: true, cooldownMs: 20000, energyCost: 25,
    description: 'Launches a recon drone that orbits above the Knight for 20 seconds with a spotlight.' },
  { id: 'smoke', displayName: 'Smoke Pellet', category: 'gadget', iconId: 'smoke', artId: 'gadgets/b_smoke_pellet',
    modelId: 'gear_smoke', useClip: 'CK_GadgetDraw', stackable: true, maxStack: 6, canEquip: true, cooldownMs: 2500, restockMs: 15000,
    description: 'Bursts a dense cloud of smoke around the Knight.' },
  { id: 'shield', displayName: 'Energy Shield', category: 'gadget', iconId: 'shield', modelId: 'gear_shield', useClip: 'CK_GadgetDraw',
    stackable: false, maxStack: 1, canEquip: true, cooldownMs: 12000, energyCost: 30,
    description: 'Projects a protective dome for 6 seconds. Impact damage from falls is blocked while it is up.' },
  { id: 'cloak', displayName: 'Optical Cloak', category: 'gadget', modelId: 'gear_cloak', iconId: 'cloak', useClip: 'CK_CrouchIdle',
    stackable: false, maxStack: 1, canEquip: true, cooldownMs: 15000, energyCost: 40,
    description: 'Bends light around the CR-X9 armor for 8 seconds, rendering the Knight nearly invisible.' },
  { id: 'beacon', displayName: 'Tracking Beacon', category: 'gadget', iconId: 'beacon', modelId: 'gear_beacon', useClip: 'CK_Interact',
    stackable: true, maxStack: 3, canEquip: true, cooldownMs: 1000, restockMs: 30000,
    description: 'Plants a glowing red beacon at the Knight\'s feet. Up to three can be active.' },
  { id: 'emp', displayName: 'EMP Device', category: 'gadget', modelId: 'gear_emp', iconId: 'emp', artId: 'gadgets/b_emp_device', useClip: 'CK_GadgetDraw',
    stackable: false, maxStack: 1, canEquip: true, cooldownMs: 18000, energyCost: 35,
    description: 'Releases a pulse that knocks out street lights within 25 m for 6 seconds.' },
  { id: 'sonic', displayName: 'Sonic Emitter', category: 'gadget', modelId: 'gear_sonic', iconId: 'sonic', artId: 'gadgets/b_sonic_device', useClip: 'CK_GadgetDraw',
    stackable: false, maxStack: 1, canEquip: true, cooldownMs: 6000, energyCost: 20,
    description: 'A focused sonic burst that shoves loose objects away within 9 m.' },
  { id: 'decoy', displayName: 'Hologram Decoy', category: 'gadget', modelId: 'gear_decoy', iconId: 'decoy', stackable: true, maxStack: 2, canEquip: true,
    description: 'Projects a hologram of the Knight to draw attention.', unavailableReason: NOT_BUILT },
  { id: 'holoprojector', displayName: 'Holoprojector', category: 'gadget', iconId: 'holoprojector', modelId: 'gear_holoprojector',
    stackable: false, maxStack: 1, canEquip: true, description: 'Projects tactical holograms of the area.', unavailableReason: NOT_BUILT },
  { id: 'gauntlet', displayName: 'Wrist Gauntlet', category: 'gadget', iconId: 'gauntlet', modelId: 'gear_gauntlet',
    stackable: false, maxStack: 1, canEquip: false, description: 'CR-X9 forearm module that controls the suit\'s gadgets. Always equipped.' },

  // ---- fictional weapons (props only) ----
  { id: 'phantom_sidearm', displayName: 'Phantom Sidearm', category: 'fictional_weapon', iconId: 'phantom_sidearm', modelId: 'gear_phantom_sidearm',
    stackable: false, maxStack: 1, canEquip: true, description: 'Sci-fi energy sidearm prop.', unavailableReason: NO_COMBAT },
  { id: 'crimson_carbine', displayName: 'Crimson Carbine', category: 'fictional_weapon', iconId: 'crimson_carbine', modelId: 'gear_crimson_carbine',
    stackable: false, maxStack: 1, canEquip: true, description: 'Sci-fi energy carbine prop.', unavailableReason: NO_COMBAT },
  { id: 'energy_launcher', displayName: 'Energy Launcher', category: 'fictional_weapon', iconId: 'energy_launcher', modelId: 'gear_energy_launcher',
    stackable: false, maxStack: 1, canEquip: true, description: 'Shoulder-mounted energy launcher prop.', unavailableReason: NO_COMBAT },
  { id: 'energy_cannon', displayName: 'Energy Cannon', category: 'fictional_weapon', modelId: 'gear_energy_cannon', iconId: 'energy_cannon',
    stackable: false, maxStack: 1, canEquip: true, description: 'Heavy energy cannon prop.', unavailableReason: NO_COMBAT },
  { id: 'energy_blade', displayName: 'Energy Blade', category: 'fictional_weapon', iconId: 'blade', modelId: 'gear_energy_blade',
    stackable: false, maxStack: 1, canEquip: true, description: 'Crimson energy blade prop.', unavailableReason: NO_COMBAT },

  // ---- vehicles (summonable blueprints, not stacks of cars) ----
  { id: 'crx1_interceptor', displayName: 'CR-X1 Crimson Interceptor', category: 'vehicle', iconId: 'interceptor', artId: 'vehicles/x1_crx1_showcase',
    modelId: 'CRX1_interceptor', stackable: false, maxStack: 1, canEquip: false,
    description: 'Armored pursuit car. Pursuit, battle and stealth modes.', unavailableReason: NO_VEHICLE },
  { id: 'crb1_batcycle', displayName: 'CR-B1 Crimson Batcycle', category: 'vehicle', iconId: 'batcycle', artId: 'vehicles/b1_crb1_showcase',
    modelId: 'CRB1_batcycle', stackable: false, maxStack: 1, canEquip: false,
    description: 'Electric-turbine hybrid motorcycle with autonomous return.', unavailableReason: NO_VEHICLE },
  { id: 'cra1_specter', displayName: 'CR-A1 Crimson Specter', category: 'vehicle', iconId: 'specter', artId: 'vehicles/a1_cra1_showcase',
    modelId: 'CRA1_specter', stackable: false, maxStack: 1, canEquip: false,
    description: 'Stealth air-superiority wing with VTOL.', unavailableReason: NO_VEHICLE },

  // ---- tools ----
  { id: 'flashlight', displayName: 'Helmet Lamp', category: 'tool', iconId: 'flashlight', stackable: false, maxStack: 1, canEquip: true,
    cooldownMs: 250, description: 'Toggles a white spotlight mounted on the CR-X9 helmet.' },
  { id: 'power_cell', displayName: 'Fusion Power Cell', category: 'tool', iconId: 'power_cell', modelId: 'power_cell_v01', useClip: 'CK_Interact',
    stackable: true, maxStack: 3, canEquip: true, cooldownMs: 1500, restockMs: 45000, description: 'Restores 60 suit energy.' },
  { id: 'first_aid', displayName: 'Med Kit', category: 'tool', iconId: 'first_aid', artId: 'gadgets/b_medkit', modelId: 'medkit_v01',
    useClip: 'CK_Interact', stackable: true, maxStack: 3, canEquip: true, cooldownMs: 2000, restockMs: 60000, description: 'Restores 50 health.' },
  { id: 'repair', displayName: 'Armor Repair Kit', category: 'tool', iconId: 'repair', modelId: 'toolbox_v01', useClip: 'CK_Interact',
    stackable: true, maxStack: 2, canEquip: true, cooldownMs: 3000, restockMs: 90000, description: 'Restores 40 CR-X9 armor integrity.' },
  { id: 'photo_camera', displayName: 'Photo Camera', category: 'tool', iconId: 'camera', stackable: false, maxStack: 1, canEquip: true,
    cooldownMs: 300, description: 'Toggles photo mode: hides the HUD for clean screenshots.' },
  { id: 'comms', displayName: 'O.E. Comms Link', category: 'tool', iconId: 'comms', modelId: 'communicator_v01', stackable: false, maxStack: 1,
    canEquip: true, description: 'Owen Enterprises tactical network uplink.', unavailableReason: NOT_BUILT },
  { id: 'forensics', displayName: 'Forensics Kit', category: 'tool', iconId: 'forensics', stackable: false, maxStack: 1, canEquip: true,
    description: 'Evidence analysis toolkit.', unavailableReason: NOT_BUILT },

  // ---- quest items (no story gates) ----
  { id: 'citadel_keycard', displayName: 'Red Citadel Keycard', category: 'quest_item', iconId: 'keycard', stackable: false, maxStack: 1,
    canEquip: false, description: 'Founder-level access card for the Red Citadel. The Citadel interior is in development.' },
];

export const CATEGORY_LABEL: Record<Category, string> = {
  gadget: 'Gadgets', fictional_weapon: 'Fictional Weapons', vehicle: 'Vehicles', tool: 'Tools', quest_item: 'Quest Items',
};
export const CATEGORY_ORDER: Category[] = ['gadget', 'fictional_weapon', 'vehicle', 'tool', 'quest_item'];

/** Default hotbar from config/hotbar_layout.json: Digit1..Digit8 -> item (those ids are item ids by design). */
export const DEFAULT_HOTBAR: { keyCode: string; itemId: string }[] = Object.entries(hotbarLayout.input)
  .filter(([code]) => /^Digit[1-8]$/.test(code))
  .map(([keyCode, itemId]) => ({ keyCode, itemId }));

/** Everything the player starts with (sandbox: all items available, no gates). */
export const STARTING_OWNED: Record<string, number> = Object.fromEntries(ITEMS.map((i) => [i.id, i.maxStack]));

export const itemById = new Map(ITEMS.map((i) => [i.id, i]));
