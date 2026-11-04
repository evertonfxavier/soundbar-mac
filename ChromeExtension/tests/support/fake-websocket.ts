import type { WebSocketLike } from '../../src/infra/websocket-app-link';

export const CONNECTING = 0;
export const OPEN = 1;
export const CLOSED = 3;

/** A WebSocket the spec drives by hand. */
export class FakeWebSocket implements WebSocketLike {
  readyState = CONNECTING;
  sent: string[] = [];
  failOnSend = false;
  onopen: ((event: Event) => unknown) | null = null;
  onmessage: ((event: MessageEvent) => unknown) | null = null;
  onclose: ((event: CloseEvent) => unknown) | null = null;
  onerror: ((event: Event) => unknown) | null = null;

  constructor(readonly url: string) {}

  send(data: string): void {
    if (this.failOnSend) throw new Error('InvalidStateError');
    this.sent.push(data);
  }

  // what the network would do
  open(): void {
    this.readyState = OPEN;
    this.onopen?.(new Event('open'));
  }

  receive(data: unknown): void {
    this.onmessage?.({ data } as MessageEvent);
  }

  close(): void {
    this.readyState = CLOSED;
    this.onclose?.({} as CloseEvent);
  }

  /** The messages sent so far, parsed. */
  get messages(): { type: string; [key: string]: unknown }[] {
    return this.sent.map((text) => JSON.parse(text) as { type: string });
  }
}

/** A factory that remembers every socket it made. */
export function socketFactory() {
  const made: FakeWebSocket[] = [];
  const create = (url: string) => {
    const socket = new FakeWebSocket(url);
    made.push(socket);
    return socket;
  };
  return {
    create,
    made,
    get last() {
      return made[made.length - 1];
    },
  };
}
