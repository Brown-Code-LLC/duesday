# Duesday — Feasibility Assessment

Status: Accepted · 2026-07-23

## Verdict

The product is feasible as specified, **provided** discovery is limited to permission-based
sources. iOS sandboxing makes several "obvious" discovery ideas impossible, and the product
must be honest about that in UI copy and App Store metadata.

## What an iOS app CAN do

| Capability | Mechanism | Notes |
|---|---|---|
| Read Gmail | Google OAuth 2.0 + Gmail REST API | Requires `gmail.readonly` (restricted scope → Google verification + possibly CASA security assessment before public release) |
| Read Outlook/Microsoft 365 | MSAL + Microsoft Graph `Mail.Read` | Delegated, read-only |
| Receive user-shared content | Share extension, document picker | User explicitly selects each item |
| OCR receipts/screenshots | Vision / VisionKit | Fully on-device |
| Local reminders | UserNotifications | Pending-request limit of 64 requires a replenishment strategy |
| Calendar/Reminders export | EventKit (write-only access is sufficient) | Optional, off by default |
| Background refresh | BGAppRefreshTask | Opportunistic only — no guaranteed cadence |
| Push-triggered sync | APNs (requires backend) | Gmail `watch` / Graph change notifications → backend → APNs |

## What an iOS app CANNOT do (and how we compensate)

| Impossible | Why | Compensation |
|---|---|---|
| Search the Apple Mail database | Sandbox; no API exists | Connect the underlying Gmail/Microsoft account; forward emails to the share sheet; import `.eml` files |
| Read SMS / iMessage | Sandbox | Manual entry, screenshot import |
| Read other apps' data or App Store purchase history | Sandbox; no API | Manual entry |
| Read bank/card transactions | No public API (no US open-banking API from Apple) | Out of scope for MVP; a future aggregator (e.g. Plaid) is a separate, disclosed integration |
| Continuously monitor the inbox on-device | iOS suspends apps | Backend watch + push, plus foreground/opportunistic sync; UI shows "last synced", never promises real-time |

## Key external gates (cannot be completed without developer credentials)

1. **Google Cloud project** — OAuth client ID (iOS type), Gmail API enabled, OAuth consent
   screen, restricted-scope verification for `gmail.readonly`.
2. **Microsoft Entra app registration** — MSAL client ID, delegated `Mail.Read`.
3. **Apple Developer account** — bundle ID, push entitlement (Phase 5), App Groups (Phase 4
   share extension), Sign in with Apple if backend accounts ship.
4. **Backend hosting + APNs key** (Phase 5).

None of these block Phases 1–2 (manual MVP), which is why the roadmap front-loads them.

## Design prototype

The supplied claude.ai/design share link is authentication-walled and could not be fetched
from this environment (HTTP 403). The design system is therefore implemented as a single
token layer (`DesignSystem` module) derived from the written spec; exporting the prototype
HTML into `docs/design/` will allow exact token matching without touching feature code.
