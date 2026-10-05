import SwiftUI
import HomewardCore

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var showingUpgrade = false
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var store = store
        let profile = store.ledger.profile
        let usage = store.limitUsage

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(String(profile.firstName.prefix(1)) + String(profile.lastName.prefix(1)))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Theme.hero, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(profile.firstName) \(profile.lastName)").font(.title3.weight(.semibold))
                            Label("\(profile.tier.title) account", systemImage: "checkmark.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.brand)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LimitBar(title: "Today", used: usage.usedTodayUSD, limit: profile.tier.dailyLimitUSD)
                    LimitBar(title: "This month", used: usage.usedThisMonthUSD, limit: profile.tier.monthlyLimitUSD)
                    if let next = profile.tier.next {
                        Button {
                            showingUpgrade = true
                        } label: {
                            Label("Raise limits to $\(MoneyFormatter.string(from: next.monthlyLimitUSD, fractionDigits: 0))/month", systemImage: "arrow.up.circle.fill")
                        }
                    }
                } header: {
                    Text("Sending limits")
                } footer: {
                    Text("Limits are shown in US dollars and reset on a rolling 24 hours and each calendar month. You'll always see them before you send, never halfway through a transfer.")
                }

                Section("Money tools") {
                    NavigationLink {
                        RateAlertsView()
                    } label: {
                        Label { Text("Rate alerts") } icon: { Image(systemName: "bell.badge") }
                            .badge(store.ledger.alerts.filter(\.isActive).count)
                    }
                    NavigationLink {
                        ScheduledTransfersView()
                    } label: {
                        Label { Text("Scheduled transfers") } icon: { Image(systemName: "calendar.badge.clock") }
                            .badge(store.ledger.scheduled.filter { !$0.isPaused }.count)
                    }
                }

                Section("Preferences") {
                    Picker("Send from", selection: $store.ledger.profile.homeCurrency) {
                        ForEach(Currency.sendCurrencies) { Text("\($0.flag) \($0.code)").tag($0) }
                    }
                    Picker("Usually send to", selection: $store.ledger.profile.favouriteTarget) {
                        ForEach(Currency.receiveCurrencies) { Text("\($0.flag) \($0.code)").tag($0) }
                    }
                    Toggle("Notifications", isOn: Binding(
                        get: { store.notificationsEnabled },
                        set: { enabled in
                            if enabled { Task { await store.requestNotifications() } } else { store.notificationsEnabled = false }
                        }))
                }

                Section("How Homeward works") {
                    InfoRow(symbol: "eye", title: "No hidden markup",
                            text: "Every quote shows the mid-market rate, our \(MoneyFormatter.percent(store.engine.policy.marginRate)) margin and the fee.")
                    InfoRow(symbol: "lock", title: "Your rate is locked",
                            text: "Rates are guaranteed for 30 minutes once you reach review.")
                    InfoRow(symbol: "person.text.rectangle", title: "Name check on every new account",
                            text: "We confirm who owns an account before you can send to it.")
                    InfoRow(symbol: "arrow.uturn.backward", title: "Automatic refunds",
                            text: "Cancel free until payout. Failed transfers are refunded without a support ticket.")
                }

                Section {
                    Button("Reset demo data", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("Homeward demo build. Rates are sample data and no real money moves.")
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showingUpgrade) { UpgradeSheet() }
            .confirmationDialog("Reset all demo data?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.resetDemo() }
            }
        }
    }
}

private struct LimitBar: View {
    let title: String
    let used: Decimal
    let limit: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("$\(MoneyFormatter.string(from: used, fractionDigits: 0)) of $\(MoneyFormatter.string(from: limit, fractionDigits: 0))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(used.doubleValue, limit.doubleValue), total: max(limit.doubleValue, 1))
                .tint(used >= limit ? .orange : Theme.brand)
        }
        .padding(.vertical, 2)
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.brand)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct UpgradeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        let current = store.ledger.profile.tier
        NavigationStack {
            List {
                ForEach(VerificationTier.allCases, id: \.self) { tier in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tier.title).font(.headline)
                            Text("$\(MoneyFormatter.string(from: tier.dailyLimitUSD, fractionDigits: 0))/day · $\(MoneyFormatter.string(from: tier.monthlyLimitUSD, fractionDigits: 0))/month")
                                .font(.subheadline.monospacedDigit())
                            Text(tier.requirements).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if tier == current {
                            Text("Current").font(.caption.weight(.semibold)).foregroundStyle(Theme.brand)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let next = current.next {
                    Button {
                        working = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            store.ledger.profile.tier = next
                            working = false
                            dismiss()
                        }
                    } label: {
                        if working { ProgressView().tint(.white) } else { Text("Upgrade to \(next.title)") }
                    }
                    .buttonStyle(.primary)
                    .padding()
                }
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
