import { registry } from '../data/registry';
import { IconRegistry } from './IconRegistry';
import { CATEGORY_LABEL, CATEGORY_ORDER, ITEMS } from './inventoryData';
import type { Category, ItemDefinition } from './inventoryTypes';
import type { InventoryService } from './uiState';

const TAB_ICON: Record<Category, string> = {
  gadget: 'batarang', fictional_weapon: 'crimson_carbine', vehicle: 'interceptor', tool: 'repair', quest_item: 'keycard',
};

export interface InventoryHooks {
  notify: (text: string, icon?: string, kind?: 'info' | 'warn') => void;
  click: () => void;
  selectSlot: (index: number) => void;
  quickVehicle: () => string;
  setQuickVehicle: (id: string) => void;
}

/**
 * Inventory screen: category tabs (default Gadgets), search / sort, glyph cards (no double circles),
 * detail panel with Equip and Assign-to-slot 1–8. Reads and writes InventoryService only.
 */
export class InventoryPanel {
  readonly el: HTMLElement;
  private tab: Category = 'gadget';
  private selected: string | null = null;
  private query = '';
  private sort: 'name' | 'status' = 'name';
  private grid!: HTMLElement;
  private detail!: HTMLElement;
  private off: () => void;

  constructor(private inv: InventoryService, private hooks: InventoryHooks) {
    this.el = document.createElement('div');
    this.el.innerHTML = `
      <div class="ck-tabs" role="tablist" aria-label="Inventory categories"></div>
      <div class="ck-toolbar">
        <input class="ck-input" type="search" placeholder="Search items…" aria-label="Search items">
        <select class="ck-select" aria-label="Sort items"><option value="name">Sort: name</option><option value="status">Sort: usable first</option></select>
        <span style="margin-left:auto;color:var(--ck-muted);font-size:12px">Select an item, then Assign to slot (or press 1–8)</span>
      </div>
      <div class="ck-inv"><div class="ck-grid" role="listbox" aria-label="Items"></div><aside class="ck-detail" aria-live="polite"></aside></div>`;
    const tabs = this.el.querySelector('.ck-tabs')!;
    for (const c of CATEGORY_ORDER) {
      const t = document.createElement('button');
      t.className = 'ck-tab';
      t.type = 'button';
      t.setAttribute('role', 'tab');
      t.dataset.cat = c;
      t.innerHTML = `<img alt="" src="${IconRegistry.url(TAB_ICON[c])}">${CATEGORY_LABEL[c]}`;
      t.addEventListener('click', () => this.setTab(c));
      tabs.appendChild(t);
    }
    const search = this.el.querySelector<HTMLInputElement>('input')!;
    search.addEventListener('input', () => {
      this.query = search.value.trim().toLowerCase();
      this.renderGrid();
    });
    const sortSel = this.el.querySelector<HTMLSelectElement>('select')!;
    sortSel.addEventListener('change', () => {
      this.sort = sortSel.value as 'name' | 'status';
      this.renderGrid();
    });
    this.grid = this.el.querySelector('.ck-grid')!;
    this.detail = this.el.querySelector('.ck-detail')!;
    this.grid.addEventListener('keydown', (e) => this.gridKeys(e));
    this.el.addEventListener('keydown', (e) => {
      // 1–8 assigns the selected item (only when focus is not in the search box)
      if (/^Digit[1-8]$/.test(e.code) && (e.target as HTMLElement).tagName !== 'INPUT' && this.selected) {
        e.preventDefault();
        this.assign(Number(e.code.slice(5)) - 1);
      }
    });
    this.off = inv.onChange(() => this.render());
    this.setTab('gadget');
  }

  dispose(): void {
    this.off();
  }

  focusFirst(): void {
    (this.grid.querySelector('.ck-card') as HTMLElement | null)?.focus();
  }

  private setTab(c: Category): void {
    this.tab = c;
    for (const t of this.el.querySelectorAll<HTMLElement>('.ck-tab')) t.setAttribute('aria-selected', String(t.dataset.cat === c));
    const items = this.items();
    this.selected = items[0]?.id ?? null;
    this.render();
  }

  private items(): ItemDefinition[] {
    let list = ITEMS.filter((i) => i.category === this.tab);
    if (this.query) list = ITEMS.filter((i) => `${i.displayName} ${i.description}`.toLowerCase().includes(this.query));
    return [...list].sort((a, b) => this.sort === 'status'
      ? Number(!!a.unavailableReason) - Number(!!b.unavailableReason) || a.displayName.localeCompare(b.displayName)
      : a.displayName.localeCompare(b.displayName));
  }

  private render(): void {
    this.renderGrid();
    this.renderDetail();
  }

  private slotOf(id: string): number {
    return this.inv.state.hotbar.findIndex((s) => s.itemId === id);
  }

