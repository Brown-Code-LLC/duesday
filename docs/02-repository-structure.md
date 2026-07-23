# Duesday — Repository Structure

```
duesday/                          # repo root
├── docs/                         # specs (this SDD set), design exports, threat model
├── duesday.xcodeproj/            # app project (filesystem-synchronized groups)
├── duesday/                      # APP TARGET — composition only
│   ├── duesdayApp.swift          # @main, store bootstrap, sample-data mode
│   ├── RootView.swift            # tab shell + cross-feature routing
│   └── Assets.xcassets/
├── DuesdayKit/                   # local Swift package — all product code
│   ├── Package.swift
│   ├── Sources/
│   │   ├── CoreModels/           # @Model entities, enums, Money, billing/spending math,
│   │   │                         #   merchant normalization, logging. No UI imports.
│   │   ├── Persistence/          # container factory, schema/migrations, repositories
│   │   ├── DesignSystem/         # tokens (color/spacing/type/radius), components, haptics
│   │   ├── TestingSupport/       # sample-data builders, in-memory preview containers
│   │   ├── FeatureOverview/      # dashboard tab
│   │   ├── FeatureSubscriptions/ # list, detail, manual entry form
│   │   ├── FeatureCalendar/      # renewal calendar tab
│   │   ├── FeatureInsights/      # spending insights tab
│   │   └── FeatureSettings/      # settings, privacy explanation, about
│   └── Tests/
│       ├── CoreModelsTests/      # money, frequency normalization, schedule, currency,
│       │                         #   merchant-normalizer fixtures
│       ├── PersistenceTests/     # repository CRUD against in-memory containers
│       └── FeatureSubscriptionsTests/  # form validation model
└── backend/                      # Phase 5 (TypeScript service) — not yet created
```

Later phases add (see ADR-1): `Notifications`, `Networking`, `Authentication`,
`EmailProviders`, `GmailProvider`, `SubscriptionDetection`, `ReceiptImport`,
`CalendarIntegration`, `Security`, `Analytics`, `MicrosoftProvider`, plus app-level
extension targets `DuesdayShare` (Phase 4) and UI-test target `duesdayUITests` (Phase 2).

Conventions
- One type per file unless types are trivially cohesive (enum clusters).
- Feature modules depend on CoreModels + Persistence + DesignSystem only; features never
  import each other — cross-feature navigation goes through the app-level router.
- Tests mirror source layout; parser fixtures (Phase 3) live under
  `Tests/SubscriptionDetectionTests/Fixtures/` as `.eml`/`.html`/`.txt` resources.
```
