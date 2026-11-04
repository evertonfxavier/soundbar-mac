import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ENTRIES, assertChromeVersion, buildExtension, makeManifest, resolveVersion } from '../../scripts/build.mjs';
import { listFiles, packageExtension, zipName } from '../../scripts/package.mjs';

const root = resolve(import.meta.dirname, '../..');
const read = (path: string) => readFileSync(path, 'utf8');

interface Manifest {
  manifest_version: number;
  version: string;
  minimum_chrome_version: string;
  icons: Record<string, string>;
  action: { default_icon: Record<string, string> };
  background: { service_worker: string };
  content_scripts: { js: string[]; world?: string }[];
}

describe('the build of the extension', () => {
  let out: string;
  let dist: string;
  let manifest: Manifest;

  beforeAll(async () => {
    out = mkdtempSync(join(tmpdir(), 'soundbar-build-'));
    dist = join(out, 'dist');
    await buildExtension({ outDir: dist, version: '1.2.3' });
    manifest = JSON.parse(read(join(dist, 'manifest.json'))) as Manifest;
  });

  afterAll(() => {
    rmSync(out, { recursive: true, force: true });
  });

  it('writes a manifest of version 3 with the version of the build', () => {
    expect(manifest.manifest_version).toBe(3);
    expect(manifest.version).toBe('1.2.3');
  });

  it('leaves no file the manifest points at missing', () => {
    const referenced = [
      manifest.background.service_worker,
      ...manifest.content_scripts.flatMap((script) => script.js),
      ...Object.values(manifest.icons),
      ...Object.values(manifest.action.default_icon),
    ];

    expect(referenced.length).toBeGreaterThan(5);
    for (const file of referenced) expect(existsSync(join(dist, file)), file).toBe(true);
  });

  it('builds exactly the scripts of ENTRIES, and the manifest uses all of them', () => {
    const referenced = [manifest.background.service_worker, ...manifest.content_scripts.flatMap((s) => s.js)].sort();

    expect(referenced).toEqual(
      Object.keys(ENTRIES)
        .map((name) => `${name}.js`)
        .sort(),
    );
  });

  it('bundles every script into one file with no imports (a content script cannot be a module)', () => {
    for (const name of Object.keys(ENTRIES)) {
      const code = read(join(dist, `${name}.js`));
      expect(code, name).not.toMatch(/^\s*(import|export)\s/m);
      expect(code, name).not.toMatch(/\brequire\(/);
    }
  });

  it('runs only the page-world script in the page world', () => {
    const inMainWorld = manifest.content_scripts
      .filter((script) => script.world === 'MAIN')
      .flatMap((script) => script.js);

    expect(inMainWorld).toEqual(['inject.js']);
  });

  it('targets the Chrome the manifest asks for as its minimum', () => {
    const source = read(join(root, 'scripts/build.mjs'));

    expect(source).toContain(`target: 'chrome${manifest.minimum_chrome_version}'`);
  });

  it('copies the icons of public/', () => {
    for (const size of [16, 32, 48, 128])
      expect(existsSync(join(dist, `icons/icon-${size}.png`)), String(size)).toBe(true);
  });

  describe('the zip', () => {
    it('has manifest.json at the top, and every file of the build, in a fixed order', () => {
      const target = packageExtension({ distDir: dist, outDir: join(out, 'zips') });

      expect(target.endsWith(zipName('1.2.3'))).toBe(true);
      const listed = execFileSync('unzip', ['-Z1', target], { encoding: 'utf8' }).trim().split('\n');
      expect(listed).toEqual(listFiles(dist));
      expect(listed).toContain('manifest.json');
      expect(listed).toContain('icons/icon-128.png');
    });

    it('is named after the version in the manifest', () => {
      expect(zipName('0.4.2')).toBe('SoundBar-Bridge-v0.4.2.zip');
    });
  });
});

describe('the version of a build', () => {
  it('is the one in SOUNDBAR_VERSION when the pipeline sets it', () => {
    expect(resolveVersion({ SOUNDBAR_VERSION: '2.0.9' })).toBe('2.0.9');
  });

  it('is the one in the VERSION file of the repository otherwise', () => {
    expect(resolveVersion({})).toBe(read(join(root, '../VERSION')).trim());
  });

  it('accepts what Chrome accepts: one to four numbers, each up to 65535', () => {
    for (const good of ['1', '0.1.7', '1.2.3.4', '65535.0.0'])
      expect(() => assertChromeVersion(good), good).not.toThrow();
  });

  it('refuses the rest', () => {
    for (const bad of ['', 'v0.1.7', '1.2.3.4.5', '1.x', '65536.0.0', '-1', '1.0.0-beta']) {
      expect(() => assertChromeVersion(bad), bad).toThrow(/version/i);
    }
  });

  it('is stamped into the manifest, which keeps its other keys', () => {
    const text = makeManifest(JSON.stringify({ manifest_version: 3, name: 'X', permissions: ['tabs'] }), '0.9.1');

    expect(JSON.parse(text)).toEqual({ manifest_version: 3, name: 'X', version: '0.9.1', permissions: ['tabs'] });
    expect(text.endsWith('}\n')).toBe(true);
  });

  it('is checked before it is stamped', () => {
    expect(() => makeManifest('{}', 'nope')).toThrow(/version/i);
  });

  it('stops the build of a bad version before it writes anything', async () => {
    const out = mkdtempSync(join(tmpdir(), 'soundbar-bad-'));
    writeFileSync(join(out, 'keep.txt'), 'x');
    try {
      await expect(buildExtension({ outDir: join(out, 'dist'), version: 'bad' })).rejects.toThrow(/version/i);
      expect(existsSync(join(out, 'dist'))).toBe(false);
    } finally {
      rmSync(out, { recursive: true, force: true });
    }
  });
});
