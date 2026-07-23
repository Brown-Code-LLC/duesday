import CoreModels
import DesignSystem
import SwiftUI

/// Ledger row per the design spec: monogram glyph (dashed gold for trials),
/// semibold name with an optional tag, a status-aware secondary line, and a
/// trailing serif price with its cadence.
struct SubscriptionRowView: View {
    let subscription: Subscription

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DSGlyphBox(
                    for: subscription.merchantName,
                    size: 38,
                    style: subscription.status == .trial ? .trial : .standard
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(subscription.merchantName)
                            .font(.dsBodyStrong(14.5))
                            .lineLimit(1)
                        if let tag = ownershipTag {
                            DSTagPill(tag, style: subscription.status == .trial ? .accent : .neutral)
                        }
                    }
                    Text(secondaryLine)
                        .font(.dsBody(12))
                        .monospacedDigit()
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Spacing.sm)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceText)
                        .font(.dsSerif(16.5))
                        .monospacedDigit()
                        .foregroundStyle(subscription.status == .trial ? Color.dsInkSecondary : Color.dsInk)
                    Text(cadenceText)
                        .font(cadenceIsEstimate ? .dsBodyItalic(11) : .dsBody(11))
                        .foregroundStyle(cadenceIsEstimate ? Color.dsAccentDeep : Color.dsInkTertiary)
                }
            }
            .padding(.vertical, 11)
            Rectangle().fill(Color.dsDivider).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var ownershipTag: String? {
        switch subscription.status {
        case .trial: return "Trial"
        default:
            switch subscription.ownershipType {
            case .personal: return nil
            case .family: return "Family"
            case .shared: return "Shared"
            case .business: return "Business"
            }
        }
    }

    private var secondaryLine: String {
        // Rising price wins, then trial conversion, then plan · next renewal.
        if let intro = subscription.introductoryPriceEndDate,
           intro >= .now,
           let regular = subscription.regularPrice,
           regular > subscription.amount {
            let to = Money(amount: regular, currencyCode: subscription.currencyCode).formatted()
            return "\(subscription.planName ?? subscription.billingFrequency.displayName) · rising to \(to) in \(intro.formatted(.dateTime.month(.abbreviated)))"
        }
        if subscription.status == .trial, let end = subscription.trialEndDate {
            let then = Money(
                amount: subscription.regularPrice ?? subscription.amount,
                currencyCode: subscription.currencyCode
            ).formatted()
            return "Ends \(end.formatted(.dateTime.month(.abbreviated).day())) · then \(then)/mo"
        }
        var parts: [String] = []
        if let plan = subscription.planName { parts.append(plan) }
        if let next = subscription.nextBillingDate {
            parts.append("renews \(next.formatted(.dateTime.month(.abbreviated).day()))")
        } else {
            parts.append(subscription.billingFrequency.displayName)
        }
        return parts.joined(separator: " · ")
    }

    private var secondaryColor: Color {
        if subscription.introductoryPriceEndDate.map({ $0 >= .now }) == true,
           subscription.regularPrice.map({ $0 > subscription.amount }) == true {
            return .dsAccentDeep
        }
        return .dsInkSecondary
    }

    private var priceText: String {
        if subscription.status == .trial {
            return Money(amount: 0, currencyCode: subscription.currencyCode).formatted()
        }
        return subscription.money.formatted()
    }

    private var cadenceText: String {
        if subscription.status == .trial { return "for now" }
        switch subscription.billingFrequency {
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .semiannual: return "half-yearly"
        case .annual: return "yearly"
        case .custom:
            if let interval = subscription.customInterval {
                return "every \(interval.count) \(interval.unit.rawValue)\(interval.count > 1 ? "s" : "")"
            }
            return "custom"
        }
    }

    private var cadenceIsEstimate: Bool { false }

    private var accessibilitySummary: String {
        var summary = "\(subscription.merchantName), \(priceText) \(cadenceText)"
        if subscription.status != .active {
            summary += ", \(subscription.status.displayName)"
        }
        summary += ", \(secondaryLine)"
        return summary
    }
}
