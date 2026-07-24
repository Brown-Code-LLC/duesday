# Duesday — Release Gates

Status: Implementation complete where locally testable · external gates remain

## Credential and service gates

- Google Cloud: production iOS OAuth client, restricted-scope verification, privacy-policy
  URL, demo video, and CASA assessment if Google requires it.
- Microsoft Entra: app registration, redirect URI, `Mail.Read offline_access` consent, and
  MSAL adapter configuration. The Graph provider is implemented and fixture-tested.
- Apple Developer: App Group/share-extension signing, APNs key, production push entitlement,
  Sign in with Apple identifiers, and TestFlight distribution profiles.
- Backend infrastructure: PostgreSQL 16, Redis, KMS-backed production key-encryption key,
  Gmail Pub/Sub topic, Graph webhook secret, APNs credentials, DNS/TLS, and deployment.

## Submission checklist

- Replace placeholder legal privacy-policy URL and support URL.
- Complete App Store privacy labels: email address and subscription ledger are linked to
  the user; no tracking; transient email bodies are not retained.
- Validate `PrivacyInfo.xcprivacy` against the shipping binary and current App Store rules.
- Run VoiceOver, Accessibility Inspector, Dynamic Type XXXL, Increase Contrast, Reduce
  Motion, and 44-point target audits on physical iPhone and iPad.
- Test DST/time-zone changes, offline launch, token revocation, expired Gmail/Graph cursors,
  notification replenishment, import cancellation, malformed documents, and data deletion.
- Profile cold launch, review-queue scrolling, 12-month mailbox backfill memory, and OCR.
- Archive a Release build, run Organizer validation, upload to TestFlight, and complete the
  migration dry run against a copy of the previous production store.

## Honest completion boundary

The repository contains the client modules, provider implementations, import pipeline,
backend API/schema/security primitives, privacy manifest, and automated tests. It does not
claim that third-party verification, production infrastructure, legal review, or App Store
approval can be completed without the developer accounts and credentials above.
