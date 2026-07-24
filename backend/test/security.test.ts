import assert from "node:assert/strict";
import test from "node:test";
import { IdempotencyWindow } from "../src/idempotency.js";
import { TokenVault } from "../src/tokenVault.js";

test("token vault round-trips without plaintext in the envelope", () => {
  const vault = new TokenVault(Buffer.alloc(32, 7));
  const envelope = vault.seal("refresh-secret");
  assert.equal(vault.open(envelope), "refresh-secret");
  assert.equal(JSON.stringify(envelope).includes("refresh-secret"), false);
});

test("webhook idempotency rejects replay until expiry", () => {
  const window = new IdempotencyWindow(100);
  assert.equal(window.accept("event-1", 0), true);
  assert.equal(window.accept("event-1", 50), false);
  assert.equal(window.accept("event-1", 101), true);
});
