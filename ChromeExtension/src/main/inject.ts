// Entry point of the page-world content script (manifest: content_scripts, world MAIN). See start-inject.ts.
import { startInject } from './start-inject';

startInject(window);