  private renderGrid(): void {
    const items = this.items();
    const focusedId = (document.activeElement as HTMLElement | null)?.dataset?.id;
    this.grid.innerHTML = '';
    if (!items.length) this.grid.innerHTML = '<p style="color:var(--ck-muted)">No items match.</p>';
    for (const d of items) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'ck-card' + (d.id === this.selected ? ' sel' : '') + (d.unavailableReason ? ' na' : '');
      b.dataset.id = d.id;
      b.setAttribute('role', 'option');
      b.setAttribute('aria-selected', String(d.id === this.selected));
      const slot = this.slotOf(d.id);
      const status = d.category === 'vehicle' ? (d.unavailableReason ? 'Blueprint · unavailable' : 'Summonable')
        : d.stackable ? `×${this.inv.quantity(d.id)}` : d.unavailableReason ? 'Not usable yet' : 'Ready';
      b.innerHTML = (slot >= 0 ? `<span class="slotno">${slot + 1}</span>` : '') + (this.inv.state.owned[d.id]?.isNew ? '<span class="dot"></span>' : '') +
        `<img alt="" src="${IconRegistry.url(d.iconId)}"><span class="t"></span><span class="s">${status}</span>`;
      b.querySelector('.t')!.textContent = d.displayName;
      b.title = d.unavailableReason ?? d.description;
      b.addEventListener('click', () => {
        this.selected = d.id;
        this.hooks.click();
        this.render();
        (this.grid.querySelector(`[data-id="${d.id}"]`) as HTMLElement | null)?.focus();
      });
      this.grid.appendChild(b);
    }
    if (focusedId) (this.grid.querySelector(`[data-id="${focusedId}"]`) as HTMLElement | null)?.focus();
  }

  private renderDetail(): void {
    const d = this.selected ? this.inv.def(this.selected) : undefined;
    if (!d) {
      this.detail.innerHTML = '<p style="color:var(--ck-muted)">Select an item.</p>';
      return;
    }
    const slot = this.slotOf(d.id);
    const meta = [
      CATEGORY_LABEL[d.category],
      d.stackable ? `${this.inv.quantity(d.id)} / ${d.maxStack}` : '',
      d.cooldownMs ? `${(d.cooldownMs / 1000).toFixed(1)} s cooldown` : '',
      d.energyCost ? `${d.energyCost} energy` : '',
      d.restockMs ? `restocks every ${Math.round(d.restockMs / 1000)} s` : '',
    ].filter(Boolean).join(' · ');
    this.detail.innerHTML = `
      <div class="big"><img alt="" src="${IconRegistry.url(d.iconId, 'glyphSVG')}"><div><h3></h3><div class="meta">${meta}</div></div></div>
      ${d.artId ? `<img class="art" alt="" src="${registry.imageUrl(d.artId)}">` : ''}
      <p class="desc"></p>
      ${d.unavailableReason ? `<p class="why">⚠ ${d.unavailableReason}</p>` : ''}
      <div class="actions"></div>`;
    this.detail.querySelector('h3')!.textContent = d.displayName;
    this.detail.querySelector('.desc')!.textContent = d.description;
    const actions = this.detail.querySelector('.actions')!;
    if (d.category === 'vehicle') {
      const quick = this.hooks.quickVehicle() === d.id;
      actions.innerHTML = `<button class="ck-btn" type="button">${quick ? '✓ Quick-call vehicle' : 'Set as quick-call vehicle'}</button>`;
      actions.querySelector('button')!.addEventListener('click', () => {
        this.hooks.setQuickVehicle(d.id);
        this.hooks.notify(`${d.displayName} set as quick-call vehicle`, d.iconId);
        this.renderDetail();
      });
      return;
    }
    if (!d.canEquip) {
      actions.innerHTML = `<p class="meta">${d.category === 'quest_item' ? 'Key item — kept in your inventory.' : 'Always equipped.'}</p>`;
      return;
    }
    actions.innerHTML = `
      <div style="display:flex;gap:8px;margin-bottom:10px">
        <button class="ck-btn primary eq" type="button">${slot >= 0 ? `Select (slot ${slot + 1})` : 'Equip'}</button>
        ${slot >= 0 ? '<button class="ck-btn ghost rm" type="button">Remove from hotbar</button>' : ''}
      </div>
      <div class="meta" style="margin-bottom:4px">Assign to slot</div>
      <div class="ck-assign">${[1, 2, 3, 4, 5, 6, 7, 8].map((n) => `<button class="ck-btn" type="button" data-n="${n - 1}" aria-label="Assign to slot ${n}">${n}</button>`).join('')}</div>`;
    actions.querySelector('.eq')!.addEventListener('click', () => {
      // equip = keep its slot, or take the selected slot, then select it
      const target = slot >= 0 ? slot : this.inv.state.selectedSlot;
      if (slot < 0) this.assign(target);
      this.hooks.selectSlot(target);
    });
    actions.querySelector('.rm')?.addEventListener('click', () => {
      this.inv.assign(null, slot);
      this.hooks.notify(`${d.displayName} removed from slot ${slot + 1}`, d.iconId);
    });
    for (const b of actions.querySelectorAll<HTMLButtonElement>('[data-n]')) {
      if (Number(b.dataset.n) === slot) b.classList.add('primary');
      b.addEventListener('click', () => this.assign(Number(b.dataset.n)));
    }
  }

  private assign(index: number): void {
    if (!this.selected) return;
    const d = this.inv.def(this.selected)!;
    const err = this.inv.assign(this.selected, index);
    if (err) this.hooks.notify(err, d.iconId, 'warn');
    else {
      this.hooks.click();
      this.hooks.notify(`${d.displayName} assigned to slot ${index + 1}`, d.iconId);
    }
  }

  /** Arrow-key navigation across the card grid. */
  private gridKeys(e: KeyboardEvent): void {
    const cards = [...this.grid.querySelectorAll<HTMLElement>('.ck-card')];
    const i = cards.indexOf(document.activeElement as HTMLElement);
    if (i < 0) return;
    const cols = Math.max(1, Math.round(this.grid.clientWidth / (cards[0].offsetWidth + 10)));
    const step: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols };
    if (step[e.key] !== undefined) {
      e.preventDefault();
      cards[Math.min(cards.length - 1, Math.max(0, i + step[e.key]))].focus();
    }
  }
}
