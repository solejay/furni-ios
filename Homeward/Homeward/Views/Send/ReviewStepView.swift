import SwiftUI
import HomewardCore

struct ReviewStepView: View {
    @Environment(AppStore.self) private var store
    @Bindable var draft: SendDraft
    let onSent: (Transfer) -> Void

    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var sentCount = 0

    var body: some View {
        if let quote = draft.lockedQuote, let recipient = draft.recipient {
            content(quote: quote, recipient: recipient)
        } else {
            ContentUnavailableView("Nothing to review", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func content(quote: Quote, recipient: Recipient) -> some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    RecipientAvatar(recipient: recipient, size: 60)
                    Text(quote.receiveAmount.formatted)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    Text("to \(recipient.fullName)").font(.headline)
                    Text(recipient.payout.summary).font(.subheadline).foregroundStyle(.secondary)
                    if let verified = recipient.verifiedName {
                        Label("Account holder: \(verified)", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.brand)
                    }
                    RateLockCountdown(quote: quote).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Breakdown") {
                LabeledContent("You pay", value: quote.sendAmount.formatted)
                LabeledContent("Fee", value: quote.fee.isZero ? "Free" : quote.fee.formatted)
                LabeledContent("Rate", value: "1 \(quote.source.code) = \(MoneyFormatter.rate(quote.customerRate)) \(quote.target.code)")
                LabeledContent("Total cost incl. margin", value: "\(quote.totalCost.formatted) (\(MoneyFormatter.percent(quote.totalCostRate)))")
                LabeledContent("Arrives", value: DeliveryEstimate.for(recipient.payout, funding: draft.funding).label)
            }
            .monospacedDigit()

            Section("Pay with") {
                ForEach(FundingSource.allCases, id: \.self) { source in
                    let affordable = source != .wallet || store.ledger.wallet.canAfford(quote.sendAmount)
                    Button {
                        draft.funding = source
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title).foregroundStyle(.primary)
                                Text(source == .wallet
                                     ? "Balance \(store.ledger.wallet.balance(quote.source).formatted)\(affordable ? "" : " (not enough)")"
                                     : source.detail)
                                    .font(.caption)
                                    .foregroundStyle(affordable ? Color.secondary : Color.orange)
                            }
                            Spacer()
                            if draft.funding == source {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .disabled(!affordable)
                }
            }

            Section {
                Picker("Reason", selection: $draft.purpose) {
                    ForEach(TransferPurpose.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Message for \(recipient.fullName.components(separatedBy: " ").first ?? "them") (optional)", text: $draft.message)
                Toggle("Repeat monthly", isOn: $draft.repeatMonthly)
            } footer: {
                Text(draft.repeatMonthly
                     ? "We'll send \(quote.sendAmount.formattedCompact) on this day each month at that day's rate. Pause or cancel any time."
                     : "Cancel for free until the money reaches \(recipient.payout.summary). If anything goes wrong, you're refunded automatically.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let expired = quote.isExpired(at: context.date)
                Button {
                    if expired { refresh() } else { send(quote: quote, recipient: recipient) }
                } label: {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Text(expired ? "Get a new rate" : "Send \(quote.receiveAmount.formattedCompact)")
                    }
                }
                .buttonStyle(.primary)
                .disabled(isSending)
                .padding()
                .background(.bar)
            }
        }
        .sensoryFeedback(.success, trigger: sentCount)
        .onAppear {
            if draft.funding == .wallet && !store.ledger.wallet.canAfford(quote.sendAmount) {
                draft.funding = .bankTransfer
            }
        }
    }

    private func refresh() {
        errorMessage = nil
        draft.lockQuote(with: store.engine)
    }

    private func send(quote: Quote, recipient: Recipient) {
        isSending = true
        errorMessage = nil
        Task {
            // A short pause so the tap feels deliberate; real apps would await the API here.
            try? await Task.sleep(for: .milliseconds(600))
            do {
                let message = draft.message.trimmingCharacters(in: .whitespaces)
                let transfer = try store.send(quote: quote, to: recipient, funding: draft.funding, purpose: draft.purpose,
                                              message: message.isEmpty ? nil : message, repeatMonthly: draft.repeatMonthly)
                sentCount += 1
                onSent(transfer)
            } catch AppStore.ActionError.send(.quoteExpired) {
                refresh()
                errorMessage = Ledger.SendError.quoteExpired.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
