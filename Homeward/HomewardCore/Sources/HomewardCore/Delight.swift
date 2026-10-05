import Foundation

// MARK: - Rate Weather

/// Today's rate described as weather, measured against the recent past. It describes, it never predicts.
public struct RateClimate: Hashable, Sendable {
    public enum Condition: String, CaseIterable, Sendable {
        case sunny, bright, mild, cloudy, overcast

        public var symbol: String {
            switch self {
            case .sunny: return "sun.max.fill"
            case .bright: return "sun.haze.fill"
            case .mild: return "cloud.sun.fill"
            case .cloudy: return "cloud.fill"
            case .overcast: return "cloud.rain.fill"
            }
        }

        public var emoji: String {
            switch self {
            case .sunny: return "☀️"
            case .bright: return "🌤️"
            case .mild: return "⛅"
            case .cloudy: return "☁️"
            case .overcast: return "🌧️"
            }
        }

        public var headline: String {
            switch self {
            case .sunny: return "Sunny day to send"
            case .bright: return "Brighter than usual"
            case .mild: return "An ordinary day"
            case .cloudy: return "Cloudier than usual"
            case .overcast: return "Overcast: rates are low"
            }
        }
    }

    /// How many earlier days today's rate beats, out of `daysCompared`.
    public let daysBeaten: Int
    public let daysCompared: Int

    public var percentile: Int { daysCompared == 0 ? 50 : Int((Double(daysBeaten) / Double(daysCompared) * 100).rounded()) }

    public var condition: Condition {
        switch percentile {
        case 80...: return .sunny
        case 60..<80: return .bright
        case 40..<60: return .mild
        case 20..<40: return .cloudy
        default: return .overcast
        }
    }

    public var detail: String {
        "Today's rate beats \(daysBeaten) of the last \(daysCompared) days."
    }

    /// Compares the last point (today) with every earlier point.
    public static func from(_ points: [RateHistory.Point]) -> RateClimate? {
        guard let today = points.last?.rate, points.count >= 2 else { return nil }
        let earlier = points.dropLast()
        return RateClimate(daysBeaten: earlier.filter { today > $0.rate }.count, daysCompared: earlier.count)
    }
}

// MARK: - Family Pot

/// Siblings abroad chip in, each in their own currency, toward one payout home.
/// One payout replaces a transfer per sibling, so the family pays one set of costs instead of several.
public struct FamilyPot: Codable, Hashable, Identifiable, Sendable {
    public struct Member: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public var name: String
        public var city: String
        public var currency: Currency
        public var isYou: Bool

        public init(id: UUID = UUID(), name: String, city: String, currency: Currency, isYou: Bool = false) {
            self.id = id
            self.name = name
            self.city = city
            self.currency = currency
            self.isYou = isYou
        }
    }

    public struct Contribution: Codable, Hashable, Identifiable, Sendable {
        public let id: UUID
        public let memberID: UUID
        public let sent: Money
        public let rate: Decimal
        /// What this contribution adds to the pot, in the pot's currency.
        public let added: Money
        public let date: Date
    }

    public enum PotError: Error, Equatable, Sendable {
        case alreadyPaidOut
        case unknownMember
        case belowMinimum(Money)
        case notFunded(remaining: Money)
        case unsupported(QuoteError)
    }

    public let id: UUID
    public var title: String
    public var recipientID: UUID
    public var target: Money
    public var members: [Member]
    public private(set) var contributions: [Contribution]
    public var createdAt: Date
    public private(set) var paidOutAt: Date?
    public private(set) var payoutReference: String?

    public init(id: UUID = UUID(), title: String, recipientID: UUID, target: Money, members: [Member],
                contributions: [Contribution] = [], createdAt: Date) {
        self.id = id
        self.title = title
        self.recipientID = recipientID
        self.target = target
        self.members = members
        self.contributions = contributions
        self.createdAt = createdAt
    }

    public var currency: Currency { target.currency }
    public var raised: Money { contributions.map(\.added).reduce(.zero(currency), +) }
    public var isFunded: Bool { raised >= target }
    public var isPaidOut: Bool { paidOutAt != nil }

    public var remaining: Money {
        let left = target - raised
        return left.amount > 0 ? left : .zero(currency)
    }

    public var progress: Double {
        guard target.amount > 0 else { return 1 }
        return min(1, (raised.amount / target.amount).doubleValue)
    }

    public func total(for memberID: UUID) -> Money {
        contributions.filter { $0.memberID == memberID }.map(\.added).reduce(.zero(currency), +)
    }

    /// Members ordered by how much they've added, so the ring reads largest slice first.
    public var shares: [(member: Member, added: Money)] {
        members.map { ($0, total(for: $0.id)) }.sorted { $0.1 > $1.1 }
    }

    /// Converts a member's money at Homeward's customer rate (margin applies, no per-contribution fee).
    @discardableResult
    public mutating func contribute(memberID: UUID, amount: Money, engine: QuoteEngine, at date: Date) throws -> Contribution {
        guard !isPaidOut else { throw PotError.alreadyPaidOut }
        guard members.contains(where: { $0.id == memberID }) else { throw PotError.unknownMember }
        if let minimum = engine.policy.minimumSend[amount.currency], amount.amount < minimum {
            throw PotError.belowMinimum(Money(minimum, amount.currency))
        }
        let rate: Decimal
        do {
            rate = try engine.customerRate(from: amount.currency, to: currency).customer
        } catch let error as QuoteError {
            throw PotError.unsupported(error)
        }
        let contribution = Contribution(id: UUID(), memberID: memberID, sent: amount, rate: rate,
                                        added: Money(amount.amount * rate, currency, rounding: .down), date: date)
        contributions.append(contribution)
        return contribution
    }

    /// Sends everything raised in one payout. Allowed once the target is met.
    public mutating func payOut(at date: Date) throws {
        guard !isPaidOut else { throw PotError.alreadyPaidOut }
        guard isFunded else { throw PotError.notFunded(remaining: remaining) }
        paidOutAt = date
        payoutReference = "POT-" + Transfer.makeReference(from: id).dropFirst(3)
    }

    /// The flat fees the family would have paid sending each contribution as its own transfer, in USD.
    public func feesAvoidedUSD(policy: PricingPolicy, rates: any RateProvider) -> Decimal {
        contributions.reduce(0) { total, contribution in
            let fee = policy.fee(forConverted: contribution.sent.amount, in: contribution.sent.currency)
            let toUSD = rates.midMarketRate(from: contribution.sent.currency, to: .USD) ?? 0
            return total + (fee * toUSD).rounded(scale: 2, mode: .plain)
        }
    }
}

