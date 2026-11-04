// @ts-check
// Builds the extension into dist/, ready to be loaded in Chrome ("Load unpacked") or zipped (scripts/package.mjs):
//   - the three scripts of src/main, each bundled by esbuild into one file with no imports (a content script
//     cannot be an ES module);
//   - manifest.json, from manifest.base.json with the version of this build;
//   - everything in public/ (the icons).
//
//   node scripts/build.mjs            one build
//   node scripts/build.mjs --watch    rebuild when a source changes
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build, context } from 'esbuild';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** The scripts the manifest points at: output name → source. */
export const ENTRIES = {
  background: 'src/main/background.ts',
  inject: 'src/main/inject.ts',
  relay: 'src/main/relay.ts',
};

/** Chrome takes one to four numbers, each up to 65535. */
export function assertChromeVersion(/** @type {string} */ version) {
  if (!/^\d+(\.\d+){0,3}$/.test(version) || version.split('.').some((part) => Number(part) > 65535)) {
    throw new Error(`Not a version Chrome accepts (one to four numbers up to 65535): "${version}"`);
  }
}

/**
 * The version of this build: SOUNDBAR_VERSION (set by the pipeline) or the VERSION file at the root of the repository,
 * the one number the app and the extension share.
 */
export function resolveVersion(/** @type {NodeJS.ProcessEnv} */ env = process.env) {
  const version = (env.SOUNDBAR_VERSION ?? readFileSync(resolve(root, '../VERSION'), 'utf8')).trim();
  assertChromeVersion(version);
  return version;
}

/** The text of manifest.json: the base manifest and `version`. */
export function makeManifest(/** @type {string} */ baseText, /** @type {string} */ version) {
  assertChromeVersion(version);
  const { manifest_version, name, ...rest } = /** @type {Record<string, unknown>} */ (JSON.parse(baseText));
  return `${JSON.stringify({ manifest_version, name, version, ...rest }, null, 2)}\n`;
}

/**
 * @param {{ outDir?: string, version?: string, watch?: boolean }} [options]
 */
export async function buildExtension({
  outDir = resolve(root, 'dist'),
  version = resolveVersion(),
  watch = false,
} = {}) {
  const manifest = makeManifest(readFileSync(resolve(root, 'manifest.base.json'), 'utf8'), version);

  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  writeFileSync(resolve(outDir, 'manifest.json'), manifest);
  if (existsSync(resolve(root, 'public'))) cpSync(resolve(root, 'public'), outDir, { recursive: true });

  /** @type {import('esbuild').BuildOptions} */
  const options = {
    entryPoints: Object.fromEntries(Object.entries(ENTRIES).map(([name, file]) => [name, resolve(root, file)])),
    outdir: outDir,
    tsconfig: resolve(root, 'tsconfig.json'),
    bundle: true,
    format: 'iife',
    platform: 'browser',
    target: 'chrome116', // minimum_chrome_version in the manifest
    legalComments: 'none',
    // Not minified: the extension is a few kilobytes, and anyone reviewing it (the Chrome Web Store included) can read it.
    minify: false,
    sourcemap: watch ? 'inline' : false,
    logLevel: 'info',
  };

  if (watch) {
    const session = await context(options);
    await session.watch();
    console.log(`Watching ${Object.values(ENTRIES).join(', ')} → ${outDir}`);
    return;
  }
  await build(options);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await buildExtension({ watch: process.argv.includes('--watch') });
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
