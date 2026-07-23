import CoreModels
import SwiftUI

/// Monetary amount in the ledger voice: serif figures with tabular digits.
/// `estimated: true` renders the amount with a `~` prefix and an italic
/// "estimated" qualifier per the spec's utility rows.
public struct AmountText: View {
    public enum Presentation {
        /// Serif row price (list/next-up rows).
        case row
        /// Plain body figure (tables, totals).
        case plain
    }

    private let money: Money
    private let estimated: Bool
    private let presentation: Presentation

    public init(_ money: Money, estimated: Bool = false, presentation: Presentation = .plain) {
        self.money = money
        self.estimated = estimated
        self.presentation = presentation
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(figure)
                .font(presentation == .row ? .dsSerif(17) : .dsBody(13.5))
                .monospacedDigit()
                .foregroundStyle(estimated ? Color.dsInkSecondary : Color.dsInk)
            if estimated {
                Text("estimated")
                    .font(.dsBodyItalic(11))
                    .foregroundStyle(Color.dsAccentDeep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var figure: String {
        (estimated ? "~" : "") + money.formatted()
    }

    private var accessibilityText: String {
        estimated ? "Estimated \(money.formatted())" : money.formatted()
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 12) {
        AmountText(Money(amount: 15.49, currencyCode: "USD"), presentation: .row)
        AmountText(Money(amount: 96.40, currencyCode: "USD"), estimated: true, presentation: .row)
        AmountText(Money(amount: 139, currencyCode: "EUR"))
    }
    .padding()
    .background(Color.dsPaper)
}
