import * as THREE from 'three';
import type { Input } from '../core/input';

/** Third-person orbit camera with mouse/gamepad look and an over-the-shoulder aim offset. */
export class FollowCamera {
  yaw = Math.PI; // camera sits at focus + (sin yaw, -, cos yaw); PI = behind a hero facing +Z
  pitch = 0.25;
  private distance = 4.2;
  private focus = new THREE.Vector3();
  private aimBlend = 0;

  constructor(private camera: THREE.PerspectiveCamera) {}

  update(dt: number, input: Input, target: THREE.Vector3, aiming: boolean): void {
    this.yaw -= input.lookX * 0.0025;
    this.pitch = THREE.MathUtils.clamp(this.pitch + input.lookY * 0.002, -0.5, 1.2);
    this.aimBlend += ((aiming ? 1 : 0) - this.aimBlend) * Math.min(1, 8 * dt);
    const want = target.clone().add(new THREE.Vector3(0, 1.55, 0));
    this.focus.lerp(want, Math.min(1, 12 * dt));
    const dist = THREE.MathUtils.lerp(this.distance, 2.3, this.aimBlend);
    const offset = new THREE.Vector3(
      Math.sin(this.yaw) * Math.cos(this.pitch),
      Math.sin(this.pitch),
      Math.cos(this.yaw) * Math.cos(this.pitch),
    ).multiplyScalar(dist);
    // shoulder offset to the camera's right while aiming
    const right = new THREE.Vector3(Math.cos(this.yaw), 0, -Math.sin(this.yaw)).multiplyScalar(0.55 * this.aimBlend);
    this.camera.position.copy(this.focus).add(offset).add(right);
    this.camera.position.y = Math.max(this.camera.position.y, target.y + 0.3); // relative to the feet (the Citadel is at y -120)
    this.camera.lookAt(this.focus.clone().add(right));
  }
}
