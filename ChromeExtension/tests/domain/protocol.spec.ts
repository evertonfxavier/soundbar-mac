import { describe, expect, it } from 'vitest';
import {
  PAGE_TAG,
  parseAppMessage,
  parseConfigMessage,
  parseContentMessage,
  parsePageEnvelope,
  parseResyncMessage,
  serialize,
  toPageEnvelope,
  toTabConfig,
} from '../../src/domain/protocol';

describe('parseAppMessage', () => {
  it('reads a set command with everything in it', () => {
    const text = JSON.stringify({ type: 'set', tabId: 7, volume: 0.4, muted: true, micMuted: false });

    expect(parseAppMessage(text)).toEqual({ type: 'set', tabId: 7, volume: 0.4, muted: true, micMuted: false });
  });

  it('carries only the fields that are there, so the others are left as they are', () => {
    const command = parseAppMessage('{"type":"set","tabId":7,"muted":true}');

    expect(command).toEqual({ type: 'set', tabId: 7, muted: true });
    expect(command).not.toHaveProperty('volume');
    expect(command).not.toHaveProperty('micMuted');
  });

  it('drops a field of the wrong type instead of trusting it', () => {
    expect(parseAppMessage('{"type":"set","tabId":7,"volume":"loud","muted":1,"micMuted":"yes"}')).toEqual({
      type: 'set',
      tabId: 7,
    });
  });

  it('needs the tab: a set command without a numeric tabId is nothing', () => {
    for (const text of ['{"type":"set"}', '{"type":"set","tabId":"7"}', '{"type":"set","tabId":null}']) {
      expect(parseAppMessage(text), text).toBeUndefined();
    }
  });

  it('reads the pong', () => {
    expect(parseAppMessage('{"type":"pong"}')).toEqual({ type: 'pong' });
  });

  it('ignores whatever else arrives, without throwing', () => {
    for (const text of ['', 'not json', 'null', '7', '"set"', '[]', '{}', '{"type":"reboot"}']) {
      expect(parseAppMessage(text), text).toBeUndefined();
    }
  });
});

describe('serialize', () => {
  it('writes the ping exactly as the app expects it', () => {
    expect(serialize({ type: 'ping' })).toBe('{"type":"ping"}');
  });
});

describe('parseContentMessage', () => {
  it('reads the hello and the microphone report', () => {
    expect(parseContentMessage({ type: 'hello' })).toEqual({ type: 'hello' });
    expect(parseContentMessage({ type: 'mic', mic: true })).toEqual({ type: 'mic', mic: true });
    expect(parseContentMessage({ type: 'mic' })).toEqual({ type: 'mic', mic: false });
  });

  it('ignores what is not one of them', () => {
    for (const raw of [undefined, null, 'hello', 3, {}, { type: 'config' }])
      expect(parseContentMessage(raw)).toBeUndefined();
  });
});

describe('toTabConfig', () => {
  it('reads the volume and the microphone switch', () => {
    expect(toTabConfig({ volume: 0.3, micMuted: true })).toEqual({ volume: 0.3, micMuted: true });
  });

  it('falls back to untouched for what is missing or wrong', () => {
    expect(toTabConfig({})).toEqual({ volume: 1, micMuted: false });
    expect(toTabConfig({ volume: 'x', micMuted: 0 })).toEqual({ volume: 1, micMuted: false });
    expect(toTabConfig({ volume: 9 })).toEqual({ volume: 1, micMuted: false });
  });

  it('is nothing when it is not an object', () => {
    for (const raw of [undefined, null, 'x', 4]) expect(toTabConfig(raw)).toBeUndefined();
  });
});

describe('parseConfigMessage', () => {
  it('reads a config message', () => {
    expect(parseConfigMessage({ type: 'config', volume: 0.5, micMuted: true })).toEqual({
      type: 'config',
      volume: 0.5,
      micMuted: true,
    });
  });

  it('ignores other messages', () => {
    expect(parseConfigMessage({ type: 'hello' })).toBeUndefined();
    expect(parseConfigMessage(null)).toBeUndefined();
  });
});

describe('parseResyncMessage', () => {
  it('reads the request to report the microphone again', () => {
    expect(parseResyncMessage({ type: 'resync' })).toEqual({ type: 'resync' });
  });

  it('ignores what is not that request', () => {
    for (const raw of [undefined, null, 'resync', {}, { type: 'config' }, { type: 'hello' }]) {
      expect(parseResyncMessage(raw)).toBeUndefined();
    }
  });
});

describe('the envelope between the page and the relay', () => {
  it('marks every message with the tag of the extension', () => {
    expect(toPageEnvelope({ type: 'mic', mic: true })).toEqual({ [PAGE_TAG]: 1, type: 'mic', mic: true });
  });

  it('opens what it wrapped, every kind', () => {
    expect(parsePageEnvelope(toPageEnvelope({ type: 'mic', mic: true }))).toEqual({ type: 'mic', mic: true });
    const config = { type: 'config', volume: 0.2, micMuted: false } as const;
    expect(parsePageEnvelope(toPageEnvelope(config))).toEqual(config);
    expect(parsePageEnvelope(toPageEnvelope({ type: 'resync' }))).toEqual({ type: 'resync' });
  });

  it('ignores the messages a page posts for its own reasons', () => {
    for (const raw of [
      null,
      'hi',
      { type: 'mic', mic: true },
      { [PAGE_TAG]: 2, type: 'mic' },
      { [PAGE_TAG]: 1, type: 'nope' },
    ]) {
      expect(parsePageEnvelope(raw)).toBeUndefined();
    }
  });
});
