import { clampVolume } from './volume';

/*
 * Every message that crosses a boundary of the extension, and the code that reads it.
 *
 *   app (Swift)  <—— WebSocket ——>  service worker  <—— chrome.runtime ——>  relay  <—— postMessage ——>  inject
 *                                                                             (isolated world)        (page world)
 *
 * What goes over the WebSocket is a contract with the app: contract/fixtures/ holds one example of each message,
 * and both this code and the Swift side are checked against it.
 */

// ---------- WebSocket: extension → app ----------

/** One tab, as the app lists it. */
export interface TabInfo {
  id: number;
  title: string;
  host: string;
  favIconUrl: string | null;
  audible: boolean;
  /** Muted in Chrome itself. */
  muted: boolean;
  /** 0 to 1. */
  volume: number;
  /** The tab holds an open microphone. */
  mic: boolean;
  /** The microphone of the tab is silenced by SoundBar. */
  micMuted: boolean;
}

export type ExtensionMessage = { type: 'tabs'; tabs: TabInfo[] } | { type: 'ping' };

export function serialize(message: ExtensionMessage): string {
  return JSON.stringify(message);
}

// ---------- WebSocket: app → extension ----------

/** Change the settings of one tab. Every field but the tab is optional: only what is present changes. */
export interface SetCommand {
  type: 'set';
  tabId: number;
  volume?: number;
  muted?: boolean;
  micMuted?: boolean;
}

export type AppMessage = SetCommand | { type: 'pong' };

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null;

/** What the app sent, or `undefined` for anything that is not a message this version understands. */
export function parseAppMessage(text: string): AppMessage | undefined {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return undefined;
  }
  if (!isRecord(raw)) return undefined;

  if (raw.type === 'pong') return { type: 'pong' };
  if (raw.type === 'set' && typeof raw.tabId === 'number') {
    const command: SetCommand = { type: 'set', tabId: raw.tabId };
    if (typeof raw.volume === 'number') command.volume = raw.volume;
    if (typeof raw.muted === 'boolean') command.muted = raw.muted;
    if (typeof raw.micMuted === 'boolean') command.micMuted = raw.micMuted;
    return command;
  }
  return undefined;
}

// ---------- chrome.runtime: content script ↔ service worker ----------

/** What a tab is told to do with its media and its microphone. */
export interface TabConfig {
  volume: number;
  micMuted: boolean;
}

/** From the relay to the service worker. */
export type ContentMessage = { type: 'hello' } | { type: 'mic'; mic: boolean };

export function parseContentMessage(raw: unknown): ContentMessage | undefined {
  if (!isRecord(raw)) return undefined;
  if (raw.type === 'hello') return { type: 'hello' };
  if (raw.type === 'mic') return { type: 'mic', mic: !!raw.mic };
  return undefined;
}

/** From the service worker to the relay of a tab. */
export interface ConfigMessage extends TabConfig {
  type: 'config';
}

/** A settings object read from a message or from storage: whatever is wrong falls back to "untouched". */
export function toTabConfig(raw: unknown): TabConfig | undefined {
  if (!isRecord(raw)) return undefined;
  return { volume: clampVolume(Number(raw.volume)), micMuted: !!raw.micMuted };
}

export function parseConfigMessage(raw: unknown): ConfigMessage | undefined {
  if (!isRecord(raw) || raw.type !== 'config') return undefined;
  const config = toTabConfig(raw);
  return config && { type: 'config', ...config };
}

/**
 * From the service worker to the relay of a tab: say again whether the page holds the microphone. The worker forgets
 * that when it is put to sleep, and a page only reports the microphone when it changes.
 */
export interface ResyncMessage {
  type: 'resync';
}

export function parseResyncMessage(raw: unknown): ResyncMessage | undefined {
  return isRecord(raw) && raw.type === 'resync' ? { type: 'resync' } : undefined;
}

// ---------- window.postMessage: relay ↔ page ----------

/** Marks the messages of this extension among everything else a page posts to itself. */
export const PAGE_TAG = '__soundbar';

export type PageMessage = { type: 'mic'; mic: boolean } | ConfigMessage | ResyncMessage;

/** The envelope the two worlds exchange. */
export function toPageEnvelope(message: PageMessage): Record<string, unknown> {
  return { [PAGE_TAG]: 1, ...message };
}

export function parsePageEnvelope(raw: unknown): PageMessage | undefined {
  if (!isRecord(raw) || raw[PAGE_TAG] !== 1) return undefined;
  if (raw.type === 'mic') return { type: 'mic', mic: !!raw.mic };
  return parseResyncMessage(raw) ?? parseConfigMessage(raw);
}
