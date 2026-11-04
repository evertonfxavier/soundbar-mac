import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/** contract/ at the root of the repository: what the extension and the app agree on, and are both checked against. */
const CONTRACT_DIR = resolve(import.meta.dirname, '../../../contract');

export function readContract<T = unknown>(path: string): T {
  return JSON.parse(readFileSync(resolve(CONTRACT_DIR, path), 'utf8')) as T;
}

export const protocol = readContract<{ host: string; port: number; originPrefix: string }>('protocol.json');
