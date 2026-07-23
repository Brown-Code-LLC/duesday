import SwiftUI

/// Design tokens implementing the Duesday "ledger" design spec
/// (docs/design source: Duesday iOS Screens.dc.html + classical styles.css).
/// Warm paper ground, ink text, bronze/gold accent used as *stroke* rather
/// than fill; hairline dividers instead of cards.
public enum DS {
    public enum Spacing {
        public static let xs: CGFloat = 4.6
        public static let sm: CGFloat = 9.2
        public static let md: CGFloat = 13.8
        public static let lg: CGFloat = 18.4
        public static let xl: CGFloat = 27.6
        public static let xxl: CGFloat = 36.8
    }

    /// Horizontal screen margin used by every screen in the spec.
    public static let screenMargin: CGFloat = 28

    public enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let field: CGFloat = 9
        public static let button: CGFloat = 10
        public static let lg: CGFloat = 16
    }

    /// Apple HIG minimum touch target.
    public static let minTouchTarget: CGFloat = 44

    /// Letter tracking for uppercase labels, in em-relative points.
    public static func tracking(_ em: CGFloat, size: CGFloat) -> CGFloat { em * size }
}

private func adaptive(light: Color, dark: Color) -> Color {
    #if os(iOS)
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
    #else
    light
    #endif
}

extension Color {
    // MARK: Ground

    /// Paper ground — the app's background everywhere.
    public static var dsPaper: Color {
        adaptive(light: Color(red: 0.953, green: 0.949, blue: 0.949),   // #f3f2f2
                 dark: Color(red: 0.090, green: 0.082, blue: 0.071))    // #171512
    }

    /// White field/glyph boxes on light; slightly lifted surface on dark.
    public static var dsField: Color {
        adaptive(light: .white,
                 dark: Color(red: 0.129, green: 0.118, blue: 0.106))    // #211E1B
    }

    // MARK: Ink

    public static var dsInk: Color {
        adaptive(light: Color(red: 0.125, green: 0.122, blue: 0.114),   // #201f1d
                 dark: Color(red: 0.953, green: 0.949, blue: 0.949))    // #f3f2f2
    }

    /// Secondary text (≈ neutral-600).
    public static var dsInkSecondary: Color { Color.dsInk.opacity(0.62) }
    /// Tertiary text (≈ neutral-500).
    public static var dsInkTertiary: Color { Color.dsInk.opacity(0.45) }

    /// Hairline divider — ink at 16%.
    public static var dsDivider: Color { Color.dsInk.opacity(0.16) }
    /// Strong rule under section headers — full ink.
    public static var dsRule: Color { Color.dsInk }

    // MARK: Accent (bronze / gold — stroke, not fill)

    public static var dsAccent: Color {
        adaptive(light: Color(red: 0.714, green: 0.510, blue: 0.208),   // #b68235
                 dark: Color(red: 0.882, green: 0.678, blue: 0.400))    // #E1AD66
    }

    /// Deep gold for text and links on light ground (accent-700).
    public static var dsAccentDeep: Color {
        adaptive(light: Color(red: 0.490, green: 0.329, blue: 0.067),   // #7d5411
                 dark: Color(red: 0.882, green: 0.678, blue: 0.400))    // #E1AD66
    }

    /// Soft gold wash used behind selected chips/segments (accent-100).
    public static var dsAccentWash: Color {
        adaptive(light: Color(red: 1.0, green: 0.953, blue: 0.894),     // #fff3e4
                 dark: Color(red: 0.882, green: 0.678, blue: 0.400).opacity(0.14))
    }

    /// Light gold border for trial/status outlines (accent-300).
    public static var dsAccentSoft: Color {
        adaptive(light: Color(red: 0.980, green: 0.796, blue: 0.553),   // #facb8d
                 dark: Color(red: 0.882, green: 0.678, blue: 0.400).opacity(0.5))
    }

    // MARK: States

    /// Rust red for failures — the spec's #8a3b2a.
    public static var dsDanger: Color {
        adaptive(light: Color(red: 0.541, green: 0.231, blue: 0.165),
                 dark: Color(red: 0.812, green: 0.463, blue: 0.373))
    }

    /// Neutral chip border (neutral-300).
    public static var dsChipBorder: Color {
        adaptive(light: Color(red: 0.843, green: 0.827, blue: 0.827),   // #d7d3d3
                 dark: Color.white.opacity(0.22))
    }

    // Legacy aliases kept so shared components read consistently.
    public static var dsBackground: Color { .dsPaper }
    public static var dsSecondaryBackground: Color { .dsField }
    public static var dsPositive: Color { .dsAccentDeep }
    public static var dsWarning: Color { .dsAccent }
}
