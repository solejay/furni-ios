import Foundation

/// How Homeward prices a transfer. Everything here is shown to the customer: no hidden spread.
public struct PricingPolicy: Codable, Hashable, Sendable {
    /// Margin applied to the mid-market rate, e.g. 0.004 = 0.4%.
    public var marginRate: Decimal
    /// Flat fee per send currency.
    public var flatFee: [Currency: Decimal]
    /// The flat fee is waived when the amount converted is at least this much.
    public var feeWaiverThreshold: [Currency: Decimal]
    public var minimumSend: [Currency: Decimal]
    public var maximumSend: [Currency: Decimal]

    public init(marginRate: Decimal, flatFee: [Currency: Decimal], feeWaiverThreshold: [Currency: Decimal],
                minimumSend: [Currency: Decimal], maximumSend: [Currency: Decimal]) {
        self.marginRate = marginRate
        self.flatFee = flatFee
        self.feeWaiverThreshold = feeWaiverThreshold
        self.minimumSend = minimumSend
        self.maximumSend = maximumSend
    }

    public static let standard = PricingPolicy(
        marginRate: Decimal(string: "0.004")!,
        flatFee: [.GBP: Decimal(string: "0.99")!, .EUR: Decimal(string: "0.99")!, .USD: Decimal(string: "1.49")!, .CAD: Decimal(string: "1.99")!],
        feeWaiverThreshold: [.GBP: 250, .EUR: 300, .USD: 300, .CAD: 400],
        minimumSend: [.GBP: 5, .EUR: 5, .USD: 5, .CAD: 10],
        maximumSend: [.GBP: 25_000, .EUR: 30_000, .USD: 30_000, .CAD: 40_000]
    )

    func fee(forConverted converted: Decimal, in currency: Currency) -> Decimal {
        if let threshold = feeWaiverThreshold[currency], converted >= threshold { return 0 }
        return flatFee[currency] ?? 0
    }
}

/// A priced, time-limited offer. The customer rate is guaranteed until `expiresAt`.
public struct Quote: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Total the sender pays.
    public let sendAmount: Money
    public let fee: Money
    /// `sendAmount - fee`, the part that gets converted.
    public let amountConverted: Money
    public let midMarketRate: Decimal
    public let customerRate: Decimal
    public let marginRate: Decimal
    /// Exactly what lands in the recipient's account.
    public let receiveAmount: Money
    public let createdAt: Date
    public let expiresAt: Date

    public var source: Currency { sendAmount.currency }
    public var target: Currency { receiveAmount.currency }

    /// What the margin costs the sender, in the send currency.
    public var marginCost: Money {
        Money(amountConverted.amount * marginRate, source, rounding: .up)
    }

    /// Fee + margin: the true cost of the transfer.
    public var totalCost: Money { fee + marginCost }

    /// Total cost as a fraction of the amount sent.
    public var totalCostRate: Decimal {
        guard sendAmount.amount > 0 else { return 0 }
        return (totalCost.amount / sendAmount.amount).rounded(scale: 4, mode: .plain)
    }

    /// What the recipient would get at the pure mid-market rate with no fee: the theoretical best.
    public var midMarketReceiveAmount: Money {
        Money(sendAmount.amount * midMarketRate, target, rounding: .down)
    }

    public func isExpired(at date: Date) -> Bool { date >= expiresAt }

    public func timeRemaining(at date: Date) -> TimeInterval { max(0, expiresAt.timeIntervalSince(date)) }
}

public enum QuoteError: Error, Equatable, Sendable {
    case unsupportedCorridor(Currency, Currency)
    case rateUnavailable
    case belowMinimum(Money)
    case aboveMaximum(Money)
    case amountDoesNotCoverFee(Money)

    public var message: String {
        switch self {
        case let .unsupportedCorridor(from, to): return "We don't send \(from.code) to \(to.code) yet."
        case .rateUnavailable: return "Rates are temporarily unavailable. Please try again shortly."
        case let .belowMinimum(min): return "The minimum transfer is \(min.formattedCompact)."
        case let .aboveMaximum(max): return "The maximum single transfer is \(max.formattedCompact)."
        case let .amountDoesNotCoverFee(fee): return "Amount must be more than the \(fee.formatted) fee."
        }
    }
}

public struct QuoteEngine: Sendable {
    public var rates: any RateProvider
    public var policy: PricingPolicy
    /// How long a quoted rate is guaranteed.
    public var lockDuration: TimeInterval

    public init(rates: any RateProvider, policy: PricingPolicy = .standard, lockDuration: TimeInterval = 30 * 60) {
        self.rates = rates
        self.policy = policy
        self.lockDuration = lockDuration
    }

