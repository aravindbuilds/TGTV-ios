import Foundation

/// Country dial codes for the phone-login picker (popular first, then A→Z).
/// Mirrors `com.tgtv.mobile.model.CountryCodes` in the Android client.
enum CountryCodes {
    struct Country: Identifiable, Hashable {
        let name: String
        let dial: String
        var id: String { name + dial }
        var label: String { "\(name)  (\(dial))" }
    }

    static let defaultDial = "+91"

    static let entries: [Country] = [
        Country(name: "India", dial: "+91"),
        Country(name: "United States", dial: "+1"),
        Country(name: "United Kingdom", dial: "+44"),
        Country(name: "United Arab Emirates", dial: "+971"),
        Country(name: "Australia", dial: "+61"),
        Country(name: "Bangladesh", dial: "+880"),
        Country(name: "Belgium", dial: "+32"),
        Country(name: "Brazil", dial: "+55"),
        Country(name: "Canada", dial: "+1"),
        Country(name: "China", dial: "+86"),
        Country(name: "Egypt", dial: "+20"),
        Country(name: "France", dial: "+33"),
        Country(name: "Germany", dial: "+49"),
        Country(name: "Hong Kong", dial: "+852"),
        Country(name: "Indonesia", dial: "+62"),
        Country(name: "Italy", dial: "+39"),
        Country(name: "Japan", dial: "+81"),
        Country(name: "Kenya", dial: "+254"),
        Country(name: "Kuwait", dial: "+965"),
        Country(name: "Malaysia", dial: "+60"),
        Country(name: "Maldives", dial: "+960"),
        Country(name: "Mexico", dial: "+52"),
        Country(name: "Nepal", dial: "+977"),
        Country(name: "Netherlands", dial: "+31"),
        Country(name: "New Zealand", dial: "+64"),
        Country(name: "Nigeria", dial: "+234"),
        Country(name: "Norway", dial: "+47"),
        Country(name: "Oman", dial: "+968"),
        Country(name: "Pakistan", dial: "+92"),
        Country(name: "Philippines", dial: "+63"),
        Country(name: "Poland", dial: "+48"),
        Country(name: "Portugal", dial: "+351"),
        Country(name: "Qatar", dial: "+974"),
        Country(name: "Russia", dial: "+7"),
        Country(name: "Saudi Arabia", dial: "+966"),
        Country(name: "Singapore", dial: "+65"),
        Country(name: "South Africa", dial: "+27"),
        Country(name: "South Korea", dial: "+82"),
        Country(name: "Spain", dial: "+34"),
        Country(name: "Sri Lanka", dial: "+94"),
        Country(name: "Sweden", dial: "+46"),
        Country(name: "Switzerland", dial: "+41"),
        Country(name: "Thailand", dial: "+66"),
        Country(name: "Turkey", dial: "+90"),
        Country(name: "Ukraine", dial: "+380"),
        Country(name: "Vietnam", dial: "+84"),
    ]

    /// Splits a saved full number like "+919876543210" into (dial, rest) using
    /// longest-prefix matching against the known codes; falls back to a short
    /// leading digit run or the default "+91".
    static func split(_ raw: String) -> (dial: String, rest: String) {
        let plus = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if plus.hasPrefix("+") {
            let digits = String(plus.dropFirst().prefix { $0.isNumber })
            for length in stride(from: 4, through: 1, by: -1) {
                guard digits.count >= length else { continue }
                let candidate = "+" + String(digits.prefix(length))
                if entries.contains(where: { $0.dial == candidate }) {
                    return (candidate, String(digits.dropFirst(length)))
                }
            }
            // Unknown prefix: take a conservative 2-digit code.
            if digits.count > 2 {
                return ("+" + String(digits.prefix(2)), String(digits.dropFirst(2)))
            }
        }
        let rest = String(plus.drop { $0 == "+" }.filter { $0.isNumber })
        return (defaultDial, rest)
    }
}
