import CoreModels
import CoreText
import Foundation
import SwiftUI
import os

/// Bundled brand fonts from the Duesday design spec:
/// Cormorant Garamond (headings/figures) and Lora (body).
/// Both are licensed under the SIL Open Font License, which permits app
/// embedding. Registered at runtime from package resources so the app target
/// needs no Info.plist font entries.
public enum DuesdayFonts {
    public static let heading = "CormorantGaramond-Regular"
    public static let headingMedium = "CormorantGaramond-Medium"
    public static let headingSemiBold = "CormorantGaramond-SemiBold"
    public static let body = "Lora-Regular"
    public static let bodySemiBold = "Lora-SemiBold"
    public static let bodyItalic = "Lora-Italic"

    private static let logger = DuesdayLog.logger(category: "designsystem")
    private nonisolated(unsafe) static var didRegister = false

    private static let fileNames = [
        "CormorantGaramond-Regular",
        "CormorantGaramond-Medium",
        "CormorantGaramond-SemiBold",
        "Lora-Regular",
        "Lora-SemiBold",
        "Lora-Italic",
    ]

    /// Registers the bundled fonts once. Safe to call repeatedly; called from
    /// theme accessors so any entry point gets fonts without explicit setup.
    public static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        for name in fileNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                logger.error("Missing bundled font \(name, privacy: .public)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already-registered errors are benign (previews re-run this).
                if let error = error?.takeRetainedValue() {
                    let code = CFErrorGetCode(error)
                    if code != CTFontManagerError.alreadyRegistered.rawValue
                        && code != CTFontManagerError.duplicatedName.rawValue {
                        logger.error("Font registration failed for \(name, privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
    }
}

extension Font {
    /// Large serif money figure (Overview hero, detail price). Regular cut —
    /// the design reserves semibold for small interface headings.
    public static func dsDisplay(_ size: CGFloat) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.heading, size: size, relativeTo: .largeTitle)
    }

    /// Screen titles ("Subscriptions", "July") — serif medium.
    public static func dsTitle(_ size: CGFloat = 30) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.headingMedium, size: size, relativeTo: .title)
    }

    /// Serif for row prices and monogram glyphs.
    public static func dsSerif(_ size: CGFloat) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.heading, size: size, relativeTo: .body)
    }

    /// Body text (Lora).
    public static func dsBody(_ size: CGFloat = 15) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.body, size: size, relativeTo: .body)
    }

    /// Emphasized body (row titles, alert titles).
    public static func dsBodyStrong(_ size: CGFloat = 14.5) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.bodySemiBold, size: size, relativeTo: .body)
    }

    /// Italic accent ("estimated").
    public static func dsBodyItalic(_ size: CGFloat = 11) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.bodyItalic, size: size, relativeTo: .caption)
    }

    /// Uppercase letterspaced labels (kickers, section captions) — pair with
    /// `.dsTracking()` and `.textCase(.uppercase)`.
    public static func dsCaption(_ size: CGFloat = 11) -> Font {
        DuesdayFonts.registerIfNeeded()
        return .custom(DuesdayFonts.body, size: size, relativeTo: .caption)
    }
}
