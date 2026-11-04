import type { SettingsStore } from '../domain/ports';
import type { TabSettingsMap } from '../domain/tabs';

const KEY = 'settings';

type StorageArea = Pick<chrome.storage.StorageArea, 'get' | 'set'>;

/**
 * The settings of the tabs in `chrome.storage.session`: they outlive the service worker going to sleep, and are
 * dropped when the browser closes (tab ids mean nothing in the next session).
 */
export class SessionSettingsStore implements SettingsStore {
  constructor(private readonly area: StorageArea) {}

  async load(): Promise<TabSettingsMap> {
    try {
      const stored: unknown = (await this.area.get(KEY))[KEY];
      return typeof stored === 'object' && stored !== null ? (stored as TabSettingsMap) : {};
    } catch (error) {
      console.warn('SoundBar: could not read the saved settings', error);
      return {};
    }
  }

  save(settings: TabSettingsMap): void {
    this.area.set({ [KEY]: settings }).catch((error: unknown) => {
      console.warn('SoundBar: could not save the settings', error);
    });
  }
}
