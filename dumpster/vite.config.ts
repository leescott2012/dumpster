import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { readdirSync } from 'fs';
import type { Plugin } from 'vite';
const PHOTOS_DIR = path.join(__dirname, '..');
const IMAGE_EXTS = new Set(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.JPG', '.JPEG', '.PNG', '.GIF', '.WEBP']);

function photosPlugin(): Plugin {
  return {
    name: 'photos-static',
    configureServer(server) {
      // Serve photos from parent directory at /photos/
      server.middlewares.use('/photos', (req, res, next) => {
        const reqPath = decodeURIComponent(req.url || '/');
        if (reqPath === '/' || reqPath === '') {
          // Return JSON manifest of all image files
          try {
            const files = readdirSync(PHOTOS_DIR).filter((f) => {
              const ext = path.extname(f);
              return IMAGE_EXTS.has(ext);
            });
            res.setHeader('Content-Type', 'application/json');
            res.setHeader('Access-Control-Allow-Origin', '*');
            res.end(JSON.stringify(files));
          } catch {
            res.statusCode = 500;
            res.end('{}');
          }
          return;
        }
        // Serve individual files
        const filePath = path.join(PHOTOS_DIR, reqPath);
        import('fs').then(({ createReadStream, statSync }) => {
          try {
            const stat = statSync(filePath);
            const ext = path.extname(filePath).toLowerCase();
            const mime: Record<string, string> = {
              '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
              '.png': 'image/png', '.gif': 'image/gif',
              '.webp': 'image/webp',
            };
            res.setHeader('Content-Type', mime[ext] || 'application/octet-stream');
            res.setHeader('Content-Length', stat.size);
            res.setHeader('Cache-Control', 'public, max-age=3600');
            createReadStream(filePath).pipe(res);
          } catch {
            next();
          }
        });
      });
    },
  };
}

export default defineConfig({
  plugins: [react(), photosPlugin()],
  server: {
    fs: {
      allow: ['..'],
    },
  },
});
