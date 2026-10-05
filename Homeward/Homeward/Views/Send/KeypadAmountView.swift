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
                    .glassSurface(cornerRadius: 99)
                }
                .accessibilityLabel("Sending to \(recipient.fullName). Tap to change.")
            }

            HStack(spacing: 0) {
                entryButton("You send", .send)
                entryButton("They get", .receive)
            }
            .padding(3)
            .glassSurface(cornerRadius: 99)

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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { key in
                    Button { press(key) } label: {
                        Group {
                            if key == "⌫" { Image(systemName: "delete.left") } else { Text(key) }
                        }
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyStyle())
                    .accessibilityLabel(key == "⌫" ? "Delete" : key == "." ? "Decimal point" : key)
                }
            }

            Button {
                if draft.quote == nil || limitMessage != nil { shakes += 1 } else { onContinue() }
            } label: {
                Label(draft.recipient == nil ? "Choose who" : "Review", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.sun, in: Capsule())
                    .shadow(color: Theme.sun.opacity(0.3), radius: 14, y: 8)
            }
            .opacity(draft.quote == nil || limitMessage != nil ? 0.4 : 1)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background {
            ZStack {
                AtmosphereBackground()
                RadialGradient(colors: [Theme.sun.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 220)
                    .ignoresSafeArea()
            }
        }
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
            draft.entry = entry
            draft.recalculate(with: store.engine)
        } label: {
            Text(title)
                .font(.footnote.weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(draft.entry == entry ? Color(.systemBackground) : Color.secondary)
                .background(draft.entry == entry ? Color.primary : Color.clear, in: Capsule())
        }
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
                .glassSurface(cornerRadius: 99)
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

/// Molded key: lighter top, darker bottom, a bright top edge, and an inset "pressed" state.
private struct KeyStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        let pressed = configuration.isPressed
        let top = dark ? Color(red: 0.11, green: 0.12, blue: 0.25) : Color(red: 0.99, green: 0.99, blue: 0.98)
        let bottom = dark ? Color(red: 0.07, green: 0.08, blue: 0.19) : Color(red: 0.91, green: 0.89, blue: 0.85)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return configuration.label
            .foregroundStyle(.primary)
            .background {
                shape.fill(LinearGradient(colors: pressed ? [bottom, top] : [top, bottom], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? (pressed ? 0.02 : 0.14) : 0.95), .black.opacity(dark ? 0.25 : 0.08)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: .black.opacity(pressed ? 0 : (dark ? 0.45 : 0.12)), radius: pressed ? 0 : 8, y: pressed ? 0 : 6)
            }
            .offset(y: pressed ? 1 : 0)
            .animation(.snappy(duration: 0.12), value: pressed)
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
