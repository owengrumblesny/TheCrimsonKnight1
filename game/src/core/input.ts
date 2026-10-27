import { type ActionId, type Bindings, isTypingTarget } from '../ui/inputBindings';

export type { ActionId as Action };

/** requestPointerLock returns a promise in modern browsers that rejects in some contexts; never let that throw. */
export function lockPointer(el: HTMLElement): void {
  try {
    const p = el.requestPointerLock?.() as unknown as Promise<void> | undefined;
    p?.catch?.(() => undefined);
  } catch {
    /* pointer lock unavailable (embedded view, no gesture) */
  }
}

/** Gamepad (standard mapping) button -> action. */
const PAD: Partial<Record<ActionId, number>> = {
  jump: 0, crouch: 1, interact: 2, inventory: 3, slotPrev: 4, slotNext: 5, grapple: 6, primaryAction: 7,
  map: 8, pause: 9, sprint: 10, summonMenu: 12,
};

/**
 * Keyboard (KeyboardEvent.code, from the shared Bindings table), pointer-lock mouse look, mouse
 * buttons/wheel and a standard gamepad. One-shot actions ignore key auto-repeat. Keys typed into
 * text fields never reach gameplay.
 */
export class Input {
  private down = new Set<string>();
  private pressed = new Set<string>();
  lookX = 0;
  lookY = 0;
  moveX = 0;
  moveY = 0;
  wheel = 0;
  /** While set (key rebinding), the next key goes to this callback instead of the game. */
  capture: ((code: string) => void) | null = null;
  private padPrev: boolean[] = [];
  private padNow: boolean[] = [];
  private static installed = false;

  constructor(private canvas: HTMLElement, private bindings: Bindings) {
    if (Input.installed) throw new Error('Input already installed'); // never double-subscribe listeners
    Input.installed = true;
    addEventListener('keydown', (e) => {
      if (this.capture) {
        e.preventDefault();
        const cb = this.capture;
        this.capture = null;
        cb(e.code);
        return;
      }
      if (isTypingTarget(document.activeElement)) return;
      if (!e.repeat) this.pressed.add(e.code);
      this.down.add(e.code);
      // only swallow keys the game owns (Tab would move focus, Space would scroll)
      if (['Space', 'Tab', 'Backquote'].includes(e.code) || this.bindings.actionFor(e.code)) e.preventDefault();
    });
    addEventListener('keyup', (e) => this.down.delete(e.code));
    addEventListener('blur', () => this.down.clear());
    canvas.addEventListener('mousedown', (e) => {
      if (this.locked) {
        this.pressed.add('Mouse' + e.button);
        this.down.add('Mouse' + e.button);
      } else lockPointer(canvas); // first click only captures the mouse
    });
    addEventListener('mouseup', (e) => this.down.delete('Mouse' + e.button));
    addEventListener('mousemove', (e) => {
      if (this.locked) {
        this.lookX += e.movementX;
        this.lookY += e.movementY;
      }
    });
    canvas.addEventListener('wheel', (e) => {
      if (this.locked) this.wheel += Math.sign(e.deltaY);
    }, { passive: true });
  }

  get locked(): boolean {
    return document.pointerLockElement === this.canvas;
  }

  held(action: ActionId): boolean {
    return this.down.has(this.bindings.get(action)) || this.padHeld(action);
  }

  /** True once per physical press (auto-repeat ignored). */
  hit(action: ActionId): boolean {
    return this.pressed.has(this.bindings.get(action)) || this.padHit(action);
  }

  private padHeld(action: ActionId): boolean {
    const b = PAD[action];
    return b !== undefined && !!this.padNow[b];
  }

  private padHit(action: ActionId): boolean {
    const b = PAD[action];
    return b !== undefined && !!this.padNow[b] && !this.padPrev[b];
  }

  get gamepadConnected(): boolean {
    return !!navigator.getGamepads?.().some((p) => p);
  }

  /** Call once per rendered frame before reading input. */
  poll(): void {
    const pad = navigator.getGamepads?.().find((p) => p);
    this.padPrev = this.padNow;
    this.padNow = pad ? pad.buttons.map((b) => b.pressed) : [];
    let mx = (this.held('moveRight') ? 1 : 0) - (this.held('moveLeft') ? 1 : 0);
    let my = (this.held('moveForward') ? 1 : 0) - (this.held('moveBack') ? 1 : 0);
    if (pad) {
      const dz = (v: number) => (Math.abs(v) < 0.15 ? 0 : v);
      mx += dz(pad.axes[0] ?? 0);
      my -= dz(pad.axes[1] ?? 0);
      this.lookX += dz(pad.axes[2] ?? 0) * 14;
      this.lookY += dz(pad.axes[3] ?? 0) * 10;
    }
    const len = Math.hypot(mx, my);
    this.moveX = len > 1 ? mx / len : mx;
    this.moveY = len > 1 ? my / len : my;
  }

  /** Drop held/pressed gameplay keys (e.g. when a menu opens) so nothing sticks. */
  clear(): void {
    this.down.clear();
    this.pressed.clear();
  }

  /** Call at the end of each rendered frame. */
  endFrame(): void {
    this.pressed.clear();
    this.lookX = 0;
    this.lookY = 0;
    this.wheel = 0;
  }
}
