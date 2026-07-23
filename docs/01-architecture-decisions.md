# Duesday — Architecture Decision Record

Status: Accepted · 2026-07-23 · Applies from Phase 1

## ADR-1: App structure — thin app target + local Swift package

**Decision.** All product code lives in a local Swift package `DuesdayKit` with one target
per module. The Xcode app target contains only composition: `@main`, dependency wiring,
navigation shell, asset catalog, Info.plist keys.

**Why.** Real compiler-enforced module boundaries; `swift test` runs the whole unit suite
without a simulator; features are mockable via protocol seams; the existing project uses
filesystem-synchronized groups, so the app target stays nearly untouched as code grows.

**Modules (phase in parentheses):**
CoreModels (1) · DesignSystem (1) · Persistence (1) · TestingSupport (1) ·
FeatureOverview (1) · FeatureSubscriptions (1–2) · FeatureCalendar (1–2) ·
FeatureInsights (1–2) · FeatureSettings (1–2) · FeatureOnboarding (2) · Notifications (2) ·
Networking (3) · Authentication (3) · EmailProviders (3) · GmailProvider (3) ·
SubscriptionDetection (3) · ReceiptImport (4) · CalendarIntegration (4) · Security (2–7) ·
Analytics (7) · MicrosoftProvider (6).

Modules are created in the phase that needs them — no empty stubs.

## ADR-2: Persistence — SwiftData

SwiftData (iOS 17+) is the store. `@Model` classes live in `CoreModels`; container setup,
repositories, and migrations live in `Persistence`. Enum-typed fields that appear in
`#Predicate` filters are stored as raw strings with typed computed accessors (SwiftData
predicates over Codable enums are unreliable); money is stored as `Decimal` + ISO-4217
currency code — never floating point. Known limitation to revisit: if CloudKit sync ships
later, unique constraints must be redesigned (CloudKit forbids them); this is the documented
trigger that would justify Core Data migration, not a reason to use it now.

## ADR-3: Deployment target — iOS 18.0

The template default (26.5) would exclude most devices. iOS 18 gives SwiftData maturity,
typed `TabView`/`Tab`, and Swift 6 concurrency, while covering the realistic install base.
Package targets also build for macOS 15 solely so `swift test` runs fast on CI/dev machines;
platform-specific UI code is guarded with `#if os(iOS)`.

## ADR-4: Concurrency — Swift 6 language mode, MainActor-default UI modules

Package tools-version 6.2, Swift 6 language mode. UI-facing targets use
`.defaultIsolation(MainActor.self)` (matching the app target's "approachable concurrency"
settings). `CoreModels` stays nonisolated with `Sendable` value types so parsing and sync
can run off the main actor. Background ingestion (Phase 3) will use `ModelActor`; `@Model`
instances never cross actor boundaries.

## ADR-5: UI data flow — @Query for reads, repositories for writes

Views observe live data with `@Query` (SwiftData's native observation — correct invalidation
for free). All mutations go through repository protocols (`SubscriptionRepository`, …)
injected via SwiftUI `Environment`, so business logic is testable and the detection pipeline
shares the same write path. View models (`@Observable`) exist only where there is real
presentation logic (form validation, review queue) — no massive-view-model pattern.

## ADR-6: Dependencies — none (Phase 1–4)

Native APIs cover everything through Phase 4. Planned exceptions, each to be justified at
adoption time: **MSAL** (Microsoft sign-in; MIT; required — Microsoft does not support
ASWebAuthenticationSession-only flows for MS accounts in a maintainable way) and possibly
**swift-snapshot-testing** (MIT; test-only). Google sign-in will use
`ASWebAuthenticationSession` + PKCE directly rather than the GoogleSignIn SDK — fewer
transitive dependencies, tokens never touch a third-party layer, and our backend performs the
code exchange so no client secret ships in the app.

## ADR-7: Backend — required at Phase 5, not before

Phases 1–4 are fully client-side (OAuth PKCE without client secret works for Gmail read-only
with a backendless code exchange for development builds). Production needs a backend for:
refresh-token custody for mailbox watch, Gmail `watch`/Graph webhook fan-in, APNs, and
cross-device sync. Stack: TypeScript + Fastify on Node 22, PostgreSQL, BullMQ (Redis) job
queue, containerized; tokens encrypted at rest with per-tenant data keys under a KMS master
key. Full contract in `docs/05-integration-strategy.md`.

## ADR-8: Detection — deterministic first, model-assisted optional

The extraction pipeline is deterministic (rules + weighted evidence scoring). An optional
`AdvancedClassifier` protocol may be backed by a model later; it is off by default, receives
redacted excerpts only, returns schema-validated JSON, and can only create *candidates*,
never confirmed subscriptions. Heuristics are never marketed as AI.

## ADR-9: Sample data is not a production path

Sample data lives in `TestingSupport`, used by previews, UI tests, and a `DEBUG`-only launch
argument (`-duesday-sample-data`) that switches to an in-memory store. Release builds contain
no seeding path.
