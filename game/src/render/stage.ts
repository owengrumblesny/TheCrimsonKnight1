import * as THREE from 'three';
import { graphicsConfig } from '../data/registry';

/** Renderer, scene, night lighting and rain for New Gotham (config/graphics.json). */
export class Stage {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 900);
  readonly moon: THREE.DirectionalLight;
  /** Soft key light riding with the camera so the crimson armor reads at night. */
  private heroKey = new THREE.PointLight(0xffe2d0, 7, 9, 1.5);
  private rain?: THREE.LineSegments;

  constructor() {
    const g = graphicsConfig;
    this.renderer = new THREE.WebGLRenderer({ antialias: g.antialias, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, g.pixelRatioCap));
    this.renderer.setSize(innerWidth, innerHeight);
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.1;
    this.renderer.shadowMap.enabled = g.shadows;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    document.body.appendChild(this.renderer.domElement);

    const night = new THREE.Color('#0b0d16');
    this.scene.background = night;
    this.scene.fog = new THREE.FogExp2(night, 0.012);
    this.scene.add(new THREE.HemisphereLight(0x8090c0, 0x20141a, 0.9));
    this.moon = new THREE.DirectionalLight(0xb8c4ff, 1.6);
    this.moon.position.set(-30, 50, 20);
    this.moon.castShadow = true;
    this.moon.shadow.mapSize.set(2048, 2048);
    const sc = this.moon.shadow.camera;
    sc.left = sc.bottom = -30;
    sc.right = sc.top = 30;
    sc.far = 150;
    this.moon.shadow.bias = -0.0005;
    this.scene.add(this.moon, this.moon.target, this.heroKey);

    addEventListener('resize', () => {
      this.camera.aspect = innerWidth / innerHeight;
      this.camera.updateProjectionMatrix();
      this.renderer.setSize(innerWidth, innerHeight);
    });
  }

  /** Keep the shadow frustum centred on the player. */
  follow(target: THREE.Vector3): void {
    this.moon.position.set(target.x - 30, target.y + 50, target.z + 20);
    this.moon.target.position.copy(target);
    const toCam = this.camera.position.clone().sub(target).setY(0).normalize();
    this.heroKey.position.copy(target).addScaledVector(toCam, 2.2).add(new THREE.Vector3(0, 2.6, 0));
    if (this.rain) this.rain.position.set(target.x, 0, target.z);
  }

  enableRain(count = 6000): void {
    const pos = new Float32Array(count * 6);
    for (let i = 0; i < count; i++) {
      const x = (Math.random() - 0.5) * 60, y = Math.random() * 30, z = (Math.random() - 0.5) * 60;
      pos.set([x, y, z, x + 0.03, y - 0.45, z], i * 6);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    this.rain = new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color: 0x8899bb, transparent: true, opacity: 0.35 }));
    this.rain.frustumCulled = false;
    this.scene.add(this.rain);
  }

  updateRain(dt: number): void {
    if (!this.rain) return;
    const a = this.rain.geometry.getAttribute('position') as THREE.BufferAttribute;
    const arr = a.array as Float32Array;
    for (let i = 1; i < arr.length; i += 6) {
      arr[i] -= 22 * dt;
      arr[i + 3] -= 22 * dt;
      if (arr[i + 3] < 0) {
        arr[i] += 30;
        arr[i + 3] += 30;
      }
    }
    a.needsUpdate = true;
  }

  render(): void {
    this.renderer.render(this.scene, this.camera);
  }
}
