import Foundation

/// Multi-currency balances the customer can hold, top up and send from.
public struct Wallet: Codable, Hashable, Sendable {
    public private(set) var balances: [Currency: Decimal]

    public init(balances: [Currency: Decimal] = [:]) {
        self.balances = balances
    }

    public enum WalletError: Error, Equatable, Sendable {
        case insufficientFunds(available: Money)
        case invalidAmount
    }

    public func balance(_ currency: Currency) -> Money {
        Money(balances[currency] ?? 0, currency)
    }

    /// Currencies with a balance, largest first, then the rest of the send currencies.
    public var displayCurrencies: [Currency] {
        let held = balances.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
        return held + Currency.sendCurrencies.filter { !held.contains($0) }
    }

    public mutating func credit(_ money: Money) throws {
        guard money.isPositive else { throw WalletError.invalidAmount }
        balances[money.currency] = (balances[money.currency] ?? 0) + money.amount
    }

    public mutating func debit(_ money: Money) throws {
        guard money.isPositive else { throw WalletError.invalidAmount }
        let available = balance(money.currency)
        guard available.amount >= money.amount else { throw WalletError.insufficientFunds(available: available) }
        balances[money.currency] = available.amount - money.amount
    }

    public func canAfford(_ money: Money) -> Bool {
        balance(money.currency).amount >= money.amount
    }
}

/// Moves transfers along at a believable pace for demos (real transfers are driven by the backend).
public struct TransferSimulator: Sendable {
    /// Seconds from creation at which each step happens.
    public var fundedAfter: TimeInterval
    public var sentAfter: TimeInterval
    public var deliveredAfter: TimeInterval

    public init(fundedAfter: TimeInterval = 3, sentAfter: TimeInterval = 7, deliveredAfter: TimeInterval = 14) {
        self.fundedAfter = fundedAfter
        self.sentAfter = sentAfter
        self.deliveredAfter = deliveredAfter
    }

    /// Applies every step that should have happened by `now`. Returns true if the transfer changed.
    @discardableResult
    public func catchUp(_ transfer: inout Transfer, now: Date) -> Bool {
        let start = transfer.createdAt
        let plan: [(TransferStatus, TransferStatus, TimeInterval)] = [
            (.awaitingFunding, .processing, fundedAfter),
            (.processing, .sentToPartner, sentAfter),
            (.sentToPartner, .delivered, deliveredAfter),
        ]
        var changed = false
        for (from, to, offset) in plan where transfer.status == from {
            let due = start.addingTimeInterval(offset)
            guard now >= due else { break }
            try? transfer.advance(to: to, at: due)
            changed = true
        }
        return changed
    }
}
