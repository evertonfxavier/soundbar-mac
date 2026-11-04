import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { installMicrophone, type MicrophoneEnvironment } from '../../../src/infra/page/microphone';
import { createFakeMedia } from '../../support/fake-media';

function setup(options: { mediaDevices?: boolean } = {}) {
  const media = createFakeMedia();
  const { FakeTrack, FakeStream, FakeMediaDevices } = media;
  const devices = new FakeMediaDevices();
  // the `enabled` the browser really has, read around the patch
  const native = Object.getOwnPropertyDescriptor(FakeTrack.prototype, 'enabled')!;
  const changes: boolean[] = [];

  const env = {
    MediaStreamTrack: FakeTrack,
    MediaStream: FakeStream,
    MediaDevices: options.mediaDevices === false ? undefined : FakeMediaDevices,
    navigator: { mediaDevices: options.mediaDevices === false ? undefined : devices },
  } as unknown as MicrophoneEnvironment;
  const control = installMicrophone(env, (mic) => changes.push(mic));

  const really = (track: InstanceType<typeof FakeTrack>) => native.get!.call(track) as boolean;
  /** The page asks for the microphone. */
  const open = async (track = new FakeTrack()) => {
    devices.next = new FakeStream([track]);
    await devices.getUserMedia();
    return track;
  };
  return { media, devices, changes, control, really, open, FakeTrack, FakeStream };
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('installMicrophone: following the microphone', () => {
  it('reports the microphone as soon as the page gets an audio track', async () => {
    const { open, changes } = setup();

    await open();

    expect(changes).toEqual([true]);
  });

  it('does not report the camera, or another microphone for the same page again', async () => {
    const { open, changes, FakeTrack } = setup();
    const video = new FakeTrack();
    video.kind = 'video';

    await open(video);
    expect(changes).toEqual([]);

    await open();
    await open();
    expect(changes).toEqual([true]);
  });

  it('reports the end of the microphone when its track ends', async () => {
    const { open, changes } = setup();
    const track = await open();

    track.stop();
    track.dispatchEvent(new Event('ended'));

    expect(changes).toEqual([true, false]);
  });

  it('notices a track that was stopped, which fires no event, at the next poll', async () => {
    const { open, changes } = setup();
    const track = await open();

    track.stop();
    expect(changes).toEqual([true]);
    vi.advanceTimersByTime(2000);

    expect(changes).toEqual([true, false]);
  });

  it('keeps the microphone while any track of the page is still live', async () => {
    const { open, changes } = setup();
    const first = await open();
    await open();

    first.stop();
    vi.advanceTimersByTime(2000);

    expect(changes).toEqual([true]);
  });
});

describe('installMicrophone: muting', () => {
  it('silences the real track, while the site still reads what it set', async () => {
    const { open, control, really } = setup();
    const track = await open();

    control.setMuted(true);

    expect(really(track)).toBe(false);
    expect(track.enabled).toBe(true);
  });

  it('does not let the site unmute what SoundBar muted, and keeps what the site wants for later', async () => {
    const { open, control, really } = setup();
    const track = await open();
    control.setMuted(true);

    track.enabled = false; // the site mutes its own button
    track.enabled = true; // …then unmutes it

    expect(really(track)).toBe(false);
    track.enabled = false;
    control.setMuted(false);
    expect(really(track)).toBe(false); // the site wanted it off
    expect(track.enabled).toBe(false);
  });

  it('restores the track when unmuted', async () => {
    const { open, control, really } = setup();
    const track = await open();
    control.setMuted(true);

    control.setMuted(false);

    expect(really(track)).toBe(true);
  });

  it('silences a microphone the page opens after the mute', async () => {
    const { open, control, really } = setup();
    control.setMuted(true);

    const track = await open();

    expect(really(track)).toBe(false);
    expect(track.enabled).toBe(true);
  });

  it('does not interfere with tracks the page did not get from the microphone', () => {
    const { FakeTrack, control, really } = setup();
    const other = new FakeTrack(); // a track the page made some other way
    control.setMuted(true);

    other.enabled = false;
    other.enabled = true;

    expect(really(other)).toBe(true);
  });
});

describe('installMicrophone: copies', () => {
  it('follows a clone of a track, with what the site wanted rather than what is muted', async () => {
    const { open, control, really } = setup();
    const track = await open();
    track.enabled = false;
    control.setMuted(true);

    const copy = track.clone();

    expect(copy.enabled).toBe(false);
    control.setMuted(false);
    expect(really(copy)).toBe(false);
    copy.enabled = true;
    expect(really(copy)).toBe(true);
  });

  it('leaves alone the clone of a track that is not a microphone', () => {
    const { FakeTrack, control, really } = setup();
    const other = new FakeTrack();
    control.setMuted(true);

    const copy = other.clone();

    expect(really(copy)).toBe(true);
  });

  it('follows the tracks of a cloned stream', async () => {
    const { open, control, really, changes, FakeStream } = setup();
    const track = await open();
    const stream = new FakeStream([track]);
    control.setMuted(true);

    const copy = stream.clone();
    const [copied] = copy.getAudioTracks();

    expect(really(copied!)).toBe(false);
    control.setMuted(false);
    expect(really(copied!)).toBe(true);
    expect(changes).toEqual([true]);
  });

  it('leaves alone the clone of a stream with no microphone in it', () => {
    const { FakeStream, FakeTrack, control, really } = setup();
    const stream = new FakeStream([new FakeTrack()]);
    control.setMuted(true);

    const [copied] = stream.clone().getAudioTracks();

    expect(really(copied!)).toBe(true);
  });
});

describe('installMicrophone: saying it again', () => {
  it('reports a microphone the page holds, even though it was reported before', async () => {
    const { open, control, changes } = setup();
    await open();
    expect(changes).toEqual([true]);

    control.resync();

    expect(changes).toEqual([true, true]);
  });

  it('says nothing for a page with no microphone: that is what the listener assumes', () => {
    const { control, changes } = setup();

    control.resync();

    expect(changes).toEqual([]);
  });

  it('says nothing once the microphone is gone, even before the next poll notices it', async () => {
    const { open, control, changes } = setup();
    const track = await open();
    track.stop();

    control.resync();

    expect(changes).toEqual([true]);
  });

  it('keeps the follow-up changes honest: the end of the microphone is still reported once', async () => {
    const { open, control, changes } = setup();
    const track = await open();
    control.resync();

    track.stop();
    track.dispatchEvent(new Event('ended'));

    expect(changes).toEqual([true, true, false]);
  });
});

describe('installMicrophone: where there is nothing to follow', () => {
  it('works where the page cannot capture at all (no MediaDevices)', () => {
    const { control, FakeTrack, really } = setup({ mediaDevices: false });
    const track = new FakeTrack();

    expect(() => control.setMuted(true)).not.toThrow();
    expect(() => control.resync()).not.toThrow();
    expect(really(track)).toBe(true);
  });

  it('does nothing, and does not fail, where `enabled` cannot be patched', () => {
    class Bare {}
    const env = { MediaStreamTrack: Bare, MediaStream: class {}, navigator: {} } as unknown as MicrophoneEnvironment;
    const control = installMicrophone(env, () => undefined);

    expect(() => control.setMuted(true)).not.toThrow();
    expect(() => control.resync()).not.toThrow();
  });
});
