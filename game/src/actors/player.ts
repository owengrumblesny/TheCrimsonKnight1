import * as THREE from 'three';
import type { Input } from '../core/input';
import { physicsConfig } from '../data/registry';
import { RAPIER, type Physics } from '../systems/physics';
import type { Hero } from './hero';

const P = physicsConfig.player;
const RADIUS = P.radius;
const HALF = (P.height - 2 * RADIUS) / 2;
const JUMP_DELAY = 0.12; // JumpStart plays at 2x; impulse lands near its push-off key
const ONE_SHOT_LOCK: Record<string, number> = {
  CK_LandHard: 0.75, CK_GadgetDraw: 0.45, CK_GadgetStow: 0.45, CK_Summon: 1.4, CK_Interact: 0.7,
};

type Mode = 'ground' | 'air' | 'glide' | 'action';

/**
 * Third-person player: Rapier kinematic character controller (fixed 60 Hz) driving the
 * CR-X9 animation state machine. Movement is camera-relative; the body turns to face travel,
 * except while aiming the grapnel, where it faces the camera and strafes.
 */
export class Player {
  private body: RAPIER.RigidBody;
  private collider: RAPIER.Collider;
  private controller: RAPIER.KinematicCharacterController;
  private prevPos = new THREE.Vector3();
  private pos = new THREE.Vector3();
  private vel = new THREE.Vector3();
  private grounded = true;
  private mode: Mode = 'ground';
  private lockTime = 0;
  private jumpTimer = -1;
  private walkMode = false;
  private crouched = false;
  private gadget: string | null = null;
  private aiming = false;
  heading = 0; // radians, 0 = facing +Z
  speed = 0;
  status = '';

  constructor(physics: Physics, private hero: Hero, spawn: THREE.Vector3) {
    const w = physics.world;
    this.body = w.createRigidBody(
      RAPIER.RigidBodyDesc.kinematicPositionBased().setTranslation(spawn.x, spawn.y + HALF + RADIUS, spawn.z),
    );
    this.collider = w.createCollider(RAPIER.ColliderDesc.capsule(HALF, RADIUS), this.body);
    this.controller = w.createCharacterController(0.02);
    this.controller.enableAutostep(0.45, 0.25, true);
    this.controller.enableSnapToGround(0.35);
    this.controller.setMaxSlopeClimbAngle((50 * Math.PI) / 180);
    this.controller.setApplyImpulsesToDynamicBodies(true);
    this.pos.copy(this.body.translation() as THREE.Vector3Like);
    this.prevPos.copy(this.pos);
    hero.onFinished((name) => this.onClipFinished(name));
  }

  /** Per-frame input handling (discrete actions). */
  handleInput(input: Input): void {
    if (input.hit('walkToggle')) this.walkMode = !this.walkMode;
    if (input.hit('crouch') && this.mode === 'ground') this.crouched = !this.crouched;
    this.aiming = input.held('grapple') && this.mode === 'ground';
    if (this.mode !== 'ground') return;
    if (input.hit('jump') && this.jumpTimer < 0) {
      this.crouched = false;
      this.jumpTimer = JUMP_DELAY;
      this.hero.play('CK_JumpStart', { fade: 0.08, timeScale: 2, restart: true });
    } else if (input.hit('interact')) {
      this.oneShot('CK_Interact');
    }
  }

  /** Gadget menu: draw a gadget (or stow the one in hand). Returns false if busy/airborne. */
  setGadget(id: string | null): boolean {
    if (this.mode !== 'ground' || id === this.gadget) return false;
    this.oneShot(id ? 'CK_GadgetDraw' : 'CK_GadgetStow');
    this.gadget = id;
    return true;
  }

  /** Summon menu: plays the wrist-module call. Returns false if busy/airborne. */
  summon(): boolean {
    if (this.mode !== 'ground') return false;
    this.oneShot('CK_Summon');
    return true;
  }

  /** Read-only state for the HUD. */
  get state() {
    return {
      mode: this.mode, crouched: this.crouched, aiming: this.aiming, walk: this.walkMode, gadget: this.gadget,
      sprinting: this.mode === 'ground' && this.speed > P.runSpeed + 0.5, heading: this.heading, speed: this.speed,
    };
  }

  private oneShot(name: string): void {
    this.mode = 'action';
    this.lockTime = ONE_SHOT_LOCK[name] ?? 0.5;
    this.hero.play(name, { fade: 0.15, restart: true });
  }

