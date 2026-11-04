/* eslint-disable @typescript-eslint/unbound-method -- patching a prototype means taking its accessors and methods off
   it and calling them again with the right `this` (`.call(track)`): that is the point of this file. */

/** What the page provides: handed in, so a spec can supply its own. */
export interface MicrophoneEnvironment {
  MediaStreamTrack: typeof MediaStreamTrack;
  MediaStream: typeof MediaStream;
  /** Absent where the page cannot capture (insecure contexts). */
  MediaDevices?: typeof MediaDevices | undefined;
  navigator: Pick<Navigator, 'mediaDevices'>;
}

export interface MicrophoneControl {
  /** Silences (or restores) every microphone track the page opened. */
  setMuted(muted: boolean): void;
  /** Says again that the page holds a microphone, if it does: whoever listens may have forgotten it. */
  resync(): void;
}

const POLL_MS = 2000;

/**
 * Follows the microphone tracks the page opens through `getUserMedia` (and their clones), tells `onChange` when the
 * page starts or stops holding one, and lets SoundBar silence them.
 *
 * Muting sets `enabled = false` on the real track, while `enabled` keeps answering what the site set (the site's
 * own mute button keeps working, and does not "unmute" us).
 */
export function installMicrophone(env: MicrophoneEnvironment, onChange: (mic: boolean) => void): MicrophoneControl {
  const trackProto = env.MediaStreamTrack.prototype;
  const original = Object.getOwnPropertyDescriptor(trackProto, 'enabled');
  if (!original?.get || !original.set) return { setMuted: () => undefined, resync: () => undefined };
  const getEnabled = original.get;
  const setEnabled = original.set;

  let muted = false;
  let lastMic = false;
  let timer: ReturnType<typeof setInterval> | undefined;
  const micTracks = new WeakSet<MediaStreamTrack>();
  const live = new Set<WeakRef<MediaStreamTrack>>();
  const wantEnabled = new WeakMap<MediaStreamTrack, boolean>(); // track → what the site wants `enabled` to be

  Object.defineProperty(trackProto, 'enabled', {
    configurable: true,
    enumerable: original.enumerable ?? false,
    get(this: MediaStreamTrack): boolean {
      return wantEnabled.get(this) ?? (getEnabled.call(this) as boolean);
    },
    set(this: MediaStreamTrack, value: boolean) {
      if (!micTracks.has(this)) {
        setEnabled.call(this, value);
        return;
      }
      wantEnabled.set(this, !!value);
      setEnabled.call(this, !!value && !muted);
    },
  });

  function micActive(): boolean {
    for (const ref of live) {
      const track = ref.deref();
      if (track?.readyState === 'live') return true;
      live.delete(ref);
    }
    return false;
  }

  function report(): void {
    const active = micActive();
    if (active === lastMic) return;
    lastMic = active;
    onChange(active);
  }

  /** `want` is what the site wants `enabled` to be: a clone inherits that, not the muted real state. */
  function trackMic(track: MediaStreamTrack, want?: boolean): void {
    if (track.kind !== 'audio' || micTracks.has(track)) return;
    micTracks.add(track);
    wantEnabled.set(track, want ?? (getEnabled.call(track) as boolean));
    live.add(new WeakRef(track));
    if (muted) setEnabled.call(track, false);
    track.addEventListener('ended', report);
    timer ??= setInterval(report, POLL_MS); // `stop()` does not fire 'ended'
    report();
  }

  if (env.MediaDevices && env.navigator.mediaDevices) {
    const getUserMedia = env.MediaDevices.prototype.getUserMedia;
    env.MediaDevices.prototype.getUserMedia = function (this: MediaDevices, ...args: Parameters<typeof getUserMedia>) {
      return getUserMedia.apply(this, args).then((stream) => {
        stream.getAudioTracks().forEach((track) => trackMic(track));
        return stream;
      });
    };
  }

  const cloneTrack = trackProto.clone;
  trackProto.clone = function (this: MediaStreamTrack) {
    const copy = cloneTrack.call(this);
    if (micTracks.has(this)) trackMic(copy, wantEnabled.get(this));
    return copy;
  };

  const cloneStream = env.MediaStream.prototype.clone;
  env.MediaStream.prototype.clone = function (this: MediaStream) {
    const copy = cloneStream.call(this);
    const sources = this.getAudioTracks();
    if (sources.some((track) => micTracks.has(track))) {
      copy.getAudioTracks().forEach((track, i) => {
        const source = sources[i];
        trackMic(track, source && micTracks.has(source) ? wantEnabled.get(source) : undefined);
      });
    }
    return copy;
  };

  return {
    setMuted(value) {
      muted = value;
      for (const ref of live) {
        const track = ref.deref();
        if (track) setEnabled.call(track, (wantEnabled.get(track) ?? true) && !muted);
      }
    },
    resync() {
      // Only a microphone is worth saying: a page with none is what the listener assumes already.
      if (!micActive()) return;
      lastMic = true;
      onChange(true);
    },
  };
}
