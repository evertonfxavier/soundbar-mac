import { describe, expect, it } from 'vitest';
import { BRIDGE_HOST, BRIDGE_PORT, BRIDGE_URL } from '../../src/domain/config';
import { parseAppMessage, serialize, type ExtensionMessage, type SetCommand } from '../../src/domain/protocol';
import { ActivityLog, MicRegistry, listTabs } from '../../src/domain/tabs';
import { protocol, readContract } from '../support/contract';

/*
 * contract/ at the root of the repository is what this extension and the SoundBar app agree on. The Swift tests
 * (Tests/SoundBarCoreTests/ContractTests.swift) read the same files: if one side changes without the other, one of
 * the two suites fails.
 */

describe('the address of the app', () => {
  it('is the one in contract/protocol.json', () => {
    expect(BRIDGE_HOST).toBe(protocol.host);
    expect(BRIDGE_PORT).toBe(protocol.port);
    expect(BRIDGE_URL).toBe(`ws://${protocol.host}:${protocol.port}`);
  });
});

describe('what the extension sends', () => {
  it('writes the tabs exactly as the fixture shows them', () => {
    const fixture = readContract<ExtensionMessage & { type: 'tabs' }>('fixtures/tabs.json');
    const mics = new MicRegistry();
    mics.set(34, 0, true);

    const tabs = listTabs(
      [
        {
          id: 12,
          title: 'Lo-fi beats to relax to',
          url: 'https://www.youtube.com/watch?v=1',
          favIconUrl: 'https://www.youtube.com/favicon.ico',
          audible: true,
          muted: false,
        },
        { id: 34, url: 'https://meet.google.com/abc', audible: false, muted: true },
      ],
      {
        settings: { 12: { volume: 0.5 }, 34: { micMuted: true } },
        mics,
        activity: new ActivityLog(),
        now: 0,
        idleMs: 15_000,
      },
    );

    expect(JSON.parse(serialize({ type: 'tabs', tabs }))).toEqual(fixture);
  });

  it('writes the ping exactly as the fixture shows it', () => {
    expect(JSON.parse(serialize({ type: 'ping' }))).toEqual(readContract('fixtures/ping.json'));
  });
});

describe('what the extension understands', () => {
  it('reads the set command of the fixture', () => {
    const fixture = readContract<SetCommand>('fixtures/set.json');

    expect(parseAppMessage(JSON.stringify(fixture))).toEqual(fixture);
    expect(fixture).toEqual({ type: 'set', tabId: 12, volume: 0.5, muted: false, micMuted: true });
  });

  it('reads the pong of the fixture', () => {
    expect(parseAppMessage(JSON.stringify(readContract('fixtures/pong.json')))).toEqual({ type: 'pong' });
  });
});
