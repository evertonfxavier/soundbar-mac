import { describe, expect, it, type Mock } from 'vitest';
import { installMediaVolume, type MediaEnvironment } from '../../../src/infra/page/media-volume';
import { createPageWindow } from '../../support/page-window';

function setup() {
  const { win } = createPageWindow();
  // the volume the browser really plays at, read around the patch
  const native = Object.getOwnPropertyDescriptor(win.HTMLMediaElement.prototype, 'volume')!;
  const control = installMediaVolume(win);
  const actual = (element: HTMLMediaElement) => native.get!.call(element) as number;
  const make = (tag: 'audio' | 'video' = 'audio') => win.document.createElement(tag);
  return { win, control, actual, make };
}

/** A mutation observer reports on a later turn. */
const nextTurn = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('installMediaVolume', () => {
  it('scales the media that is already in the page', () => {
    const { win, control, actual, make } = setup();
    const audio = make();
    win.document.body.append(audio);

    control.setVolume(0.5);

    expect(actual(audio)).toBe(0.5);
  });

  it('lets the site go on reading the volume it believes it has', () => {
    const { win, control, actual, make } = setup();
    const audio = make();
    win.document.body.append(audio);
    control.setVolume(0.5);

    expect(audio.volume).toBe(1);
    audio.volume = 0.8;

    expect(audio.volume).toBe(0.8);
    expect(actual(audio)).toBeCloseTo(0.4);
  });

  it('gives the site its own volume back when the factor returns to full', () => {
    const { win, control, actual, make } = setup();
    const audio = make();
    win.document.body.append(audio);
    control.setVolume(0.5);
    audio.volume = 0.8;

    control.setVolume(1);

    expect(actual(audio)).toBeCloseTo(0.8);
  });

  it('keeps the factor to what a volume can be, and reads a bad one as untouched', () => {
    const { win, control, actual, make } = setup();
    const audio = make();
    win.document.body.append(audio);

    control.setVolume(-3);
    expect(actual(audio)).toBe(0);

    control.setVolume(9);
    expect(actual(audio)).toBe(1);

    control.setVolume(0.5);
    control.setVolume(Number.NaN);
    expect(actual(audio)).toBe(1);
  });

  it('scales the media that is added to the page later', async () => {
    const { win, control, actual, make } = setup();
    control.setVolume(0.5);

    const video = make('video');
    const wrapper = win.document.createElement('div');
    wrapper.append(video);
    win.document.body.append(wrapper); // nested: not the added node itself
    const direct = make();
    win.document.body.append(direct);
    await nextTurn();

    expect(actual(video)).toBe(0.5);
    expect(actual(direct)).toBe(0.5);
  });

  it('does not touch what is added while the factor is full', async () => {
    const { win, control, actual, make } = setup();
    control.setVolume(0.5);
    control.setVolume(1);
    const late = make();
    late.volume = 0.7;

    win.document.body.append(late);
    await nextTurn();

    expect(actual(late)).toBeCloseTo(0.7);
  });

  it('ignores the text and the comments that are added', async () => {
    const { win, control } = setup();
    control.setVolume(0.5);

    win.document.body.append('just text', win.document.createComment('note'));

    await expect(nextTurn()).resolves.toBeUndefined();
  });

  it('scales a media element the site created and plays without ever inserting it', () => {
    const { control, actual, make } = setup();
    const audio = make();
    control.setVolume(0.5);

    void audio.play();

    expect(actual(audio)).toBe(0.5);
  });

  it('plays through the original play, with what the site passed', () => {
    const { win } = createPageWindow();
    const originalPlay = win.HTMLMediaElement.prototype.play as Mock;
    installMediaVolume(win);
    const audio = win.document.createElement('audio');

    void audio.play();

    expect(originalPlay).toHaveBeenCalledOnce();
  });

  it('still lets the browser refuse a volume outside 0 to 1', () => {
    const { make } = setup();

    expect(() => {
      make().volume = 2;
    }).toThrow();
  });

  it('leaves an element alone when the browser refuses the scaled volume', () => {
    const { win } = createPageWindow();
    const proto = win.HTMLMediaElement.prototype;
    const real = Object.getOwnPropertyDescriptor(proto, 'volume')!;
    Object.defineProperty(proto, 'volume', {
      configurable: true,
      get: real.get!,
      set(value: number) {
        if (value === 0.25) throw new Error('refused');
        real.set!.call(this, value);
      },
    });
    const control = installMediaVolume(win);
    win.document.body.append(win.document.createElement('audio'));

    expect(() => control.setVolume(0.25)).not.toThrow();
  });

  it('does nothing, and does not fail, where the volume cannot be patched', () => {
    class Bare {}
    const env = {
      HTMLMediaElement: Bare,
      MutationObserver: class {},
      document: {},
    } as unknown as MediaEnvironment;

    expect(() => installMediaVolume(env).setVolume(0.5)).not.toThrow();
  });
});
