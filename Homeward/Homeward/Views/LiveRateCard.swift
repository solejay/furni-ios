import SwiftUI
import HomewardCore

/// Rate weather as a calibration dial: one tick per earlier day (low to high), lit when today beats it.
struct LiveRateCard: View {
    @Environment(AppStore.self) private var store
    let source: Currency
    let initialTarget: Currency
    @State private var target: Currency?

    private var currentTarget: Currency { target ?? initialTarget }

    var body: some View {
        let mid = store.midRate(source, currentTarget)
        let customer = (try? store.engine.customerRate(from: source, to: currentTarget).customer) ?? mid
        let history = RateHistory.sample(current: mid, days: 30, endingAt: store.rates.asOf, seed: Self.seed(source, currentTarget))
        let climate = RateClimate.from(history)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("02 · RATE WEATHER · \(source.code)→\(currentTarget.code)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(Currency.receiveCurrencies) { currency in
                        Button("\(currency.flag) \(currency.name)") { target = currency }
                    }
                } label: {
                    Text("\(currentTarget.code) ▾")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
                .accessibilityLabel("Change currency, currently \(currentTarget.name)")
            }

            HStack(alignment: .center, spacing: 16) {
                RateDial(points: history)
                VStack(alignment: .leading, spacing: 6) {
                    if let climate {
                        HStack(spacing: 8) {
                            Image(systemName: climate.condition.symbol).foregroundStyle(Theme.brand)
                            Text(Self.word(climate.condition))
                                .font(.system(size: 28, design: .serif).italic())
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(MoneyFormatter.rate(customer))
                            .font(.system(size: 22, weight: .medium).monospacedDigit())
                            .contentTransition(.numericText(value: customer.doubleValue))
                            .animation(.default, value: customer)
                        Text(currentTarget.code).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(climate?.detail ?? "") Mid-market \(MoneyFormatter.rate(mid)), our margin \(MoneyFormatter.percent(store.engine.policy.marginRate)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink("Alert me at a better rate") {
                        RateAlertsView(prefillSource: source, prefillTarget: currentTarget)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                }
            }

            Text("Measured against the past 30 days. Not a forecast. Sample rates.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .card()
    }

    static func word(_ condition: RateClimate.Condition) -> String {
        switch condition {
        case .sunny: return "Sunny"
        case .bright: return "Bright"
        case .mild: return "Mild"
        case .cloudy: return "Cloudy"
        case .overcast: return "Overcast"
        }
    }

    static func seed(_ a: Currency, _ b: Currency) -> UInt64 {
        (a.code + b.code).unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }
}

struct RateDial: View {
    let points: [RateHistory.Point]

    var body: some View {
        let today = points.last?.rate ?? 0
        let earlier = points.dropLast().map(\.rate).sorted()
        let beaten = earlier.filter { today > $0 }.count
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 12
            let start = -225.0, sweep = 270.0
            func point(_ degrees: Double, _ r: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
            }
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius * 0.68, y: center.y - radius * 0.68, width: radius * 1.36, height: radius * 1.36)),
                           with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            for (index, rate) in earlier.enumerated() {
                let degrees = start + sweep * Double(index) / Double(max(earlier.count - 1, 1))
                var tick = Path()
                tick.move(to: point(degrees, radius - 6))
                tick.addLine(to: point(degrees, radius + (index % 7 == 0 ? 4 : 0)))
                context.stroke(tick, with: .color(today > rate ? Theme.sun : Color.secondary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let needleDegrees = start + sweep * Double(beaten) / Double(max(earlier.count, 1))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: point(needleDegrees, radius - 16))
            context.stroke(needle, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(Theme.sun))
            context.draw(Text("\(beaten)/\(earlier.count) DAYS").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: center.x, y: center.y + 24))
        }
        .frame(width: 136, height: 136)
        .accessibilityElement()
        .accessibilityLabel("Today's rate beats \(beaten) of the last \(earlier.count) days")
    }
}
