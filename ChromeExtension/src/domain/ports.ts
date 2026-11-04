import type { TabConfig } from './protocol';
import type { TabSettingsMap, TabSnapshot } from './tabs';

/*
 * What the domain needs from the outside world. The adapters are in src/infra; the specs use fakes.
 */

/** The browser tabs. */
export interface TabsGateway {
  list(): Promise<TabSnapshot[]>;
  /** Mutes or unmutes the tab in Chrome itself. A tab that is gone is not an error. */
  setMuted(tabId: number, muted: boolean): Promise<void>;
  /** Tells the content scripts of the tab what to apply. A tab with no content script is not an error. */
  sendConfig(tabId: number, config: TabConfig): void;
  /** Asks the content scripts of the tab to say again whether the page holds the microphone. Same leniency. */
  requestMicReport(tabId: number): void;
}

/** Where the settings survive the service worker being put to sleep (and are forgotten when the browser closes). */
export interface SettingsStore {
  load(): Promise<TabSettingsMap>;
  save(settings: TabSettingsMap): void;
}

/** The connection to the SoundBar app. */
export interface AppLink {
  onOpen: (() => void) | null;
  onMessage: ((text: string) => void) | null;
  /** Opens the connection, unless it is open or opening. */
  connect(): void;
  isOpen(): boolean;
  /** Sends text if the connection is open; losing the connection while sending is not an error. */
  send(text: string): void;
}
