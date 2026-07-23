# Duesday — Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Google restricted-scope verification (gmail.readonly) delayed or requires CASA audit | High | Blocks public Gmail launch | Start verification at Phase 3 kickoff; app fully functional via manual entry + imports meanwhile; consider `gmail.metadata` tier for a reduced mode |
| 2 | Detection false positives erode trust | Medium | High | Everything lands in review queue; field-level confidence; conservative thresholds; "not a subscription" feedback loop feeds the rule registry |
| 3 | iOS background limits make sync feel stale | High | Medium | Honest "last synced" UI, push-nudged sync via backend (P5), foreground + pull-to-refresh always available; never promise real-time |
| 4 | 64 pending-notification limit with many subscriptions | Medium | Medium | Schedule nearest-N horizon (e.g. 40) + replenish on foreground/BGTask/notification delivery; covered by scheduling tests |
| 5 | SwiftData maturity issues (predicates, migrations, CloudKit constraints) | Medium | Medium | Raw-string enum storage for predicates; VersionedSchema from day 1; migration tests; documented Core Data escape hatch (ADR-2) |
| 6 | Malicious email HTML / phishing links | Medium | High | Sanitizer allowlist, no remote content, link-domain interstitial (threat model) |
| 7 | Token compromise | Low | Critical | ThisDeviceOnly Keychain, backend envelope encryption, revocation on disconnect, no token logging |
| 8 | Currency confusion (summing mixed currencies) | Medium | Medium | Type-level rule: totals only exist per-currency; tests assert no cross-currency addition |
| 9 | DST / time-zone reminder drift | Medium | Medium | Calendar-component scheduling (not epoch offsets); TZ/DST test matrix |
| 10 | Scope creep into "bank sync" expectations | Medium | Medium | Explicit non-goals in onboarding copy and App Store description |
| 11 | Backend cost/complexity before product-market fit | Medium | Medium | Phases 1–4 run entirely client-side; backend deferred to P5 and sized minimally |
| 12 | MSAL dependency risk (size, churn) | Low | Low | Isolated behind EmailProvider protocol; Microsoft support is last (P6) |
| 13 | App Review skepticism about mail access | Medium | High | Clear in-app purpose strings, privacy explanation screen before OAuth, review notes with demo account |
| 14 | Design prototype inaccessible (403) — fidelity gap | Certain (now) | Low | Token-layer isolation in DesignSystem; re-skin without feature changes once HTML is exported into `docs/design/` |
