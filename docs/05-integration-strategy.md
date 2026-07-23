# Duesday — Integration Strategy (Email, Detection, Backend)

## Provider abstraction

```swift
protocol EmailProvider {           // Phase 3, module EmailProviders
    var kind: EmailProviderKind { get }
    func authenticate() async throws -> ProviderSession          // ASWebAuthenticationSession/MSAL
    func refreshCredentials() async throws
    func disconnect() async throws                               // revoke + wipe keychain
    func accountProfile() async throws -> ProviderProfile
    func grantedPermissions() async throws -> [ProviderScope]
    func searchMessages(_ query: ProviderQuery) async throws -> [MessageRef]
    func messageMetadata(_ refs: [MessageRef]) async throws -> [MessageMetadata]
    func messageContent(_ ref: MessageRef) async throws -> MimeMessage
    func incrementalChanges(since cursor: SyncCursor?) async throws -> ChangeSet // historyId / delta
    func purgeLocalCache() async throws
}
```

`GmailProvider` ships first (Phase 3). `MicrosoftProvider` (Phase 6) implements the same
protocol over Graph. Neither blocks Phases 1–2.

## Gmail specifics

- Auth: `ASWebAuthenticationSession` + PKCE. Dev builds may exchange the code directly
  (iOS Google clients need no secret); production routes the exchange through the backend so
  refresh tokens can also power server-side watch.
- Scope: `https://www.googleapis.com/auth/gmail.readonly` (restricted — verification gate).
- Search, not download: targeted queries built from a localized term registry
  (subscription, renewal, membership, recurring, trial, invoice, receipt, payment, charged,
  billing, plan, auto-renew, cancellation, price change, payment failed — plus per-locale
  equivalents and merchant-specific sender patterns, e.g. `from:(*.netflix.com)`), category
  filters (`category:purchases`), and date windows (initial backfill 12 months, paged).
- Incremental: store `historyId` as `syncCursor`; fall back to windowed search when history
  is expired (404).

## Detection pipeline (Phase 3, module SubscriptionDetection)

Deterministic stages, each pure and fixture-tested:
provider search → metadata retrieval → MIME parse → HTML sanitize → text normalize →
merchant detect (sender domain registry + display-name heuristics) → amount/currency extract
(locale-aware, `Decimal`) → frequency extract ("billed monthly", "/mo", "annual plan") →
billing-date extract → trial detect → cancellation detect → price-change detect →
field+candidate confidence scoring (weighted evidence) → duplicate match (messageID →
merchant+amount+currency+interval+date-proximity → existing subscriptions/candidates) →
candidate creation → user review queue.

Rules: never invent values (missing = nil), keep ≤160-char evidence snippets, everything
else discarded. Confidence weights are data-driven constants with fixture-based calibration
tests. Optional model-assisted classifier per ADR-8.

## Backend (Phase 5) — production architecture

- **Stack:** TypeScript, Node 22, Fastify, PostgreSQL 16, BullMQ on Redis, Docker;
  dev/staging/prod environments; secrets in the platform KMS/secret manager.
- **Auth model:** Sign in with Apple → backend session (short-lived JWT + rotating refresh);
  device binding via APNs token registration.
- **API (v1, JSON, TLS):**
  - `POST /v1/oauth/google/exchange` {code, codeVerifier} → stores refresh token, returns
    account descriptor (never the refresh token).
  - `POST /v1/oauth/google/revoke`, same for microsoft.
  - `POST /v1/accounts/:id/watch` — start Gmail `users.watch` (Pub/Sub) / Graph subscription.
  - `POST /v1/webhooks/gmail` (Pub/Sub push, OIDC-verified), `POST /v1/webhooks/msgraph`
    (validationToken + clientState).
  - `POST /v1/devices` — APNs registration. Silent push nudges the app to sync; message
    content never transits our servers unless server-side processing is explicitly enabled.
  - `DELETE /v1/users/me` — 30-day cascading deletion, audit-logged.
- **DB schema (core):** `users`, `email_accounts` (provider, address, status, cursor),
  `oauth_tokens` (ciphertext, key_id, expiry), `devices` (apns_token), `webhook_events`
  (idempotency), `audit_log` (actor, action, entity — no content).
- **Token encryption:** envelope encryption — per-row data key (AES-256-GCM) wrapped by KMS
  master key; keys rotated; tokens never logged.
- **Workers:** watch-renewal job (Gmail watch expires ≤7 days; Graph ≤3), sync-nudge job,
  deletion job; retries with exponential backoff + jitter, dead-letter queue.
- **Hygiene:** per-user and per-IP rate limits, idempotency keys on mutating routes,
  webhook signature verification, structured audit logging without message content,
  retention: webhook payload metadata 30 days, audit log 1 year.

## Import workflows (Phase 4)

Share extension + document picker accept PDFs, images, `.eml`, text. VisionKit/Vision OCR
on-device → same normalization/extraction stages → review queue. Files carry
`ImportedDocument` records and are purged post-processing (`deletionDate`).

## Apple Mail stance

Apple Mail cannot be searched by third-party apps. UI copy offers: connect the underlying
Gmail/Microsoft account, share/forward the email into Duesday, or manual entry. No feature
ever implies otherwise.