  private onClipFinished(name: string): void {
    if (this.mode === 'action' && name !== 'CK_GadgetDraw') this.lockTime = Math.min(this.lockTime, 0);
  }

  /** Fixed-step simulation. camYaw: camera yaw so movement is camera-relative. */
  fixedUpdate(dt: number, input: Input, camYaw: number, glideHeld: boolean): void {
    this.prevPos.copy(this.pos);
    const wish = new THREE.Vector3(input.moveX, 0, input.moveY);
    const moving = wish.lengthSq() > 0.01;
    // camera looks toward -Z at yaw 0: forward = (sin(yaw+PI), cos(yaw+PI)) in XZ
    const fwd = new THREE.Vector3(-Math.sin(camYaw), 0, -Math.cos(camYaw));
    const right = new THREE.Vector3(-fwd.z, 0, fwd.x);
    const dir = fwd.multiplyScalar(wish.z).add(right.multiplyScalar(wish.x));

    let target = 0;
    if (this.mode === 'ground' && moving) {
      target = this.crouched ? 1.4 : this.aiming ? P.walkSpeed : this.walkMode ? P.walkSpeed
        : input.held('sprint') ? P.sprintSpeed : P.runSpeed;
      target *= Math.min(1, wish.length());
    }
    if (this.mode === 'glide') target = 9;
    if (this.mode === 'air') target = Math.hypot(this.vel.x, this.vel.z);

    if (this.mode === 'ground' || this.mode === 'glide' || (this.mode === 'air' && moving)) {
      const accel = this.mode === 'ground' ? 14 : 3;
      const desired = moving ? dir.clone().normalize().multiplyScalar(target)
        : this.mode === 'glide' ? new THREE.Vector3(Math.sin(this.heading), 0, Math.cos(this.heading)).multiplyScalar(target)
        : new THREE.Vector3();
      this.vel.x += (desired.x - this.vel.x) * Math.min(1, accel * dt);
      this.vel.z += (desired.z - this.vel.z) * Math.min(1, accel * dt);
    } else if (this.mode === 'action') {
      this.vel.x *= 0.8;
      this.vel.z *= 0.8;
    }

    // facing
    if (this.aiming) {
      this.heading = camYaw + Math.PI;
    } else if (Math.hypot(this.vel.x, this.vel.z) > 0.3 && this.mode !== 'action') {
      const want = Math.atan2(this.vel.x, this.vel.z);
      let d = want - this.heading;
      d = Math.atan2(Math.sin(d), Math.cos(d));
      this.heading += d * Math.min(1, (this.mode === 'ground' ? 12 : 4) * dt);
    }

    // jump / gravity / glide
    if (this.jumpTimer >= 0) {
      this.jumpTimer -= dt;
      if (this.jumpTimer < 0) {
        this.vel.y = P.jumpImpulse;
        this.mode = 'air';
        this.grounded = false;
        this.hero.play('CK_Airborne', { fade: 0.25 });
      }
    }
    this.vel.y += physicsConfig.gravity[1] * dt;
    if (this.mode === 'air' && glideHeld && this.vel.y < -2) this.mode = 'glide';
    if (this.mode === 'glide') {
      if (!glideHeld) this.mode = 'air';
      else this.vel.y = Math.max(this.vel.y, -P.glideFallSpeed);
    }

    // snap-to-ground would cancel a jump on its first frames, so only snap while not rising
    if (this.vel.y > 0) this.controller.disableSnapToGround();
    else this.controller.enableSnapToGround(0.35);
    const delta = { x: this.vel.x * dt, y: this.vel.y * dt, z: this.vel.z * dt };
    this.controller.computeColliderMovement(this.collider, delta);
    const m = this.controller.computedMovement();
    const t = this.body.translation();
    this.body.setNextKinematicTranslation({ x: t.x + m.x, y: t.y + m.y, z: t.z + m.z });
    this.grounded = this.controller.computedGrounded();
    if (this.grounded) {
      this.coyote = 0;
      if (this.vel.y <= 0) {
        if (this.mode === 'air' || this.mode === 'glide') this.land(this.vel.y);
        this.vel.y = -0.5;
      }
    } else if (this.mode === 'ground' && this.jumpTimer < 0) {
      // walked off a ledge: short grace period before switching to the air state
      this.coyote += dt;
      if (this.coyote > 0.2) {
        this.mode = 'air';
        this.hero.play('CK_Airborne', { fade: 0.3 });
      }
    }
    this.pos.set(t.x + m.x, t.y + m.y, t.z + m.z);
    if (this.pos.y < -50) this.respawn();

    if (this.mode === 'action') {
      this.lockTime -= dt;
      if (this.lockTime <= 0) this.mode = 'ground';
    }
    this.speed = Math.hypot(this.vel.x, this.vel.z);
  }

