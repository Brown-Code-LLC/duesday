# Duesday — Privacy & Security Model

Principle: the mailbox is the most sensitive data source a user can grant. Treat every
email-derived byte as toxic until minimized.

## Data classification & storage

| Data | Class | Store | Protection |
|---|---|---|---|
| OAuth access/refresh tokens | Secret | Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no iCloud sync) or backend token vault (Phase 5) | Never UserDefaults, never SwiftData, never logs |
| Email bodies | Sensitive, transient | Memory during parsing only; sanitized excerpts ≤160 chars as evidence snippets | Purged after candidate creation |
| Provider message IDs, sync cursors | Internal | SwiftData | File protection `.completeUntilFirstUserAuthentication`; DB directory excluded from iCloud backup review in Phase 7 |
| Subscriptions, candidates, reminders | Personal | SwiftData | Same |
| Imported files (PDF/images/.eml) | Sensitive, transient | App container `Documents/Imports` with `.complete` file protection | Deleted after extraction or on user request; `deletionDate` audited |
| Analytics | De-identified | (Phase 7) | Event names + counts only — never merchant names, amounts, emails, message content, tokens |

## Hard rules (enforced in code review + tests)

1. No token or email content in `UserDefaults`, logs, analytics, or crash reports.
   `os.Logger` wrappers default all interpolations to `.private`.
2. All network traffic is TLS via ATS defaults; no ATS exceptions.
3. Email HTML is sanitized before display: allowlist-based tag/attribute stripping, all
   remote loads blocked (no tracking pixels), links shown with resolved destination domain
   and opened only after user confirmation; `javascript:`/`data:` URLs rejected.
4. Cancellation URLs are validated (https, host shown to user) before opening.
5. Minimum OAuth scopes: Gmail `gmail.readonly` (metadata-only mode evaluated first;
   full readonly needed for MIME bodies), Microsoft `Mail.Read offline_access`.
6. The app never uploads mailbox content to third parties. Optional advanced classification
   (ADR-8) is opt-in, disclosed, redacted, and excerpt-only.

## User-facing controls (feature commitments)

- Connected-account screen shows: account, scopes in plain language, read-only status,
  last sync, disconnect button, "delete imported data" button.
- Disconnect = revoke token (provider endpoint) + delete Keychain entry + optionally purge
  derived candidates/evidence.
- Full local-data deletion; backend deletion cascades within 30 days (Phase 5).
- Export: JSON + CSV of subscriptions/renewals (no raw email content is retained to export).
- App lock: Face ID / passcode via `LAContext`, blur-over-content redaction when the app
  resigns active (prevents sensitive app-switcher snapshots).
- Notification previews: system preview settings respected; our payloads keep amounts out
  of the lock screen unless the user opts into detailed previews in-app.

## Threat model (summary)

| Threat | Mitigation |
|---|---|
| Token theft from device backup | ThisDeviceOnly Keychain class, no token in files |
| Malicious email content (HTML/JS injection) | Sanitizer allowlist, no WebView JS, no remote loads |
| Unsafe/phishing cancellation links | URL validation + domain disclosure interstitial |
| Compromised imported file (malformed PDF/image) | Parse via system frameworks in-process with size caps; failures are contained and reported, files purged |
| Replay of backend webhooks (Phase 5) | Signature verification (Google JWT / Graph clientState), idempotency keys, timestamp windows |
| Unauthorized local access | App lock, data protection classes, snapshot redaction |
| Over-collection drift | Evidence snippets capped and reviewed; retention tests assert no body persistence |

## Compliance artifacts (Phase 7 gate)

- `PrivacyInfo.xcprivacy` with required-reason APIs (UserDefaults, file timestamps).
- App Store privacy labels: data linked to user = email address (account), subscriptions;
  no tracking.
- Google restricted-scope verification package (privacy policy URL, demo video, CASA if
  required by user count).
