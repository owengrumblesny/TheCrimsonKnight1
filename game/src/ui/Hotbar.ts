import { IconRegistry, keyLabel } from './IconRegistry';
import { type Bindings, SLOT_ACTIONS } from './inputBindings';
import type { InventoryService } from './uiState';

/**
 * Bottom-center 8-slot hotbar. Rendered from InventoryService state (never hand-written markup);
 * key labels come from the live Bindings, so rebinding updates the bar. Selecting never uses an item.
 */
export class Hotbar {
  readonly el: HTMLElement;
  private slots: HTMLButtonElement[] = [];
  private cds: HTMLDivElement[] = [];

  constructor(
    private inventory: InventoryService,
    private bindings: Bindings,
    private onSelect: (index: number) => void,
  ) {
    this.el = document.createElement('nav');
    this.el.className = 'ck-hotbar ck-ui ck-hud-widget';
    this.el.setAttribute('aria-label', 'Equipment quick access');
    for (let i = 0; i < 8; i++) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'ck-slot';
      b.addEventListener('click', () => this.onSelect(i));
      // keep keyboard focus off the slot after a click so Space/digits keep going to the game
      b.addEventListener('mouseup', () => b.blur());
      const cd = document.createElement('div');
      cd.className = 'ck-cd';
      this.slots.push(b);
      this.cds.push(cd);
      this.el.appendChild(b);
    }
    inventory.onChange(() => this.render());
    bindings.onChange(() => this.render());
    this.render();
  }

  render(): void {
    const sel = this.inventory.state.selectedSlot;
    this.inventory.state.hotbar.forEach((slot, i) => {
      const b = this.slots[i];
      const key = keyLabel(this.bindings.get(SLOT_ACTIONS[i]));
      const def = slot.itemId ? this.inventory.def(slot.itemId) : undefined;
      const qty = def ? this.inventory.quantity(def.id) : 0;
      const name = def?.displayName ?? 'Empty';
      b.setAttribute('aria-pressed', String(i === sel && !!def));
      b.setAttribute('aria-label', `Slot ${i + 1}: ${name}`);
      b.classList.toggle('ck-empty', !def);
      b.classList.toggle('ck-unusable', !!def?.unavailableReason);
      b.classList.toggle('ck-out', !!def && qty === 0);
      const status = !def ? 'Assign an item from the inventory (Tab)'
        : def.unavailableReason ? def.unavailableReason
        : qty === 0 ? 'None left — restocks over time'
        : `Use: ${keyLabel(this.bindings.get('primaryAction'))}${def.energyCost ? ` · ${def.energyCost} energy` : ''}`;
      b.innerHTML = `<span class="ck-key">${key}</span>` +
        `<img alt="" src="${def ? IconRegistry.url(def.iconId, 'circle') : IconRegistry.url('key_prompt', 'glyph')}">` +
        (def?.stackable ? `<span class="ck-qty">${qty}</span>` : '') +
        (def?.unavailableReason ? '<span class="ck-badge">N/A</span>' : '') +
        `<span class="ck-tip">${name}<small>${status}</small></span>`;
      b.appendChild(this.cds[i]);
    });
  }

  /** Brief 100 ms highlight when a slot's key is pressed. */
  flash(i: number): void {
    const b = this.slots[i];
    b.classList.add('ck-flash');
    setTimeout(() => b.classList.remove('ck-flash'), 100);
  }

  /** Per-frame cooldown rings, driven by the inventory's real cooldown timestamps. */
  update(now: number): void {
    this.inventory.state.hotbar.forEach((slot, i) => {
      const f = slot.itemId ? this.inventory.cooldownFraction(slot.itemId, now) : 0;
      const cd = this.cds[i];
      cd.style.background = f > 0 ? `conic-gradient(rgba(10,8,12,.72) ${f * 360}deg, transparent 0)` : '';
    });
  }
}
