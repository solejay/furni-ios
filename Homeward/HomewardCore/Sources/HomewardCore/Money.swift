import Foundation

/// Currencies Homeward can send from or pay out in.
public enum Currency: String, Codable, CaseIterable, Identifiable, Sendable {
    // Send currencies
    case GBP, EUR, USD, CAD
    // Payout currencies
    case NGN, GHS, KES, INR

    public var id: String { rawValue }
    public var code: String { rawValue }

    public var name: String {
        switch self {
        case .GBP: return "British Pound"
        case .EUR: return "Euro"
        case .USD: return "US Dollar"
        case .CAD: return "Canadian Dollar"
        case .NGN: return "Nigerian Naira"
        case .GHS: return "Ghanaian Cedi"
        case .KES: return "Kenyan Shilling"
        case .INR: return "Indian Rupee"
        }
    }

    public var symbol: String {
        switch self {
        case .GBP: return "£"
        case .EUR: return "€"
        case .USD: return "$"
        case .CAD: return "CA$"
        case .NGN: return "₦"
        case .GHS: return "GH₵"
        case .KES: return "KSh"
        case .INR: return "₹"
        }
    }

    public var flag: String {
        switch self {
        case .GBP: return "🇬🇧"
        case .EUR: return "🇪🇺"
        case .USD: return "🇺🇸"
        case .CAD: return "🇨🇦"
        case .NGN: return "🇳🇬"
        case .GHS: return "🇬🇭"
        case .KES: return "🇰🇪"
        case .INR: return "🇮🇳"
        }
    }

    /// Number of digits after the decimal point.
    public var minorUnitScale: Int { 2 }

    public var canSend: Bool { Currency.sendCurrencies.contains(self) }
    public var canReceive: Bool { Currency.receiveCurrencies.contains(self) }

    public static let sendCurrencies: [Currency] = [.GBP, .EUR, .USD, .CAD]
    public static let receiveCurrencies: [Currency] = [.NGN, .GHS, .KES, .INR]
}

/// An amount of a single currency, always held at the currency's minor-unit precision.
public struct Money: Codable, Hashable, Comparable, Sendable {
    public let amount: Decimal
    public let currency: Currency

    /// Creates money, rounding half-even ("banker's") to the currency's minor units.
    public init(_ amount: Decimal, _ currency: Currency) {
        self.amount = amount.rounded(scale: currency.minorUnitScale, mode: .bankers)
        self.currency = currency
    }

    public init(_ amount: Decimal, _ currency: Currency, rounding mode: NSDecimalNumber.RoundingMode) {
        self.amount = amount.rounded(scale: currency.minorUnitScale, mode: mode)
        self.currency = currency
    }

    public static func zero(_ currency: Currency) -> Money { Money(0, currency) }

    public var isZero: Bool { amount == 0 }
    public var isPositive: Bool { amount > 0 }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot add \(lhs.currency) to \(rhs.currency)")
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot subtract \(rhs.currency) from \(lhs.currency)")
        return Money(lhs.amount - rhs.amount, lhs.currency)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Cannot compare \(lhs.currency) with \(rhs.currency)")
        return lhs.amount < rhs.amount
    }

    /// "£1,250.00"
    public var formatted: String { MoneyFormatter.string(from: self) }
    /// "£1,250"; drops ".00" for whole amounts.
    public var formattedCompact: String { MoneyFormatter.string(from: self, dropZeroFraction: true) }
}

extension Decimal {
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    public var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Parses user-typed numbers such as "1,250.5" without depending on the device locale.
    public init?(userInput: String) {
        let cleaned = userInput
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty,
              cleaned.allSatisfy({ $0.isNumber || $0 == "." }),
              cleaned.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        self = value
    }
}

/// Locale-independent formatting so amounts read the same everywhere and tests are deterministic.
public enum MoneyFormatter {
    public static func string(from money: Money, dropZeroFraction: Bool = false, showSymbol: Bool = true) -> String {
        let number = string(from: money.amount, fractionDigits: money.currency.minorUnitScale, dropZeroFraction: dropZeroFraction)
        return showSymbol ? money.currency.symbol + number : number + " " + money.currency.code
    }

    public static func string(from value: Decimal, fractionDigits: Int, dropZeroFraction: Bool = false) -> String {
        let rounded = value.rounded(scale: fractionDigits, mode: .bankers)
        let negative = rounded < 0
        let absolute = negative ? -rounded : rounded
        let raw = NSDecimalNumber(decimal: absolute).stringValue
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let integerPart = String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        if fraction.count < fractionDigits {
            fraction += String(repeating: "0", count: fractionDigits - fraction.count)
        }

        var grouped = ""
        for (index, char) in integerPart.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(",") }
            grouped.append(char)
        }
        grouped = String(grouped.reversed())

        let showFraction = fractionDigits > 0 && !(dropZeroFraction && fraction.allSatisfy { $0 == "0" })
        return (negative ? "-" : "") + grouped + (showFraction ? "." + fraction : "")
    }

    /// Exchange rates get more precision when they are small (e.g. NGN→GBP).
    public static func rate(_ rate: Decimal) -> String {
        let digits: Int
        switch rate.doubleValue {
        case ..<0.01: digits = 6
        case ..<1: digits = 4
        case ..<100: digits = 4
        default: digits = 2
        }
        return string(from: rate, fractionDigits: digits)
    }

    /// "0.45%"
    public static func percent(_ fraction: Decimal, fractionDigits: Int = 2) -> String {
        string(from: fraction * 100, fractionDigits: fractionDigits) + "%"
    }
}
