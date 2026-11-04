// @ts-check
// Zips dist/ into ../build/SoundBar-Bridge-v<version>.zip, with manifest.json at the top of the archive: what the Chrome
// Web Store takes, and what "Load unpacked" wants after unzipping.
//
//   node scripts/package.mjs          (run `node scripts/build.mjs` first, or use `pnpm package`)
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export const zipName = (/** @type {string} */ version) => `SoundBar-Bridge-v${version}.zip`;

/** Every file under `dir`, relative to it, in a fixed order (so the same build gives the same archive). */
export function listFiles(/** @type {string} */ dir) {
  /** @type {string[]} */
  const files = [];
  const walk = (/** @type {string} */ current) => {
    for (const entry of readdirSync(current).sort()) {
      const path = join(current, entry);
      if (statSync(path).isDirectory()) walk(path);
      else files.push(relative(dir, path));
    }
  };
  walk(dir);
  return files;
}

/**
 * @param {{ distDir?: string, outDir?: string }} [options]
 * @returns the path of the zip
 */
export function packageExtension({ distDir = resolve(root, 'dist'), outDir = resolve(root, '../build') } = {}) {
  const manifest = JSON.parse(readFileSync(join(distDir, 'manifest.json'), 'utf8'));
  const target = join(outDir, zipName(String(manifest.version)));

  mkdirSync(outDir, { recursive: true });
  rmSync(target, { force: true });
  // `-X` leaves out the owner and the extra timestamps of the files; the list on stdin fixes the order.
  execFileSync('zip', ['-X', '-q', target, '-@'], { cwd: distDir, input: listFiles(distDir).join('\n') });
  return target;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    console.log(packageExtension());
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
