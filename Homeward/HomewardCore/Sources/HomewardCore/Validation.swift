import Foundation

/// Catches typos *before* money moves. Most misdirected transfers start with one wrong digit.
public enum PayoutValidator {
    public enum Issue: Equatable, Sendable {
        case empty(field: String)
        case wrongLength(field: String, expected: String)
        case notNumeric(field: String)
        case checksumFailed
        case unknownBank
        case wrongNetwork(expected: GhanaNetwork, detected: GhanaNetwork?)
        case invalidFormat(field: String, example: String)

        public var message: String {
            switch self {
            case let .empty(field): return "Enter the \(field)."
            case let .wrongLength(field, expected): return "The \(field) should be \(expected)."
            case let .notNumeric(field): return "The \(field) should only contain digits."
            case .checksumFailed: return "This account number doesn't match the bank selected. Check for a mistyped digit."
            case .unknownBank: return "Choose a bank."
            case let .wrongNetwork(expected, detected):
                if let detected { return "This looks like a \(detected.title) number, not \(expected.title)." }
                return "This number doesn't belong to \(expected.title)."
            case let .invalidFormat(field, example): return "Check the \(field), e.g. \(example)."
            }
        }
    }

    /// Returns the first problem found, or nil when the details look valid.
    public static func validate(_ details: PayoutDetails) -> Issue? {
        switch details {
        case let .nigeriaBank(code, account): return validateNUBAN(bankCode: code, accountNumber: account)
        case let .ghanaMobileMoney(network, phone): return validateGhanaMobile(network: network, phone: phone)
        case let .ghanaBank(bank, account):
            if bank.trimmingCharacters(in: .whitespaces).isEmpty { return .unknownBank }
            let digits = account.filter { !$0.isWhitespace }
            if digits.isEmpty { return .empty(field: "account number") }
            if !digits.allSatisfy(\.isASCIIDigit) { return .notNumeric(field: "account number") }
            if !(10...16).contains(digits.count) { return .wrongLength(field: "account number", expected: "10–16 digits") }
            return nil
        case let .kenyaMpesa(phone): return validateKenyaMpesa(phone: phone)
        case let .indiaBank(ifsc, account): return validateIndiaBank(ifsc: ifsc, accountNumber: account)
        case let .indiaUPI(vpa): return validateUPI(vpa)
        }
    }

    // MARK: Nigeria

    /// NUBAN check digit (CBN standard): weights 3,7,3 repeated over the 3-digit bank code followed by
    /// the 9-digit serial; the check digit is (10 - sum mod 10) mod 10.
    public static func nubanCheckDigit(bankCode: String, serial: String) -> Int? {
        let input = bankCode + serial
        guard bankCode.count == 3, serial.count == 9, input.allSatisfy(\.isASCIIDigit) else { return nil }
        let weights = [3, 7, 3, 3, 7, 3, 3, 7, 3, 3, 7, 3]
        let sum = zip(input, weights).reduce(0) { $0 + Int(String($1.0))! * $1.1 }
        return (10 - sum % 10) % 10
    }

    public static func validateNUBAN(bankCode: String, accountNumber: String) -> Issue? {
        guard Bank.nigerianBank(code: bankCode) != nil else { return .unknownBank }
        let account = accountNumber.filter { !$0.isWhitespace }
        if account.isEmpty { return .empty(field: "account number") }
        if !account.allSatisfy(\.isASCIIDigit) { return .notNumeric(field: "account number") }
        if account.count != 10 { return .wrongLength(field: "account number", expected: "10 digits") }
        // Only classic 3-digit bank codes have a publicly verifiable check digit.
        if bankCode.count == 3,
           let expected = nubanCheckDigit(bankCode: bankCode, serial: String(account.prefix(9))),
           expected != Int(String(account.last!))! {
            return .checksumFailed
        }
        return nil
    }

    /// Builds a valid NUBAN from a bank code and 9-digit serial (used for demo data and tests).
    public static func makeNUBAN(bankCode: String, serial: String) -> String? {
        nubanCheckDigit(bankCode: bankCode, serial: serial).map { serial + String($0) }
    }

    // MARK: Ghana

    /// Normalises "+233 24 123 4567", "233241234567" or "0241234567" to "0241234567".
    public static func normalizeGhanaPhone(_ phone: String) -> String? {
        var digits = phone.filter(\.isASCIIDigit)
        if digits.hasPrefix("233") { digits = "0" + digits.dropFirst(3) }
        else if digits.count == 9 { digits = "0" + digits }
        return digits.count == 10 && digits.hasPrefix("0") ? digits : nil
    }

    public static func ghanaNetwork(for phone: String) -> GhanaNetwork? {
        guard let local = normalizeGhanaPhone(phone) else { return nil }
        let prefix = String(local.prefix(3))
        return GhanaNetwork.allCases.first { $0.prefixes.contains(prefix) }
    }

