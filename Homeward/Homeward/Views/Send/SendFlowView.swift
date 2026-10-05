import SwiftUI
import HomewardCore

enum SendStep: Hashable {
    case recipient
    case addRecipient
    case review
    case tracking(UUID)
}

struct SendFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: SendRequest
    @State private var draft: SendDraft?
    @State private var path: [SendStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let draft {
                    AmountStepView(draft: draft) {
                        if draft.recipient == nil {
                            path.append(.recipient)
                        } else {
                            draft.lockQuote(with: store.engine)
                            path.append(.review)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .navigationDestination(for: SendStep.self) { step in
                if let draft {
                    switch step {
                    case .recipient:
                        RecipientStepView(draft: draft, path: $path)
                    case .addRecipient:
                        AddRecipientView(fixedCountry: Country(currency: draft.target)) { recipient in
                            store.save(recipient)
                            draft.recipient = recipient
                            draft.lockQuote(with: store.engine)
                            path.append(.review)
                        }
                    case .review:
                        ReviewStepView(draft: draft) { transfer in
                            path.append(.tracking(transfer.id))
                        }
                    case let .tracking(id):
                        TransferDetailView(transferID: id, isConfirmation: true)
                            .navigationBarBackButtonHidden()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                            }
                    }
                }
            }
        }
        .onAppear {
            guard draft == nil else { return }
            let target = request.target ?? request.recipient?.currency ?? store.ledger.profile.favouriteTarget
            let new = SendDraft(source: request.amount?.currency ?? store.ledger.profile.homeCurrency, target: target)
            new.recipient = request.recipient
            new.sendText = request.amount.map(SendDraft.text) ?? ""
            new.recalculate(with: store.engine)
            draft = new
        }
        .interactiveDismissDisabled(!path.isEmpty && !isOnTracking)
    }

    private var isOnTracking: Bool {
        if case .tracking = path.last { return true }
        return false
    }
}

// MARK: - Amount

struct AmountStepView: View {
    @Environment(AppStore.self) private var store
    @Bindable var draft: SendDraft
    let onContinue: () -> Void
    @FocusState private var focus: SendDraft.Entry?
    @State private var showComparison = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let recipient = draft.recipient {
                    HStack(spacing: 10) {
                        RecipientAvatar(recipient: recipient, size: 36)
                        Text("To \(recipient.fullName)").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Change") { draft.recipient = nil }.font(.subheadline)
                    }
                    .card()
                }

                VStack(spacing: 0) {
                    amountRow(title: "You send", text: $draft.sendText, entry: .send,
                              currency: $draft.source, options: Currency.sendCurrencies)
                    Divider()
                    amountRow(title: draft.recipient.map { "\($0.fullName.components(separatedBy: " ").first ?? "") gets" } ?? "They get",
                              text: $draft.receiveText, entry: .receive,
                              currency: $draft.target, options: Currency.receiveCurrencies)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let error = draft.quoteError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let quote = draft.quote {
                    PriceBreakdown(quote: quote, payout: draft.recipient?.payout)
                    ComparisonCard(quote: quote, expanded: $showComparison)
                    LimitHint(quote: quote)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: onContinue)
                .buttonStyle(.primary)
                .disabled(draft.quote == nil || limitBlocked)
                .padding()
                .background(.bar)
        }
        .navigationTitle("Send money")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.sendText) { if focus == .send { draft.entry = .send; draft.recalculate(with: store.engine) } }
        .onChange(of: draft.receiveText) { if focus == .receive { draft.entry = .receive; draft.recalculate(with: store.engine) } }
        .onChange(of: draft.source) { draft.recalculate(with: store.engine) }
        .onChange(of: draft.target) {
            if let recipient = draft.recipient, recipient.currency != draft.target { draft.recipient = nil }
            draft.recalculate(with: store.engine)
        }
        // Keep the live quote in step with the moving rate.
        .onChange(of: store.rates) { draft.recalculate(with: store.engine) }
        .onAppear { if draft.sendText.isEmpty && draft.receiveText.isEmpty { focus = .send } }
    }

    private var limitBlocked: Bool {
        guard let quote = draft.quote else { return false }
        return store.limitUsage.check(amountUSD: store.usd(quote.sendAmount)) != .allowed
    }

    private func amountRow(title: String, text: Binding<String>, entry: SendDraft.Entry,
                           currency: Binding<Currency>, options: [Currency]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .focused($focus, equals: entry)
                    .accessibilityLabel(title)
            }
            Menu {
                ForEach(options) { option in
                    Button("\(option.flag) \(option.code) · \(option.name)") { currency.wrappedValue = option }
                }
            } label: {
                HStack(spacing: 6) {
                    FlagBadge(currency: currency.wrappedValue, size: 28)
                    Text(currency.wrappedValue.code).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { focus = entry }
    }
}

