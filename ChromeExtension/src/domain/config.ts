/**
 * Where the SoundBar app listens for this extension. The app side is `BrowserBridge.defaultPort`;
 * both read the same value from `contract/protocol.json` in their specs, so they cannot drift apart.
 */
export const BRIDGE_HOST = '127.0.0.1';
export const BRIDGE_PORT = 38765;
export const BRIDGE_URL = `ws://${BRIDGE_HOST}:${BRIDGE_PORT}`;

/** A tab stays in the list this long after it went quiet, so its slider does not vanish between two songs. */
export const IDLE_MS = 15_000;

/** The heartbeat. While the socket is open its traffic also keeps the service worker alive (Chrome 116+). */
export const TICK_MS = 10_000;

/** Tab events come in bursts: the state is published once, this long after the last one. */
export const SEND_DEBOUNCE_MS = 150;

/** The alarm that wakes a sleeping service worker to reconnect (Chrome allows 30 s at the shortest). */
export const RECONNECT_ALARM = 'soundbar-reconnect';
export const RECONNECT_PERIOD_MINUTES = 0.5;

/** A volume under this counts as changed by the user, which keeps the tab listed even when it is silent. */
export const CHANGED_BELOW = 0.995;
