import * as THREE from 'three';

/**
 * Maps the placeholder GLBs' flat vertex colours onto Owen's material PNGs (assets/materials).
 * The placeholders use 15 palette colours; each maps to the PNG it was clearly drawn from.
 * Colours with no matching PNG (lane-line yellow, foliage greens) keep their vertex colour.
 */
type Rgb = [number, number, number];

interface Rule {
  rgb: Rgb;
  tex: (assetId: string, category: string) => string | null;
}

const RULES: Rule[] = [
  // dark slate: road surface / building shells / metal bodies
  { rgb: [30, 33, 40], tex: (id, cat) => (id.startsWith('road_tile') ? 'wet_asphalt' : cat === 'architecture' ? 'concrete' : 'gunmetal') },
  { rgb: [35, 80, 95], tex: () => 'glass' },
  { rgb: [230, 40, 60], tex: () => 'red_emissive' },
  { rgb: [255, 40, 60], tex: () => 'red_emissive' },
  { rgb: [72, 77, 87], tex: () => 'gunmetal' },
  { rgb: [52, 56, 65], tex: () => 'gunmetal' },
  { rgb: [158, 18, 32], tex: () => 'crimson_metal' },
  { rgb: [145, 13, 31], tex: () => 'crimson_metal' },
  { rgb: [77, 5, 17], tex: () => 'crimson_metal' },
  { rgb: [100, 99, 101], tex: () => 'concrete' },
  { rgb: [17, 18, 25], tex: () => 'black_rubber' },
];

const SURFACE: Record<string, { rough: number; metal: number; emissive?: number; tint?: number }> = {
  wet_asphalt: { rough: 0.3, metal: 0.1 },
  concrete: { rough: 0.85, metal: 0.0, tint: 1.6 },
  glass: { rough: 0.08, metal: 0.4, emissive: 0.35 },
  red_emissive: { rough: 0.4, metal: 0.0, emissive: 2.2 },
  gunmetal: { rough: 0.35, metal: 0.8, tint: 1.3 },
  crimson_metal: { rough: 0.45, metal: 0.35 },
  black_rubber: { rough: 0.8, metal: 0.0 },
  cavern_stone: { rough: 0.95, metal: 0.0, tint: 1.4 },
};

const shared = new Map<string, THREE.MeshStandardMaterial>();
const uvDone = new WeakSet<THREE.BufferGeometry>();

/** Shared PBR material for one of the material PNGs. */
export function pngMaterial(texId: string, getTexture: (id: string) => THREE.Texture): THREE.MeshStandardMaterial {
  let m = shared.get(texId);
  if (!m) {
    const s = SURFACE[texId] ?? { rough: 0.6, metal: 0.1 };
    const map = getTexture(texId);
    m = new THREE.MeshStandardMaterial({
      map,
      roughness: s.rough,
      metalness: s.metal,
      color: new THREE.Color().setScalar(s.tint ?? 1),
      flatShading: true,
    });
    if (s.emissive) {
      m.emissive.set(0xffffff);
      m.emissiveMap = map;
      m.emissiveIntensity = s.emissive;
    }
    m.name = 'PNG_' + texId;
    shared.set(texId, m);
  }
  return m;
}

/** Tri-planar box UVs (1 texture tile per 2 m) for placeholder meshes that ship without UVs. */
export function ensureBoxUVs(geo: THREE.BufferGeometry, metresPerTile = 2): void {
  if (geo.getAttribute('uv') || uvDone.has(geo)) return;
  if (geo.index) {
    // per-face projection needs unshared vertices; convert in place (geometry is shared by clones)
    const flat = geo.toNonIndexed();
    geo.setIndex(null);
    for (const name of Object.keys(flat.attributes)) geo.setAttribute(name, flat.getAttribute(name));
  }
  const p = geo.getAttribute('position') as THREE.BufferAttribute;
  const uv = new Float32Array(p.count * 2);
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3(), n = new THREE.Vector3();
  for (let i = 0; i < p.count; i += 3) {
    a.fromBufferAttribute(p, i);
    b.fromBufferAttribute(p, i + 1);
    c.fromBufferAttribute(p, i + 2);
    n.subVectors(c, b).cross(a.clone().sub(b)).set(Math.abs(n.x), Math.abs(n.y), Math.abs(n.z));
    for (let k = 0; k < 3; k++) {
      const v = [a, b, c][k];
      const [u, w] = n.x >= n.y && n.x >= n.z ? [v.y, v.z] : n.y >= n.z ? [v.x, v.z] : [v.x, v.y];
      uv[(i + k) * 2] = u / metresPerTile;
      uv[(i + k) * 2 + 1] = w / metresPerTile;
    }
  }
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  uvDone.add(geo);
}

function meanVertexColor(geo: THREE.BufferGeometry): Rgb | null {
  const col = geo.getAttribute('color') as THREE.BufferAttribute | undefined;
  if (!col) return null;
  let r = 0, g = 0, b = 0;
  for (let i = 0; i < col.count; i++) {
    r += col.getX(i);
    g += col.getY(i);
    b += col.getZ(i);
  }
  // raw COLOR_0 values, i.e. the placeholder palette as authored
  return [(r / col.count) * 255, (g / col.count) * 255, (b / col.count) * 255];
}

/** Material PNG id for a placeholder mesh, or null to keep its vertex colour. */
export function textureIdFor(mesh: THREE.Mesh, assetId: string, category: string): string | null {
  const rgb = meanVertexColor(mesh.geometry);
  if (!rgb) return null;
  let best: Rule | null = null;
  let bestD = Infinity;
  for (const rule of RULES) {
    const d = Math.hypot(rgb[0] - rule.rgb[0], rgb[1] - rule.rgb[1], rgb[2] - rule.rgb[2]);
    if (d < bestD) {
      bestD = d;
      best = rule;
    }
  }
  return best && bestD < 22 ? best.tex(assetId, category) : null;
}

/** Replacement material for a placeholder mesh (null = keep the GLB's own). */
export function materialFor(
  mesh: THREE.Mesh,
  entry: { id: string; category: string },
  getTexture: (id: string) => THREE.Texture,
  override?: string,
): THREE.Material | null {
  const texId = override ?? textureIdFor(mesh, entry.id, entry.category);
  if (!texId) return null;
  ensureBoxUVs(mesh.geometry);
  return pngMaterial(texId, getTexture);
}
