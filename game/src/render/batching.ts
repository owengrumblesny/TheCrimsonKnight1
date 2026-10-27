import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export interface MergedPart {
  geometry: THREE.BufferGeometry;
  material: THREE.Material;
}

/**
 * Collapse every mesh under `root` into one geometry per material (transforms baked in).
 * Placeholder assets are dozens of separate boxes; merging them turns ~30 draw calls per building
 * type into 2–3, which the benchmark showed is the main cost on the Radeon 610M.
 */
export function mergeByMaterial(root: THREE.Object3D): MergedPart[] {
  root.updateMatrixWorld(true);
  const groups = new Map<THREE.Material, THREE.BufferGeometry[]>();
  root.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh || Array.isArray(mesh.material)) return;
    const g = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry.clone();
    g.applyMatrix4(mesh.matrixWorld);
    g.morphAttributes = {};
    const list = groups.get(mesh.material) ?? [];
    list.push(g);
    groups.set(mesh.material, list);
  });
  const out: MergedPart[] = [];
  for (const [material, geos] of groups) {
    // keep only attributes every piece has; recompute normals if any piece lacked them
    const common = Object.keys(geos[0].attributes).filter((a) => geos.every((g) => g.getAttribute(a)));
    const needNormals = !common.includes('normal');
    for (const g of geos) {
      for (const a of Object.keys(g.attributes)) if (!common.includes(a)) g.deleteAttribute(a);
      if (needNormals) g.computeVertexNormals();
    }
    const merged = geos.length === 1 ? geos[0] : mergeGeometries(geos, false);
    if (!merged) continue;
    merged.computeBoundingSphere();
    merged.computeBoundingBox();
    out.push({ geometry: merged, material });
  }
  return out;
}
