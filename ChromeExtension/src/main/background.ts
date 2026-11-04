// Entry point of the service worker (manifest: background.service_worker). See start-background.ts.
import { startBackground } from './start-background';

startBackground(chrome, (url) => new WebSocket(url));
