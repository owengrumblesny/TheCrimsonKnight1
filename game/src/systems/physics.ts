import RAPIER from '@dimforge/rapier3d-compat';
import * as THREE from 'three';
import { physicsConfig } from '../data/registry';

export { RAPIER };

/** Rapier world stepped at the fixed rate from config/physics.json. */
export class Physics {
  readonly world: RAPIER.World;
  readonly dt = physicsConfig.fixedTimestep;

  private constructor() {
    const [x, y, z] = physicsConfig.gravity;
    this.world = new RAPIER.World({ x, y, z });
    this.world.timestep = this.dt;
  }

  static async create(): Promise<Physics> {
    await RAPIER.init();
    return new Physics();
  }

  step(): void {
    this.world.step();
  }

  addGround(size: number): void {
    // Observed in testing: with a 400 m slab centred on the spawn, the character controller sank
    // through it at (0,0) (but not 1.5 m away). An offset, larger slab fixed it; root cause not isolated.
    const body = this.world.createRigidBody(RAPIER.RigidBodyDesc.fixed().setTranslation(37.3, -0.5, 41.9));
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(size / 2 + 50, 0.5, size / 2 + 50), body);
  }

  /** Static box collider matching an object's world-space bounds (initial collision proxy). */
  addStaticBox(box: THREE.Box3): void {
    const c = box.getCenter(new THREE.Vector3());
    const h = box.getSize(new THREE.Vector3()).multiplyScalar(0.5);
    if (h.x < 0.02 || h.y < 0.02 || h.z < 0.02) return;
    const body = this.world.createRigidBody(RAPIER.RigidBodyDesc.fixed().setTranslation(c.x, c.y, c.z));
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(h.x, h.y, h.z), body);
  }

  /** Dynamic box for physics play (crates, barrels...). Returns the body for render sync. */
  addDynamicBox(box: THREE.Box3, mass = 20): RAPIER.RigidBody {
    const c = box.getCenter(new THREE.Vector3());
    const h = box.getSize(new THREE.Vector3()).multiplyScalar(0.5);
    const body = this.world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(c.x, c.y, c.z));
    const vol = Math.max(8 * h.x * h.y * h.z, 1e-3);
    this.world.createCollider(RAPIER.ColliderDesc.cuboid(h.x, h.y, h.z).setDensity(mass / vol).setFriction(0.8), body);
    return body;
  }
}
