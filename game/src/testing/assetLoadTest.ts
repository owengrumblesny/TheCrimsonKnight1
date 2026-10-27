import * as THREE from 'three';
import { HERO_ID, heroClips, registry } from '../data/registry';

export interface LoadTestResult {
  total: number;
  passed: number;
  failed: { id: string; error: string }[];
  images: { total: number; failed: string[] };
  hero: { skinnedMeshes: number; bones: number; clips: number; expectedClips: number; missingClips: string[] } | null;
  ms: number;
}

declare global {
  interface Window {
    __CK_TEST__?: LoadTestResult;
  }
}

/**
 * Loads every asset in config/asset_manifest.json through the game's own registry and checks
 * each yields renderable meshes; checks the hero has SkinnedMesh + bones + every clip listed in
 * config/crx9_clips.json. Open the game with ?test=assets — result goes to window.__CK_TEST__.
 */
export async function runAssetLoadTest(): Promise<LoadTestResult> {
  const t0 = performance.now();
  const failed: LoadTestResult['failed'] = [];
  const ids = registry.entries.map((e) => e.id);
  const queue = [...ids];
  const worker = async () => {
    for (let id = queue.shift(); id; id = queue.shift()) {
      try {
        const obj = await registry.instance(id);
        let meshes = 0;
        obj.traverse((o) => {
          if ((o as THREE.Mesh).isMesh) meshes++;
        });
        const size = new THREE.Box3().setFromObject(obj).getSize(new THREE.Vector3());
        if (!meshes) throw new Error('no meshes');
        if (!(size.x > 0 && size.y > 0 && size.z > 0)) throw new Error('degenerate bounds');
      } catch (e) {
        failed.push({ id, error: String((e as Error)?.message ?? e) });
      }
    }
  };
  await Promise.all(Array.from({ length: 8 }, worker));

  // every registered PNG (material textures, UI icons, concept boards, board cut-outs + frames) must load and decode
  const imgs = [...registry.textures, ...registry.icons, ...registry.artwork,
    ...registry.boardImages.flatMap((b) => [b, ...(b.frames ?? []).map((file) => ({ id: b.id, file }))])];
  const badImgs: string[] = [];
  await Promise.all(imgs.map((e) => new Promise<void>((resolve) => {
    const img = new Image();
    img.onload = () => {
      if (!img.naturalWidth) badImgs.push(e.file);
      resolve();
    };
    img.onerror = () => {
      badImgs.push(e.file);
      resolve();
    };
    img.src = '/' + e.file;
  })));

  let hero: LoadTestResult['hero'] = null;
  try {
    const gltf = await registry.gltf(HERO_ID);
    let skinned = 0;
    let bones = 0;
    gltf.scene.traverse((o) => {
      if ((o as THREE.SkinnedMesh).isSkinnedMesh) skinned++;
      if ((o as THREE.Bone).isBone) bones++;
    });
    const names = new Set(gltf.animations.map((a) => a.name));
    const missing = heroClips.map((c) => c.name).filter((n) => !names.has(n));
    hero = { skinnedMeshes: skinned, bones, clips: gltf.animations.length, expectedClips: heroClips.length, missingClips: missing };
    if (!skinned || !bones || missing.length) failed.push({ id: HERO_ID, error: 'rig/clip check failed' });
  } catch (e) {
    failed.push({ id: HERO_ID, error: String(e) });
  }

  const result: LoadTestResult = { total: ids.length, passed: ids.length - failed.filter((f) => ids.includes(f.id)).length, failed, images: { total: imgs.length, failed: badImgs }, hero, ms: Math.round(performance.now() - t0) };
  window.__CK_TEST__ = result;
  const pre = document.createElement('pre');
  pre.style.cssText = 'position:fixed;inset:0;margin:0;padding:24px;background:#0b0b10;color:#e8dede;font:13px ui-monospace,monospace;overflow:auto';
  pre.textContent = `ASSET LOAD TEST — ${failed.length ? 'FAIL' : 'PASS'}\n\n` + JSON.stringify(result, null, 2);
  document.body.appendChild(pre);
  console.info('[CK] asset load test', result);
  return result;
}
