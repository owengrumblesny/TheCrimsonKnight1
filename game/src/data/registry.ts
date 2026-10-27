import * as THREE from 'three';
import { GLTFLoader, type GLTF } from 'three/addons/loaders/GLTFLoader.js';
import manifestJson from '../../../config/asset_manifest.json';
import clipsJson from '../../../config/crx9_clips.json';
import physicsJson from '../../../config/physics.json';
import controlsJson from '../../../config/controls.json';
import graphicsJson from '../../../config/graphics.json';
import worldJson from '../../../config/world.json';
import catalogJson from '../../../config/image_catalog.json';
import animGraphJson from '../../../config/animation_graph.json';
import { materialFor } from '../render/materials';

export interface AssetEntry {
  id: string;
  category: string;
  file: string;
  stage: string;
  rigged: boolean;
  animation_clips: number;
  up_axis: 'Y' | 'Z';
}

export interface ImageEntry {
  id: string;
  file: string;
  size?: number[];
}

export interface ClipMeta {
  name: string;
  frames: number;
  fps: number;
  duration: number;
  loop: boolean;
  refSpeed: number | null;
  description: string;
}

export const physicsConfig = physicsJson;
export const controlsConfig = controlsJson as Record<string, string>;
export const graphicsConfig = graphicsJson;
export const worldConfig = worldJson;
export const heroClips = clipsJson.clips as ClipMeta[];

/** One image cut from Owen's concept boards (config/image_catalog.json). */
export interface BoardImage {
  id: string;
  file: string;
  category: string;
  label?: string;
  size?: number[];
  frames?: string[];
}

/** Clip name -> board image ids showing the reference key poses for that clip. */
export const clipReferences = animGraphJson.referenceImages as unknown as Record<string, string[]>;

export const HERO_ID = 'crimson_knight_CRX9_rigged';

/** Canonical asset registry built from config/asset_manifest.json (models, material PNGs, icons, artwork). */
class AssetRegistry {
  readonly entries: AssetEntry[] = manifestJson.assets as AssetEntry[];
  readonly textures: ImageEntry[] = manifestJson.textures;
  readonly icons: ImageEntry[] = manifestJson.ui_icons;
  readonly artwork: ImageEntry[] = manifestJson.reference_images;
  readonly boardImages: BoardImage[] = catalogJson.images as BoardImage[];
  private byId = new Map(this.entries.map((a) => [a.id, a]));
  private imageById = new Map(this.boardImages.map((i) => [i.id, i]));
  private loader = new GLTFLoader();
  private texLoader = new THREE.TextureLoader();
  private cache = new Map<string, Promise<GLTF>>();
  private texCache = new Map<string, THREE.Texture>();

  get(id: string): AssetEntry {
    const entry = this.byId.get(id);
    if (!entry) throw new Error(`Unknown asset id "${id}" (not in config/asset_manifest.json)`);
    return entry;
  }

  url(id: string): string {
    return '/' + this.get(id).file;
  }

  iconUrl(id: string): string {
    const icon = this.icons.find((i) => i.id === id);
    if (!icon) throw new Error(`Unknown UI icon "${id}" (not in asset_manifest.json ui_icons)`);
    return '/' + icon.file;
  }

  artworkUrl(id: string): string {
    const art = this.artwork.find((i) => i.id === id);
    if (!art) throw new Error(`Unknown artwork "${id}" (not in asset_manifest.json reference_images)`);
    return '/' + art.file;
  }

  /** A board image entry by catalog id, e.g. 'gadgets/b_batarangs'. */
  boardImage(id: string): BoardImage {
    const img = this.imageById.get(id);
    if (!img) throw new Error(`Unknown board image "${id}" (not in config/image_catalog.json)`);
    return img;
  }

  imageUrl(id: string): string {
    return '/' + this.boardImage(id).file;
  }

  /** Frame URLs for an animation strip (or the single image when it has no frames). */
  imageFrames(id: string): string[] {
    const img = this.boardImage(id);
    return (img.frames ?? [img.file]).map((f) => '/' + f);
  }

  /** Board image as a texture (billboards, holo panels, effect sprites). */
  imageTexture(id: string): Promise<THREE.Texture> {
    return this.texLoader.loadAsync(this.imageUrl(id)).then((t) => {
      t.colorSpace = THREE.SRGBColorSpace;
      t.anisotropy = 8;
      return t;
    });
  }

  /** One of Owen's material PNGs (assets/materials), sRGB and repeating; shared per id. */
  texture(id: string): THREE.Texture {
    let tex = this.texCache.get(id);
    if (!tex) {
      const entry = this.textures.find((t) => t.id === id);
      if (!entry) throw new Error(`Unknown texture "${id}" (not in asset_manifest.json textures)`);
      tex = this.texLoader.load('/' + entry.file);
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
      tex.anisotropy = 8;
      this.texCache.set(id, tex);
    }
    return tex;
  }

  /** Loads an image from the manifest's artwork list as a texture. */
  artworkTexture(id: string): Promise<THREE.Texture> {
    return this.texLoader.loadAsync(this.artworkUrl(id)).then((t) => {
      t.colorSpace = THREE.SRGBColorSpace;
      t.anisotropy = 8;
      return t;
    });
  }

  /** Raw glTF, cached per id. */
  gltf(id: string): Promise<GLTF> {
    let p = this.cache.get(id);
    if (!p) {
      p = this.loader.loadAsync(this.url(id));
      this.cache.set(id, p);
    }
    return p;
  }

  /**
   * A Y-up copy of the asset's scene (Z-up placeholders are rotated -90 deg about X), with each
   * vertex-coloured placeholder mesh re-skinned in the matching material PNG.
   */
  async instance(id: string, textureOverride?: string): Promise<THREE.Object3D> {
    const gltf = await this.gltf(id);
    const entry = this.get(id);
    const holder = new THREE.Group();
    holder.name = id;
    const scene = gltf.scene.clone(true);
    if (entry.up_axis === 'Z') scene.rotation.x = -Math.PI / 2;
    holder.add(scene);
    holder.updateMatrixWorld(true);
    if (!entry.rigged) {
      scene.traverse((o) => {
        const mesh = o as THREE.Mesh;
        if (mesh.isMesh) {
          const mat = materialFor(mesh, entry, (t) => this.texture(t), textureOverride);
          if (mat) mesh.material = mat;
        }
      });
    }
    return holder;
  }
}

export const registry = new AssetRegistry();
