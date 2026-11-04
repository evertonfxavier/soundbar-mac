/* eslint-disable @typescript-eslint/unbound-method -- patching a prototype means taking its accessors and methods off
   it and calling them again with the right `this` (`.call(element)`): that is the point of this file. */
import { clampVolume } from '../../domain/volume';

/** What the page provides: handed in, so a spec can supply its own. */
export interface MediaEnvironment {
  HTMLMediaElement: typeof HTMLMediaElement;
  MutationObserver: typeof MutationObserver;
  document: Document;
}

export interface MediaVolumeControl {
  /** Scales the volume of every <audio> and <video> of the page by `volume` (0 to 1). */
  setVolume(volume: number): void;
}

const isElement = (node: Node): node is Element => node.nodeType === 1;

/**
 * Scales the volume of the media of the page by a factor, without the page noticing: the site still reads, and
 * writes, the volume it believes it has (a player slider keeps working).
 *
 * It replaces `HTMLMediaElement.prototype.volume` and `.play`, so it has to run in the page's own JS world,
 * before the page's scripts.
 */
export function installMediaVolume(env: MediaEnvironment): MediaVolumeControl {
  const proto = env.HTMLMediaElement.prototype;
  const original = Object.getOwnPropertyDescriptor(proto, 'volume');
  if (!original?.get || !original.set) return { setVolume: () => undefined };
  const getVolume = original.get;
  const setVolume = original.set;

  let factor = 1;
  const siteVolume = new WeakMap<HTMLMediaElement, number>(); // element → the volume the site believes it set
  const tracked = new Set<WeakRef<HTMLMediaElement>>();

  function track(element: HTMLMediaElement): void {
    if (siteVolume.has(element)) return;
    siteVolume.set(element, getVolume.call(element) as number);
    tracked.add(new WeakRef(element));
  }

  function apply(element: HTMLMediaElement): void {
    try {
      setVolume.call(element, (siteVolume.get(element) ?? 1) * factor);
    } catch {
      // the element refused (detached, or a getter that throws): leave it be
    }
  }

  function applyAll(): void {
    for (const ref of tracked) {
      const element = ref.deref();
      if (element) apply(element);
      else tracked.delete(ref);
    }
  }

  Object.defineProperty(proto, 'volume', {
    configurable: true,
    enumerable: original.enumerable ?? false,
    get(this: HTMLMediaElement): number {
      return siteVolume.get(this) ?? (getVolume.call(this) as number);
    },
    set(this: HTMLMediaElement, value: number) {
      if (!(value >= 0 && value <= 1)) {
        setVolume.call(this, value); // let the browser throw, as it would
        return;
      }
      if (!siteVolume.has(this)) tracked.add(new WeakRef(this));
      siteVolume.set(this, value);
      setVolume.call(this, value * factor);
    },
  });

  const originalPlay = proto.play;
  proto.play = function (this: HTMLMediaElement, ...args: Parameters<typeof originalPlay>) {
    track(this);
    apply(this);
    return originalPlay.apply(this, args);
  };

  let observer: MutationObserver | null = null;

  /** Media added to the page later is scaled as it appears. */
  function ensureObserver(): void {
    if (observer) return;
    observer = new env.MutationObserver((records) => {
      if (factor === 1) return;
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (!isElement(node)) continue;
          const found =
            node instanceof env.HTMLMediaElement ? [node] : node.querySelectorAll<HTMLMediaElement>('audio,video');
          for (const element of found) {
            track(element);
            apply(element);
          }
        }
      }
    });
    observer.observe(env.document, { childList: true, subtree: true });
  }

  return {
    setVolume(volume) {
      factor = clampVolume(volume);
      ensureObserver();
      env.document.querySelectorAll<HTMLMediaElement>('audio,video').forEach(track);
      applyAll();
    },
  };
}
