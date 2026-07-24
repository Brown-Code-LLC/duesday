import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
const unavailable = async (): Promise<never> => {
  throw new Error("Production repository adapter is not configured");
};
const app = await buildApp({
  exchangeGoogle: unavailable,
  revokeGoogle: unavailable,
  registerDevice: unavailable,
  deleteUser: unavailable,
  enqueueSync: unavailable,
  gmailWebhookSecret: process.env.GMAIL_WEBHOOK_SECRET ?? "",
  msgraphClientState: process.env.MSGRAPH_CLIENT_STATE ?? ""
});
await app.listen({ host: "0.0.0.0", port: config.port });
