import Foundation

public enum Country: String, Codable, CaseIterable, Identifiable, Sendable {
    case nigeria = "NG", ghana = "GH", kenya = "KE", india = "IN"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .nigeria: return "Nigeria"
        case .ghana: return "Ghana"
        case .kenya: return "Kenya"
        case .india: return "India"
        }
    }

    public var currency: Currency {
        switch self {
        case .nigeria: return .NGN
        case .ghana: return .GHS
        case .kenya: return .KES
        case .india: return .INR
        }
    }

    public var flag: String { currency.flag }

    public init?(currency: Currency) {
        guard let match = Country.allCases.first(where: { $0.currency == currency }) else { return nil }
        self = match
    }

    public var payoutMethods: [PayoutMethod] {
        switch self {
        case .nigeria: return [.bankAccount]
        case .ghana: return [.mobileMoney, .bankAccount]
        case .kenya: return [.mobileMoney]
        case .india: return [.bankAccount, .upi]
        }
    }
}

public enum PayoutMethod: String, Codable, CaseIterable, Sendable {
    case bankAccount, mobileMoney, upi

    public var title: String {
        switch self {
        case .bankAccount: return "Bank account"
        case .mobileMoney: return "Mobile money"
        case .upi: return "UPI"
        }
    }
}

public struct Bank: Codable, Hashable, Identifiable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    /// Nigerian banks with their CBN codes. Three-digit codes are deposit-money banks whose NUBANs
    /// carry a verifiable check digit; longer codes are microfinance/fintech banks.
    public static let nigeria: [Bank] = [
        Bank(code: "044", name: "Access Bank"),
        Bank(code: "023", name: "Citibank Nigeria"),
        Bank(code: "050", name: "Ecobank Nigeria"),
        Bank(code: "070", name: "Fidelity Bank"),
        Bank(code: "011", name: "First Bank of Nigeria"),
        Bank(code: "214", name: "First City Monument Bank"),
        Bank(code: "058", name: "Guaranty Trust Bank"),
        Bank(code: "030", name: "Heritage Bank"),
        Bank(code: "082", name: "Keystone Bank"),
        Bank(code: "076", name: "Polaris Bank"),
        Bank(code: "221", name: "Stanbic IBTC Bank"),
        Bank(code: "068", name: "Standard Chartered"),
        Bank(code: "232", name: "Sterling Bank"),
        Bank(code: "032", name: "Union Bank"),
        Bank(code: "033", name: "United Bank for Africa"),
        Bank(code: "035", name: "Wema Bank"),
        Bank(code: "057", name: "Zenith Bank"),
        Bank(code: "50211", name: "Kuda Microfinance Bank"),
        Bank(code: "50515", name: "Moniepoint Microfinance Bank"),
        Bank(code: "999992", name: "OPay"),
        Bank(code: "100004", name: "PalmPay"),
    ]

    public static func nigerianBank(code: String) -> Bank? { nigeria.first { $0.code == code } }
}

public enum GhanaNetwork: String, Codable, CaseIterable, Sendable {
    case mtn, telecel, airtelTigo

    public var title: String {
        switch self {
        case .mtn: return "MTN MoMo"
        case .telecel: return "Telecel Cash"
        case .airtelTigo: return "AT Money"
        }
    }

    /// Local (0-prefixed) number prefixes for each network.
    public var prefixes: [String] {
        switch self {
        case .mtn: return ["024", "025", "053", "054", "055", "059"]
        case .telecel: return ["020", "050"]
        case .airtelTigo: return ["026", "027", "056", "057"]
        }
    }
}

/// Where the money goes. Each case carries exactly the fields that payout rail needs.
public enum PayoutDetails: Codable, Hashable, Sendable {
    case nigeriaBank(bankCode: String, accountNumber: String)
    case ghanaMobileMoney(network: GhanaNetwork, phone: String)
    case ghanaBank(bankName: String, accountNumber: String)
    case kenyaMpesa(phone: String)
    case indiaBank(ifsc: String, accountNumber: String)
    case indiaUPI(vpa: String)

    public var method: PayoutMethod {
        switch self {
        case .nigeriaBank, .ghanaBank, .indiaBank: return .bankAccount
        case .ghanaMobileMoney, .kenyaMpesa: return .mobileMoney
        case .indiaUPI: return .upi
        }
    }

    public var country: Country {
        switch self {
        case .nigeriaBank: return .nigeria
        case .ghanaMobileMoney, .ghanaBank: return .ghana
        case .kenyaMpesa: return .kenya
        case .indiaBank, .indiaUPI: return .india
        }
    }

    /// "GTBank ·· 4821", "M-Pesa ·· 678"
    public var summary: String {
        switch self {
        case let .nigeriaBank(code, account):
            return "\(Bank.nigerianBank(code: code)?.name ?? "Bank") ·· \(account.suffix(4))"
        case let .ghanaMobileMoney(network, phone):
            return "\(network.title) ·· \(phone.suffix(3))"
        case let .ghanaBank(bank, account):
            return "\(bank) ·· \(account.suffix(4))"
        case let .kenyaMpesa(phone):
            return "M-Pesa ·· \(phone.suffix(3))"
        case let .indiaBank(ifsc, account):
            return "\(ifsc.prefix(4)) ·· \(account.suffix(4))"
        case let .indiaUPI(vpa):
            return vpa
        }
    }
}

public struct Recipient: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// The name as the sender typed it.
    public var fullName: String
    /// The account holder's name as reported by the receiving bank or wallet, once checked.
    public var verifiedName: String?
    public var nickname: String?
    public var payout: PayoutDetails
    public var createdAt: Date

    public init(id: UUID = UUID(), fullName: String, verifiedName: String? = nil, nickname: String? = nil,
                payout: PayoutDetails, createdAt: Date = Date()) {
        self.id = id
        self.fullName = fullName
        self.verifiedName = verifiedName
        self.nickname = nickname
        self.payout = payout
        self.createdAt = createdAt
    }

    public var country: Country { payout.country }
    public var currency: Currency { payout.country.currency }
    public var displayName: String { nickname.map { "\($0) (\(fullName))" } ?? fullName }

    public var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}
