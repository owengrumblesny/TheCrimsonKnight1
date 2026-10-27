import { controlsConfig } from '../data/registry';

export type Action =
  | 'moveForward' | 'moveBack' | 'moveLeft' | 'moveRight' | 'sprint' | 'jump' | 'interact'
  | 'summonMenu' | 'gadgetMenu' | 'grapple' | 'crouch' | 'walkToggle' | 'sandboxMenu' | 'pause';

/** Keyboard (bindings from config/controls.json), pointer-lock mouse look and a standard gamepad. */
export class Input {
  private down = new Set<string>();
  private pressed = new Set<string>();
  lookX = 0;
  lookY = 0;
  moveX = 0;
  moveY = 0;
  private padButtons: boolean[] = [];

  constructor(canvas: HTMLElement) {
    addEventListener('keydown', (e) => {
      if (!this.down.has(e.code)) this.pressed.add(e.code);
      this.down.add(e.code);
      if (['Space', 'Tab', 'Backquote'].includes(e.code)) e.preventDefault();
    });
    addEventListener('keyup', (e) => this.down.delete(e.code));
    addEventListener('blur', () => this.down.clear());
    canvas.addEventListener('click', () => canvas.requestPointerLock?.());
    addEventListener('mousemove', (e) => {
      if (document.pointerLockElement === canvas) {
        this.lookX += e.movementX;
        this.lookY += e.movementY;
      }
    });
    addEventListener('mousedown', (e) => this.pressed.add('Mouse' + e.button));
  }

  private code(action: Action): string {
    return controlsConfig[action] ?? '';
  }

  held(action: Action): boolean {
    return this.down.has(this.code(action)) || this.padHeld(action);
  }

  /** True once per key press. */
  hit(action: Action): boolean {
    return this.pressed.has(this.code(action)) || this.padHit(action);
  }

  /** True once per press of a raw key code (e.g. 'Digit1'). */
  hitCode(code: string): boolean {
    return this.pressed.has(code);
  }

  private static PAD: Partial<Record<Action, number>> = {
    jump: 0, crouch: 1, interact: 2, gadgetMenu: 3, grapple: 6, sprint: 7, summonMenu: 12, pause: 9, sandboxMenu: 8,
  };
  private padNow: boolean[] = [];

  private padHeld(action: Action): boolean {
    const b = Input.PAD[action];
    return b !== undefined && !!this.padNow[b];
  }

  private padHit(action: Action): boolean {
    const b = Input.PAD[action];
    return b !== undefined && !!this.padNow[b] && !this.padButtons[b];
  }

  /** Call once per rendered frame before reading input. */
  poll(): void {
    const pad = navigator.getGamepads?.().find((p) => p);
    this.padButtons = this.padNow;
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

  /** Call at the end of each rendered frame. */
  endFrame(): void {
    this.pressed.clear();
    this.lookX = 0;
    this.lookY = 0;
  }
}
