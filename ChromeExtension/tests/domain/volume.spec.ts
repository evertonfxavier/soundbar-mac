import { describe, expect, it } from 'vitest';
import { clampVolume } from '../../src/domain/volume';

describe('clampVolume', () => {
  it('keeps what is already between 0 and 1', () => {
    for (const volume of [0, 0.25, 0.5, 1]) expect(clampVolume(volume)).toBe(volume);
  });

  it('brings what is outside back to the nearest end', () => {
    expect(clampVolume(-0.4)).toBe(0);
    expect(clampVolume(7)).toBe(1);
  });

  it('reads what is not a usable number as untouched: full volume', () => {
    for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY])
      expect(clampVolume(bad)).toBe(1);
  });
});
