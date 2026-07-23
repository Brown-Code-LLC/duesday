import SwiftUI

/// SwiftUI environment seam for the write path (ADR-5). Defaults to nil;
/// feature views fall back to a SwiftData-backed repository built from the
/// injected `modelContext`, and tests/previews can override with a mock.
extension EnvironmentValues {
    @Entry public var subscriptionRepository: (any SubscriptionRepository)?
}

extension View {
    public func subscriptionRepository(_ repository: any SubscriptionRepository) -> some View {
        environment(\.subscriptionRepository, repository)
    }
}
