import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { baseOf, nextVersion } from './release.mjs';

describe('baseOf', () => {
  it('keeps the major and the minor of the version in VERSION', () => {
    assert.equal(baseOf('0.1.0'), '0.1');
    assert.equal(baseOf('2.14.7'), '2.14');
  });

  it('refuses what is not a version', () => {
    for (const bad of ['', '1', 'v1.2.3', '1.x.0', 'latest', '1.2.3-beta']) assert.throws(() => baseOf(bad), /version/i, bad);
  });

  it('accepts the VERSION file of this repository (the pipeline reads it)', () => {
    const version = readFileSync(new URL('../VERSION', import.meta.url), 'utf8').trim();

    assert.doesNotThrow(() => baseOf(version), version);
  });
});

describe('nextVersion', () => {
  it('starts at 0 when nothing was released for that major.minor', () => {
    assert.equal(nextVersion('0.1', []), '0.1.0');
  });

  it('goes one past the highest release, comparing the numbers (not the text)', () => {
    assert.equal(nextVersion('0.1', ['v0.1.0', 'v0.1.9', 'v0.1.10', 'v0.1.2']), '0.1.11');
  });

  it('does not count other minors or majors, nor tags that are not releases of the version', () => {
    const tags = ['v0.2.5', 'v1.1.9', 'v0.10.3', 'v0.1.3-beta', 'v0.1.x', 'nightly', 'v0.1.2'];
    assert.equal(nextVersion('0.1', tags), '0.1.3');
  });

  it('starts over when the minor goes up', () => {
    assert.equal(nextVersion('0.2', ['v0.1.7', 'v0.1.8']), '0.2.0');
  });

  it('ignores the spaces and the blank lines of a list read from a command', () => {
    assert.equal(nextVersion('0.1', ['', '  v0.1.4  ', '\n', 'v0.1.1']), '0.1.5');
  });
});
