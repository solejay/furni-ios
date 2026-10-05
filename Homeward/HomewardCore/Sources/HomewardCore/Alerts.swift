import Foundation

/// "Tell me when £1 gets me ₦2,100."
public struct RateAlert: Codable, Hashable, Identifiable, Sendable {
    public enum Direction: String, Codable, Sendable { case atOrAbove, atOrBelow }

    public let id: UUID
    public var source: Currency
    public var target: Currency
    public var targetRate: Decimal
    public var direction: Direction
    public var isActive: Bool
    public var lastTriggeredAt: Date?

    public init(id: UUID = UUID(), source: Currency, target: Currency, targetRate: Decimal,
                direction: Direction = .atOrAbove, isActive: Bool = true, lastTriggeredAt: Date? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.targetRate = targetRate
        self.direction = direction
        self.isActive = isActive
        self.lastTriggeredAt = lastTriggeredAt
    }

    public func isMet(by rate: Decimal) -> Bool {
        switch direction {
        case .atOrAbove: return rate >= targetRate
        case .atOrBelow: return rate <= targetRate
        }
    }

    /// Fires at most once per `cooldown` so a rate hovering at the target doesn't spam the user.
    public func shouldNotify(rate: Decimal, at now: Date, cooldown: TimeInterval = 12 * 3600) -> Bool {
        guard isActive, isMet(by: rate) else { return false }
        guard let last = lastTriggeredAt else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    public var summary: String {
        let symbol = direction == .atOrAbove ? "≥" : "≤"
        return "1 \(source.code) \(symbol) \(MoneyFormatter.rate(targetRate)) \(target.code)"
    }
}

public struct RecurringSchedule: Codable, Hashable, Sendable {
    public enum Frequency: Codable, Hashable, Sendable {
        case weekly
        case fortnightly
        /// Day of month 1...31; clamps to the last day in shorter months.
        case monthly(day: Int)

        public var title: String {
            switch self {
            case .weekly: return "Every week"
            case .fortnightly: return "Every 2 weeks"
            case let .monthly(day): return "Monthly on the \(RecurringSchedule.ordinal(day))"
            }
        }
    }

    public var frequency: Frequency
    public var startDate: Date

    public init(frequency: Frequency, startDate: Date) {
        self.frequency = frequency
        self.startDate = startDate
    }

    /// The next `count` run dates strictly after `date` (runs on/after `startDate` only).
    public func nextDates(after date: Date, count: Int, calendar: Calendar) -> [Date] {
        var results: [Date] = []
        var index = 0
        while results.count < count && index < 10_000 {
            if let candidate = occurrence(index, calendar: calendar), candidate > date {
                results.append(candidate)
            }
            index += 1
        }
        return results
    }

    private func occurrence(_ index: Int, calendar: Calendar) -> Date? {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * index, to: startDate)
        case .fortnightly:
            return calendar.date(byAdding: .day, value: 14 * index, to: startDate)
        case let .monthly(day):
            let startMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate))!
            guard let month = calendar.date(byAdding: .month, value: index, to: startMonth),
                  let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(max(day, 1), range.count)
            let time = calendar.dateComponents([.hour, .minute], from: startDate)
            components.hour = time.hour
            components.minute = time.minute
            guard let candidate = calendar.date(from: components) else { return nil }
            return candidate >= startDate ? candidate : nil
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

/// "Mum's allowance": a transfer that repeats on a schedule at the rate of the day.
public struct ScheduledTransfer: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var recipientID: UUID
    public var sendAmount: Money
    public var target: Currency
    public var schedule: RecurringSchedule
    public var fundingSource: FundingSource
    public var isPaused: Bool

    public init(id: UUID = UUID(), title: String, recipientID: UUID, sendAmount: Money, target: Currency,
                schedule: RecurringSchedule, fundingSource: FundingSource = .wallet, isPaused: Bool = false) {
        self.id = id
        self.title = title
        self.recipientID = recipientID
        self.sendAmount = sendAmount
        self.target = target
        self.schedule = schedule
        self.fundingSource = fundingSource
        self.isPaused = isPaused
    }

    public func nextRun(after date: Date, calendar: Calendar) -> Date? {
        isPaused ? nil : schedule.nextDates(after: date, count: 1, calendar: calendar).first
    }
}

/// Verification levels and their limits, stated up front so nobody is surprised mid-transfer.
public enum VerificationTier: String, Codable, CaseIterable, Sendable {
    case basic, verified, enhanced

    public var title: String {
        switch self {
        case .basic: return "Basic"
        case .verified: return "Verified"
        case .enhanced: return "Enhanced"
        }
    }

    /// Limits in USD-equivalent.
    public var dailyLimitUSD: Decimal {
        switch self {
        case .basic: return 500
        case .verified: return 5_000
        case .enhanced: return 25_000
        }
    }

    public var monthlyLimitUSD: Decimal {
        switch self {
        case .basic: return 1_500
        case .verified: return 20_000
        case .enhanced: return 100_000
        }
    }

    public var requirements: String {
        switch self {
        case .basic: return "Phone and email confirmed"
        case .verified: return "Photo ID and a selfie: about 2 minutes"
        case .enhanced: return "Proof of address and source of funds"
        }
    }

    public var next: VerificationTier? {
        switch self {
        case .basic: return .verified
        case .verified: return .enhanced
        case .enhanced: return nil
        }
    }
}

public struct LimitUsage: Hashable, Sendable {
    public let usedTodayUSD: Decimal
    public let usedThisMonthUSD: Decimal
    public let tier: VerificationTier

    public var remainingTodayUSD: Decimal { max(0, tier.dailyLimitUSD - usedTodayUSD) }
    public var remainingThisMonthUSD: Decimal { max(0, tier.monthlyLimitUSD - usedThisMonthUSD) }
    public var remainingUSD: Decimal { min(remainingTodayUSD, remainingThisMonthUSD) }

    public enum Check: Equatable, Sendable {
        case allowed
        case exceedsDaily(remainingUSD: Decimal)
        case exceedsMonthly(remainingUSD: Decimal)
    }

    public func check(amountUSD: Decimal) -> Check {
        if amountUSD > remainingTodayUSD { return .exceedsDaily(remainingUSD: remainingTodayUSD) }
        if amountUSD > remainingThisMonthUSD { return .exceedsMonthly(remainingUSD: remainingThisMonthUSD) }
        return .allowed
    }

    /// Counts every transfer that wasn't cancelled or refunded.
    public static func compute(transfers: [Transfer], tier: VerificationTier, rates: any RateProvider,
                               now: Date, calendar: Calendar) -> LimitUsage {
        let counted = transfers.filter { $0.status != .cancelled && $0.status != .refunded }
        func usd(_ transfer: Transfer) -> Decimal {
            let rate = rates.midMarketRate(from: transfer.quote.source, to: .USD) ?? 0
            return transfer.quote.sendAmount.amount * rate
        }
        let dayAgo = now.addingTimeInterval(-86_400)
        let today = counted.filter { $0.createdAt > dayAgo && $0.createdAt <= now }.map(usd).reduce(0, +)
        let month = counted.filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .map(usd).reduce(0, +)
        return LimitUsage(usedTodayUSD: today.rounded(scale: 2, mode: .plain),
                          usedThisMonthUSD: month.rounded(scale: 2, mode: .plain), tier: tier)
    }
}
