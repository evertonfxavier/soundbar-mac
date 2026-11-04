import { JSDOM } from 'jsdom';
import { vi } from 'vitest';
import type { InjectEnvironment } from '../../src/main/start-inject';
import { createFakeMedia, type FakeMedia } from './fake-media';

export type PageGlobal = InjectEnvironment & Window & typeof globalThis;

export interface PageWindow {
  win: PageGlobal;
  media: FakeMedia;
  devices: InstanceType<FakeMedia['FakeMediaDevices']>;
  /** What the page has posted to itself (window.postMessage is not delivered in jsdom, only recorded). */
  posted: unknown[];
  /** Delivers a message to the page as if the frame had posted it to itself. */
  deliver(data: unknown): void;
}

/**
 * A page of its own: a fresh jsdom window (so the prototypes one spec patches are not patched in the next), with the
 * media classes jsdom lacks added. jsdom's `HTMLMediaElement.play` is "not implemented" (it only reports an error),
 * so it is replaced by a stub.
 */
export function createPageWindow(): PageWindow {
  const dom = new JSDOM('<!doctype html><body></body>', { pretendToBeVisual: true });
  const win = dom.window as unknown as PageGlobal;
  const media = createFakeMedia();
  const devices = new media.FakeMediaDevices();

  win.HTMLMediaElement.prototype.play = vi.fn(() => Promise.resolve());
  Object.assign(win, {
    MediaStreamTrack: media.FakeTrack,
    MediaStream: media.FakeStream,
    MediaDevices: media.FakeMediaDevices,
  });
  Object.defineProperty(win.navigator, 'mediaDevices', { value: devices });

  const posted: unknown[] = [];
  win.postMessage = ((message: unknown) => {
    posted.push(message);
  }) as Window['postMessage'];

  return {
    win,
    media,
    devices,
    posted,
    deliver: (data) => win.dispatchEvent(new win.MessageEvent('message', { data, source: win })),
  };
}
