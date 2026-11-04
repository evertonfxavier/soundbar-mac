import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  BRIDGE_URL,
  RECONNECT_ALARM,
  RECONNECT_PERIOD_MINUTES,
  SEND_DEBOUNCE_MS,
  TICK_MS,
} from '../../src/domain/config';
import { startBackground } from '../../src/main/start-background';
import { socketFactory } from '../support/fake-websocket';

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- the browser calls each kind of listener with its own arguments
type Listener = (...args: any[]) => unknown;

/** The pieces of `chrome` the worker touches, recording the listeners it adds. */
function fakeChrome(tabs: Partial<chrome.tabs.Tab>[] = []) {
  const on = () => {
    const listeners: Listener[] = [];
    return { listeners, addListener: (fn: Listener) => listeners.push(fn) };
  };
  const events = {
    message: on(),
    startup: on(),
    installed: on(),
    updated: on(),
    removed: on(),
    replaced: on(),
    alarm: on(),
  };
  const api = {
    runtime: { onMessage: events.message, onStartup: events.startup, onInstalled: events.installed },
    tabs: {
      query: vi.fn(() => Promise.resolve(tabs)),
      update: vi.fn(() => Promise.resolve({})),
      sendMessage: vi.fn(() => Promise.resolve()),
      onUpdated: events.updated,
      onRemoved: events.removed,
      onReplaced: events.replaced,
    },
    storage: { session: { get: vi.fn(() => Promise.resolve({})), set: vi.fn(() => Promise.resolve()) } },
    alarms: { create: vi.fn(() => Promise.resolve()), onAlarm: events.alarm },
  };
  return { api: api as unknown as typeof chrome, raw: api, events };
}

