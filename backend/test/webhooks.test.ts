import assert from "node:assert/strict";
import test from "node:test";
import { buildApp, type AppDependencies } from "../src/app.js";
import { renewExpiringWatches } from "../src/workers/watchRenewal.js";

function makeDeps(overrides: Partial<AppDependencies> = {}): AppDependencies & { synced: string[] } {
  const synced: string[] = [];
  return {
    synced,
    exchangeGoogle: async () => ({ accountId: "a-1", email: "a@b.com" }),
    revokeGoogle: async () => {},
    registerDevice: async () => {},
    deleteUser: async () => {},
    enqueueSync: async (accountId: string) => {
      synced.push(accountId);
    },
    gmailWebhookSecret: "gmail-secret",
    msgraphClientState: "graph-state",
    ...overrides
  };
}

test("msgraph handshake echoes the validation token as text/plain", async () => {
  const deps = makeDeps();
  const app = await buildApp(deps);
  const response = await app.inject({
    method: "POST",
    url: "/v1/webhooks/msgraph?validationToken=token-123"
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["content-type"]?.toString().includes("text/plain"), true);
  assert.equal(response.body, "token-123");
  await app.close();
});

test("msgraph notifications with the right clientState enqueue sync once", async () => {
  const deps = makeDeps();
  const app = await buildApp(deps);
  const notification = {
    value: [
      { clientState: "graph-state", subscriptionId: "sub-1", resourceData: { id: "m-1" } },
      { clientState: "WRONG", subscriptionId: "sub-2", resourceData: { id: "m-2" } }
    ]
  };
  const first = await app.inject({ method: "POST", url: "/v1/webhooks/msgraph", payload: notification });
  assert.equal(first.statusCode, 202);
  assert.deepEqual(deps.synced, ["sub-1"]);

  // Replay of the same notification is idempotent.
  const second = await app.inject({ method: "POST", url: "/v1/webhooks/msgraph", payload: notification });
  assert.equal(second.statusCode, 202);
  assert.deepEqual(deps.synced, ["sub-1"]);
  await app.close();
});

test("gmail webhook rejects a bad signature", async () => {
  const deps = makeDeps();
  const app = await buildApp(deps);
  const response = await app.inject({
    method: "POST",
    url: "/v1/webhooks/gmail",
    headers: { "x-duesday-signature": "nope", "x-event-id": "e-1" },
    payload: { accountId: "a-1" }
  });
  assert.equal(response.statusCode, 401);
  assert.deepEqual(deps.synced, []);
  await app.close();
});

test("watch renewal renews per provider and flags failures", async () => {
  const renewed: string[] = [];
  const failed: string[] = [];
  const result = await renewExpiringWatches({
    findExpiring: async () => [
      { accountId: "g-1", provider: "gmail" },
      { accountId: "m-1", provider: "microsoft" },
      { accountId: "g-2", provider: "gmail" }
    ],
    renewGmailWatch: async (accountId) => {
      if (accountId === "g-2") throw new Error("expired grant");
      renewed.push(accountId);
    },
    renewGraphSubscription: async (accountId) => {
      renewed.push(accountId);
    },
    markWatchFailed: async (accountId) => {
      failed.push(accountId);
    }
  });
  assert.deepEqual(renewed, ["g-1", "m-1"]);
  assert.deepEqual(failed, ["g-2"]);
  assert.deepEqual(result, { renewed: 2, failed: 1 });
});
