import type { TabsGateway } from '../domain/ports';
import type { TabConfig } from '../domain/protocol';
import type { TabSnapshot } from '../domain/tabs';

type ChromeTabs = Pick<typeof chrome.tabs, 'query' | 'update' | 'sendMessage'>;

/** The tabs of Chrome, through `chrome.tabs`. */
export class ChromeTabsGateway implements TabsGateway {
  constructor(private readonly tabs: ChromeTabs) {}

  async list(): Promise<TabSnapshot[]> {
    const all = await this.tabs.query({});
    return all.flatMap((tab) => (tab.id === undefined ? [] : [toSnapshot(tab, tab.id)]));
  }

  async setMuted(tabId: number, muted: boolean): Promise<void> {
    try {
      await this.tabs.update(tabId, { muted });
    } catch {
      // the tab was closed between the command and now
    }
  }

  sendConfig(tabId: number, config: TabConfig): void {
    // a tab without our content script (chrome://, the Web Store…) has nobody to receive it
    this.tabs.sendMessage(tabId, { type: 'config', ...config }).catch(() => undefined);
  }

  requestMicReport(tabId: number): void {
    this.tabs.sendMessage(tabId, { type: 'resync' }).catch(() => undefined);
  }
}

function toSnapshot(tab: chrome.tabs.Tab, id: number): TabSnapshot {
  const snapshot: TabSnapshot = { id, audible: !!tab.audible, muted: !!tab.mutedInfo?.muted };
  if (tab.title !== undefined) snapshot.title = tab.title;
  if (tab.url !== undefined) snapshot.url = tab.url;
  if (tab.pendingUrl !== undefined) snapshot.pendingUrl = tab.pendingUrl;
  if (tab.favIconUrl !== undefined) snapshot.favIconUrl = tab.favIconUrl;
  return snapshot;
}