const flush = (ms = 0) => vi.advanceTimersByTimeAsync(ms);

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('startBackground', () => {
  it('connects to the app at once', () => {
    const sockets = socketFactory();

    startBackground(fakeChrome().api, sockets.create);

    expect(sockets.made.map((s) => s.url)).toEqual([BRIDGE_URL]);
  });

  it('registers every listener while it starts, before anything is awaited', () => {
    const { api, events } = fakeChrome();

    startBackground(api, socketFactory().create);

    for (const [name, event] of Object.entries(events)) expect(event.listeners, name).toHaveLength(1);
  });

  it('sets the alarm that wakes a sleeping worker', () => {
    const { api, raw } = fakeChrome();

    startBackground(api, socketFactory().create);

    expect(raw.alarms.create).toHaveBeenCalledWith(RECONNECT_ALARM, { periodInMinutes: RECONNECT_PERIOD_MINUTES });
  });

  it('keeps the heartbeat going: it reconnects when the app comes back', async () => {
    const sockets = socketFactory();
    startBackground(fakeChrome().api, sockets.create);
    sockets.last!.open();
    sockets.last!.close();

    await flush(TICK_MS);

    expect(sockets.made).toHaveLength(2);
  });

  it('answers the alarm with a heartbeat, and ignores the alarms that are not its own', async () => {
    const sockets = socketFactory();
    const { api, events } = fakeChrome();
    startBackground(api, sockets.create);
    sockets.last!.open();
    await flush();
    const before = sockets.last!.sent.length;

    events.alarm.listeners[0]!({ name: 'someone-else' });
    expect(sockets.last!.sent).toHaveLength(before);

    events.alarm.listeners[0]!({ name: RECONNECT_ALARM });
    expect(sockets.last!.sent).toContain('{"type":"ping"}');
  });

  it('connects again when the browser starts, and when the extension is installed or updated', () => {
    const sockets = socketFactory();
    const { api, events } = fakeChrome();
    startBackground(api, sockets.create);
    sockets.last!.open();
    sockets.last!.close();

    events.installed.listeners[0]!();
    expect(sockets.made).toHaveLength(2);

    sockets.last!.close();
    events.startup.listeners[0]!();
    expect(sockets.made).toHaveLength(3);
  });

  it('tells the app about the tabs that make sound', async () => {
    const sockets = socketFactory();
    const { api } = fakeChrome([{ id: 1, title: 'Lo-fi', url: 'https://www.youtube.com/w', audible: true }]);
    startBackground(api, sockets.create);

    sockets.last!.open();
    await flush();

    expect(sockets.last!.messages).toEqual([
      {
        type: 'tabs',
        tabs: [expect.objectContaining({ id: 1, title: 'Lo-fi', host: 'www.youtube.com', audible: true })],
      },
    ]);
  });

  it('asks every tab to report its microphone again when the app connects, since it forgot while asleep', async () => {
    const sockets = socketFactory();
    const { api, raw } = fakeChrome([{ id: 1 }, { id: 2, audible: true }]);
    startBackground(api, sockets.create);
    expect(raw.tabs.sendMessage).not.toHaveBeenCalled(); // nothing to ask while there is nobody to tell

    sockets.last!.open();
    await flush();

    expect(raw.tabs.sendMessage).toHaveBeenCalledWith(1, { type: 'resync' });
    expect(raw.tabs.sendMessage).toHaveBeenCalledWith(2, { type: 'resync' });
  });

  it('applies a command of the app to the browser and to the page', async () => {
    const sockets = socketFactory();
    const { api, raw } = fakeChrome();
    startBackground(api, sockets.create);
    sockets.last!.open();

    sockets.last!.receive('{"type":"set","tabId":9,"volume":0.5,"muted":true}');
    await flush();

    expect(raw.tabs.update).toHaveBeenCalledWith(9, { muted: true });
    expect(raw.tabs.sendMessage).toHaveBeenCalledWith(9, { type: 'config', volume: 0.5, micMuted: false });
    expect(raw.storage.session.set).toHaveBeenCalledWith({ settings: { 9: { volume: 0.5, micMuted: false } } });
  });

  describe('the messages of the content scripts', () => {
    const fromTab = (tabId: number, frameId = 0) => ({ tab: { id: tabId }, frameId });

    it('answers a hello with the settings of the tab, and says the answer comes later', async () => {
      const { api, events } = fakeChrome();
      startBackground(api, socketFactory().create);
      const respond = vi.fn();

      const keepOpen = events.message.listeners[0]!({ type: 'hello' }, fromTab(4), respond);
      await flush();

      expect(keepOpen).toBe(true);
      expect(respond).toHaveBeenCalledWith({ volume: 1, micMuted: false });
    });

    it('takes the microphone report of a frame, and shows it to the app', async () => {
      const sockets = socketFactory();
      const { api, events } = fakeChrome([{ id: 4 }]);
      startBackground(api, sockets.create);
      sockets.last!.open();
      await flush();

      const answer = events.message.listeners[0]!({ type: 'mic', mic: true }, fromTab(4, 2), vi.fn());
      await flush(SEND_DEBOUNCE_MS);

      expect(answer).toBeUndefined();
      expect(sockets.last!.messages.at(-1)).toEqual({
        type: 'tabs',
        tabs: [expect.objectContaining({ id: 4, mic: true })],
      });
    });

    it('ignores a message that did not come from a tab, or that it does not know', () => {
      const { api, events } = fakeChrome();
      startBackground(api, socketFactory().create);
      const respond = vi.fn();

      expect(events.message.listeners[0]!({ type: 'hello' }, { frameId: 0 }, respond)).toBeUndefined();
      expect(events.message.listeners[0]!({ type: 'nope' }, fromTab(4), respond)).toBeUndefined();
      expect(events.message.listeners[0]!(undefined, fromTab(4), respond)).toBeUndefined();
      expect(respond).not.toHaveBeenCalled();
    });

    it('treats a message with no frame as the main frame', async () => {
      const { api, events } = fakeChrome();
      startBackground(api, socketFactory().create);
      const respond = vi.fn();

      events.message.listeners[0]!({ type: 'hello' }, { tab: { id: 4 } }, respond);
      await flush();

      expect(respond).toHaveBeenCalled();
    });
  });

  describe('the events of the tabs', () => {
    it('publishes when a tab changes', async () => {
      const sockets = socketFactory();
      const tabs: Partial<chrome.tabs.Tab>[] = [{ id: 1, audible: true }];
      const { api, events } = fakeChrome(tabs);
      startBackground(api, sockets.create);
      sockets.last!.open();
      await flush();

      tabs.push({ id: 2, audible: true });
      events.updated.listeners[0]!(2, { status: 'complete' });
      await flush(SEND_DEBOUNCE_MS);

      expect(sockets.last!.messages.at(-1)).toEqual({
        type: 'tabs',
        tabs: [expect.objectContaining({ id: 1 }), expect.objectContaining({ id: 2 })],
      });
    });

    it('forgets the settings of a closed tab and moves them to the tab that replaced another', async () => {
      const { api, events, raw } = fakeChrome();
      raw.storage.session.get.mockResolvedValue({ settings: { 1: { volume: 0.5 }, 2: { volume: 0.2 } } });
      startBackground(api, socketFactory().create);

      events.removed.listeners[0]!(1);
      await flush();
      expect(raw.storage.session.set).toHaveBeenLastCalledWith({ settings: { 2: { volume: 0.2 } } });

      events.replaced.listeners[0]!(7, 2);
      await flush();
      expect(raw.storage.session.set).toHaveBeenLastCalledWith({ settings: { 7: { volume: 0.2 } } });
    });
  });
});