    public func customerRate(from source: Currency, to target: Currency) throws -> (mid: Decimal, customer: Decimal) {
        guard source.canSend, target.canReceive else { throw QuoteError.unsupportedCorridor(source, target) }
        guard let mid = rates.midMarketRate(from: source, to: target), mid > 0 else { throw QuoteError.rateUnavailable }
        let customer = (mid * (1 - policy.marginRate)).rounded(scale: 6, mode: .down)
        return (mid, customer)
    }

    /// "I want to send X."
    public func quote(sending send: Money, to target: Currency, at now: Date = Date()) throws -> Quote {
        let source = send.currency
        let (mid, customer) = try customerRate(from: source, to: target)
        try checkLimits(send)

        // Fee waiver is judged on the amount sent: sending at or above the threshold is fee-free.
        let fee = policy.fee(forConverted: send.amount, in: source)
        let converted = send.amount - fee
        guard converted > 0 else { throw QuoteError.amountDoesNotCoverFee(Money(fee, source)) }

        return Quote(
            id: UUID(),
            sendAmount: send,
            fee: Money(fee, source),
            amountConverted: Money(converted, source),
            midMarketRate: mid,
            customerRate: customer,
            marginRate: policy.marginRate,
            receiveAmount: Money(converted * customer, target, rounding: .down),
            createdAt: now,
            expiresAt: now.addingTimeInterval(lockDuration)
        )
    }

    /// "I want them to receive exactly Y." Returns the cheapest quote that delivers at least Y.
    public func quote(receiving receive: Money, from source: Currency, at now: Date = Date()) throws -> Quote {
        let (_, customer) = try customerRate(from: source, to: receive.currency)
        let converted = (receive.amount / customer).rounded(scale: source.minorUnitScale, mode: .up)
        let fee = policy.fee(forConverted: converted, in: source)
        var send = converted + fee
        // Adding the fee can push the send amount over the waiver threshold, which removes the fee again.
        if fee > 0, let threshold = policy.feeWaiverThreshold[source], send >= threshold {
            send = max(converted, threshold)
        }

        var quote = try quote(sending: Money(send, source), to: receive.currency, at: now)
        // Guard against rounding leaving the recipient a minor unit short.
        var attempts = 0
        while quote.receiveAmount < receive && attempts < 5 {
            send += Decimal(string: "0.01")!
            quote = try self.quote(sending: Money(send, source), to: receive.currency, at: now)
            attempts += 1
        }
        return quote
    }

    private func checkLimits(_ send: Money) throws {
        if let min = policy.minimumSend[send.currency], send.amount < min {
            throw QuoteError.belowMinimum(Money(min, send.currency))
        }
        if let max = policy.maximumSend[send.currency], send.amount > max {
            throw QuoteError.aboveMaximum(Money(max, send.currency))
        }
    }
}

/// Side-by-side comparison with typical alternatives so customers can see the saving.
/// The benchmark figures are illustrative assumptions, not measurements of named providers.
public struct ProviderBenchmark: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let marginRate: Decimal
    /// Flat fee in USD, converted to the send currency at mid-market.
    public let feeUSD: Decimal
    public var id: String { name }

    public static let illustrative: [ProviderBenchmark] = [
        ProviderBenchmark(name: "Typical high-street bank", marginRate: Decimal(string: "0.035")!, feeUSD: 15),
        ProviderBenchmark(name: "Typical money-transfer app", marginRate: Decimal(string: "0.018")!, feeUSD: Decimal(string: "2.99")!),
    ]
}

public struct ProviderComparison: Hashable, Sendable, Identifiable {
    public let providerName: String
    public let receiveAmount: Money
    /// How much more the Homeward recipient gets.
    public let extraWithHomeward: Money
    public var id: String { providerName }
}

extension QuoteEngine {
    public func compare(_ quote: Quote, against benchmarks: [ProviderBenchmark] = ProviderBenchmark.illustrative) -> [ProviderComparison] {
        guard let usdToSource = rates.midMarketRate(from: .USD, to: quote.source) else { return [] }
        return benchmarks.map { benchmark in
            let fee = benchmark.feeUSD * usdToSource
            let converted = max(0, quote.sendAmount.amount - fee)
            let rate = quote.midMarketRate * (1 - benchmark.marginRate)
            let receive = Money(converted * rate, quote.target, rounding: .down)
            let extra = quote.receiveAmount - receive
            return ProviderComparison(providerName: benchmark.name, receiveAmount: receive,
                                      extraWithHomeward: extra.amount > 0 ? extra : .zero(quote.target))
        }
    }
}
