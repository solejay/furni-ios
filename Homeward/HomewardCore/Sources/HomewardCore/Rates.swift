import Foundation

/// Source of mid-market ("real") exchange rates.
public protocol RateProvider: Sendable {
    /// Units of `target` per one unit of `source`, or nil if the pair isn't available.
    func midMarketRate(from source: Currency, to target: Currency) -> Decimal?
}

/// Rates expressed against USD and crossed for every other pair.
public struct USDCrossRates: RateProvider, Codable, Hashable {
    /// Units of each currency per 1 USD.
    public var perUSD: [Currency: Decimal]
    public var asOf: Date

    public init(perUSD: [Currency: Decimal], asOf: Date) {
        self.perUSD = perUSD
        self.perUSD[.USD] = 1
        self.asOf = asOf
    }

    public func midMarketRate(from source: Currency, to target: Currency) -> Decimal? {
        if source == target { return 1 }
        guard let s = perUSD[source], let t = perUSD[target], s > 0 else { return nil }
        // Keep 8 significant decimals: plenty for display and conversion, and stable to compare.
        return (t / s).rounded(scale: 8, mode: .plain)
    }

    /// Illustrative sample rates for the demo. Not live market data.
    public static func sample(asOf: Date = Date()) -> USDCrossRates {
        USDCrossRates(perUSD: [
            .GBP: Decimal(string: "0.7450")!,
            .EUR: Decimal(string: "0.8560")!,
            .CAD: Decimal(string: "1.3850")!,
            .NGN: Decimal(string: "1532.40")!,
            .GHS: Decimal(string: "12.05")!,
            .KES: Decimal(string: "129.20")!,
            .INR: Decimal(string: "87.95")!,
        ], asOf: asOf)
    }

    /// The same rates with every payout currency nudged by a factor (used to simulate live movement).
    public func nudged(by factors: [Currency: Double], asOf: Date) -> USDCrossRates {
        var next = perUSD
        for (currency, factor) in factors {
            guard let value = next[currency] else { continue }
            next[currency] = (value * Decimal(factor)).rounded(scale: 6, mode: .plain)
        }
        return USDCrossRates(perUSD: next, asOf: asOf)
    }
}

/// Deterministic pseudo-random rate history for charts and "is now a good time?" insights.
public enum RateHistory {
    public struct Point: Hashable, Sendable, Identifiable {
        public let date: Date
        public let rate: Decimal
        public var id: Date { date }
    }

    /// `days` daily points ending at `end` and finishing exactly at `current`.
    public static func sample(current: Decimal, days: Int, endingAt end: Date, seed: UInt64) -> [Point] {
        guard days > 0 else { return [] }
        var generator = SplitMix64(seed: seed)
        var walk: [Double] = [0]
        for _ in 1..<days {
            // Up to ±0.6% per day.
            let step = (Double(generator.next() % 1_201) - 600) / 100_000
            walk.append(walk.last! + step)
        }
        // Anchor the last point at today's rate.
        let offset = walk.last!
        let base = current.doubleValue
        return walk.enumerated().map { index, value in
            let date = end.addingTimeInterval(-Double(days - 1 - index) * 86_400)
            let rate = Decimal(base * (1 + value - offset)).rounded(scale: 4, mode: .plain)
            return Point(date: date, rate: index == days - 1 ? current : rate)
        }
    }

    public struct Insight: Hashable, Sendable {
        public let average: Decimal
        public let high: Decimal
        public let low: Decimal
        /// Current rate relative to the period average: +0.012 means 1.2% better than average.
        public let versusAverage: Decimal
    }

    public static func insight(for points: [Point]) -> Insight? {
        guard let current = points.last?.rate, !points.isEmpty else { return nil }
        let rates = points.map(\.rate)
        let total = rates.reduce(Decimal(0), +)
        let average = total / Decimal(rates.count)
        guard average > 0 else { return nil }
        return Insight(
            average: average.rounded(scale: 4, mode: .plain),
            high: rates.max()!,
            low: rates.min()!,
            versusAverage: ((current - average) / average).rounded(scale: 4, mode: .plain)
        )
    }
}

/// Small deterministic PRNG so sample data is identical across launches and platforms.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
