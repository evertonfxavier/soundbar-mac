import { describe, expect, it, vi } from 'vitest';
import { PAGE_TAG, toPageEnvelope } from '../../src/domain/protocol';
import { startRelay } from '../../src/main/start-relay';
import { createPageWindow } from '../support/page-window';

function setup(options: { answer?: unknown } = {}) {
  const answer = 'answer' in options ? options.answer : { volume: 0.5, micMuted: true };
  const page = createPageWindow();
  let fromWorker: ((message: unknown) => void) | undefined;
  const runtime = {
    sendMessage: vi.fn((message: { type: string }) => Promise.resolve(message.type === 'hello' ? answer : undefined)),
    onMessage: { addListener: (fn: (message: unknown) => void) => (fromWorker = fn) },
  };
  startRelay({ window: page.win, runtime: runtime as never });
  return { page, runtime, toRelay: (message: unknown) => fromWorker?.(message) };
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('startRelay', () => {
  it('says hello to the worker and hands the answer to the page as its config', async () => {
    const { page, runtime } = setup();
    await settle();

    expect(runtime.sendMessage).toHaveBeenCalledWith({ type: 'hello' });
    expect(page.posted).toEqual([{ [PAGE_TAG]: 1, type: 'config', volume: 0.5, micMuted: true }]);
  });

  it('hands the page a new config when the worker sends one', async () => {
    const { page, toRelay } = setup();
    await settle();

    toRelay({ type: 'config', volume: 0.2, micMuted: false });

    expect(page.posted.at(-1)).toEqual({ [PAGE_TAG]: 1, type: 'config', volume: 0.2, micMuted: false });
  });

  it('passes on to the page the worker asking it to report the microphone again', async () => {
    const { page, toRelay } = setup();
    await settle();

    toRelay({ type: 'resync' });

    expect(page.posted.at(-1)).toEqual({ [PAGE_TAG]: 1, type: 'resync' });
  });

  it('ignores what the worker sends that is neither a config nor a resync', async () => {
    const { page, toRelay } = setup();
    await settle();
    const before = page.posted.length;

    toRelay({ type: 'hello' });
    toRelay(null);

    expect(page.posted).toHaveLength(before);
  });

  it('hands the worker the microphone report of the page', async () => {
    const { page, runtime } = setup();
    await settle();

    page.deliver(toPageEnvelope({ type: 'mic', mic: true }));

    expect(runtime.sendMessage).toHaveBeenLastCalledWith({ type: 'mic', mic: true });
  });

  it('ignores what the page posts that is not its report, or that came from elsewhere', async () => {
    const { page, runtime } = setup();
    await settle();
    const calls = runtime.sendMessage.mock.calls.length;

    page.deliver(toPageEnvelope({ type: 'config', volume: 0.1, micMuted: false }));
    page.deliver({ type: 'mic', mic: true }); // no tag
    page.win.dispatchEvent(new page.win.MessageEvent('message', { data: toPageEnvelope({ type: 'mic', mic: true }) }));

    expect(runtime.sendMessage.mock.calls).toHaveLength(calls);
  });

  it('gives the page nothing when the worker has no answer', async () => {
    const { page } = setup({ answer: undefined });
    await settle();

    expect(page.posted).toEqual([]);
  });

  it('survives the worker not answering at all (an extension that was reloaded)', async () => {
    const page = createPageWindow();
    const runtime = {
      sendMessage: vi.fn(() => Promise.reject(new Error('Extension context invalidated.'))),
      onMessage: { addListener: vi.fn() },
    };

    expect(() => startRelay({ window: page.win, runtime: runtime as never })).not.toThrow();
    await settle();
    expect(page.posted).toEqual([]);
  });

  it('survives the runtime throwing (an orphaned script)', async () => {
    const page = createPageWindow();
    const runtime = {
      sendMessage: vi.fn(() => {
        throw new Error('Extension context invalidated.');
      }),
      onMessage: {
        addListener: vi.fn(() => {
          throw new Error('Extension context invalidated.');
        }),
      },
    };

    expect(() => startRelay({ window: page.win, runtime: runtime as never })).not.toThrow();
    page.deliver(toPageEnvelope({ type: 'mic', mic: true }));
    await settle();
    expect(page.posted).toEqual([]);
  });
});
