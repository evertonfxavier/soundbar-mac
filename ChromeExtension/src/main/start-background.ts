import { BRIDGE_URL, RECONNECT_ALARM, RECONNECT_PERIOD_MINUTES, TICK_MS } from '../domain/config';
import { parseContentMessage } from '../domain/protocol';
import { BridgeService } from '../domain/usecases/bridge-service';
import { ChromeTabsGateway } from '../infra/chrome-tabs';
import { SessionSettingsStore } from '../infra/session-settings';
import { WebSocketAppLink, type WebSocketFactory } from '../infra/websocket-app-link';

/**
 * The service worker: builds the service, connects it to the SoundBar app and hands it every browser event it reacts to.
 *
 * The listeners are added right here, synchronously, as a service worker must: one registered later would miss the
 * event that woke the worker up.
 */
export function startBackground(api: typeof chrome, createSocket: WebSocketFactory): BridgeService {
  const service = new BridgeService({
    tabs: new ChromeTabsGateway(api.tabs),
    store: new SessionSettingsStore(api.storage.session),
    link: new WebSocketAppLink(BRIDGE_URL, createSocket),
  });

  api.runtime.onMessage.addListener((raw: unknown, sender, sendResponse) => {
    const tabId = sender.tab?.id;
    if (tabId === undefined) return undefined;
    const message = parseContentMessage(raw);
    if (message?.type === 'hello') {
      void service.hello(tabId, sender.frameId ?? 0).then(sendResponse);
      return true; // the answer comes later
    }
    if (message?.type === 'mic') service.micChanged(tabId, sender.frameId ?? 0, message.mic);
    return undefined;
  });

  api.tabs.onUpdated.addListener((tabId, info) => service.tabUpdated(tabId, info.status));
  api.tabs.onRemoved.addListener((tabId) => void service.tabRemoved(tabId));
  api.tabs.onReplaced.addListener((addedId, removedId) => void service.tabReplaced(addedId, removedId));

  void api.alarms.create(RECONNECT_ALARM, { periodInMinutes: RECONNECT_PERIOD_MINUTES });
  api.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === RECONNECT_ALARM) service.tick();
  });
  api.runtime.onStartup.addListener(() => service.connect());
  api.runtime.onInstalled.addListener(() => service.connect());

  setInterval(() => service.tick(), TICK_MS);
  service.connect();
  return service;
}
