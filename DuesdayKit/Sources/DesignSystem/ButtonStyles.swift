import SwiftUI

/// Primary call-to-action per the design spec: gold *outline*, not a filled
/// block — the accent is always a stroke. 52pt height, 10pt radius.
public struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody(16))
            .foregroundStyle(Color.dsAccentDeep.opacity(isEnabled ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                configuration.isPressed ? Color.dsAccent.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.button)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.button)
                    .stroke(Color.dsAccent.opacity(isEnabled ? 1 : 0.45), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet text button ("Not now", "Set up manually instead").
public struct DSQuietButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody(15))
            .foregroundStyle(Color.dsInkSecondary)
            .frame(maxWidth: .infinity, minHeight: DS.minTouchTarget)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Compact outlined action used in the detail screen's bottom row.
public struct DSCompactOutlineButtonStyle: ButtonStyle {
    private let tint: Color

    public init(tint: Color = .dsInkSecondary) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBody(13))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: DS.minTouchTarget)
            .background(
                configuration.isPressed ? Color.dsInk.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.button)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.button)
                    .stroke(Color.dsChipBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button))
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    public static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DSQuietButtonStyle {
    public static var dsQuiet: DSQuietButtonStyle { DSQuietButtonStyle() }
}

#Preview {
    VStack(spacing: DS.Spacing.md) {
        Button("Connect an email account") {}.buttonStyle(.dsPrimary)
        Button("Set up manually instead") {}.buttonStyle(.dsQuiet)
        Button("Disabled") {}.buttonStyle(.dsPrimary).disabled(true)
        HStack(spacing: 8) {
            Button("Mark cancelled") {}.buttonStyle(DSCompactOutlineButtonStyle())
            Button("Archive") {}.buttonStyle(DSCompactOutlineButtonStyle())
        }
    }
    .padding(DS.screenMargin)
    .background(Color.dsPaper)
}
