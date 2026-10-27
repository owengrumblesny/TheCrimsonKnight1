import type { Settings } from '../ui/uiState';

export type Bus = 'music' | 'ambience' | 'sfx' | 'vehicles' | 'ui';
export type SoundEvent =
  | 'ui.click' | 'ui.open' | 'ui.close' | 'ui.select' | 'ui.deny'
  | 'armor.step' | 'armor.jump' | 'armor.land' | 'armor.activate'
  | 'gadget.deploy' | 'gadget.throw' | 'gadget.pulse' | 'vehicle.summon';

/**
 * Minimal Web Audio foundation: one AudioContext, master + per-bus gains, and ORIGINAL synthesized
 * placeholder sounds (no downloaded or third-party audio). Real recordings can replace any event later
 * by decoding a buffer for it. Audio stays silent until unlock() is called from a user gesture.
 */
export class AudioManager {
  private ctx: AudioContext | null = null;
  private master!: GainNode;
  private buses = {} as Record<Bus, GainNode>;
  private noise!: AudioBuffer;
  private ambience: { src: AudioBufferSourceNode; gain: GainNode } | null = null;
  private lastPlayed = new Map<SoundEvent, number>();
  private active = 0;

  constructor(private settings: Settings) {}

  get unlocked(): boolean {
    return !!this.ctx && this.ctx.state === 'running';
  }

  /** Must be called from a click/keypress (browser autoplay policy). Safe to call repeatedly. */
  async unlock(): Promise<void> {
    if (!this.ctx) {
      const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (!Ctx) return;
      this.ctx = new Ctx();
      this.master = this.ctx.createGain();
      this.master.connect(this.ctx.destination);
      for (const b of ['music', 'ambience', 'sfx', 'vehicles', 'ui'] as Bus[]) {
        this.buses[b] = this.ctx.createGain();
        this.buses[b].connect(this.master);
      }
      this.noise = this.ctx.createBuffer(1, this.ctx.sampleRate * 2, this.ctx.sampleRate);
      const d = this.noise.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      this.applySettings(this.settings);
    }
    if (this.ctx.state !== 'running') await this.ctx.resume();
  }

  applySettings(s: Settings): void {
    this.settings = s;
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(s.muted ? 0 : s.volumes.master, t, 0.05);
    for (const b of Object.keys(this.buses) as Bus[]) this.buses[b].gain.setTargetAtTime(s.volumes[b], t, 0.05);
  }

  /** Rain/city ambience loop (filtered noise). Starting twice never stacks loops. */
  startAmbience(): void {
    if (!this.ctx || this.ambience) return;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    src.loop = true;
    const lp = this.ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 2400;
    const gain = this.ctx.createGain();
    gain.gain.value = 0;
    gain.gain.setTargetAtTime(0.16, this.ctx.currentTime, 1.5);
    src.connect(lp).connect(gain).connect(this.buses.ambience);
    src.start();
    this.ambience = { src, gain };
  }

  /** Play a one-shot. strength 0..1 scales landings. Rate-limited per event and capped overall. */
  play(event: SoundEvent, strength = 1): void {
    const ctx = this.ctx;
    if (!ctx || ctx.state !== 'running' || this.active > 24) return;
    const now = performance.now();
    if (now - (this.lastPlayed.get(event) ?? 0) < 45) return;
    this.lastPlayed.set(event, now);
    const t = ctx.currentTime;
    const bus = event.startsWith('ui.') ? this.buses.ui : event.startsWith('vehicle') ? this.buses.vehicles : this.buses.sfx;
    const tone = (type: OscillatorType, f0: number, f1: number, dur: number, vol: number, delay = 0) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(f0, t + delay);
      o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + delay + dur);
      g.gain.setValueAtTime(0.0001, t + delay);
      g.gain.exponentialRampToValueAtTime(vol, t + delay + 0.005);
      g.gain.exponentialRampToValueAtTime(0.0001, t + delay + dur);
      o.connect(g).connect(bus);
      o.start(t + delay);
      o.stop(t + delay + dur + 0.02);
      this.track(o);
    };
    const hiss = (freq: number, q: number, dur: number, vol: number, type: BiquadFilterType = 'bandpass') => {
      const s = ctx.createBufferSource();
      s.buffer = this.noise;
      s.playbackRate.value = 0.8 + Math.random() * 0.4;
      const f = ctx.createBiquadFilter();
      f.type = type;
      f.frequency.value = freq;
      f.Q.value = q;
      const g = ctx.createGain();
      g.gain.setValueAtTime(vol, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      s.connect(f).connect(g).connect(bus);
      s.start(t, Math.random());
      s.stop(t + dur + 0.02);
      this.track(s);
    };
    switch (event) {
      case 'ui.click': tone('triangle', 1200, 900, 0.05, 0.25); break;
      case 'ui.select': tone('sine', 660, 990, 0.08, 0.25); break;
      case 'ui.open': tone('sine', 320, 640, 0.12, 0.22); break;
      case 'ui.close': tone('sine', 640, 300, 0.12, 0.2); break;
      case 'ui.deny': tone('square', 180, 140, 0.14, 0.12); break;
      case 'armor.step': hiss(900 + Math.random() * 300, 1.2, 0.09, 0.35); tone('sine', 90, 60, 0.07, 0.25); break;
      case 'armor.jump': hiss(1400, 0.8, 0.18, 0.25); tone('sawtooth', 220, 440, 0.12, 0.05); break;
      case 'armor.land': hiss(500, 0.7, 0.25 + 0.3 * strength, 0.4 + 0.5 * strength); tone('sine', 110, 40, 0.3 + 0.3 * strength, 0.5 * strength + 0.2); break;
      case 'armor.activate': tone('sawtooth', 300, 900, 0.25, 0.08); tone('sine', 900, 1200, 0.15, 0.12, 0.2); break;
      case 'gadget.deploy': tone('square', 500, 1500, 0.1, 0.07); hiss(3000, 2, 0.12, 0.2); break;
      case 'gadget.throw': hiss(2200, 3, 0.25, 0.35, 'highpass'); break;
      case 'gadget.pulse': tone('sine', 1800, 300, 0.6, 0.2); hiss(600, 0.5, 0.5, 0.25); break;
      case 'vehicle.summon': tone('sine', 880, 880, 0.12, 0.2); tone('sine', 1320, 1320, 0.18, 0.2, 0.14); break;
    }
  }

  private track(node: AudioScheduledSourceNode): void {
    this.active++;
    node.onended = () => this.active--;
  }

  /** Duck the world ambience while a menu pauses the game (UI sounds keep working). */
  setPaused(paused: boolean): void {
    if (!this.ctx || !this.ambience) return;
    this.ambience.gain.gain.setTargetAtTime(paused ? 0.04 : 0.16, this.ctx.currentTime, 0.3);
  }
}
