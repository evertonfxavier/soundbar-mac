import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { IDLE_MS, SEND_DEBOUNCE_MS } from '../../../src/domain/config';
import type { AppLink, SettingsStore, TabsGateway } from '../../../src/domain/ports';
import type { TabConfig } from '../../../src/domain/protocol';
import type { TabSettingsMap, TabSnapshot } from '../../../src/domain/tabs';
import { BridgeService } from '../../../src/domain/usecases/bridge-service';

class FakeLink implements AppLink {
  onOpen: (() => void) | null = null;
  onMessage: ((text: string) => void) | null = null;
  open = false;
  connects = 0;
  sent: string[] = [];

  connect() {
    this.connects++;
  }
  isOpen() {
    return this.open;
  }
  send(text: string) {
    this.sent.push(text);
  }

  /** What the app would do. */
  connectNow() {
    this.open = true;
    this.onOpen?.();
  }
  command(command: object) {
    this.onMessage?.(JSON.stringify(command));
  }
  get tabsSent() {
    return this.sent
      .map((s) => JSON.parse(s) as { type: string; tabs?: { id: number }[] })
      .filter((m) => m.type === 'tabs');
  }
  get pings() {
    return this.sent.filter((s) => s === '{"type":"ping"}').length;
  }
}

class FakeTabs implements TabsGateway {
  tabs: TabSnapshot[] = [];
  muted: [number, boolean][] = [];
  configs: [number, TabConfig][] = [];
  micReports: number[] = [];
  list() {
    return Promise.resolve(this.tabs);
  }
  requestMicReport(tabId: number) {
    this.micReports.push(tabId);
  }
  setMuted(tabId: number, muted: boolean) {
    this.muted.push([tabId, muted]);
    return Promise.resolve();
  }
  sendConfig(tabId: number, config: TabConfig) {
    this.configs.push([tabId, config]);
  }
}

class FakeStore implements SettingsStore {
  saved: TabSettingsMap[] = [];
  constructor(private readonly initial: TabSettingsMap = {}) {}
  load() {
    return Promise.resolve(structuredClone(this.initial));
  }
  save(settings: TabSettingsMap) {
    this.saved.push(structuredClone(settings));
  }
  get last() {
    return this.saved[this.saved.length - 1];
  }
}

const playing = (id: number): TabSnapshot => ({
  id,
  audible: true,
  muted: false,
  title: `tab ${id}`,
  url: 'https://example.com',
});

function setup(initial: TabSettingsMap = {}) {
  const link = new FakeLink();
  const tabs = new FakeTabs();
  const store = new FakeStore(initial);
  const service = new BridgeService({ tabs, store, link, now: () => Date.now() });
  return { link, tabs, store, service };
}

/** Lets the pending promises run, and any timer that is due. */
const settle = (ms = 0) => vi.advanceTimersByTimeAsync(ms);

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(1_000_000);
});

afterEach(() => {
  vi.useRealTimers();
});

