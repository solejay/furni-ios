import SwiftUI
import HomewardCore

/// Full-bleed marigold amount entry with its own keypad. Type what you send or what they get;
/// the other side is worked out live.
struct KeypadAmountView: View {
    @Environment(AppStore.self) private var store
    @Bindable var draft: SendDraft
    let onContinue: () -> Void
    @State private var showingMaths = false
    @State private var shakes = 0
    @Namespace private var entryNamespace

    private var entryText: String {
        (draft.entry == .send ? draft.sendText : draft.receiveText).replacingOccurrences(of: ",", with: "")
    }

    private var entryCurrency: Currency { draft.entry == .send ? draft.source : draft.target }

    private var displayed: String {
        let raw = entryText
        guard !raw.isEmpty else { return "0" }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts[0]).map { MoneyFormatter.string(from: Decimal($0), fractionDigits: 0) } ?? "0"
        return parts.count > 1 ? whole + "." + parts[1] : whole
    }

    private var limitMessage: String? {
        guard let quote = draft.quote else { return nil }
        switch store.limitUsage.check(amountUSD: store.usd(quote.sendAmount)) {
        case .allowed: return nil
        case let .exceedsDaily(remaining): return "Over today's limit. About $\(MoneyFormatter.string(from: remaining, fractionDigits: 0)) left."
        case let .exceedsMonthly(remaining): return "Over this month's limit. About $\(MoneyFormatter.string(from: remaining, fractionDigits: 0)) left."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            StepsHeader(current: 1)
            if let recipient = draft.recipient {
                Button { draft.recipient = nil } label: {
                    HStack(spacing: 8) {
                        RecipientAvatar(recipient: recipient, size: 28)
                        Text("To \(recipient.nickname ?? recipient.fullName)")
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                    .liquidGlass(Capsule(), interactive: true)
                }
                .accessibilityLabel("Sending to \(recipient.fullName). Tap to change.")
            }

            // The selected side wears tinted glass that morphs across when you switch.
            LiquidGlassGroup(spacing: 12) {
                HStack(spacing: 4) {
                    entryButton("You send", .send)
                    entryButton("They get", .receive)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(entryCurrency.symbol).font(.system(size: 34, weight: .bold, design: .rounded)).opacity(0.7)
                Text(displayed)
                    .font(.system(size: displayed.count <= 4 ? 90 : displayed.count <= 7 ? 70 : 52, weight: .light))
                    .tracking(-3)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .modifier(Shake(animatableData: CGFloat(shakes)))
            .animation(.snappy(duration: 0.2), value: displayed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entryCurrency.name) \(displayed)")

            Group {
                if let quote = draft.quote {
                    if draft.entry == .send {
                        Text("\(draft.recipient.map { $0.nickname ?? $0.fullName.components(separatedBy: " ").first ?? "" } ?? "They") get **\(quote.receiveAmount.formatted)**")
                    } else {
                        Text("You pay **\(quote.sendAmount.formatted)**")
                    }
                } else {
                    Text(" ")
                }
            }
            .font(.headline)
            .monospacedDigit()

            HStack(spacing: 8) {
                currencyMenu(selection: $draft.source, options: Currency.sendCurrencies)
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).opacity(0.6)
                currencyMenu(selection: $draft.target, options: Currency.receiveCurrencies)
            }

            if let error = draft.quoteError ?? limitMessage {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(Theme.coral)
                    .background(Theme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            } else if let quote = draft.quote {
                Button("1 \(quote.source.code) = \(MoneyFormatter.rate(quote.customerRate)) \(quote.target.code) · \(quote.fee.isZero ? "no fee" : "fee \(quote.fee.formatted)") · Show the maths") {
                    showingMaths = true
                }
                .font(.footnote.weight(.semibold))
                .underline()
            } else {
                Text("Mid-market \(MoneyFormatter.rate(store.midRate(draft.source, draft.target))) · our margin \(MoneyFormatter.percent(store.engine.policy.marginRate))")
                    .font(.footnote)
                    .opacity(0.7)
            }

            Spacer(minLength: 0)

            LiquidGlassGroup(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { key in
                    Button { press(key) } label: {
                        Group {
                            if key == "⌫" { Image(systemName: "delete.left") } else { Text(key) }
                        }
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .contentShape(Rectangle())
                        .liquidGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "⌫" ? "Delete" : key == "." ? "Decimal point" : key)
                }
            }
            }

            Button {
                if draft.quote == nil || limitMessage != nil { shakes += 1 } else { onContinue() }
            } label: {
                Label(draft.recipient == nil ? "Choose who" : "Review", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Theme.ink)
            }
            .liquidGlassButton(prominent: true)
            .tint(Theme.sun)
            .controlSize(.large)
            .opacity(draft.quote == nil || limitMessage != nil ? 0.4 : 1)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(AtmosphereBackground())
        .tint(Theme.brand)
        .navigationTitle("Send home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: draft.source) { draft.recalculate(with: store.engine) }
        .onChange(of: draft.target) {
            if let recipient = draft.recipient, recipient.currency != draft.target { draft.recipient = nil }
            draft.recalculate(with: store.engine)
        }
        .onChange(of: store.rates) { draft.recalculate(with: store.engine) }
        .sheet(isPresented: $showingMaths) {
            if let quote = draft.quote { MathsSheet(quote: quote, payout: draft.recipient?.payout) }
        }
        .sensoryFeedback(.error, trigger: shakes)
    }

    private func entryButton(_ title: String, _ entry: SendDraft.Entry) -> some View {
        Button {
            guard draft.entry != entry else { return }
            // Carry the worked-out amount over so switching sides doesn't lose it.
            if entry == .receive { draft.receiveText = draft.receiveText.replacingOccurrences(of: ",", with: "") }
            else { draft.sendText = draft.sendText.replacingOccurrences(of: ",", with: "") }
            withAnimation(.bouncy) { draft.entry = entry }
            draft.recalculate(with: store.engine)
        } label: {
            if draft.entry == entry {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(.primary)
                    .liquidGlass(Capsule(), interactive: true)
                    .liquidGlassID("entry", in: entryNamespace)
            } else {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.entry == entry ? .isSelected : [])
    }

    private func currencyMenu(selection: Binding<Currency>, options: [Currency]) -> some View {
        Menu {
            ForEach(options) { option in
                Button("\(option.flag) \(option.code) · \(option.name)") { selection.wrappedValue = option }
            }
        } label: {
            Text("\(selection.wrappedValue.flag) \(selection.wrappedValue.code)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(.primary)
                .liquidGlass(Capsule(), interactive: true)
        }
    }

    private func press(_ key: String) {
        var value = entryText
        switch key {
        case "⌫":
            if !value.isEmpty { value.removeLast() }
        case ".":
            if !value.contains(".") { value = (value.isEmpty ? "0" : value) + "." }
        default:
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 1, parts[1].count >= 2 { shakes += 1; return }
            if parts.count == 1, parts[0].drop(while: { $0 == "0" }).count >= 7 { shakes += 1; return }
            value = value == "0" ? key : value + key
        }
        if draft.entry == .send { draft.sendText = value } else { draft.receiveText = value }
        draft.recalculate(with: store.engine)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

/// Horizontal shake for rejected input.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// The full breakdown plus a bar comparison with typical providers.
struct MathsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let quote: Quote
    let payout: PayoutDetails?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PriceBreakdown(quote: quote, payout: payout)
                    Text("SAME \(quote.sendAmount.formattedCompact), ELSEWHERE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary)
                    let rows = [("Homeward", quote.receiveAmount, true)] + store.engine.compare(quote).map { ($0.providerName, $0.receiveAmount, false) }
                    let top = rows.map { $0.1.amount.doubleValue }.max() ?? 1
                    ForEach(rows, id: \.0) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.0).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(row.1.formattedCompact).font(.subheadline.monospacedDigit())
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(row.2 ? AnyShapeStyle(Theme.sun) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                                    .frame(width: geo.size.width * row.1.amount.doubleValue / top)
                            }
                            .frame(height: 12)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                    Text("Illustrative: a typical bank at a 3.5% margin plus a $15 fee, and a typical app at 1.8% plus $2.99. Not quotes from named providers.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("The maths")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
