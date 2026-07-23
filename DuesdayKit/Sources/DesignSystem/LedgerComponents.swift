import CoreModels
import SwiftUI

// Shared building blocks of the ledger aesthetic: uppercase section captions
// over rules, monogram glyph boxes, outline tag pills, filter chips, and
// hairline key-value rows.

/// Uppercase, letterspaced label ("NEXT UP", kickers).
public struct DSCaptionLabel: View {
    private let text: String
    private let size: CGFloat
    private let color: Color

    public init(_ text: String, size: CGFloat = 11, color: Color = .dsInkSecondary) {
        self.text = text
        self.size = size
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.dsCaption(size))
            .textCase(.uppercase)
            .tracking(DS.tracking(0.16, size: size))
            .foregroundStyle(color)
    }
}

/// Section header: caption (+ optional trailing detail) sitting on a strong
/// ink rule, per the list/settings screens of the spec.
public struct DSSectionHeader: View {
    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                DSCaptionLabel(title)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.dsBody(12))
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInkSecondary)
                }
            }
            Rectangle()
                .fill(Color.dsRule)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Merchant monogram box: serif initial in a hairline-bordered square.
/// Trials get a dashed gold border (spec: list 1k).
public struct DSGlyphBox: View {
    public enum Style {
        case standard
        case trial
        case accent
    }

    private let letter: String
    private let size: CGFloat
    private let style: Style

    public init(for name: String, size: CGFloat = 38, style: Style = .standard) {
        self.letter = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        self.size = size
        self.style = style
    }

    public var body: some View {
        Text(letter)
            .font(.dsSerif(size * 0.5))
            .foregroundStyle(Color.dsAccentDeep)
            .frame(width: size, height: size)
            .background(Color.dsField, in: RoundedRectangle(cornerRadius: size * 0.21))
            .overlay {
                switch style {
                case .standard:
                    RoundedRectangle(cornerRadius: size * 0.21)
                        .stroke(Color.dsDivider, lineWidth: 1)
                case .trial:
                    RoundedRectangle(cornerRadius: size * 0.21)
                        .stroke(Color.dsAccent, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                case .accent:
                    RoundedRectangle(cornerRadius: size * 0.21)
                        .stroke(Color.dsAccent, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Small uppercase outline pill ("TRIAL", "SHARED", "ACTIVE").
public struct DSTagPill: View {
    public enum Style {
        case accent
        case neutral
    }

    private let text: String
    private let style: Style
    private let capsule: Bool

    public init(_ text: String, style: Style = .neutral, capsule: Bool = false) {
        self.text = text
        self.style = style
        self.capsule = capsule
    }

    public var body: some View {
        Text(text)
            .font(.dsCaption(10))
            .textCase(.uppercase)
            .tracking(DS.tracking(0.07, size: 10))
            .foregroundStyle(style == .accent ? Color.dsAccentDeep : Color.dsInkSecondary)
            .padding(.horizontal, capsule ? 8 : 5)
            .padding(.vertical, capsule ? 2 : 1)
            .overlay {
                if capsule {
                    Capsule().stroke(borderColor, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(borderColor, lineWidth: 1)
                }
            }
            .accessibilityLabel(text)
    }

    private var borderColor: Color {
        style == .accent ? .dsAccentSoft : .dsChipBorder
    }
}

/// Rounded filter chip ("Active · 15") with a gold selected state.
public struct DSFilterChip: View {
    private let text: String
    private let isSelected: Bool
    private let filled: Bool
    private let action: () -> Void

    public init(_ text: String, isSelected: Bool, filled: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.isSelected = isSelected
        self.filled = filled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.dsBody(12))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.dsAccentDeep : Color.dsInkSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(
                    isSelected && filled ? Color.dsAccentWash : .clear,
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(
                        isSelected ? Color.dsAccent : Color.dsChipBorder,
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Hairline key-value row used in the detail record and settings.
public struct DSLedgerRow<Trailing: View>: View {
    private let label: String
    private let topRule: Bool
    private let trailing: Trailing

    public init(_ label: String, topRule: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.topRule = topRule
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(topRule ? Color.dsRule : Color.dsDivider)
                .frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.dsBody(13.5))
                    .foregroundStyle(Color.dsInkSecondary)
                Spacer()
                trailing
                    .font(.dsBody(13.5))
                    .monospacedDigit()
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .combine)
    }
}

extension DSLedgerRow where Trailing == Text {
    public init(_ label: String, value: String, topRule: Bool = false) {
        self.init(label, topRule: topRule) { Text(value) }
    }
}

/// Notification preview card (onboarding education + reminder settings).
public struct DSNotificationPreviewCard: View {
    private let kicker: String
    private let time: String
    private let message: String

    public init(kicker: String, time: String, message: String) {
        self.kicker = kicker
        self.time = time
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("D")
                .font(.dsSerif(18))
                .foregroundStyle(Color.dsAccentDeep)
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.dsAccent, lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(kicker)
                        .font(.dsBodyStrong(12))
                    Spacer()
                    Text(time)
                        .font(.dsBody(12))
                        .foregroundStyle(Color.dsInkTertiary)
                }
                Text(message)
                    .font(.dsBody(13))
                    .foregroundStyle(Color.dsInk.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.dsField, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(Color.dsDivider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
