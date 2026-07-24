# Duesday — Release & TestFlight Checklist (Phase 7)

## Developer credentials required before external testing
- [ ] Google Cloud: iOS OAuth client ID → `DuesdayGoogleOAuthClientID` in `Config/Info.plist`;
      begin restricted-scope (`gmail.readonly`) verification (privacy policy URL, demo video).
- [ ] Microsoft Entra: app registration (public client, mobile redirect
      `duesday.oauth://microsoft`) → `DuesdayMicrosoftOAuthClientID`.
- [ ] Apple Developer: production bundle ID (`com.browncode.duesday` configured), push
      entitlement when the backend ships, App Store Connect record.
- [ ] Backend hosting: `DATABASE_URL`, `REDIS_URL`, `TOKEN_KEK_BASE64` (32-byte
      key from a secret manager), `APPLE_AUDIENCE`, `GMAIL_WEBHOOK_SECRET`,
      `MSGRAPH_CLIENT_STATE`; APNs auth key.

## Security review (threat model in docs/04)
- [x] Tokens only in Keychain (`ThisDeviceOnly`) / backend envelope-encrypted vault.
- [x] No email bodies persisted — evidence snippets ≤160 chars; retention test cover.
- [x] Link opening gated behind domain disclosure; http(s)-only validation at entry.
- [x] Webhook signature/clientState verification with idempotent replay handling.
- [x] Logs redact authorization headers, codes, and tokens (backend) and use
      privacy-tagged os.Logger interpolation (app).
- [ ] Penetration pass on the backend before public traffic.

## Privacy review
- [x] `PrivacyInfo.xcprivacy`: no tracking, no collected data types, required-reason
      APIs declared (UserDefaults, file timestamps).
- [x] Purpose strings: Face ID, write-only Calendar.
- [x] Disconnect revokes + optionally purges imported detections; delete-everything wipes
      all entities and scheduled notifications.
- [ ] App Store privacy labels: "Data Not Collected" (verify against final analytics stance —
      the Analytics module is a counting stub with no network path today).

## Performance & accessibility
- [ ] Launch-time profile on oldest supported hardware (iOS 18 baseline).
- [ ] Instruments pass over a 25-message sync (memory ceiling, no body retention).
- [x] Dynamic Type via relative text styles; VoiceOver labels/hints; 44 pt targets;
      reduced-motion-safe animations.
- [ ] Full VoiceOver walkthrough of review queue and month grid.

## Localization
- [x] String Catalog generation enabled; display strings centralized per module.
- [ ] Extract to `Localizable.xcstrings` and commission first translations.

## TestFlight gate
- [ ] Archive with release configuration; confirm no DEBUG-only paths
      (`-duesday-sample-data`, auto-enable flag) are reachable.
- [ ] Background refresh observed end-to-end on device (`app.duesday.refresh`).
- [ ] Notification delivery + deep link on a locked device.
- [ ] Gmail + Outlook connect/sync/disconnect happy path with real accounts.
- [ ] Export CSV/JSON opens in Files/Numbers; delete-everything leaves an empty ledger.
- [ ] App Review notes: demo account, honest description of email access
      (read-only, targeted, user-reviewed), no real-time claims.
