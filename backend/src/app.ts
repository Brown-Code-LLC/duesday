import Fastify from "fastify";
import rateLimit from "@fastify/rate-limit";
import { timingSafeEqual } from "node:crypto";
import { IdempotencyWindow } from "./idempotency.js";

export interface AppDependencies {
  exchangeGoogle(code: string, verifier: string): Promise<{ accountId: string; email: string }>;
  revokeGoogle(accountId: string): Promise<void>;
  registerDevice(userId: string, token: string): Promise<void>;
  deleteUser(userId: string): Promise<void>;
  enqueueSync(accountId: string): Promise<void>;
  gmailWebhookSecret: string;
  /** Shared secret echoed by Graph notifications as clientState. */
  msgraphClientState: string;
}

export async function buildApp(deps: AppDependencies) {
  const app = Fastify({ logger: { redact: ["req.headers.authorization", "req.body.code", "req.body.codeVerifier", "req.body.apnsToken"] } });
  await app.register(rateLimit, { max: 100, timeWindow: "1 minute" });
  const events = new IdempotencyWindow();

  app.get("/health", async () => ({ status: "ok" }));

  app.post<{ Body: { code: string; codeVerifier: string } }>(
    "/v1/oauth/google/exchange",
    async (request, reply) => {
      if (!request.body?.code || !request.body?.codeVerifier) return reply.code(400).send({ error: "invalid_request" });
      return deps.exchangeGoogle(request.body.code, request.body.codeVerifier);
    }
  );

  app.post<{ Params: { id: string } }>("/v1/oauth/google/revoke/:id", async (request, reply) => {
    await deps.revokeGoogle(request.params.id);
    return reply.code(204).send();
  });

  app.post<{ Body: { userId: string; apnsToken: string } }>("/v1/devices", async (request, reply) => {
    await deps.registerDevice(request.body.userId, request.body.apnsToken);
    return reply.code(204).send();
  });

  app.post<{ Headers: { "x-duesday-signature"?: string; "x-event-id"?: string }; Body: { accountId?: string } }>(
    "/v1/webhooks/gmail",
    async (request, reply) => {
      const supplied = Buffer.from(request.headers["x-duesday-signature"] ?? "");
      const expected = Buffer.from(deps.gmailWebhookSecret);
      if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
        return reply.code(401).send({ error: "invalid_signature" });
      }
      const eventId = request.headers["x-event-id"];
      if (!eventId || !request.body.accountId) return reply.code(400).send({ error: "invalid_event" });
      if (!events.accept(eventId)) return reply.code(202).send({ duplicate: true });
      await deps.enqueueSync(request.body.accountId);
      return reply.code(202).send({ accepted: true });
    }
  );

  // Microsoft Graph change notifications: the subscription handshake echoes
  // validationToken as text/plain; real notifications must carry the
  // clientState secret set when the subscription was created.
  app.post<{
    Querystring: { validationToken?: string };
    Body: {
      value?: Array<{ clientState?: string; resourceData?: { id?: string }; subscriptionId?: string }>;
    } | null;
  }>("/v1/webhooks/msgraph", async (request, reply) => {
    if (request.query.validationToken) {
      return reply.code(200).type("text/plain").send(request.query.validationToken);
    }
    const notifications = request.body?.value ?? [];
    if (notifications.length === 0) return reply.code(400).send({ error: "invalid_event" });

    let accepted = 0;
    for (const notification of notifications) {
      const supplied = Buffer.from(notification.clientState ?? "");
      const expected = Buffer.from(deps.msgraphClientState);
      if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) continue;
      const eventId = `msgraph:${notification.subscriptionId ?? ""}:${notification.resourceData?.id ?? ""}`;
      if (!notification.subscriptionId || !events.accept(eventId)) continue;
      await deps.enqueueSync(notification.subscriptionId);
      accepted += 1;
    }
    // Graph expects 202 regardless; bad clientState entries are dropped, not
    // errored, to avoid leaking validity oracles.
    return reply.code(202).send({ accepted });
  });

  app.delete<{ Params: { userId: string } }>("/v1/users/:userId", async (request, reply) => {
    await deps.deleteUser(request.params.userId);
    return reply.code(202).send({ deletionScheduledWithinDays: 30 });
  });

  return app;
}
