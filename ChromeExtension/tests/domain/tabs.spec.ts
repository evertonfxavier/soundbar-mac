import { describe, expect, it } from 'vitest';
import {
  ActivityLog,
  MicRegistry,
  hostOf,
  listTabs,
  type TabSettingsMap,
  type TabSnapshot,
} from '../../src/domain/tabs';

const IDLE = 15_000;
const NOW = 1_000_000;

const tab = (overrides: Partial<TabSnapshot> & { id: number }): TabSnapshot => ({
  audible: false,
  muted: false,
  ...overrides,
});

interface Options {
  settings?: TabSettingsMap;
  mics?: MicRegistry;
  activity?: ActivityLog;
  now?: number;
}

function list(
  tabs: TabSnapshot[],
  { settings = {}, mics = new MicRegistry(), activity = new ActivityLog(), now = NOW }: Options = {},
) {
  return listTabs(tabs, { settings, mics, activity, now, idleMs: IDLE });
}

describe('hostOf', () => {
  it('is the host of an address, port included', () => {
    expect(hostOf('https://www.youtube.com/watch?v=1')).toBe('www.youtube.com');
    expect(hostOf('http://localhost:5173/app')).toBe('localhost:5173');
  });

  it('is empty for what is not an address', () => {
    expect(hostOf('')).toBe('');
    expect(hostOf('not a url')).toBe('');
  });
});

describe('ActivityLog', () => {
  it('knows a tab was active only inside the window', () => {
    const log = new ActivityLog();
    log.touch(1, 100);

    expect(log.wasActiveWithin(1, 100 + IDLE - 1, IDLE)).toBe(true);
    expect(log.wasActiveWithin(1, 100 + IDLE, IDLE)).toBe(false);
  });

  it('knows nothing of a tab never seen, or one that was forgotten', () => {
    const log = new ActivityLog();
    expect(log.wasActiveWithin(1, 5_000_000, IDLE)).toBe(false);

    log.touch(1, 5_000_000);
    log.forget(1);
    expect(log.wasActiveWithin(1, 5_000_000, IDLE)).toBe(false);
  });
});

describe('MicRegistry', () => {
  it('says a tab uses the microphone while any of its frames does', () => {
    const mics = new MicRegistry();
    mics.set(1, 0, false);
    mics.set(1, 5, true);
    expect(mics.isUsedBy(1)).toBe(true);

    mics.set(1, 5, false);
    expect(mics.isUsedBy(1)).toBe(false);
  });

  it('forgets a tab when it is cleared, and knows nothing of the others', () => {
    const mics = new MicRegistry();
    mics.set(1, 0, true);
    mics.clear(1);

    expect(mics.isUsedBy(1)).toBe(false);
    expect(mics.isUsedBy(99)).toBe(false);
  });
});

describe('listTabs', () => {
  it('lists a tab that makes sound, with what the app shows of it', () => {
    const result = list([
      tab({
        id: 1,
        title: 'Lo-fi',
        url: 'https://www.youtube.com/watch?v=1',
        favIconUrl: 'https://www.youtube.com/f.ico',
        audible: true,
      }),
    ]);

    expect(result).toEqual([
      {
        id: 1,
        title: 'Lo-fi',
        host: 'www.youtube.com',
        favIconUrl: 'https://www.youtube.com/f.ico',
        audible: true,
        muted: false,
        volume: 1,
        mic: false,
        micMuted: false,
      },
    ]);
  });

  it('does not list a quiet tab nobody touched', () => {
    expect(list([tab({ id: 1, url: 'https://example.com' })])).toEqual([]);
  });

  it('lists a tab that uses the microphone, and says so', () => {
    const mics = new MicRegistry();
    mics.set(2, 0, true);

    expect(list([tab({ id: 2 })], { mics })).toMatchObject([{ id: 2, mic: true, audible: false }]);
  });

  it('keeps listing a tab for a while after it went quiet, then lets it go', () => {
    const activity = new ActivityLog();
    const quiet = [tab({ id: 3 })];
    list([tab({ id: 3, audible: true })], { activity, now: NOW });

    expect(list(quiet, { activity, now: NOW + IDLE - 1 })).toHaveLength(1);
    expect(list(quiet, { activity, now: NOW + IDLE })).toHaveLength(0);
  });

  it('keeps a tab SoundBar changed, however quiet it is', () => {
    const quiet = [tab({ id: 4 })];
    expect(list(quiet, { settings: { 4: { volume: 0.5 } } })).toMatchObject([{ id: 4, volume: 0.5 }]);
    expect(list(quiet, { settings: { 4: { micMuted: true } } })).toMatchObject([{ id: 4, micMuted: true }]);
    expect(list([tab({ id: 4, muted: true })])).toMatchObject([{ id: 4, muted: true }]);
  });

  it('does not count a volume that is full, or within half a percent of it, as a change', () => {
    expect(list([tab({ id: 5 })], { settings: { 5: { volume: 1 } } })).toEqual([]);
    expect(list([tab({ id: 5 })], { settings: { 5: { volume: 0.996 } } })).toEqual([]);
    expect(list([tab({ id: 5 })], { settings: { 5: { volume: 0.99 } } })).toHaveLength(1);
  });

  it('falls back to the address being loaded when the tab has none yet', () => {
    const [first] = list([tab({ id: 6, audible: true, pendingUrl: 'https://new.example.org/x' })]);
    expect(first?.host).toBe('new.example.org');

    const [second] = list([tab({ id: 7, audible: true, url: '', pendingUrl: 'https://other.example.org' })]);
    expect(second?.host).toBe('other.example.org');
  });

  it('gives empty text and no icon where the browser had none', () => {
    const [only] = list([tab({ id: 8, audible: true })]);

    expect(only).toMatchObject({ title: '', host: '', favIconUrl: null });
  });

  it('records the activity it saw, for the next call', () => {
    const activity = new ActivityLog();
    list([tab({ id: 9, audible: true })], { activity });

    expect(activity.wasActiveWithin(9, NOW + 1, IDLE)).toBe(true);
  });
});
