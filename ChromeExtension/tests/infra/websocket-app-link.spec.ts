import { describe, expect, it, vi } from 'vitest';
import { WebSocketAppLink } from '../../src/infra/websocket-app-link';
import { socketFactory } from '../support/fake-websocket';

const URL = 'ws://127.0.0.1:38765';

describe('WebSocketAppLink', () => {
  it('opens a socket to its address', () => {
    const sockets = socketFactory();

    new WebSocketAppLink(URL, sockets.create).connect();

    expect(sockets.made.map((s) => s.url)).toEqual([URL]);
  });

  it('is open only once the socket is', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    expect(link.isOpen()).toBe(false);

    link.connect();
    expect(link.isOpen()).toBe(false);

    sockets.last?.open();
    expect(link.isOpen()).toBe(true);
  });

  it('does not open a second socket while one is open or opening', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);

    link.connect();
    link.connect();
    sockets.last?.open();
    link.connect();

    expect(sockets.made).toHaveLength(1);
  });

  it('opens a new socket once the old one closed', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    link.connect();
    sockets.last?.open();

    sockets.last?.close();
    expect(link.isOpen()).toBe(false);
    link.connect();

    expect(sockets.made).toHaveLength(2);
  });

  it('is not misled by a socket that closes after it was replaced', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    link.connect();
    const first = sockets.last;
    first?.close();
    link.connect();
    sockets.last?.open();

    first?.onclose?.({} as CloseEvent); // a late event of the first socket

    expect(link.isOpen()).toBe(true);
  });

  it('tells its owner when the socket opens and what text arrives', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    link.onOpen = vi.fn();
    link.onMessage = vi.fn();
    link.connect();

    sockets.last?.open();
    sockets.last?.receive('{"type":"pong"}');

    expect(link.onOpen).toHaveBeenCalledOnce();
    expect(link.onMessage).toHaveBeenCalledWith('{"type":"pong"}');
  });

  it('ignores what is not text (binary frames), and works without anyone listening', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    link.onMessage = vi.fn();
    link.connect();

    sockets.last?.receive(new Uint8Array([1]));
    expect(link.onMessage).not.toHaveBeenCalled();

    link.onMessage = null;
    expect(() => {
      sockets.last?.open();
      sockets.last?.receive('x');
    }).not.toThrow();
  });

  it('sends text through the open socket', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    link.connect();
    sockets.last?.open();

    link.send('hello');

    expect(sockets.last?.sent).toEqual(['hello']);
  });

  it('does not fail to send with no socket, nor when the socket refuses', () => {
    const sockets = socketFactory();
    const link = new WebSocketAppLink(URL, sockets.create);
    expect(() => link.send('x')).not.toThrow();

    link.connect();
    sockets.last!.failOnSend = true;
    expect(() => link.send('x')).not.toThrow();
  });

  it('stays closed, and tries again at the next connect, when the socket cannot even be created', () => {
    const create = vi.fn(() => {
      throw new Error('SecurityError');
    });
    const link = new WebSocketAppLink(URL, create);

    expect(() => link.connect()).not.toThrow();
    link.connect();

    expect(create).toHaveBeenCalledTimes(2);
    expect(link.isOpen()).toBe(false);
  });

  it('swallows the error event of the socket (the close that follows is what matters)', () => {
    const sockets = socketFactory();
    new WebSocketAppLink(URL, sockets.create).connect();

    expect(() => sockets.last?.onerror?.(new Event('error'))).not.toThrow();
  });
});
