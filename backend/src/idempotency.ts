export class IdempotencyWindow {
  private readonly seen = new Map<string, number>();
  constructor(private readonly ttlMs = 30 * 24 * 60 * 60 * 1000) {}

  accept(key: string, now = Date.now()): boolean {
    this.prune(now);
    if (this.seen.has(key)) return false;
    this.seen.set(key, now + this.ttlMs);
    return true;
  }

  private prune(now: number) {
    for (const [key, expiry] of this.seen) {
      if (expiry <= now) this.seen.delete(key);
    }
  }
}