    public static func validateGhanaMobile(network: GhanaNetwork, phone: String) -> Issue? {
        if phone.trimmingCharacters(in: .whitespaces).isEmpty { return .empty(field: "phone number") }
        guard normalizeGhanaPhone(phone) != nil else {
            return .invalidFormat(field: "phone number", example: "024 123 4567")
        }
        let detected = ghanaNetwork(for: phone)
        return detected == network ? nil : .wrongNetwork(expected: network, detected: detected)
    }

    // MARK: Kenya

    /// Normalises to "2547XXXXXXXX" / "2541XXXXXXXX".
    public static func normalizeKenyaPhone(_ phone: String) -> String? {
        var digits = phone.filter(\.isASCIIDigit)
        if digits.hasPrefix("254") { digits = String(digits.dropFirst(3)) }
        else if digits.hasPrefix("0") { digits = String(digits.dropFirst()) }
        guard digits.count == 9, digits.hasPrefix("7") || digits.hasPrefix("1") else { return nil }
        return "254" + digits
    }

    public static func validateKenyaMpesa(phone: String) -> Issue? {
        if phone.trimmingCharacters(in: .whitespaces).isEmpty { return .empty(field: "phone number") }
        return normalizeKenyaPhone(phone) == nil ? .invalidFormat(field: "M-Pesa number", example: "0712 345 678") : nil
    }

    // MARK: India

    public static func isValidIFSC(_ ifsc: String) -> Bool {
        let code = Array(ifsc.uppercased())
        guard code.count == 11 else { return false }
        return code[0..<4].allSatisfy { $0.isASCII && $0.isLetter }
            && code[4] == "0"
            && code[5...].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public static func validateIndiaBank(ifsc: String, accountNumber: String) -> Issue? {
        if ifsc.isEmpty { return .empty(field: "IFSC code") }
        if !isValidIFSC(ifsc) { return .invalidFormat(field: "IFSC code", example: "HDFC0001234") }
        let account = accountNumber.filter { !$0.isWhitespace }
        if account.isEmpty { return .empty(field: "account number") }
        if !account.allSatisfy(\.isASCIIDigit) { return .notNumeric(field: "account number") }
        if !(9...18).contains(account.count) { return .wrongLength(field: "account number", expected: "9–18 digits") }
        return nil
    }

    public static func validateUPI(_ vpa: String) -> Issue? {
        let trimmed = vpa.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty(field: "UPI ID") }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        let allowedHandle = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard parts.count == 2,
              (2...256).contains(parts[0].count),
              parts[0].unicodeScalars.allSatisfy(allowedHandle.contains),
              parts[1].count >= 2,
              parts[1].allSatisfy({ $0.isASCII && $0.isLetter })
        else { return .invalidFormat(field: "UPI ID", example: "name@okbank") }
        return nil
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// Compares the name the sender typed with the name the bank reports, so money doesn't go to a stranger.
public enum NameMatcher {
    public enum Verdict: String, Codable, Sendable {
        /// Every word the sender typed appears in the bank's name.
        case match
        /// Some overlap: nicknames, initials or a missing middle name. Worth a second look.
        case partial
        /// No meaningful overlap. Very likely the wrong account.
        case mismatch
    }

    public static func tokens(_ name: String) -> [String] {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    public static func compare(entered: String, verified: String) -> Verdict {
        let typed = tokens(entered)
        let actual = tokens(verified)
        guard !typed.isEmpty, !actual.isEmpty else { return .mismatch }

        func matches(_ a: String, _ b: String) -> Bool {
            if a == b { return true }
            // "Ade" vs "Adebayo", or an initial "A" vs "Adebayo".
            let (short, long) = a.count <= b.count ? (a, b) : (b, a)
            return (short.count == 1 || short.count >= 3) && long.hasPrefix(short)
        }

        var remaining = actual
        var exact = 0
        var fuzzy = 0
        for word in typed {
            if let index = remaining.firstIndex(of: word) {
                exact += 1
                remaining.remove(at: index)
            } else if let index = remaining.firstIndex(where: { matches(word, $0) }) {
                fuzzy += 1
                remaining.remove(at: index)
            }
        }

        if exact == typed.count && exact >= min(2, actual.count) { return .match }
        if exact + fuzzy >= 1 && (exact >= 1 || fuzzy >= 2) { return .partial }
        return .mismatch
    }
}

/// Looks up the account holder's name on the receiving side.
public protocol AccountNameResolver: Sendable {
    func resolveName(for details: PayoutDetails) async throws -> String
}

public enum AccountLookupError: Error, Equatable, Sendable {
    case accountNotFound
    case serviceUnavailable
}

/// In-memory resolver for demos and tests.
public struct DirectoryNameResolver: AccountNameResolver {
    public var directory: [PayoutDetails: String]
    public var fallback: @Sendable (PayoutDetails) -> String?
    public var latency: Duration

    public init(directory: [PayoutDetails: String], latency: Duration = .zero,
                fallback: @escaping @Sendable (PayoutDetails) -> String? = { _ in nil }) {
        self.directory = directory
        self.latency = latency
        self.fallback = fallback
    }

    public func resolveName(for details: PayoutDetails) async throws -> String {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let name = directory[details] ?? fallback(details) { return name }
        throw AccountLookupError.accountNotFound
    }
}
