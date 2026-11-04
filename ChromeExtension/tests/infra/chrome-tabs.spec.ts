import { describe, expect, it, vi } from 'vitest';
import { ChromeTabsGateway } from '../../src/infra/chrome-tabs';

function fakeTabs(tabs: Partial<chrome.tabs.Tab>[] = []) {
  return {
    query: vi.fn(() => Promise.resolve(tabs as chrome.tabs.Tab[])),
    update: vi.fn(() => Promise.resolve({} as chrome.tabs.Tab)),
    sendMessage: vi.fn(() => Promise.resolve()),
  };
}

describe('ChromeTabsGateway', () => {
  it('lists every tab of every window, reduced to what the app is told', async () => {
    const tabs = fakeTabs([
      {
        id: 1,
        title: 'Lo-fi',
        url: 'https://www.youtube.com/watch',
        pendingUrl: 'https://next.example.com',
        favIconUrl: 'https://www.youtube.com/f.ico',
        audible: true,
        mutedInfo: { muted: true },
      },
      { id: 2 },
    ]);

    const list = await new ChromeTabsGateway(tabs as never).list();

    expect(tabs.query).toHaveBeenCalledWith({});
    expect(list).toEqual([
      {
        id: 1,
        title: 'Lo-fi',
        url: 'https://www.youtube.com/watch',
        pendingUrl: 'https://next.example.com',
        favIconUrl: 'https://www.youtube.com/f.ico',
        audible: true,
        muted: true,
      },
      { id: 2, audible: false, muted: false },
    ]);
  });

  it('skips a tab that has no id (it cannot be addressed)', async () => {
    const tabs = fakeTabs([{ title: 'ghost' }, { id: 5 }]);

    expect(await new ChromeTabsGateway(tabs as never).list()).toEqual([{ id: 5, audible: false, muted: false }]);
  });

  it('mutes a tab in the browser', async () => {
    const tabs = fakeTabs();

    await new ChromeTabsGateway(tabs as never).setMuted(7, true);

    expect(tabs.update).toHaveBeenCalledWith(7, { muted: true });
  });

  it('does not fail when the tab was closed before the mute arrived', async () => {
    const tabs = fakeTabs();
    tabs.update.mockRejectedValueOnce(new Error('No tab with id: 7'));

    await expect(new ChromeTabsGateway(tabs as never).setMuted(7, true)).resolves.toBeUndefined();
  });

  it('sends the config to the content scripts of the tab', () => {
    const tabs = fakeTabs();

    new ChromeTabsGateway(tabs as never).sendConfig(7, { volume: 0.5, micMuted: true });

    expect(tabs.sendMessage).toHaveBeenCalledWith(7, { type: 'config', volume: 0.5, micMuted: true });
  });

  it('does not fail when the tab has no content script to receive it', async () => {
    const tabs = fakeTabs();
    tabs.sendMessage.mockRejectedValueOnce(new Error('Could not establish connection. Receiving end does not exist.'));

    new ChromeTabsGateway(tabs as never).sendConfig(7, { volume: 1, micMuted: false });

    await Promise.resolve(); // an unhandled rejection would fail the run here
  });

  it('asks the content scripts of the tab to report the microphone again', () => {
    const tabs = fakeTabs();

    new ChromeTabsGateway(tabs as never).requestMicReport(7);

    expect(tabs.sendMessage).toHaveBeenCalledWith(7, { type: 'resync' });
  });

  it('does not fail when the tab cannot be asked (no content script, or already gone)', async () => {
    const tabs = fakeTabs();
    tabs.sendMessage.mockRejectedValueOnce(new Error('Could not establish connection. Receiving end does not exist.'));

    new ChromeTabsGateway(tabs as never).requestMicReport(7);

    await Promise.resolve(); // an unhandled rejection would fail the run here
  });
});
