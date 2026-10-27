import controlsJson from '../../../config/controls.json';
import hotbarLayout from './data/hotbar_layout.json';

/**
 * One binding table for the whole game: gameplay actions (config/controls.json), hotbar slots and
 * UI toggles (src/ui/data/hotbar_layout.json), plus the player's saved overrides.
 */
export type ActionId =
  | 'moveForward' | 'moveBack' | 'moveLeft' | 'moveRight' | 'sprint' | 'jump' | 'interact' | 'crouch' | 'walkToggle'
  | 'grapple' | 'summonMenu' | 'primaryAction' | 'secondaryAction' | 'sandboxMenu' | 'pause'
  | 'slotPrev' | 'slotNext' | 'inventory' | 'map'
  | 'slot1' | 'slot2' | 'slot3' | 'slot4' | 'slot5' | 'slot6' | 'slot7' | 'slot8';

export interface ActionInfo {
  id: ActionId;
  label: string;
  group: 'Movement' | 'Actions' | 'Hotbar' | 'Menus';
  /** not rebindable from the settings screen */
  fixed?: boolean;
}

const C = controlsJson as Record<string, string>;
const H = hotbarLayout.input as Record<string, string>;
const codeFor = (value: string) => Object.entries(H).find(([, v]) => v === value)?.[0];

/**
 * Defaults. hotbar_layout suggests Q/E for previous/next slot, but E is the game's Interact key,
 * so (as the UI directive requires) E stays Interact and next-slot moves to R. Mouse wheel also cycles.
 */
export const DEFAULT_BINDINGS: Record<ActionId, string> = {
  moveForward: C.moveForward, moveBack: C.moveBack, moveLeft: C.moveLeft, moveRight: C.moveRight,
  sprint: C.sprint, jump: C.jump, interact: C.interact, crouch: C.crouch, walkToggle: C.walkToggle,
  grapple: C.grapple, summonMenu: C.summonMenu, primaryAction: C.primaryAction, secondaryAction: C.secondaryAction,
  sandboxMenu: C.sandboxMenu, pause: C.pause,
  slotPrev: codeFor('previous_slot') ?? 'KeyQ',
  slotNext: 'KeyR',
  inventory: codeFor('toggle_inventory') ?? 'Tab',
  map: codeFor('toggle_map') ?? 'KeyM',
  slot1: 'Digit1', slot2: 'Digit2', slot3: 'Digit3', slot4: 'Digit4', slot5: 'Digit5', slot6: 'Digit6', slot7: 'Digit7', slot8: 'Digit8',
};

export const ACTIONS: ActionInfo[] = [
  { id: 'moveForward', label: 'Move forward', group: 'Movement' }, { id: 'moveBack', label: 'Move back', group: 'Movement' },
  { id: 'moveLeft', label: 'Move left', group: 'Movement' }, { id: 'moveRight', label: 'Move right', group: 'Movement' },
  { id: 'sprint', label: 'Sprint', group: 'Movement' }, { id: 'jump', label: 'Jump / glide (hold in air)', group: 'Movement' },
  { id: 'crouch', label: 'Crouch', group: 'Movement' }, { id: 'walkToggle', label: 'Walk / run toggle', group: 'Movement' },
  { id: 'primaryAction', label: 'Use selected item', group: 'Actions' }, { id: 'grapple', label: 'Aim', group: 'Actions' },
  { id: 'interact', label: 'Interact', group: 'Actions' }, { id: 'summonMenu', label: 'Call vehicle', group: 'Actions' },
  { id: 'slotPrev', label: 'Previous hotbar slot', group: 'Hotbar' }, { id: 'slotNext', label: 'Next hotbar slot', group: 'Hotbar' },
  ...([1, 2, 3, 4, 5, 6, 7, 8] as const).map((n) => ({ id: `slot${n}` as ActionId, label: `Hotbar slot ${n}`, group: 'Hotbar' as const })),
  { id: 'inventory', label: 'Inventory', group: 'Menus' }, { id: 'map', label: 'Map', group: 'Menus' },
  { id: 'pause', label: 'Pause / back', group: 'Menus', fixed: true }, { id: 'sandboxMenu', label: 'Animation debug', group: 'Menus' },
  { id: 'secondaryAction', label: 'Secondary (unused)', group: 'Actions' },
];

export const SLOT_ACTIONS: ActionId[] = ['slot1', 'slot2', 'slot3', 'slot4', 'slot5', 'slot6', 'slot7', 'slot8'];

/** Bindings = defaults + validated overrides. */
export class Bindings {
  private map: Record<ActionId, string>;
  private listeners = new Set<() => void>();

  constructor(overrides: Partial<Record<string, string>> = {}) {
    this.map = { ...DEFAULT_BINDINGS };
    for (const [k, v] of Object.entries(overrides)) {
      const fixed = ACTIONS.find((a) => a.id === k)?.fixed;
      if (k in this.map && !fixed && typeof v === 'string' && v.length < 32) this.map[k as ActionId] = v;
    }
  }

  get(action: ActionId): string {
    return this.map[action];
  }

  /** Action bound to a code, or undefined. */
  actionFor(code: string): ActionId | undefined {
    return (Object.keys(this.map) as ActionId[]).find((a) => this.map[a] === code);
  }

  /** Overrides relative to defaults (what gets saved). */
  overrides(): Record<string, string> {
    return Object.fromEntries((Object.keys(this.map) as ActionId[]).filter((a) => this.map[a] !== DEFAULT_BINDINGS[a]).map((a) => [a, this.map[a]]));
  }

  /** Other actions already using a code. */
  conflicts(action: ActionId, code: string): ActionId[] {
    return (Object.keys(this.map) as ActionId[]).filter((a) => a !== action && this.map[a] === code);
  }

  /**
   * Rebind an action. If the key is taken, the two actions swap keys so nothing is left unbound.
   * Returns the action that was swapped, if any.
   */
  rebind(action: ActionId, code: string): ActionId | null {
    if (ACTIONS.find((a) => a.id === action)?.fixed) return null;
    const clash = this.conflicts(action, code)[0] ?? null;
    if (clash) this.map[clash] = this.map[action];
    this.map[action] = code;
    this.listeners.forEach((l) => l());
    return clash;
  }

  reset(): void {
    this.map = { ...DEFAULT_BINDINGS };
    this.listeners.forEach((l) => l());
  }

  onChange(fn: () => void): void {
    this.listeners.add(fn);
  }
}

/** True when keyboard input belongs to a text field rather than the game. */
export function isTypingTarget(el: Element | null): boolean {
  if (!el) return false;
  const tag = el.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (el as HTMLElement).isContentEditable;
}
