/*
 * jsdom has no MediaStream, MediaStreamTrack or MediaDevices. These stand in for them, with the one behavior the
 * microphone code relies on: `MediaStream.clone()` copies its tracks without going through `MediaStreamTrack.clone()`.
 *
 * The code under test patches the prototypes of these classes, so every spec gets classes of its own.
 */
export function createFakeMedia() {
  class FakeTrack extends EventTarget {
    kind = 'audio';
    readyState: 'live' | 'ended' = 'live';
    private on = true;

    get enabled(): boolean {
      return this.on;
    }

    set enabled(value: boolean) {
      this.on = value;
    }

    clone(): FakeTrack {
      return this.copy();
    }

    stop(): void {
      this.readyState = 'ended';
    }

    /** What the browser does internally, out of reach of the patched `clone`. */
    copy(): FakeTrack {
      const duplicate = new FakeTrack();
      duplicate.kind = this.kind;
      duplicate.on = this.on;
      return duplicate;
    }
  }

  class FakeStream {
    constructor(readonly tracks: FakeTrack[]) {}

    getAudioTracks(): FakeTrack[] {
      return this.tracks.filter((track) => track.kind === 'audio');
    }

    clone(): FakeStream {
      return new FakeStream(this.tracks.map((track) => track.copy()));
    }
  }

  class FakeMediaDevices {
    /** What the next getUserMedia hands out. */
    next: FakeStream = new FakeStream([new FakeTrack()]);

    getUserMedia(): Promise<FakeStream> {
      return Promise.resolve(this.next);
    }
  }

  return { FakeTrack, FakeStream, FakeMediaDevices };
}

export type FakeMedia = ReturnType<typeof createFakeMedia>;
