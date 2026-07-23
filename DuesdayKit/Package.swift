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
                "TestingSupport",
                "FeatureOnboarding",
                "FeatureOverview",
                "FeatureSubscriptions",
                "FeatureCalendar",
                "FeatureInsights",
                "FeatureSettings",
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
            dependencies: ["CoreModels", "Persistence", "DesignSystem"],
            swiftSettings: mainActorDefault
        ),
        .target(
            name: "FeatureSubscriptions",
            dependencies: ["CoreModels", "Persistence", "DesignSystem"],
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
            dependencies: ["CoreModels", "Persistence", "DesignSystem", "Notifications", "AppSecurity"],
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
    ]
)
