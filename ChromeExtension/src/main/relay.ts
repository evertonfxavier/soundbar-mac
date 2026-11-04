// Entry point of the isolated-world content script (manifest: content_scripts). See start-relay.ts.
import { startRelay } from './start-relay';

startRelay({ window, runtime: chrome.runtime });
