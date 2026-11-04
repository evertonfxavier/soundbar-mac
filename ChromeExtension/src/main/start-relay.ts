import {
  parseConfigMessage,
  parsePageEnvelope,
  parseResyncMessage,
  toPageEnvelope,
  toTabConfig,
  type ContentMessage,
  type PageMessage,
} from '../domain/protocol';

export interface RelayEnvironment {
  window: Pick<Window, 'addEventListener' | 'postMessage'>;
  runtime: Pick<typeof chrome.runtime, 'sendMessage' | 'onMessage'>;
}

/**
 * The isolated world of a frame: the only one that can use `chrome.runtime`, so it carries messages between the page
 * world (src/main/start-inject.ts) and the service worker.
 */
export function startRelay({ window: win, runtime }: RelayEnvironment): void {
  const toPage = (message: PageMessage) => win.postMessage(toPageEnvelope(message), '*');

  const toWorker = (message: ContentMessage): Promise<unknown> => {
    try {
      return runtime.sendMessage(message).catch(() => undefined);
    } catch {
      return Promise.resolve(undefined); // the extension was reloaded: this script is orphaned
    }
  };

  win.addEventListener('message', (event: MessageEvent) => {
    if (event.source !== win) return;
    const message = parsePageEnvelope(event.data);
    if (message?.type === 'mic') void toWorker({ type: 'mic', mic: message.mic });
  });

  try {
    runtime.onMessage.addListener((raw: unknown) => {
      const config = parseConfigMessage(raw);
      if (config) toPage(config);
      else if (parseResyncMessage(raw)) toPage({ type: 'resync' });
    });
  } catch {
    // orphaned, as above
  }

  void toWorker({ type: 'hello' }).then((answer) => {
    const config = toTabConfig(answer);
    if (config) toPage({ type: 'config', ...config });
  });
}
