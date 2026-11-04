/**
 * A volume kept to what a media element accepts, 0 to 1. Something that is not a number (or not finite)
 * means "untouched", which is full volume.
 */
export function clampVolume(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 1;
}
