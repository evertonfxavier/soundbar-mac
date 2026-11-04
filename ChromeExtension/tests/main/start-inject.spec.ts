import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PAGE_TAG, toPageEnvelope } from '../../src/domain/protocol';
import { startInject } from '../../src/main/start-inject';
import { createPageWindow } from '../support/page-window';

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

const config = (volume: number, micMuted = false) => toPageEnvelope({ type: 'config', volume, micMuted });

describe('startInject', () => {
  it('scales the media of the page when the relay delivers the config', () => {
    const page = createPageWindow();
    const native = Object.getOwnPropertyDescriptor(page.win.HTMLMediaElement.prototype, 'volume')!;
    startInject(page.win);
    const audio = page.win.document.createElement('audio');
    page.win.document.body.append(audio);

    page.deliver(config(0.5));

    expect(native.get!.call(audio)).toBe(0.5);
  });

  it('silences the microphone of the page when the config says so, and reports it first', async () => {
    const page = createPageWindow();
    const native = Object.getOwnPropertyDescriptor(page.media.FakeTrack.prototype, 'enabled')!;
    startInject(page.win);

    await page.devices.getUserMedia();
    expect(page.posted).toEqual([{ [PAGE_TAG]: 1, type: 'mic', mic: true }]);

    const [track] = page.devices.next.getAudioTracks();
    page.deliver(config(1, true));
    expect(native.get!.call(track)).toBe(false);
  });

  it('says again that it holds the microphone when the relay asks, and says nothing if it holds none', async () => {
    const page = createPageWindow();
    startInject(page.win);

    page.deliver(toPageEnvelope({ type: 'resync' }));
    expect(page.posted).toEqual([]);

    await page.devices.getUserMedia();
    page.deliver(toPageEnvelope({ type: 'resync' }));

    expect(page.posted).toEqual([
      { [PAGE_TAG]: 1, type: 'mic', mic: true },
      { [PAGE_TAG]: 1, type: 'mic', mic: true },
    ]);
  });

  it('listens only to the frame itself, and only to its own kind of message', () => {
    const page = createPageWindow();
    const native = Object.getOwnPropertyDescriptor(page.win.HTMLMediaElement.prototype, 'volume')!;
    startInject(page.win);
    const audio = page.win.document.createElement('audio');
    page.win.document.body.append(audio);

    // another window posts a config
    page.win.dispatchEvent(new page.win.MessageEvent('message', { data: config(0.1) }));
    // the page itself posts something that is not ours, or that is not a config
    page.deliver({ type: 'config', volume: 0.1, micMuted: false });
    page.deliver(toPageEnvelope({ type: 'mic', mic: true }));
    page.deliver('hello');

    expect(native.get!.call(audio)).toBe(1);
  });

  it('is set up once per frame, however many times the script runs', () => {
    const page = createPageWindow();

    startInject(page.win);
    const patched = Object.getOwnPropertyDescriptor(page.win.HTMLMediaElement.prototype, 'volume');
    startInject(page.win);

    expect(Object.getOwnPropertyDescriptor(page.win.HTMLMediaElement.prototype, 'volume')).toEqual(patched);
  });
});