// MARK: - Your Year Home

/// A twelve-month recap of what you sent home, for the story-style "Your Year Home" screen.
public struct YearInReview: Hashable, Sendable {
    public struct RecipientTotal: Hashable, Sendable {
        public let recipient: Recipient
        public let transfers: Int
        public let delivered: Money
    }

    public let start: Date
    public let end: Date
    public let transferCount: Int
    /// Total sent in the currency used most often.
    public let totalSent: Money
    public let deliveredByCurrency: [Money]
    public let recipients: [RecipientTotal]
    /// Extra the families received compared with a typical bank, valued in the main send currency.
    public let savedVersusBank: Money
    /// Month (1–12) and amount sent in the busiest month.
    public let busiestMonth: (month: Int, sent: Money)?
    public let fastestDelivery: TimeInterval?
    public let averageDelivery: TimeInterval?

    public static func == (lhs: YearInReview, rhs: YearInReview) -> Bool {
        lhs.start == rhs.start && lhs.end == rhs.end && lhs.transferCount == rhs.transferCount && lhs.totalSent == rhs.totalSent
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(transferCount)
        hasher.combine(totalSent)
    }

    /// Covers the twelve months up to `now`. Returns nil when nothing was delivered.
    public static func compute(transfers: [Transfer], engine: QuoteEngine, now: Date, calendar: Calendar) -> YearInReview? {
        guard let start = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }
        let delivered = transfers.filter { $0.status == .delivered && $0.createdAt > start && $0.createdAt <= now }
        guard !delivered.isEmpty else { return nil }

        let bySource = Dictionary(grouping: delivered, by: \.quote.source)
        let main = bySource.max { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key.rawValue > rhs.key.rawValue : lhs.value.count < rhs.value.count
        }!.key
        let mainTransfers = bySource[main]!
        let totalSent = mainTransfers.map(\.quote.sendAmount).reduce(.zero(main), +)

        let deliveredByCurrency = Dictionary(grouping: delivered, by: \.quote.target)
            .map { currency, list in list.map(\.quote.receiveAmount).reduce(.zero(currency), +) }
            .sorted { $0.currency.rawValue < $1.currency.rawValue }

        func total(_ list: [Transfer]) -> RecipientTotal {
            let amounts: [Money] = list.map(\.quote.receiveAmount)
            let sum: Money = amounts.reduce(Money.zero(list[0].quote.target), +)
            return RecipientTotal(recipient: list[0].recipient, transfers: list.count, delivered: sum)
        }
        func ranksBefore(_ lhs: RecipientTotal, _ rhs: RecipientTotal) -> Bool {
            if lhs.transfers != rhs.transfers { return lhs.transfers > rhs.transfers }
            return lhs.recipient.fullName < rhs.recipient.fullName
        }
        let groups: [[Transfer]] = Array(Dictionary(grouping: delivered, by: \.recipient.id).values)
        let recipients: [RecipientTotal] = groups.map(total).sorted(by: ranksBefore)

        let bank = ProviderBenchmark.illustrative[0]
        var saved: Decimal = 0
        for transfer in mainTransfers {
            if let comparison = engine.compare(transfer.quote, against: [bank]).first, transfer.quote.midMarketRate > 0 {
                saved += comparison.extraWithHomeward.amount / transfer.quote.midMarketRate
            }
        }

        let byMonth = Dictionary(grouping: mainTransfers) { calendar.component(.month, from: $0.createdAt) }
            .map { month, list in (month: month, sent: list.map(\.quote.sendAmount).reduce(.zero(main), +)) }
        let busiest = byMonth.max { $0.sent == $1.sent ? $0.month > $1.month : $0.sent < $1.sent }

        let durations = delivered.compactMap { transfer in transfer.date(of: .delivered).map { $0.timeIntervalSince(transfer.createdAt) } }

        return YearInReview(
            start: start, end: now, transferCount: delivered.count, totalSent: totalSent,
            deliveredByCurrency: deliveredByCurrency, recipients: recipients,
            savedVersusBank: Money(saved, main, rounding: .down), busiestMonth: busiest,
            fastestDelivery: durations.min(),
            averageDelivery: durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        )
    }
}
