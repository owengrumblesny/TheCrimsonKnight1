/**
 * CR-X9 suit vitals that gameplay actually uses (so the HUD never shows invented numbers):
 *  - health: lost to hard-landing impacts the armor can't absorb; slowly regenerates; 0 = suit critical -> respawn
 *  - armor:  integrity, absorbs most impact damage; restored only by repair kits
 *  - energy: spent by sprinting, gliding and powered gadgets; recharges when not exerting
 */
export class Vitals {
  health = 100;
  armor = 100;
  energy = 100;
  readonly max = 100;
  shieldUntil = 0;
  private lastHurt = -Infinity;

  /** Impact from a landing at vertical speed vy (negative = falling). Returns damage dealt to health. */
  impact(vy: number, now: number, hardSpeed: number): number {
    const excess = -vy - hardSpeed;
    if (excess <= 0 || now < this.shieldUntil) return 0;
    let dmg = excess * 7;
    const absorbed = Math.min(this.armor, dmg * 0.7);
    this.armor -= absorbed;
    dmg -= absorbed;
    this.health = Math.max(0, this.health - dmg);
    this.lastHurt = now;
    return dmg;
  }

  /** Spend energy; returns false (and spends nothing) when there isn't enough. */
  spend(amount: number): boolean {
    if (this.energy < amount) return false;
    this.energy -= amount;
    return true;
  }

  restore(kind: 'health' | 'armor' | 'energy', amount: number): number {
    const before = this[kind];
    this[kind] = Math.min(this.max, before + amount);
    return this[kind] - before;
  }

  /** dt in seconds; exertion = sprinting or gliding this frame. */
  update(dt: number, now: number, exertion: 'sprint' | 'glide' | null): void {
    if (exertion === 'sprint') this.energy = Math.max(0, this.energy - 7 * dt);
    else if (exertion === 'glide') this.energy = Math.max(0, this.energy - 5 * dt);
    else this.energy = Math.min(this.max, this.energy + 9 * dt);
    if (now - this.lastHurt > 6000 && this.health > 0) this.health = Math.min(this.max, this.health + 2 * dt);
  }

  get critical(): boolean {
    return this.health <= 0;
  }

  reset(): void {
    this.health = this.armor = this.energy = 100;
    this.shieldUntil = 0;
  }
}
