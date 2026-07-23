# Duesday — Data Model

All entities are SwiftData `@Model` classes in `CoreModels`. IDs are `UUID` with unique
attributes. Money is `Decimal` + ISO-4217 `currencyCode: String`. Enum fields used in
predicates are persisted as raw strings (`*Raw`) with typed computed accessors (see ADR-2).
Timestamps are `Date` (UTC); user-facing scheduling math is done in the user's calendar.

## Entities

### UserAccount
`id`, `providerRaw` (EmailProviderKind: gmail | microsoft), `emailAddress`, `displayName?`,
`connectionStatusRaw` (connected | expired | revoked | error | disconnected),
`grantedScopes: [String]`, `lastSyncDate?`, `syncCursor?` (Gmail historyId / Graph
deltaLink), `createdAt`, `updatedAt`.
Tokens are **never** stored here — Keychain only (`docs/04-privacy-model.md`).

### Subscription
`id`, `merchantName`, `normalizedMerchantName` (via `MerchantNormalizer`, indexed for
duplicate matching), `planName?`, `amount: Decimal`, `currencyCode`,
`billingFrequencyRaw` (weekly | monthly | quarterly | semiannual | annual | custom),
`customInterval?` (Codable `{count, unit: day|week|month|year}` — only when frequency is
custom), `statusRaw` (active | trial | paused | canceled | expired), `startDate?`,
`trialEndDate?`, `nextBillingDate?`, `lastBillingDate?`, `introductoryPrice?: Decimal`,
`regularPrice?: Decimal`, `introductoryPriceEndDate?`, `categoryRaw`
(streaming | music | software | productivity | news | fitness | gaming | utilities |
insurance | food | shopping | education | finance | other), `paymentMethodLabel?` (free-text
like "Visa ••4242" — never a PAN), `ownershipTypeRaw` (personal | family | shared |
business), `websiteURL?`, `cancellationURL?`, `cancellationInstructions?`, `notes?`,
`detectionSourceRaw` (manual | gmail | microsoft | importedDocument | shareExtension),
`confidence?: Double` (0…1, nil for manual), `createdAt`, `updatedAt`, `archivedAt?`.
Relationships: `renewalEvents: [RenewalEvent]` (cascade), `reminderRules: [ReminderRule]`
(cascade).

### RenewalEvent
`id`, `subscription` (inverse), `expectedDate`, `expectedAmount?: Decimal`, `actualDate?`,
`actualAmount?: Decimal`, `statusRaw` (expected | confirmed | missed | failed | refunded),
`sourceMessageID?` (provider message id, never message content), `createdAt`.
Currency is the parent subscription's; a renewal that changes currency is a new detection.

### DetectionCandidate
`id`, `sourceAccountID?` (UserAccount.id), `sourceMessageID?`, `merchantName?`,
`amount?: Decimal`, `currencyCode?`, `billingFrequencyRaw?`, `detectedDate`,
`nextBillingDate?`, `trialEndDate?`, `evidence: [DetectionEvidence]` (Codable — see below),
`confidenceScore: Double`, `fieldConfidence: [String: Double]`, `reviewStatusRaw`
(pending | confirmed | edited | merged | ignored | rejected),
`possibleDuplicateSubscriptionID?`, `createdAt`.
Every extracted field is optional: **missing means unknown — values are never invented.**

`DetectionEvidence` (value type): `field` (merchant | amount | currency | frequency |
nextBillingDate | trialEnd | cancellation | priceChange), `reasonRaw`
(trustedSenderDomain | recurringPhrase | labeledAmount | explicitInterval |
explicitRenewalDate | repeatedReceipt | cancellationLanguage | headerBodyAgreement | …),
`snippet` (≤160 chars, redacted excerpt), `weight: Double`.

### ReminderRule
`id`, `subscription` (inverse), `reminderTypeRaw` (billingDay | beforeBilling | trialEnd |
priceIncrease | paymentFailed | syncFailure), `leadTimeDays: Int` (0 for billing-day),
`timeOfDayMinutes: Int` (minutes from local midnight), `isEnabled: Bool`.

### ImportedDocument
`id`, `fileTypeRaw` (pdf | image | emailFile | text), `originalFilename`,
`processingStatusRaw` (pending | processing | processed | failed | deleted),
`extractedTextHash?` (SHA-256 of normalized text — dedup without retaining content),
`createdAt`, `deletionDate?` (files auto-purged after processing; see privacy model).

## Derived values (never persisted)

- `SpendingMath.monthlyEstimate` / `annualEstimate` — frequency normalization
  (weekly ×52/12, monthly ×1, quarterly ÷3, semiannual ÷6, annual ÷12, custom from
  occurrences/year). Displayed with an "estimated" label.
- `SpendingMath.totalsByCurrency` — totals are grouped per currency; **different currencies
  are never summed**; conversion only if an explicit FX feature ships later.
- `BillingSchedule.nextDate / occurrences(in:)` — calendar-correct projection from an anchor
  date (handles month-end clamping, DST, time-zone changes by using `Calendar` arithmetic,
  never 86 400-second math).

## Schema versioning

`DuesdaySchemaV1` is declared as a `VersionedSchema`; future changes go through
`SchemaMigrationPlan` stages with migration tests (Phase 7 gate).
