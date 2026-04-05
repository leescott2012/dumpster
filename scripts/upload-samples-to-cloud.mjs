/**
 * Uploads all sample photos to Vercel Blob via the deployed API,
 * then rewrites public/sample-photos.json with cloud URLs.
 */
import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dir, '..');
const SAMPLE_DIR = join(ROOT, 'public', 'sample-photos');
const JSON_PATH = join(ROOT, 'public', 'sample-photos.json');
const API = 'https://dumpster-omega.vercel.app/api/upload-photo';

const samples = JSON.parse(readFileSync(JSON_PATH, 'utf8'));

let updated = 0;
const results = [];

for (const photo of samples) {
  // Skip if already a cloud URL
  if (photo.url.startsWith('http')) {
    console.log(`SKIP (already cloud): ${photo.filename}`);
    results.push(photo);
    continue;
  }

  const filePath = join(SAMPLE_DIR, photo.filename);
  let fileBytes;
  try {
    fileBytes = readFileSync(filePath);
  } catch {
    console.warn(`MISSING: ${photo.filename}`);
    results.push(photo);
    continue;
  }

  // Detect content type
  const ext = photo.filename.split('.').pop()?.toLowerCase();
  const typeMap = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', mov: 'video/quicktime', mp4: 'video/mp4' };
  const contentType = typeMap[ext] || 'image/jpeg';

  try {
    const res = await fetch(API, {
      method: 'POST',
      headers: {
        'content-type': contentType,
        'x-filename': encodeURIComponent(photo.filename),
      },
      body: fileBytes,
    });
    if (!res.ok) {
      const txt = await res.text();
      console.error(`FAIL ${photo.filename}: ${res.status} ${txt}`);
      results.push(photo);
      continue;
    }
    const { url } = await res.json();
    console.log(`OK ${photo.filename} → ${url}`);
    results.push({ ...photo, url });
    updated++;
  } catch (err) {
    console.error(`ERROR ${photo.filename}:`, err.message);
    results.push(photo);
  }
}

writeFileSync(JSON_PATH, JSON.stringify(results, null, 2));
console.log(`\nDone. ${updated} photos uploaded to cloud.`);
