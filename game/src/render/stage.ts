import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { PRESETS, type Preset, type Quality } from './quality';

/** Renderer, scene, night lighting, reflections, rain and post-processing for New Gotham. */
export class Stage {
  readonly renderer: THREE.WebGLRenderer;
  readonly scene = new THREE.Scene();
  readonly camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.1, 900);
  readonly moon: THREE.DirectionalLight;
  quality: Quality = 'high';
  preset: Preset = PRESETS.high;
  /** Soft key light riding with the camera so the crimson armor reads at night. */
  private heroKey = new THREE.PointLight(0xffe2d0, 7, 9, 1.5);
  private rain?: THREE.LineSegments;
  private composer: EffectComposer | null = null;
  private bloom: UnrealBloomPass | null = null;
  private fog: THREE.FogExp2;

  constructor(antialias: boolean) {
    this.renderer = new THREE.WebGLRenderer({ antialias, powerPreference: 'high-performance' });
    this.renderer.setSize(innerWidth, innerHeight);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.1;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.info.autoReset = false; // the perf overlay counts all passes of a frame
    document.body.appendChild(this.renderer.domElement);

    const night = new THREE.Color('#0b0d16');
    this.scene.background = night;
    this.fog = new THREE.FogExp2(night, 0.012);
    this.scene.fog = this.fog;
    // image-based reflections: one-time prefiltered environment, dimmed to night levels
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromScene(nightEnvironment(), 0.04).texture;
    pmrem.dispose();
    this.scene.add(new THREE.HemisphereLight(0x8090c0, 0x20141a, 0.7));
    this.moon = new THREE.DirectionalLight(0xb8c4ff, 1.6);
    this.moon.position.set(-30, 50, 20);
    this.moon.castShadow = true;
    this.moon.shadow.bias = -0.0005;
    this.moon.shadow.normalBias = 0.02;
    this.scene.add(this.moon, this.moon.target, this.heroKey);

    addEventListener('resize', () => this.resize());
  }

  private resize(): void {
    this.camera.aspect = innerWidth / innerHeight;
    this.camera.updateProjectionMatrix();
    const p = this.preset;
    // render at the preset's internal height (e.g. 720p) and let the browser upscale the canvas
    const ratio = p.renderHeight ? Math.min(p.maxPixelRatio, p.renderHeight / innerHeight) : Math.min(devicePixelRatio, p.maxPixelRatio);
    this.renderer.setPixelRatio(ratio);
    this.renderer.setSize(innerWidth, innerHeight);
    this.composer?.setPixelRatio(ratio);
    this.composer?.setSize(innerWidth, innerHeight);
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
    this.applyRain();
  }

  private applyRain(): void {
    if (this.rain) this.rain.geometry.setDrawRange(0, Math.floor(this.preset.rain * this.rain.geometry.getAttribute('position').count));
  }

  updateRain(dt: number): void {
    if (!this.rain) return;
    const a = this.rain.geometry.getAttribute('position') as THREE.BufferAttribute;
    const arr = a.array as Float32Array;
    const n = (this.rain.geometry.drawRange.count === Infinity ? arr.length / 3 : this.rain.geometry.drawRange.count) * 3;
    for (let i = 1; i < n; i += 6) {
      arr[i] -= 22 * dt;
      arr[i + 3] -= 22 * dt;
      if (arr[i + 3] < 0) {
        arr[i] += 30;
        arr[i + 3] += 30;
      }
    }
    a.needsUpdate = true;
  }

  /** Apply a graphics preset (see quality.ts). Shader-affecting changes trigger one recompile here, never mid-play. */
  applyQuality(q: Quality): void {
    this.quality = q;
    const p = (this.preset = PRESETS[q]);
    this.resize();
    this.moon.castShadow = p.shadows;
    this.renderer.shadowMap.type = p.softShadows ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap;
    const sc = this.moon.shadow.camera;
    sc.left = sc.bottom = -p.shadowRange;
    sc.right = sc.top = p.shadowRange;
    sc.far = 150;
    sc.updateProjectionMatrix();
    if (this.moon.shadow.mapSize.x !== p.shadowMap) {
      this.moon.shadow.mapSize.set(p.shadowMap, p.shadowMap);
      this.moon.shadow.map?.dispose();
      this.moon.shadow.map = null;
    }
    this.camera.far = p.drawDistance;
    this.camera.updateProjectionMatrix();
    this.fog.density = p.fogDensity;
    this.applyRain();
    this.scene.traverse((o) => {
      const mats = (o as THREE.Mesh).material;
      if (!mats) return;
      for (const m of Array.isArray(mats) ? mats : [mats]) {
        const std = m as THREE.MeshStandardMaterial;
        if ('envMapIntensity' in std) std.envMapIntensity = p.envIntensity;
        for (const t of [std.map, std.normalMap, std.roughnessMap, std.emissiveMap]) {
          if (t) {
            t.anisotropy = p.anisotropy;
            t.needsUpdate = true;
          }
        }
        m.needsUpdate = true;
      }
    });
    if (p.bloom && !this.composer) {
      this.composer = new EffectComposer(this.renderer);
      this.composer.addPass(new RenderPass(this.scene, this.camera));
      // high threshold = only emissives (eyes, emblem, neon, lamps) bloom
      this.bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth / 2, innerHeight / 2), 0.55, 0.4, 0.92);
      this.composer.addPass(this.bloom);
      this.composer.addPass(new OutputPass());
      this.resize();
    }
    if (this.bloom) this.bloom.enabled = p.bloom;
  }

  render(): void {
    this.renderer.info.reset();
    if (this.composer && this.preset.bloom) this.composer.render();
    else this.renderer.render(this.scene, this.camera);
  }
}

/** Reflection source: dark sky dome with a few warm street-light and crimson neon panels (rendered once). */
function nightEnvironment(): THREE.Scene {
  const env = new THREE.Scene();
  const dome = new THREE.Mesh(
    new THREE.SphereGeometry(50, 32, 16),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      uniforms: {},
      vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: 'varying vec3 vP; void main(){ float h = vP.y * 0.5 + 0.5; vec3 c = mix(vec3(0.05,0.045,0.05), vec3(0.09,0.11,0.17), smoothstep(0.35,1.0,h)); gl_FragColor = vec4(c,1.0); }',
    }),
  );
  env.add(dome);
  const panel = (color: number, intensity: number, x: number, y: number, z: number, w: number, h: number) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity) }));
    m.position.set(x, y, z);
    m.lookAt(0, 0, 0);
    env.add(m);
  };
  panel(0xffb070, 3, 30, 12, 10, 6, 3);
  panel(0xffb070, 3, -28, 10, -16, 6, 3);
  panel(0xff2030, 4, 6, 8, -34, 10, 2);
  panel(0x8fb4ff, 1.5, -10, 40, 20, 30, 8);
  panel(0xffe0c0, 2, 0, 25, 35, 14, 4);
  return env;
}
