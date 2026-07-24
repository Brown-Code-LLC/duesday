// swift-tools-version: 6.2
import PackageDescription

// UI-facing targets default to MainActor isolation, matching the app target's
// "approachable concurrency" configuration (ADR-4). CoreModels stays nonisolated
// so parsing/sync work can run off the main actor.
let mainActorDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "DuesdayKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "DuesdayKit",
            targets: [
                "CoreModels",
                "DesignSystem",
                "Persistence",
                "Notifications",
                "AppSecurity",
                "Networking",
                "Authentication",
                "EmailProviders",
                "GmailProvider",
                "SubscriptionDetection",
                "ReceiptImport",
                "CalendarIntegration",
                "MicrosoftProvider",
                "Analytics",
                "TestingSupport",
                "FeatureOnboarding",
                "FeatureOverview",
                "FeatureSubscriptions",
                "FeatureCalendar",
                "FeatureInsights",
                "FeatureSettings",
                "FeatureDetectionReview",
            ]
        )
    ],
    targets: [
        .target(name: "CoreModels"),
        .target(
            name: "DesignSystem",
            dependencies: ["CoreModels"],
            resources: [.process("Resources")],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "Persistence",
            dependencies: ["CoreModels"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "Notifications",
            dependencies: ["CoreModels"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "AppSecurity",
            swiftSettings: mainActorDefault
        ),
        // Sync/parsing infrastructure stays nonisolated so it can run off the
        // main actor (ADR-4).
        .target(name: "Networking", dependencies: ["CoreModels"]),
        .target(name: "Authentication", dependencies: ["Networking", "CoreModels"]),
        .target(name: "EmailProviders", dependencies: ["CoreModels"]),
        .target(
            name: "GmailProvider",
            dependencies: ["EmailProviders", "Networking", "Authentication", "CoreModels"]
        ),
        .target(name: "SubscriptionDetection", dependencies: ["CoreModels"]),
        .target(
            name: "ReceiptImport",
            dependencies: ["CoreModels", "SubscriptionDetection"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "CalendarIntegration",
            dependencies: ["CoreModels"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "MicrosoftProvider",
            dependencies: ["EmailProviders", "Networking", "CoreModels"]
        ),
        .target(name: "Analytics"),
        .target(
            name: "FeatureDetectionReview",
            dependencies: [
                "CoreModels", "Persistence", "DesignSystem",
                "SubscriptionDetection", "FeatureSubscriptions",
            ],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "TestingSupport",
            dependencies: ["CoreModels", "Persistence"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureOnboarding",
            dependencies: ["DesignSystem", "Notifications"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureOverview",
            dependencies: ["CoreModels", "Persistence", "DesignSystem", "FeatureDetectionReview"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureSubscriptions",
            dependencies: ["CoreModels", "Persistence", "DesignSystem", "CalendarIntegration"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureCalendar",
            dependencies: ["CoreModels", "Persistence", "DesignSystem"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureInsights",
            dependencies: ["CoreModels", "Persistence", "DesignSystem"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureSettings",
            dependencies: [
                "CoreModels", "Persistence", "DesignSystem", "Notifications",
                "AppSecurity", "Networking", "Authentication", "EmailProviders",
                "GmailProvider", "MicrosoftProvider", "SubscriptionDetection",
                "ReceiptImport",
            ],
            swiftSettings: mainActorDefault
        ),
        .testTarget(
            name: "CoreModelsTests",
            dependencies: ["CoreModels"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "CoreModels", "TestingSupport"],
            swiftSettings: mainActorDefault
        ),
        .testTarget(
            name: "FeatureSubscriptionsTests",
            dependencies: ["FeatureSubscriptions", "TestingSupport"],
            swiftSettings: mainActorDefault
        ),
        .testTarget(
            name: "NotificationsTests",
            dependencies: ["Notifications", "CoreModels"],
            swiftSettings: mainActorDefault
        ),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"]),
        .testTarget(name: "AuthenticationTests", dependencies: ["Authentication", "Networking"]),
        .testTarget(name: "GmailProviderTests", dependencies: ["GmailProvider", "EmailProviders"]),
        .testTarget(
            name: "ReceiptImportTests",
            dependencies: ["ReceiptImport", "SubscriptionDetection", "CoreModels"],
            swiftSettings: mainActorDefault
        ),
        .testTarget(
            name: "MicrosoftProviderTests",
            dependencies: ["MicrosoftProvider", "EmailProviders", "Networking"]
        ),
        .testTarget(
            name: "FeatureDetectionReviewTests",
            dependencies: ["FeatureDetectionReview", "Persistence", "CoreModels"],
            swiftSettings: mainActorDefault
        ),
        .testTarget(
            name: "SubscriptionDetectionTests",
            dependencies: ["SubscriptionDetection", "CoreModels"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