describe('BridgeService: the connection', () => {
  it('connects when asked, and again at every heartbeat while it is not connected', () => {
    const { service, link } = setup();

    service.connect();
    service.tick();

    expect(link.connects).toBe(2);
    expect(link.pings).toBe(0);
  });

  it('asks every tab to report its microphone again whenever a connection opens', async () => {
    const { link, tabs } = setup();
    tabs.tabs = [playing(1), { id: 2, audible: false, muted: false }];
    expect(tabs.micReports).toEqual([]);

    link.connectNow();
    await settle();
    expect(tabs.micReports).toEqual([1, 2]);

    link.connectNow(); // the app came back
    await settle();
    expect(tabs.micReports).toEqual([1, 2, 1, 2]);
  });

  it('lists a call that began while the app was away, once its page answers', async () => {
    const { link, tabs, service } = setup();
    tabs.tabs = [{ id: 7, audible: false, muted: false, title: 'Call' }];
    link.connectNow();
    await settle();
    expect(link.tabsSent.at(-1)?.tabs).toEqual([]); // the worker slept: it does not know about the microphone yet

    service.micChanged(7, 0, true); // the answer to the request above
    await settle(SEND_DEBOUNCE_MS);

    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 7, mic: true })]);
  });

  it('does not ask while there is no connection', async () => {
    const { tabs, service } = setup();
    tabs.tabs = [playing(1)];

    service.connect();
    service.tick();
    await settle();

    expect(tabs.micReports).toEqual([]);
  });

  it('tells the app the tabs as soon as the connection opens', async () => {
    const { link, tabs } = setup();
    tabs.tabs = [playing(1)];

    link.connectNow();
    await settle();

    expect(link.tabsSent).toEqual([{ type: 'tabs', tabs: [expect.objectContaining({ id: 1, audible: true })] }]);
  });

  it('sends nothing while the connection is not open', async () => {
    const { link, tabs, service } = setup();
    tabs.tabs = [playing(1)];

    service.tabUpdated(1, 'complete');
    await settle(SEND_DEBOUNCE_MS);

    expect(link.sent).toEqual([]);
  });

  it('pings at every heartbeat while connected, and only repeats the tabs when they changed', async () => {
    const { link, tabs, service } = setup();
    tabs.tabs = [playing(1)];
    link.connectNow();
    await settle();

    service.tick();
    await settle();
    expect(link.pings).toBe(1);
    expect(link.tabsSent).toHaveLength(1);

    tabs.tabs = [playing(1), playing(2)];
    service.tick();
    await settle();
    expect(link.pings).toBe(2);
    expect(link.tabsSent).toHaveLength(2);
    expect(link.tabsSent[1]?.tabs?.map((t) => t.id)).toEqual([1, 2]);
  });

  it('starts over when it reconnects: the new connection gets the tabs again, unchanged or not', async () => {
    const { link, tabs } = setup();
    tabs.tabs = [playing(1)];
    link.connectNow();
    await settle();

    link.connectNow();
    await settle();

    expect(link.tabsSent).toHaveLength(2);
  });
});

describe('BridgeService: the events of the tabs', () => {
  it('publishes once for a burst of events, after the quiet period', async () => {
    const { link, tabs, service } = setup();
    link.open = true;
    tabs.tabs = [playing(1)];

    for (let i = 0; i < 5; i++) service.tabUpdated(1, 'complete');
    await settle(SEND_DEBOUNCE_MS - 1);
    expect(link.sent).toEqual([]);

    await settle(1);
    expect(link.tabsSent).toHaveLength(1);
  });

  it('lists a quiet tab while its microphone is open, and drops it a while after the microphone closes', async () => {
    const { link, tabs, service } = setup();
    link.open = true;
    tabs.tabs = [{ id: 3, audible: false, muted: false }];

    service.micChanged(3, 0, true);
    await settle(SEND_DEBOUNCE_MS);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: true })]);

    service.micChanged(3, 0, false);
    await settle(SEND_DEBOUNCE_MS);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: false })]); // still recent

    await settle(IDLE_MS);
    service.tabUpdated(3, 'complete');
    await settle(SEND_DEBOUNCE_MS);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([]);
  });

  it('shows the microphone of a tab the browser reports', async () => {
    const { link, tabs, service } = setup();
    link.open = true;
    tabs.tabs = [{ id: 3, audible: false, muted: false }];

    service.micChanged(3, 0, true);
    await settle(SEND_DEBOUNCE_MS);

    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: true })]);
  });

  it('forgets the microphone of a tab that loads again', async () => {
    const { link, tabs, service } = setup();
    link.open = true;
    tabs.tabs = [{ id: 3, audible: false, muted: false }];
    service.micChanged(3, 0, true);
    await settle(SEND_DEBOUNCE_MS);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: true })]);

    service.tabUpdated(3, 'loading');
    await settle(SEND_DEBOUNCE_MS);

    // still listed (it was active a moment ago), but the page that held the microphone is gone
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: false })]);
  });

  it('keeps the microphone when a tab finishes loading, since only a new load drops it', async () => {
    const { link, tabs, service } = setup();
    link.open = true;
    tabs.tabs = [{ id: 3, audible: false, muted: false }];
    service.micChanged(3, 0, true);
    service.tabUpdated(3, 'complete');
    await settle(SEND_DEBOUNCE_MS);

    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: true })]);
  });

  it('answers a frame that says hello with the settings of its tab', async () => {
    const { service } = setup({ 4: { volume: 0.3, micMuted: true } });

    await expect(service.hello(4, 0)).resolves.toEqual({ volume: 0.3, micMuted: true });
    await expect(service.hello(5, 0)).resolves.toEqual({ volume: 1, micMuted: false });
  });

  it('forgets the old microphone when the main frame says hello, but not for a subframe', async () => {
    const { link, tabs, service } = setup();
    link.open = true;
    tabs.tabs = [{ id: 3, audible: false, muted: false }];
    service.micChanged(3, 0, true);

    await service.hello(3, 7); // a subframe starting says nothing about the main frame's microphone
    service.tabUpdated(3, 'complete');
    await settle(SEND_DEBOUNCE_MS);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: true })]);

    await service.hello(3, 0); // the main frame starting: a new page
    service.tabUpdated(3, 'complete');
    await settle(SEND_DEBOUNCE_MS);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 3, mic: false })]);
  });

  it('forgets the settings of a tab that was closed', async () => {
    const { service, store } = setup({ 4: { volume: 0.3 }, 9: { volume: 0.6 } });

    await service.tabRemoved(4);

    expect(store.last).toEqual({ 9: { volume: 0.6 } });
  });

  it('moves the settings to the tab that replaced another, and tells its content scripts', async () => {
    const { service, store, tabs } = setup({ 4: { volume: 0.3, micMuted: true } });

    await service.tabReplaced(8, 4);

    expect(store.last).toEqual({ 8: { volume: 0.3, micMuted: true } });
    expect(tabs.configs).toEqual([[8, { volume: 0.3, micMuted: true }]]);
  });

  it('replacing a tab that had no settings changes nothing', async () => {
    const { service, store, tabs } = setup({ 9: { volume: 0.6 } });

    await service.tabReplaced(8, 4);

    expect(store.last).toEqual({ 9: { volume: 0.6 } });
    expect(tabs.configs).toEqual([[8, { volume: 1, micMuted: false }]]);
  });
});

