# Duesday — Implementation Roadmap

Milestones are cut so the project compiles and tests pass at every merge.

## Phase 1 — Foundation (this milestone)
DuesdayKit package; CoreModels (all 6 entities, Money, BillingFrequency + custom intervals,
BillingSchedule date math, SpendingMath, MerchantNormalizer, privacy-safe logging);
Persistence (container factory with in-memory + fallback bootstrap, SubscriptionRepository);
DesignSystem (tokens + StatusBadge, state views, button styles, AmountText, haptics);
TestingSupport (sample data, preview containers); feature-module shells with live-data empty
states; app DI + 5-tab navigation shell; unit tests (money, frequency, schedule, currency
grouping, normalizer, repository, form model). **Exit:** `swift test` green, simulator build
green.

## Phase 2 — Manual MVP
Onboarding + privacy explanation + notification pre-permission education; full manual
subscription form (validation, all fields incl. trial/intro pricing/cancellation info);
subscription detail (edit, archive, delete, cancellation info, reminder rules); dashboard
(monthly/annual estimates per currency, next 7/30-day totals, upcoming list); renewal
calendar; Notifications module (rule → nearest-N scheduling within the 64-request budget,
replenishment on foreground/BGTask, category actions, deep links, quiet hours, DST/TZ
tests); settings (appearance, app lock via LAContext, export JSON/CSV, delete-all);
snapshot + UI tests; accessibility pass (Dynamic Type, VoiceOver labels, 44 pt targets).

## Phase 3 — Gmail integration
Networking (URLSession client, retry/backoff, no third-party HTTP lib); Authentication
(ASWebAuthenticationSession + PKCE, Keychain token store); EmailProviders abstraction +
GmailProvider; targeted search + incremental sync (historyId); MIME parser + HTML sanitizer;
SubscriptionDetection pipeline + confidence + dedup; review queue UI (confirm/edit/merge/
ignore/reject, evidence display, bulk confirm for high confidence only); disconnect +
delete-imported-data flows; parser fixture suite (16 fixture classes per spec).
**External gate:** Google Cloud OAuth client.

## Phase 4 — Import workflows
Share extension (App Group), document picker, VisionKit scan; OCR extraction → shared
pipeline; import review; secure file lifecycle (protection class, purge, `deletionDate`).

## Phase 5 — Backend & remote sync
TypeScript service per integration doc; token vault; Gmail watch + Graph webhooks; APNs
silent sync nudges; BGAppRefreshTask + backoff; last-sync status UI; idempotent ingestion.
**External gates:** hosting, APNs key, Pub/Sub topic.

## Phase 6 — Microsoft integration
MSAL dependency (justified per ADR-6); MicrosoftProvider over Graph delta queries;
multi-account support surfaced in accounts UI; provider-parity fixture tests.

## Phase 7 — Hardening & submission
Security review vs threat model; privacy manifest + labels; performance (launch, scroll,
sync memory); accessibility audit; localization scaffolding (String Catalogs already on);
App Store assets; TestFlight checklist; data-migration tests (SchemaV1→V2 dry run).

## Testing map (spec → suite)
Unit: CoreModelsTests, PersistenceTests, NotificationsTests (P2), DetectionTests (P3).
Fixtures: 16 email classes (P3), OCR samples (P4). UI: onboarding, manual add, review queue,
disconnect (P2/P3). Accessibility: audit tests (P2). Security: keychain/log-redaction/
sanitizer tests (P2–P3). Backend: API contract + webhook replay tests (P5). Offline &
migration: P5/P7.
