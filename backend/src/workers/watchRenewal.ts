/**
 * Watch-renewal worker: provider mailbox watches expire (Gmail ≤7 days,
 * Graph subscriptions ≤3 days), so a periodic pass re-arms any that are
 * close to lapsing. Dependency-injected like the app so it is testable
 * without providers or a database.
 */
export interface ExpiringWatch {
  accountId: string;
  provider: "gmail" | "microsoft";
}

export interface WatchRenewalDependencies {
  /** Watches expiring within the look-ahead window. */
  findExpiring(withinMinutes: number): Promise<ExpiringWatch[]>;
  renewGmailWatch(accountId: string): Promise<void>;
  renewGraphSubscription(accountId: string): Promise<void>;
  /** Called when a renewal fails so the account can be flagged for re-auth. */
  markWatchFailed(accountId: string, reason: string): Promise<void>;
}

export interface WatchRenewalResult {
  renewed: number;
  failed: number;
}

export async function renewExpiringWatches(
  deps: WatchRenewalDependencies,
  lookAheadMinutes = 12 * 60
): Promise<WatchRenewalResult> {
  const expiring = await deps.findExpiring(lookAheadMinutes);
  let renewed = 0;
  let failed = 0;
  for (const watch of expiring) {
    try {
      if (watch.provider === "gmail") {
        await deps.renewGmailWatch(watch.accountId);
      } else {
        await deps.renewGraphSubscription(watch.accountId);
      }
      renewed += 1;
    } catch (error) {
      failed += 1;
      const reason = error instanceof Error ? error.message : "unknown";
      await deps.markWatchFailed(watch.accountId, reason);
    }
  }
  return { renewed, failed };
}

/** Runs the renewal pass on an interval; returns a stop function. */
export function startWatchRenewalLoop(
  deps: WatchRenewalDependencies,
  intervalMs = 15 * 60 * 1000,
  onResult: (result: WatchRenewalResult) => void = () => {}
): () => void {
  const timer = setInterval(() => {
    void renewExpiringWatches(deps).then(onResult).catch(() => {});
  }, intervalMs);
  timer.unref?.();
  return () => clearInterval(timer);
}
