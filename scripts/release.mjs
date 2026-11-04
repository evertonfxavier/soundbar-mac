#!/usr/bin/env node
// The number of the next release, for the pipeline (.github/workflows/pipeline.yml). The tests are in release.test.mjs
// (`node --test scripts/release.test.mjs`).
//
// The VERSION file holds major.minor.patch, but only the first two numbers are chosen by hand: the patch of a release
// counts up from the releases already made (the tags v<major>.<minor>.<patch>), so a merge never needs a version bump.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

/** The major and the minor of a version ("0.1.0" → "0.1"): the part that is chosen by hand, in VERSION. */
export function baseOf(version) {
  const match = /^(\d+)\.(\d+)\.\d+$/.exec(version);
  if (!match) throw new Error(`Not a version (expected major.minor.patch): "${version}"`);
  return `${match[1]}.${match[2]}`;
}

/** The release after the ones already made for `base` ("0.1" + `v0.1.0`, `v0.1.3` → "0.1.4"): the patch counts up by itself. */
export function nextVersion(base, tags) {
  const prefix = `v${base}.`;
  const released = tags
    .map((tag) => tag.trim())
    .filter((tag) => tag.startsWith(prefix) && /^\d+$/.test(tag.slice(prefix.length)))
    .map((tag) => Number(tag.slice(prefix.length)));
  return `${base}.${released.length > 0 ? Math.max(...released) + 1 : 0}`;
}

// ----- command line: `release.mjs base 0.1.0`, `release.mjs next-version 0.1 < tags` ----------------------------------
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [command, ...args] = process.argv.slice(2);
  try {
    if (command === 'base') {
      console.log(baseOf(args[0] ?? ''));
    } else if (command === 'next-version') {
      console.log(nextVersion(args[0] ?? '', readFileSync(0, 'utf8').split('\n')));
    } else {
      throw new Error('Usage: release.mjs base <version> | next-version <major.minor> (tags on stdin)');
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
