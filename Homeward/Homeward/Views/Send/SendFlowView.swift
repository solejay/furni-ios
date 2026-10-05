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
                    KeypadAmountView(draft: draft) {
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
