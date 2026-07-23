import Foundation

/// Currency codes offered in pickers. The user's locale currency is listed
/// first; arbitrary ISO codes remain possible through detection/import paths.
enum CurrencyCatalog {
    static let common: [String] = [
        "USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF", "SEK", "NOK", "DKK",
        "PLN", "CZK", "INR", "CNY", "KRW", "SGD", "HKD", "NZD", "BRL", "MXN",
        "ZAR", "NGN", "GHS", "KES", "AED", "SAR", "TRY",
    ]

    static func ordered(locale: Locale = .current) -> [String] {
        let localCode = locale.currency?.identifier.uppercased()
        var codes = common
        if let localCode {
            codes.removeAll { $0 == localCode }
            codes.insert(localCode, at: 0)
        }
        return codes
    }

    static func displayName(for code: String, locale: Locale = .current) -> String {
        if let name = locale.localizedString(forCurrencyCode: code) {
            return "\(code) — \(name)"
        }
        return code
    }
}
