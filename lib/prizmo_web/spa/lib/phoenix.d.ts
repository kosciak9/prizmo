declare module 'phoenix' {
  export class Socket {
    constructor(endPoint: string, opts?: Record<string, unknown>)
    connect(params?: Record<string, unknown>): void
    disconnect(callback?: () => void, code?: number, reason?: string): void
    channel(topic: string, params?: Record<string, unknown>): Channel
  }

  export class Channel {
    topic: string
    join(timeout?: number): Push
    leave(timeout?: number): Push
    push(event: string, payload: Record<string, unknown>, timeout?: number): Push
    on(event: string, callback: (payload: any) => void): number
    off(event: string, ref?: number): void
  }

  export class Push {
    receive(status: 'ok' | 'error' | 'timeout', callback: (payload: any) => void): Push
  }
}
