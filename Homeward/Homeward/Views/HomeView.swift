import SwiftUI
import HomewardCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    let selectTab: (RootView.Tab) -> Void
    @State private var showingTopUp = false
    @State private var showingYear = false

    private var profile: Ledger.Profile { store.ledger.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    BalanceHero(showTopUp: { showingTopUp = true })

                    LiveRateCard(source: profile.homeCurrency, initialTarget: profile.favouriteTarget)

                    if !store.inFlightTransfers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "On the way")
                            ForEach(store.inFlightTransfers) { transfer in
                                NavigationLink {
                                    TransferDetailView(transferID: transfer.id)
                                } label: {
                                    InFlightCard(transfer: transfer)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    QuickSendRow()

                    ForEach(store.ledger.pots.filter { !$0.isPaidOut }) { pot in
                        NavigationLink {
                            FamilyPotView(potID: pot.id)
                        } label: {
                            PotCard(pot: pot, recipient: store.recipient(id: pot.recipientID))
                        }
                        .buttonStyle(.plain)
                    }

                    YearHomeCard { showingYear = true }

                    UpcomingScheduledCard()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Recent activity", action: ("See all", { selectTab(.activity) }))
                        VStack(spacing: 0) {
                            ForEach(store.ledger.transfers.prefix(4)) { transfer in
                                NavigationLink {
                                    TransferDetailView(transferID: transfer.id)
                                } label: {
                                    TransferRow(transfer: transfer)
                                }
                                .buttonStyle(.plain)
                                if transfer.id != store.ledger.transfers.prefix(4).last?.id { Divider().padding(.leading, 56) }
                            }
                        }
                        .card()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hi, \(profile.firstName)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        RateAlertsView()
                    } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Rate alerts")
                }
            }
            .sheet(isPresented: $showingTopUp) { TopUpView() }
            .fullScreenCover(isPresented: $showingYear) { YearHomeView() }
        }
    }
}

private struct BalanceHero: View {
    @Environment(AppStore.self) private var store
    let showTopUp: () -> Void
    @State private var selected: Currency = .GBP

    var body: some View {
        let wallet = store.ledger.wallet
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Balance").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Picker("Currency", selection: $selected) {
                    ForEach(wallet.displayCurrencies) { currency in
                        Text("\(currency.flag) \(currency.code)").tag(currency)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
            Text(wallet.balance(selected).formatted)
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 150)
            HStack(spacing: 12) {
                Button {
                    store.sendRequest = SendRequest()
                } label: {
                    Label("Send home", systemImage: "airplane")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.sun, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Button(action: showTopUp) {
                    Label("Add", systemImage: "plus")
                        .font(.headline)
                        .frame(minWidth: 96, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(minHeight: 340, alignment: .top)
        .background {
            ZStack {
                Theme.night
                RouteMapView(origin: Place.origin(for: store.ledger.profile.homeCurrency),
                             destinations: Array(Set(store.ledger.recipients.map { Place.destination(for: $0.country) })).sorted { $0.code < $1.code },
                             inFlight: Dictionary(store.inFlightTransfers.map { (Place.destination(for: $0.recipient.country).code, $0.status.progress) },
                                                  uniquingKeysWith: max))
                    .padding(.top, 90)
                    .padding(.bottom, 70)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onAppear { selected = store.ledger.profile.homeCurrency }
    }
}

private struct QuickSendRow: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Send again")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(store.ledger.recentRecipients) { recipient in
                        Button {
                            store.sendRequest = SendRequest(recipient: recipient, target: recipient.currency)
                        } label: {
                            VStack(spacing: 6) {
                                RecipientAvatar(recipient: recipient, size: 56)
                                Text(recipient.nickname ?? recipient.fullName.components(separatedBy: " ").first ?? "")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Send to \(recipient.fullName)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct UpcomingScheduledCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let now = Date()
        let upcoming = store.ledger.scheduled
            .compactMap { scheduled in scheduled.nextRun(after: now, calendar: store.calendar).map { (scheduled, $0) } }
            .sorted { $0.1 < $1.1 }
        if let next = upcoming.first, let recipient = store.recipient(id: next.0.recipientID) {
            let scheduled = next.0
            let date = next.1
            NavigationLink {
                ScheduledTransfersView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 44, height: 44)
                        .background(Theme.brand.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scheduled.title).font(.subheadline.weight(.semibold))
                        Text("\(scheduled.sendAmount.formattedCompact) to \(recipient.fullName) · \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

struct TopUpView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var currency: Currency = .GBP
    @State private var amountText = "100"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.sendCurrencies) { Text("\($0.flag) \($0.code)").tag($0) }
                    }
                    HStack {
                        Text(currency.symbol).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("Demo: funds arrive instantly. In production this would show your unique account details for an instant bank transfer, or take a debit card.")
                }
            }
            .navigationTitle("Add money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount = Decimal(userInput: amountText), amount > 0 {
                            store.topUp(Money(amount, currency))
                        }
                        dismiss()
                    }
                    .disabled((Decimal(userInput: amountText) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { currency = store.ledger.profile.homeCurrency }
    }
}
