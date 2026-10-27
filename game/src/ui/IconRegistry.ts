import iconManifest from './data/icon_manifest.json';

/** One entry of CRIMSON_KNIGHT_UI_PACK/config/icon_manifest.json (installed at public/ui/). */
export interface IconEntry {
  id: string;
  category: string;
  displayName: string;
  glyphPNG: string;
  circlePNG?: string;
  glyphSVG?: string;
  circleSVG?: string;
  ready: boolean;
}

export type IconRole = 'circle' | 'glyph' | 'glyphSVG';

const entries = iconManifest.icons as IconEntry[];
const byId = new Map(entries.map((e) => [e.id, e]));

/** Fallback when an id is missing: the neutral notification glyph (never crash the UI). */
const UNKNOWN_ID = 'notification';

/** Builds a URL for a manifest-relative path, honouring Vite's BASE_URL (works under a sub-path or file://). */
export function uiUrl(relativePath: string): string {
  return `${import.meta.env.BASE_URL}ui/${relativePath.replace(/^\/+/, '')}`;
}

export const IconRegistry = {
  all(): IconEntry[] {
    return entries;
  },

  has(id: string): boolean {
    return byId.has(id);
  },

  get(id: string): IconEntry {
    return byId.get(id) ?? byId.get(UNKNOWN_ID)!;
  },

  /**
   * circle = framed circular PNG (hotbar slots only), glyph = transparent symbol for cards/menus,
   * glyphSVG = crisp vector glyph. Falls back to the glyph PNG when a role is not available.
   */
  url(id: string, role: IconRole = 'glyph'): string {
    const e = this.get(id);
    const path = role === 'circle' ? e.circlePNG ?? e.glyphPNG : role === 'glyphSVG' ? e.glyphSVG ?? e.glyphPNG : e.glyphPNG;
    return uiUrl(path);
  },

  /** Keycap image for a KeyboardEvent.code (Digit1, KeyQ, Tab...), or null when the pack has none. */
  keycap(code: string): string | null {
    const map: Record<string, string> = {
      Tab: 'key_tab', ShiftLeft: 'key_shift', ShiftRight: 'key_shift', Space: 'key_space', Escape: 'key_esc',
      ControlLeft: 'key_ctrl', ControlRight: 'key_ctrl', Mouse0: 'key_mouse1', Mouse2: 'key_mouse2',
    };
    const id = map[code] ?? (/^Digit\d$/.test(code) ? `key_${code.slice(5)}` : /^Key[A-Z]$/.test(code) ? `key_${code.slice(3).toLowerCase()}` : '');
    return byId.has(id) ? uiUrl(byId.get(id)!.glyphPNG) : null;
  },
};

/** Short human label for a key code: Digit1 -> 1, KeyQ -> Q, Mouse0 -> LMB. */
export function keyLabel(code: string): string {
  if (/^Digit\d$/.test(code)) return code.slice(5);
  if (/^Key[A-Z]$/.test(code)) return code.slice(3);
  const names: Record<string, string> = {
    Space: 'Space', Tab: 'Tab', Escape: 'Esc', ShiftLeft: 'Shift', ShiftRight: 'R-Shift', ControlLeft: 'Ctrl', CapsLock: 'Caps',
    Backquote: '`', Mouse0: 'LMB', Mouse1: 'MMB', Mouse2: 'RMB', WheelUp: 'Wheel ↑', WheelDown: 'Wheel ↓',
  };
  return names[code] ?? code;
}
