import SwiftUI
import HomewardCore

struct RateAlertsView: View {
    @Environment(AppStore.self) private var store
    var prefillSource: Currency?
    var prefillTarget: Currency?
    @State private var adding = false

    var body: some View {
        @Bindable var store = store
        List {
            if store.ledger.alerts.isEmpty {
                ContentUnavailableView("No rate alerts", systemImage: "bell.slash",
                                       description: Text("Get a notification when the rate hits your target."))
            }
            ForEach($store.ledger.alerts) { $alert in
                let current = store.midRate(alert.source, alert.target)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $alert.isActive) {
                        Text(alert.summary).font(.body.weight(.medium).monospacedDigit())
                    }
                    let distance = alert.targetRate > 0 ? (current - alert.targetRate) / alert.targetRate : 0
                    HStack {
                        Text("Now \(MoneyFormatter.rate(current))").monospacedDigit()
                        Text("·")
                        Text(alert.isMet(by: current)
                             ? "Target reached"
                             : "\(MoneyFormatter.percent(abs(distance), fractionDigits: 1)) to go")
                    }
                    .font(.caption)
                    .foregroundStyle(alert.isMet(by: current) ? Color.green : Color.secondary)
                    if let last = alert.lastTriggeredAt {
                        Text("Last alerted \(last.dayAndTime)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { store.ledger.alerts.remove(atOffsets: $0) }
        }
        .navigationTitle("Rate alerts")
        .toolbar {
            Button { adding = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("New alert")
        }
        .sheet(isPresented: $adding) {
            NewAlertSheet(source: prefillSource ?? store.ledger.profile.homeCurrency,
                          target: prefillTarget ?? store.ledger.profile.favouriteTarget)
        }
        .onAppear { if prefillTarget != nil && !store.ledger.alerts.contains(where: { $0.target == prefillTarget }) { adding = true } }
    }
}

private struct NewAlertSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var source: Currency
    @State var target: Currency
    @State private var rateText = ""
    @State private var direction: RateAlert.Direction = .atOrAbove

    var body: some View {
        let current = store.midRate(source, target)
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $source) {
                        ForEach(Currency.sendCurrencies) { Text("\($0.flag) \($0.code)").tag($0) }
                    }
                    Picker("To", selection: $target) {
                        ForEach(Currency.receiveCurrencies) { Text("\($0.flag) \($0.code)").tag($0) }
                    }
                }
                Section {
                    Picker("Alert me when the rate is", selection: $direction) {
                        Text("At or above").tag(RateAlert.Direction.atOrAbove)
                        Text("At or below").tag(RateAlert.Direction.atOrBelow)
                    }
                    TextField("Target rate", text: $rateText).keyboardType(.decimalPad).monospacedDigit()
                } footer: {
                    Text("1 \(source.code) is \(MoneyFormatter.rate(current)) \(target.code) right now (mid-market).")
                }
                Section {
                    HStack {
                        ForEach([1.0, 2.0, 3.0], id: \.self) { percent in
                            Button("+\(Int(percent))%") {
                                rateText = MoneyFormatter.string(from: current * Decimal(1 + percent / 100), fractionDigits: 2)
                                direction = .atOrAbove
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("New rate alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let rate = Decimal(userInput: rateText) else { return }
                        store.ledger.alerts.append(RateAlert(source: source, target: target, targetRate: rate, direction: direction))
                        dismiss()
                    }
                    .disabled((Decimal(userInput: rateText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if rateText.isEmpty {
                    rateText = MoneyFormatter.string(from: current * Decimal(string: "1.01")!, fractionDigits: 2)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ScheduledTransfersView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List {
            if store.ledger.scheduled.isEmpty {
                ContentUnavailableView("Nothing scheduled", systemImage: "calendar",
                                       description: Text("Turn on “Repeat monthly” when you send to set one up."))
            }
            ForEach($store.ledger.scheduled) { $scheduled in
                let recipient = store.recipient(id: scheduled.recipientID)
                let nextDates = scheduled.isPaused ? [] : scheduled.schedule.nextDates(after: Date(), count: 3, calendar: store.calendar)
                let estimate = try? store.engine.quote(sending: scheduled.sendAmount, to: scheduled.target)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let recipient { RecipientAvatar(recipient: recipient, size: 36) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scheduled.title).font(.body.weight(.semibold))
                            Text("\(scheduled.sendAmount.formattedCompact) to \(recipient?.fullName ?? "deleted recipient") · \(scheduled.schedule.frequency.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let estimate {
                        Text("≈ \(estimate.receiveAmount.formattedCompact) at today's rate")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !nextDates.isEmpty {
                        Text("Next: " + nextDates.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", "))
                            .font(.caption)
                    }
                    HStack {
                        Toggle("Paused", isOn: $scheduled.isPaused).font(.subheadline)
                    }
                    if let recipient {
                        Button("Send now instead") {
                            store.sendRequest = SendRequest(recipient: recipient, amount: scheduled.sendAmount, target: scheduled.target)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { store.ledger.scheduled.remove(atOffsets: $0) }
        }
        .navigationTitle("Scheduled")
    }
}
