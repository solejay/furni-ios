import SwiftUI
import Charts
import HomewardCore

/// Live rate with 30-day context, so people can tell whether today is a good day to send.
struct LiveRateCard: View {
    @Environment(AppStore.self) private var store
    let source: Currency
    let initialTarget: Currency
    @State private var target: Currency?

    private var currentTarget: Currency { target ?? initialTarget }

    var body: some View {
        let mid = store.midRate(source, currentTarget)
        let customer = (try? store.engine.customerRate(from: source, to: currentTarget).customer) ?? mid
        let history = RateHistory.sample(current: mid, days: 30, endingAt: store.rates.asOf,
                                         seed: Self.seed(source, currentTarget))
        let insight = RateHistory.insight(for: history)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1 \(source.code) =").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(MoneyFormatter.rate(customer)) \(currentTarget.code)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText(value: customer.doubleValue))
                        .animation(.default, value: customer)
                    Text("Mid-market \(MoneyFormatter.rate(mid)) · our margin \(MoneyFormatter.percent(store.engine.policy.marginRate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(Currency.receiveCurrencies) { currency in
                        Button("\(currency.flag) \(currency.name)") { target = currency }
                    }
                } label: {
                    HStack(spacing: 4) {
                        FlagBadge(currency: currentTarget, size: 26)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .padding(6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .accessibilityLabel("Change currency, currently \(currentTarget.name)")
            }

            Chart(history) { point in
                AreaMark(x: .value("Day", point.date), y: .value("Rate", point.rate.doubleValue))
                    .foregroundStyle(LinearGradient(colors: [Theme.brand.opacity(0.25), Theme.brand.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Day", point.date), y: .value("Rate", point.rate.doubleValue))
                    .foregroundStyle(Theme.brand)
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: Self.domain(history))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 110)
            .accessibilityLabel("30-day rate chart")

            if let insight {
                HStack(spacing: 6) {
                    let better = insight.versusAverage >= 0
                    Image(systemName: better ? "arrow.up.right" : "arrow.down.right")
                    Text(better
                         ? "\(MoneyFormatter.percent(insight.versusAverage, fractionDigits: 1)) better than the 30-day average"
                         : "\(MoneyFormatter.percent(-insight.versusAverage, fractionDigits: 1)) below the 30-day average")
                    Spacer()
                    NavigationLink("Set alert") {
                        RateAlertsView(prefillSource: source, prefillTarget: currentTarget)
                    }
                    .font(.caption.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(insight.versusAverage >= 0 ? Color.green : Color.orange)
            }

            Text("Sample rates for demonstration · updated \(store.rates.asOf.shortTime)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .card()
    }

    static func seed(_ a: Currency, _ b: Currency) -> UInt64 {
        (a.code + b.code).unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }

    static func domain(_ points: [RateHistory.Point]) -> ClosedRange<Double> {
        let values = points.map(\.rate.doubleValue)
        guard let low = values.min(), let high = values.max(), high > low else { return 0...1 }
        let pad = (high - low) * 0.15
        return (low - pad)...(high + pad)
    }
}