/// Every number that affects what arrives, in plain language.
struct PriceBreakdown: View {
    let quote: Quote
    let payout: PayoutDetails?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Our fee", quote.fee.isZero ? "Free" : quote.fee.formatted,
                note: quote.fee.isZero ? "No fee on transfers this size" : nil)
            row("We convert", quote.amountConverted.formatted)
            row("Our rate", "1 \(quote.source.code) = \(MoneyFormatter.rate(quote.customerRate)) \(quote.target.code)")
            row("Mid-market rate", "\(MoneyFormatter.rate(quote.midMarketRate))",
                note: "The real rate you'd see on Google")
            row("Our margin", "\(MoneyFormatter.percent(quote.marginRate)) (\(quote.marginCost.formatted))")
            Divider()
            row("Total cost", "\(quote.totalCost.formatted) · \(MoneyFormatter.percent(quote.totalCostRate))", bold: true)
            if let payout {
                row("Arrives", DeliveryEstimate.for(payout, funding: .wallet).label)
            }
        }
        .font(.subheadline)
        .card()
    }

    private func row(_ title: String, _ value: String, note: String? = nil, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(bold ? Color.primary : Color.secondary)
                if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
            Text(value)
                .fontWeight(bold ? .semibold : .regular)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ComparisonCard: View {
    @Environment(AppStore.self) private var store
    let quote: Quote
    @Binding var expanded: Bool

    var body: some View {
        let comparisons = store.engine.compare(quote)
        if let best = comparisons.max(by: { $0.extraWithHomeward < $1.extraWithHomeward }), best.extraWithHomeward.isPositive {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "sparkles").foregroundStyle(Theme.sun)
                        Text("Up to **\(best.extraWithHomeward.formattedCompact)** more than a typical bank")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(comparisons) { comparison in
                        HStack {
                            Text(comparison.providerName).foregroundStyle(.secondary)
                            Spacer()
                            Text(comparison.receiveAmount.formattedCompact).monospacedDigit()
                        }
                        .font(.footnote)
                    }
                    HStack {
                        Text("Homeward").fontWeight(.semibold)
                        Spacer()
                        Text(quote.receiveAmount.formattedCompact).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.footnote)
                    Text("Illustrative comparison: a typical bank at a 3.5% margin plus a $15 fee, and a typical app at 1.8% plus $2.99. Not a quote from any named provider.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .card()
        }
    }
}

struct LimitHint: View {
    @Environment(AppStore.self) private var store
    let quote: Quote

    var body: some View {
        let usage = store.limitUsage
        switch usage.check(amountUSD: store.usd(quote.sendAmount)) {
        case .allowed:
            EmptyView()
        case let .exceedsDaily(remaining), let .exceedsMonthly(remaining):
            VStack(alignment: .leading, spacing: 6) {
                Label("This is over your \(usage.tier.title) limit", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.subheadline.weight(.semibold))
                Text("You can send about $\(MoneyFormatter.string(from: remaining, fractionDigits: 0)) more right now. \(usage.tier.next.map { "Upgrade to \($0.title) in Account: \($0.requirements.lowercased())." } ?? "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.orange)
            .card()
        }
    }
}
