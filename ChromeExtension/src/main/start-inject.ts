import { parsePageEnvelope, toPageEnvelope } from '../domain/protocol';
import { installMediaVolume, type MediaEnvironment } from '../infra/page/media-volume';
import { installMicrophone, type MicrophoneEnvironment } from '../infra/page/microphone';

/** The marker that keeps a frame from being set up twice. */
const INJECTED = '__soundbarInjected';

export type InjectEnvironment = MediaEnvironment &
  MicrophoneEnvironment &
  Pick<Window, 'addEventListener' | 'postMessage'>;

/**
 * Runs in the page's own JS world (before the page's scripts), in every frame:
 *   1. scales the volume of <audio> and <video> by a per-tab factor;
 *   2. follows the microphone tracks from getUserMedia, so the mic of the tab can be muted from SoundBar.
 * What to apply arrives from the relay (src/main/start-relay.ts); the microphone state goes back through it.
 */
export function startInject(win: InjectEnvironment): void {
  if (Reflect.has(win, INJECTED)) return;
  Object.defineProperty(win, INJECTED, { value: true });

  const media = installMediaVolume(win);
  const microphone = installMicrophone(win, (mic) => {
    win.postMessage(toPageEnvelope({ type: 'mic', mic }), '*');
  });

  win.addEventListener('message', (event: MessageEvent) => {
    if (event.source !== (win as unknown)) return; // only what this frame posted to itself
    const message = parsePageEnvelope(event.data);
    if (message?.type === 'config') {
      media.setVolume(message.volume);
      microphone.setMuted(message.micMuted);
    } else if (message?.type === 'resync') {
      microphone.resync();
    }
  });
}
