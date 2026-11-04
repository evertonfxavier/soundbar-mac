import { IDLE_MS, SEND_DEBOUNCE_MS } from '../config';
import type { AppLink, SettingsStore, TabsGateway } from '../ports';
import { parseAppMessage, serialize, type SetCommand, type TabConfig } from '../protocol';
import { ActivityLog, MicRegistry, listTabs, type TabSettingsMap } from '../tabs';
import { clampVolume } from '../volume';

export interface BridgeDependencies {
  tabs: TabsGateway;
  store: SettingsStore;
  link: AppLink;
  now?: () => number;
}

/**
 * The work of the service worker: tell the SoundBar app which tabs make sound or use the microphone, and apply
 * the volume, mute and microphone settings the app sends back.
 *
 * Everything the worker reacts to is a method here; wiring them to the browser's events is src/main/start-background.ts.
 */
export class BridgeService {
  private settings: TabSettingsMap = {};
  private readonly activity = new ActivityLog();
  private readonly mics = new MicRegistry();
  private readonly loaded: Promise<void>;
  private readonly now: () => number;
  private lastSent = '';
  private sendTimer: ReturnType<typeof setTimeout> | undefined;

  constructor(private readonly deps: BridgeDependencies) {
    this.now = deps.now ?? Date.now;
    this.loaded = deps.store.load().then((saved) => {
      this.settings = saved;
    });
    deps.link.onOpen = () => {
      this.lastSent = ''; // a new connection knows nothing yet
      void this.sendState(true);
      void this.askForMicReports();
    };
    deps.link.onMessage = (text) => {
      const message = parseAppMessage(text);
      if (message?.type === 'set') void this.applySet(message);
    };
  }

  // ---------- Connection ----------

  connect(): void {
    this.deps.link.connect();
  }

  /** The heartbeat (a timer and an alarm call it): while connected, ping and publish; otherwise, try to connect. */
  tick(): void {
    if (this.deps.link.isOpen()) {
      this.deps.link.send(serialize({ type: 'ping' }));
      void this.sendState();
    } else {
      this.deps.link.connect();
    }
  }

  // ---------- Events of the tabs and of their content scripts ----------

  /** A frame of a tab started. It gets the settings of its tab; the main frame also forgets its old microphone. */
  async hello(tabId: number, frameId: number): Promise<TabConfig> {
    await this.loaded;
    if (frameId === 0) this.mics.clear(tabId);
    return this.configOf(tabId);
  }

  micChanged(tabId: number, frameId: number, mic: boolean): void {
    this.mics.set(tabId, frameId, mic);
    this.scheduleSend();
  }

  tabUpdated(tabId: number, status: string | undefined): void {
    if (status === 'loading') this.mics.clear(tabId);
    this.scheduleSend();
  }

  async tabRemoved(tabId: number): Promise<void> {
    await this.loaded;
    delete this.settings[tabId];
    this.activity.forget(tabId);
    this.mics.clear(tabId);
    this.persist();
    this.scheduleSend();
  }

  /** Chrome swaps a tab for another (a prerendered page): the settings follow. */
  async tabReplaced(addedId: number, removedId: number): Promise<void> {
    await this.loaded;
    const moved = this.settings[removedId];
    if (moved) this.settings[addedId] = moved;
    delete this.settings[removedId];
    this.persist();
    this.pushConfig(addedId);
    this.scheduleSend();
  }

  // ---------- Commands from the app ----------

  private async applySet(command: SetCommand): Promise<void> {
    await this.loaded;
    const id = command.tabId;
    const mine = (this.settings[id] ??= { volume: 1, micMuted: false });
    if (command.volume !== undefined) mine.volume = clampVolume(command.volume);
    if (command.micMuted !== undefined) mine.micMuted = command.micMuted;
    if (command.muted !== undefined) await this.deps.tabs.setMuted(id, command.muted);
    this.persist();
    this.pushConfig(id);
    this.scheduleSend();
  }

  // ---------- Publishing ----------

  /**
   * The worker forgets which pages hold a microphone when the browser puts it to sleep, and a page only says so when
   * that changes: a call that began while the app was not running would never be listed. So, on every new connection,
   * every tab is asked again. The answers arrive as `micChanged` and are published a moment later.
   */
  private async askForMicReports(): Promise<void> {
    for (const tab of await this.deps.tabs.list()) this.deps.tabs.requestMicReport(tab.id);
  }

  private async sendState(force = false): Promise<void> {
    if (!this.deps.link.isOpen()) return;
    const payload = serialize({ type: 'tabs', tabs: await this.listTabs() });
    if (!force && payload === this.lastSent) return;
    this.lastSent = payload;
    this.deps.link.send(payload);
  }

  private async listTabs() {
    await this.loaded;
    return listTabs(await this.deps.tabs.list(), {
      settings: this.settings,
      mics: this.mics,
      activity: this.activity,
      now: this.now(),
      idleMs: IDLE_MS,
    });
  }

  private scheduleSend(): void {
    clearTimeout(this.sendTimer);
    this.sendTimer = setTimeout(() => void this.sendState(), SEND_DEBOUNCE_MS);
  }

  private configOf(tabId: number): TabConfig {
    const mine = this.settings[tabId];
    return { volume: mine?.volume ?? 1, micMuted: !!mine?.micMuted };
  }

  private pushConfig(tabId: number): void {
    this.deps.tabs.sendConfig(tabId, this.configOf(tabId));
  }

  private persist(): void {
    this.deps.store.save(this.settings);
  }
}
