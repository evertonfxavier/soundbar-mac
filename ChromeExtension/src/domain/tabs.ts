import { CHANGED_BELOW } from './config';
import type { TabConfig, TabInfo } from './protocol';

/** What the extension knows about a tab from the browser, reduced to what the app is told. */
export interface TabSnapshot {
  id: number;
  title?: string;
  url?: string;
  pendingUrl?: string;
  favIconUrl?: string;
  audible: boolean;
  /** Muted in Chrome itself. */
  muted: boolean;
}

/** The settings SoundBar applied to a tab. A tab nobody touched has none. */
export type TabSettings = Partial<TabConfig>;
export type TabSettingsMap = Record<number, TabSettings | undefined>;

/** The host of an address ("www.youtube.com"), or nothing for what is not an address. */
export function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return '';
  }
}

/** When each tab last made sound or used the microphone. */
export class ActivityLog {
  private readonly lastActive = new Map<number, number>();

  touch(tabId: number, now: number): void {
    this.lastActive.set(tabId, now);
  }

  wasActiveWithin(tabId: number, now: number, windowMs: number): boolean {
    return now - (this.lastActive.get(tabId) ?? 0) < windowMs;
  }

  forget(tabId: number): void {
    this.lastActive.delete(tabId);
  }
}

/** Which frames of each tab hold an open microphone (a tab has one, or many, with iframes). */
export class MicRegistry {
  private readonly frames = new Map<number, Map<number, boolean>>();

  set(tabId: number, frameId: number, mic: boolean): void {
    let tab = this.frames.get(tabId);
    if (!tab) {
      tab = new Map();
      this.frames.set(tabId, tab);
    }
    tab.set(frameId, mic);
  }

  /** The tab holds the microphone in at least one frame. */
  isUsedBy(tabId: number): boolean {
    const tab = this.frames.get(tabId);
    return !!tab && [...tab.values()].some(Boolean);
  }

  /** A tab that loads again starts with no microphone. */
  clear(tabId: number): void {
    this.frames.delete(tabId);
  }
}

export interface ListContext {
  settings: TabSettingsMap;
  mics: MicRegistry;
  activity: ActivityLog;
  now: number;
  idleMs: number;
}

/**
 * The tabs the app should show: the ones making sound or using the microphone, the ones that did a moment ago,
 * and the ones SoundBar changed (so a muted tab does not disappear).
 */
export function listTabs(
  tabs: readonly TabSnapshot[],
  { settings, mics, activity, now, idleMs }: ListContext,
): TabInfo[] {
  const listed: TabInfo[] = [];
  for (const tab of tabs) {
    const mine = settings[tab.id];
    const mic = mics.isUsedBy(tab.id);
    if (tab.audible || mic) activity.touch(tab.id, now);

    const volume = mine?.volume ?? 1;
    const changed = volume < CHANGED_BELOW || !!mine?.micMuted || tab.muted;
    if (!changed && !activity.wasActiveWithin(tab.id, now, idleMs)) continue;

    listed.push({
      id: tab.id,
      title: tab.title ?? '',
      host: hostOf(tab.url ? tab.url : (tab.pendingUrl ?? '')),
      favIconUrl: tab.favIconUrl ? tab.favIconUrl : null,
      audible: tab.audible,
      muted: tab.muted,
      volume,
      mic,
      micMuted: !!mine?.micMuted,
    });
  }
  return listed;
}