  private coyote = 0;

  /** Called on touchdown with the feet position (effects hook). */
  onLand: ((hard: boolean, feet: THREE.Vector3) => void) | null = null;

  private land(vy: number): void {
    this.onLand?.(vy < -P.hardLandingSpeed, this.pos.clone().setY(this.pos.y - HALF - RADIUS));
    if (vy < -P.hardLandingSpeed) {
      this.oneShot('CK_LandHard');
      this.vel.x = this.vel.z = 0;
    } else {
      this.mode = 'ground';
      this.hero.play('CK_LandSoft', { fade: 0.08, restart: true });
      this.landTime = 0.3;
    }
  }

  private landTime = 0;

  private respawn(): void {
    this.teleport(new THREE.Vector3(0, 3, 0));
  }

  /** Debug/sandbox: move the capsule (feet position) and drop into the air state. */
  teleport(feet: THREE.Vector3): void {
    const c = feet.clone().setY(feet.y + HALF + RADIUS);
    this.body.setTranslation(c, true);
    this.vel.set(0, 0, 0);
    this.pos.copy(c);
    this.prevPos.copy(c);
    this.mode = 'air';
    this.hero.play('CK_Airborne', { fade: 0.2 });
  }

  /** Per-frame: choose locomotion clip + rate and place the visual (interpolated). */
  update(dt: number, alpha: number): void {
    this.landTime -= dt;
    if (this.mode === 'ground' && this.jumpTimer < 0 && !(this.landTime > 0 && this.speed < 0.5)) {
      const s = this.speed;
      let clip: string;
      if (this.crouched) clip = s < 0.2 ? 'CK_CrouchIdle' : 'CK_CrouchWalk';
      else if (this.aiming) clip = s < 0.2 ? 'CK_GrappleAim' : this.strafeClip();
      else if (s < 0.2) clip = 'CK_Idle';
      else if (s < 2.8) clip = 'CK_Walk';
      else if (s < 7.6) clip = 'CK_Run';
      else clip = 'CK_Sprint';
      this.hero.play(clip, { fade: 0.25 });
      this.hero.setTimeScale(this.hero.rateFor(clip, Math.max(s, 0.3)) * (this.backpedal() ? -1 : 1));
    } else if (this.mode === 'glide') {
      this.hero.play('CK_Glide', { fade: 0.35 });
    }
    this.hero.root.position.lerpVectors(this.prevPos, this.pos, alpha).y -= HALF + RADIUS;
    this.hero.root.rotation.y = this.heading;
    // glide: pitch the whole body toward horizontal flight
    const pitch = this.mode === 'glide' ? 0.9 : 0;
    this.hero.root.rotation.x += (pitch - this.hero.root.rotation.x) * Math.min(1, 5 * dt);
    this.status = `${this.mode}${this.crouched ? ' crouch' : ''}${this.aiming ? ' aim' : ''}${this.walkMode ? ' walk' : ''}` +
      ` | ${this.hero.current} | ${this.speed.toFixed(1)} m/s`;
  }

  /** Movement direction relative to facing, used for strafing while aiming. */
  private localVel(): THREE.Vector2 {
    const c = Math.cos(this.heading), s = Math.sin(this.heading);
    // forward = (sin h, cos h); character's left = (cos h, -sin h)
    return new THREE.Vector2(this.vel.x * c - this.vel.z * s, this.vel.x * s + this.vel.z * c);
  }

  private strafeClip(): string {
    const v = this.localVel();
    if (Math.abs(v.x) > Math.abs(v.y)) return v.x > 0 ? 'CK_StrafeLeft' : 'CK_StrafeRight';
    return 'CK_Walk';
  }

  private backpedal(): boolean {
    return this.aiming && this.hero.current === 'CK_Walk' && this.localVel().y < -0.2;
  }

  get position(): THREE.Vector3 {
    return this.hero.root.position;
  }
}
