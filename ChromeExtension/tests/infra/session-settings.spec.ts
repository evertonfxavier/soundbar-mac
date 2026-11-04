import { afterEach, describe, expect, it, vi } from 'vitest';
import { SessionSettingsStore } from '../../src/infra/session-settings';

afterEach(() => {
  vi.restoreAllMocks();
});

const area = (stored: unknown = {}) => ({
  get: vi.fn(() => Promise.resolve(stored)),
  set: vi.fn(() => Promise.resolve()),
});

describe('SessionSettingsStore', () => {
  it('loads what was saved under "settings"', async () => {
    const storage = area({ settings: { 4: { volume: 0.3, micMuted: true } } });

    expect(await new SessionSettingsStore(storage as never).load()).toEqual({ 4: { volume: 0.3, micMuted: true } });
    expect(storage.get).toHaveBeenCalledWith('settings');
  });

  it('starts empty when nothing was saved, or what was saved is not an object', async () => {
    for (const stored of [{}, { settings: null }, { settings: 'x' }, { settings: 3 }]) {
      expect(await new SessionSettingsStore(area(stored) as never).load(), JSON.stringify(stored)).toEqual({});
    }
  });

  it('starts empty, and says why, when the storage cannot be read', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const storage = area();
    storage.get.mockRejectedValueOnce(new Error('boom'));

    expect(await new SessionSettingsStore(storage as never).load()).toEqual({});
    expect(warn).toHaveBeenCalled();
  });

  it('saves the settings under "settings"', () => {
    const storage = area();

    new SessionSettingsStore(storage as never).save({ 4: { volume: 0.3 } });

    expect(storage.set).toHaveBeenCalledWith({ settings: { 4: { volume: 0.3 } } });
  });

  it('says so, and goes on, when the storage cannot be written', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const storage = area();
    storage.set.mockRejectedValueOnce(new Error('quota'));

    new SessionSettingsStore(storage as never).save({});
    await vi.waitFor(() => expect(warn).toHaveBeenCalled());
  });
});
