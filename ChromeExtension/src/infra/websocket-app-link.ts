import type { AppLink } from '../domain/ports';

/** The part of `WebSocket` this adapter uses (so a spec can stand in for it). */
export interface WebSocketLike {
  readonly readyState: number;
  send(data: string): void;
  onopen: ((event: Event) => unknown) | null;
  onmessage: ((event: MessageEvent) => unknown) | null;
  onclose: ((event: CloseEvent) => unknown) | null;
  onerror: ((event: Event) => unknown) | null;
}

export type WebSocketFactory = (url: string) => WebSocketLike;

const CONNECTING = 0;
const OPEN = 1;

/** The connection to the SoundBar app, over a WebSocket on the local machine. */
export class WebSocketAppLink implements AppLink {
  onOpen: (() => void) | null = null;
  onMessage: ((text: string) => void) | null = null;

  private socket: WebSocketLike | null = null;

  constructor(
    private readonly url: string,
    private readonly create: WebSocketFactory,
  ) {}

  isOpen(): boolean {
    return this.socket?.readyState === OPEN;
  }

  connect(): void {
    const current = this.socket;
    if (current && (current.readyState === OPEN || current.readyState === CONNECTING)) return;

    let socket: WebSocketLike;
    try {
      socket = this.create(this.url);
    } catch {
      return; // the next heartbeat tries again
    }
    this.socket = socket;
    socket.onopen = () => this.onOpen?.();
    socket.onmessage = (event) => {
      if (typeof event.data === 'string') this.onMessage?.(event.data);
    };
    socket.onclose = () => {
      if (this.socket === socket) this.socket = null;
    };
    socket.onerror = () => undefined; // `onclose` follows, and the heartbeat reconnects
  }

  send(text: string): void {
    try {
      this.socket?.send(text);
    } catch {
      // the app went away while sending: `onclose` is on its way
    }
  }
}
