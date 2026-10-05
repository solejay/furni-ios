import SwiftUI
import HomewardCore

/// The tracker: where the money is, when it'll land, and what you can do about it.
struct TransferDetailView: View {
    @Environment(AppStore.self) private var store
    let transferID: UUID
    var isConfirmation = false

    @State private var confirmingCancel = false
    @State private var showingHelp = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var showingPostcard = false

    var body: some View {
        if let transfer = store.transfer(id: transferID) {
            content(transfer)
        } else {
            ContentUnavailableView("Transfer not found", systemImage: "questionmark.circle")
        }
    }

    private func content(_ transfer: Transfer) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                TransferReceiptView(model: ReceiptModel(transfer: transfer))
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    if transfer.isDelayed(at: context.date) {
                        Label {
                            Text("Taking longer than usual. We're on it and will notify you the moment it lands. You don't need to do anything, and if it can't be delivered you'll be refunded automatically.")
                        } icon: {
                            Image(systemName: "clock.badge.exclamationmark")
                        }
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .card()
                    }
                }
                trackingTimeline(transfer)
                details(transfer)
                actions(transfer)
            }
            .padding()
            .animation(.snappy, value: transfer.status)
        }
        .background(AtmosphereBackground())
        .navigationTitle(isConfirmation ? "Sent" : "Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Cancel this transfer?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel transfer", role: .destructive) {
                do { try store.cancel(transfer) } catch { errorMessage = error.localizedDescription }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(transfer.status == .awaitingFunding
                 ? "Nothing has been charged yet."
                 : "\(transfer.quote.sendAmount.formatted) will be refunded to your \(transfer.fundingSource.inlineTitle) right away.")
        }
        .sheet(isPresented: $showingHelp) { HelpSheet(transfer: transfer) }
        .sheet(isPresented: $showingPostcard) { PostcardSheet(transfer: transfer) }
        .sensoryFeedback(.success, trigger: transfer.status == .delivered)
    }

    private func trackingTimeline(_ transfer: Transfer) -> some View {
        let steps = transfer.trackingSteps
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        stepIcon(step.state)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.state == .done ? Theme.brand : Color(.separator))
                                .frame(width: 2)
                                .frame(minHeight: 30)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(step.title)
                                .font(.subheadline.weight(step.state == .upcoming ? .regular : .semibold))
                                .foregroundStyle(step.state == .upcoming ? Color.secondary : Color.primary)
                            Spacer()
                            if let date = step.date {
                                Text(date.shortTime).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        if let detail = step.detail, step.state != .upcoming {
                            Text(detail).font(.caption).foregroundStyle(step.state == .problem ? Color.orange : Color.secondary)
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func stepIcon(_ state: TrackingStep.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand).font(.title3)
        case .current:
            ProgressView().controlSize(.small).frame(width: 22, height: 22)
        case .upcoming:
            Image(systemName: "circle").foregroundStyle(Color(.separator)).font(.title3)
        case .problem:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.title3)
        }
    }

    private func details(_ transfer: Transfer) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Reference").foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = transfer.reference
                    copied = true
                } label: {
                    Label(transfer.reference, systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.monospaced())
                }
            }
            detailRow("You sent", transfer.quote.sendAmount.formatted)
            detailRow("Fee", transfer.quote.fee.isZero ? "Free" : transfer.quote.fee.formatted)
            detailRow("Rate", "1 \(transfer.quote.source.code) = \(MoneyFormatter.rate(transfer.quote.customerRate)) \(transfer.quote.target.code)")
            detailRow("They receive", transfer.quote.receiveAmount.formatted)
            detailRow("Paid with", transfer.fundingSource.title)
            detailRow("To", transfer.recipient.payout.summary)
            detailRow("Reason", transfer.purpose.title)
            if let message = transfer.message { detailRow("Message", "“\(message)”") }
            if let payout = transfer.payoutReference { detailRow("Payout reference", payout) }
        }
        .font(.subheadline)
        .card()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).monospacedDigit()
        }
    }

    private func actions(_ transfer: Transfer) -> some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.orange)
            }
            if transfer.status == .delivered {
                Button {
                    showingPostcard = true
                } label: {
                    Label("Send \(transfer.recipient.fullName.components(separatedBy: " ").first ?? "them") a postcard", systemImage: "envelope.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                ShareLink(item: Self.receipt(for: transfer), subject: Text("Transfer receipt \(transfer.reference)")) {
                    Label("Share receipt", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if transfer.canCancel {
                Button(role: .destructive) {
                    confirmingCancel = true
                } label: {
                    Text("Cancel transfer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if !isConfirmation {
                Button {
                    store.sendRequest = SendRequest(recipient: store.recipient(id: transfer.recipient.id) ?? transfer.recipient,
                                                    amount: transfer.quote.sendAmount, target: transfer.quote.target)
                } label: {
                    Label("Send again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Button {
                showingHelp = true
            } label: {
                Label("Get help with this transfer", systemImage: "questionmark.bubble")
            }
            .font(.subheadline)
            .padding(.top, 4)
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval < 3600 ? [.minute, .second] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }

    static func receipt(for transfer: Transfer) -> String {
        """
        Homeward transfer receipt
        Reference: \(transfer.reference)
        Sent: \(transfer.quote.sendAmount.formatted) on \(transfer.createdAt.dayAndTime)
        Fee: \(transfer.quote.fee.formatted)
        Rate: 1 \(transfer.quote.source.code) = \(MoneyFormatter.rate(transfer.quote.customerRate)) \(transfer.quote.target.code)
        Delivered: \(transfer.quote.receiveAmount.formatted) to \(transfer.recipient.fullName) (\(transfer.recipient.payout.summary))
        \(transfer.payoutReference.map { "Payout reference: \($0)" } ?? "")
        """
    }
}

/// Help that already knows which transfer you mean: no "please send your reference number".
private struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let transfer: Transfer

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Reference", value: transfer.reference)
                    LabeledContent("Status", value: transfer.status.title)
                    LabeledContent("Expected", value: transfer.estimatedDelivery.dayAndTime)
                } header: {
                    Text("We'll attach these details")
                }
                Section("Common questions") {
                    DisclosureGroup("My transfer says delivered but they haven't got it") {
                        Text("Bank apps can take a few minutes to show incoming money. Share the payout reference \(transfer.payoutReference ?? "(shown once delivered)") with the recipient; their bank can trace it instantly.")
                            .font(.footnote)
                    }
                    DisclosureGroup("Can I change the recipient's details?") {
                        Text(transfer.canCancel
                             ? "Cancel this transfer for free and send a new one. Any payment already made is refunded right away."
                             : "The money is already with the payout partner. If the details were wrong it will bounce back and you'll be refunded automatically.")
                            .font(.footnote)
                    }
                    DisclosureGroup("Why was my rate different from Google?") {
                        Text("Google shows the mid-market rate. We add a \(MoneyFormatter.percent(transfer.quote.marginRate)) margin, and every quote shows it before you send.")
                            .font(.footnote)
                    }
                }
                Section {
                    Button {
                        dismiss()
                    } label: {
                        Label("Chat with a person: average reply under 2 minutes", systemImage: "message.fill")
                    }
                } footer: {
                    Text("Demo: chat is not connected in this build.")
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
