#!/usr/bin/env node

/**
 * generate-icons.js
 * Generates PNG icon files for the DUMPSTER PWA app.
 *
 * Icons produced (saved to ../public/):
 *   - icon-192.png        (192x192, regular)
 *   - icon-512.png        (512x512, regular)
 *   - apple-touch-icon.png (180x180, no corner radius)
 *   - icon-maskable-192.png (192x192, maskable safe-zone padding)
 *   - icon-maskable-512.png (512x512, maskable safe-zone padding)
 *   - favicon.svg          (32x32, SVG)
 *
 * Design: Black background (#0a0a0a), gold bold "D" (#C8A96E), centered.
 *
 * Usage:
 *   npm install sharp --save-dev   # one-time
 *   npm run generate-icons         # or: node scripts/generate-icons.js
 */

import { writeFileSync, readFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PUBLIC_DIR = join(__dirname, '..', 'public');
const SVG_DIR = join(__dirname, 'svg-sources');

if (!existsSync(PUBLIC_DIR)) {
  mkdirSync(PUBLIC_DIR, { recursive: true });
}

// ---------------------------------------------------------------------------
// SVG generation
// ---------------------------------------------------------------------------

function createIconSVG(size, { maskable = false, cornerRadius = null } = {}) {
  const fontSize = maskable ? size * 0.50 : size * 0.68;
  const rx = cornerRadius !== null ? cornerRadius : Math.round(size * 0.15);
  const rectRx = maskable ? 0 : rx;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect fill="#0a0a0a" width="${size}" height="${size}" rx="${rectRx}"/>
  <text
    x="${size / 2}"
    y="${size / 2}"
    font-size="${fontSize}"
    font-weight="800"
    fill="#C8A96E"
    text-anchor="middle"
    dominant-baseline="central"
    font-family="'SF Pro Display', 'Helvetica Neue', 'Arial Black', system-ui, -apple-system, sans-serif"
  >D</text>
</svg>`;
}

const FAVICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect fill="#0a0a0a" width="32" height="32" rx="6"/>
  <text x="16" y="17" font-size="22" font-weight="800" fill="#C8A96E" text-anchor="middle" dominant-baseline="central" font-family="'SF Pro Display', 'Helvetica Neue', 'Arial Black', system-ui, -apple-system, sans-serif">D</text>
</svg>`;

// ---------------------------------------------------------------------------
// Icon specs
// ---------------------------------------------------------------------------

const icons = [
  { filename: 'icon-192.png',          svgSource: 'icon-192.svg',          size: 192, maskable: false },
  { filename: 'icon-512.png',          svgSource: 'icon-512.svg',          size: 512, maskable: false },
  { filename: 'apple-touch-icon.png',  svgSource: 'apple-touch-icon.svg',  size: 180, maskable: false, cornerRadius: 0 },
  { filename: 'icon-maskable-192.png', svgSource: 'icon-maskable-192.svg', size: 192, maskable: true },
  { filename: 'icon-maskable-512.png', svgSource: 'icon-maskable-512.svg', size: 512, maskable: true },
];

// ---------------------------------------------------------------------------
// sharp loader
// ---------------------------------------------------------------------------

async function loadSharp() {
  try {
    return (await import('sharp')).default;
  } catch {
    return null;
  }
}

async function installAndLoadSharp() {
  console.log('  sharp is not installed. Installing sharp...');
  const { execSync } = await import('child_process');
  try {
    execSync('npm install sharp --save-dev', {
      cwd: join(__dirname, '..'),
      stdio: 'inherit',
    });
    console.log('  sharp installed successfully.\n');
    // Clear module cache and re-import
    return (await import('sharp')).default;
  } catch (err) {
    console.error(`  Failed to install sharp: ${err.message}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  console.log('');
  console.log('  DUMPSTER Icon Generator');
  console.log('  =======================');
  console.log(`  Output: ${PUBLIC_DIR}`);
  console.log('');

  // 1. Write favicon.svg (always works, no deps needed)
  writeFileSync(join(PUBLIC_DIR, 'favicon.svg'), FAVICON_SVG);
  console.log('  [OK] favicon.svg');

  // 2. Try to load sharp
  let sharp = await loadSharp();
  if (!sharp) {
    sharp = await installAndLoadSharp();
  }

  if (!sharp) {
    // Fallback: write SVG files instead of PNGs
    console.log('');
    console.log('  Could not load sharp. Writing SVG fallbacks...');
    console.log('');
    for (const icon of icons) {
      const svgContent = getSVGContent(icon);
      const svgFilename = icon.filename.replace('.png', '.svg');
      writeFileSync(join(PUBLIC_DIR, svgFilename), svgContent);
      console.log(`  [SVG] ${svgFilename} (${icon.size}x${icon.size})`);
    }
    console.log('');
    console.log('  To generate proper PNGs:');
    console.log('    npm install sharp --save-dev');
    console.log('    npm run generate-icons');
    console.log('');
    return;
  }

  // 3. Generate PNGs
  console.log('');
  let allOk = true;
  for (const icon of icons) {
    const svgContent = getSVGContent(icon);
    const svgBuffer = Buffer.from(svgContent);
    const outPath = join(PUBLIC_DIR, icon.filename);

    try {
      await sharp(svgBuffer, { density: 300 })
        .resize(icon.size, icon.size)
        .png()
        .toFile(outPath);

      const label = icon.maskable ? 'maskable' : 'regular';
      console.log(`  [OK] ${icon.filename}  ${icon.size}x${icon.size}  (${label})`);
    } catch (err) {
      console.error(`  [FAIL] ${icon.filename}: ${err.message}`);
      allOk = false;
    }
  }

  console.log('');
  if (allOk) {
    console.log('  All icons generated successfully!');
  } else {
    console.log('  Some icons failed. Check errors above.');
  }
  console.log('');
}

/**
 * Get SVG content for an icon, preferring pre-built SVG source files
 * over dynamically generated ones.
 */
function getSVGContent(icon) {
  const svgPath = join(SVG_DIR, icon.svgSource);
  if (existsSync(svgPath)) {
    return readFileSync(svgPath, 'utf-8');
  }
  return createIconSVG(icon.size, {
    maskable: icon.maskable,
    cornerRadius: icon.cornerRadius,
  });
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