describe('BridgeService: the commands of the app', () => {
  it('applies a volume: remembers it, tells the tab, and lists the tab even when it is quiet', async () => {
    const { link, tabs, store } = setup();
    link.connectNow();
    tabs.tabs = [{ id: 6, audible: false, muted: false }];
    await settle();

    link.command({ type: 'set', tabId: 6, volume: 0.4 });
    await settle(SEND_DEBOUNCE_MS);

    expect(store.last).toEqual({ 6: { volume: 0.4, micMuted: false } });
    expect(tabs.configs).toEqual([[6, { volume: 0.4, micMuted: false }]]);
    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 6, volume: 0.4 })]);
  });

  it('keeps a volume to what the page accepts', async () => {
    const { link, tabs } = setup();

    link.command({ type: 'set', tabId: 6, volume: 7 });
    await settle();
    link.command({ type: 'set', tabId: 7, volume: -2 });
    await settle();

    expect(tabs.configs).toEqual([
      [6, { volume: 1, micMuted: false }],
      [7, { volume: 0, micMuted: false }],
    ]);
  });

  it('mutes and unmutes the tab in the browser', async () => {
    const { link, tabs } = setup();

    link.command({ type: 'set', tabId: 6, muted: true });
    await settle();
    link.command({ type: 'set', tabId: 6, muted: false });
    await settle();

    expect(tabs.muted).toEqual([
      [6, true],
      [6, false],
    ]);
  });

  it('switches the microphone of a tab off, and leaves the volume as it was', async () => {
    const { link, tabs } = setup({ 6: { volume: 0.5, micMuted: false } });

    link.command({ type: 'set', tabId: 6, micMuted: true });
    await settle();

    expect(tabs.configs).toEqual([[6, { volume: 0.5, micMuted: true }]]);
  });

  it('ignores what it does not understand', async () => {
    const { link, tabs, store } = setup();

    link.onMessage?.('not json');
    link.command({ type: 'reboot' });
    link.command({ type: 'set' });
    link.command({ type: 'pong' });
    await settle(SEND_DEBOUNCE_MS);

    expect(tabs.configs).toEqual([]);
    expect(store.saved).toEqual([]);
  });
});

describe('BridgeService: the settings that survived a sleep', () => {
  it('lists a quiet tab whose volume was changed before the worker slept', async () => {
    const { link, tabs } = setup({ 6: { volume: 0.5 } });
    tabs.tabs = [{ id: 6, audible: false, muted: false }];

    link.connectNow();
    await settle();

    expect(link.tabsSent.at(-1)?.tabs).toEqual([expect.objectContaining({ id: 6, volume: 0.5 })]);
  });
});
