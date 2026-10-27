import { defineConfig, type Plugin } from 'vite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The asset SDK lives one level above /game (assets/, config/). Serve it in dev and copy it
// into the production build so asset URLs come straight from config/asset_manifest.json.
const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SERVED_DIRS = ['assets', 'config', 'ui', 'references'];
const BUILD_COPY = ['assets/models', 'assets/materials', 'assets/images', 'ui/icons', 'references/original_images'];
const MIME: Record<string, string> = {
  '.glb': 'model/gltf-binary',
  '.json': 'application/json',
  '.png': 'image/png',
};

function projectAssets(): Plugin {
  return {
    name: 'ck-project-assets',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = decodeURIComponent((req.url ?? '').split('?')[0]);
        if (!SERVED_DIRS.includes(url.split('/')[1])) return next();
        const file = path.join(PROJECT_ROOT, url);
        if (!file.startsWith(PROJECT_ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return next();
        res.setHeader('Content-Type', MIME[path.extname(file)] ?? 'application/octet-stream');
        fs.createReadStream(file).pipe(res);
      });
    },
    writeBundle(options) {
      const out = options.dir ?? path.resolve('dist');
      for (const dir of BUILD_COPY) {
        fs.cpSync(path.join(PROJECT_ROOT, dir), path.join(out, dir), { recursive: true });
      }
    },
  };
}

export default defineConfig({
  plugins: [projectAssets()],
  server: { fs: { allow: [PROJECT_ROOT] } },
  build: { chunkSizeWarningLimit: 2500 },
});
