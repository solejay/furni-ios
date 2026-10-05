import SwiftUI
import HomewardCore

/// Ring showing each family member's share of the pot.
struct PotRing: View {
    let pot: FamilyPot
    var lineWidth: CGFloat = 14

    static let colors: [Color] = [Theme.brand, Theme.sun, Color(red: 0.20, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.33, blue: 0.53), .purple]

    var body: some View {
        let shares = pot.shares
        let target = max(pot.target.amount.doubleValue, 1)
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            ForEach(Array(shares.enumerated()), id: \.element.member.id) { index, share in
                let start = shares.prefix(index).map { $0.added.amount.doubleValue }.reduce(0, +) / target
                let end = min(1, start + share.added.amount.doubleValue / target)
                Circle()
                    .trim(from: start, to: end)
                    .stroke(Self.colors[index % Self.colors.count], style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(duration: 0.8), value: pot.raised)
        .accessibilityElement()
        .accessibilityLabel("\(Int(pot.progress * 100)) percent raised")
    }
}

/// Compact card for Home.
struct PotCard: View {
    let pot: FamilyPot
    let recipient: Recipient?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                PotRing(pot: pot, lineWidth: 7)
                Text("\(Int(pot.progress * 100))%").font(.caption.weight(.bold).monospacedDigit())
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(pot.title).font(.subheadline.weight(.semibold))
                Text(pot.isPaidOut ? "Sent to \(recipient?.fullName ?? "family")"
                     : "\(pot.raised.formattedCompact) of \(pot.target.formattedCompact) · \(pot.members.count) of you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: -6) {
                    ForEach(pot.members) { member in
                        Text(String(member.name.prefix(1)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(PotRing.colors[(pot.shares.firstIndex { $0.member.id == member.id } ?? 0) % PotRing.colors.count]))
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .card()
    }
}

struct FamilyPotView: View {
    @Environment(AppStore.self) private var store
    let potID: UUID
    @State private var contributing = false
    @State private var confirmingPayout = false
    @State private var celebrate = 0

    var body: some View {
        if let pot = store.ledger.pots.first(where: { $0.id == potID }) {
            content(pot)
        } else {
            ContentUnavailableView("Pot not found", systemImage: "circle.dashed")
        }
    }

    private func content(_ pot: FamilyPot) -> some View {
        let recipient = store.recipient(id: pot.recipientID)
        let fees = pot.feesAvoidedUSD(policy: store.engine.policy, rates: store.rates)
        return ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 14) {
                    ZStack {
                        PotRing(pot: pot, lineWidth: 18)
                        VStack(spacing: 2) {
                            Text(pot.raised.formattedCompact)
                                .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text("of \(pot.target.formattedCompact)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(28)
                    }
                    .frame(width: 210, height: 210)
                    Text(pot.title).font(.title2.weight(.bold))
                    if let recipient {
                        Text("One payout to \(recipient.fullName) · \(recipient.payout.summary)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if pot.isPaidOut, let date = pot.paidOutAt {
                        Label("Sent \(date.dayAndTime) · ref \(pot.payoutReference ?? "")", systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.green)
                    } else if !pot.isFunded {
                        Text("\(pot.remaining.formattedCompact) to go").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                    }
                }
                .frame(maxWidth: .infinity)
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Who's in").font(.headline)
                    ForEach(Array(pot.shares.enumerated()), id: \.element.member.id) { index, share in
                        HStack(spacing: 12) {
                            Circle().fill(PotRing.colors[index % PotRing.colors.count]).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(share.member.isYou ? "You" : share.member.name).font(.subheadline.weight(.medium))
                                Text("\(share.member.city) · \(share.member.currency.flag) \(share.member.currency.code)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(share.added.isZero ? "Not yet" : share.added.formattedCompact)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(share.added.isZero ? Color.secondary : Color.primary)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Activity").font(.headline)
                    ForEach(pot.contributions.reversed()) { contribution in
                        let member = pot.members.first { $0.id == contribution.memberID }
                        HStack {
                            Text("\(member?.isYou == true ? "You" : member?.name ?? "Someone") added \(contribution.sent.formattedCompact)")
                            Spacer()
                            Text("+\(contribution.added.formattedCompact)").monospacedDigit().foregroundStyle(.green)
                        }
                        .font(.footnote)
                    }
                    if fees > 0 {
                        Label("Pooling avoids about $\(MoneyFormatter.string(from: fees, fractionDigits: 2)) in separate transfer fees, and \(recipient.map { $0.fullName.components(separatedBy: " ").first ?? "" } ?? "the family") gets one payment instead of \(pot.contributions.count).",
                              systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Family pot")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !pot.isPaidOut {
                Group {
                    if pot.isFunded {
                        Button("Send \(pot.raised.formattedCompact) home") { confirmingPayout = true }
                    } else {
                        Button("Add my share") { contributing = true }
                    }
                }
                .buttonStyle(.primary)
                .padding()
                .background(.bar)
            }
        }
        .sheet(isPresented: $contributing) { ContributeSheet(pot: pot) }
        .confirmationDialog("Send the pot now?", isPresented: $confirmingPayout, titleVisibility: .visible) {
            Button("Send \(pot.raised.formatted)") {
                store.payOutPot(pot.id)
                celebrate += 1
            }
        } message: {
            Text("Everything raised goes to \(recipient?.fullName ?? "the recipient") in one payout.")
        }
        .sensoryFeedback(.success, trigger: celebrate)
    }
}

private struct ContributeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pot: FamilyPot
    @State private var amountText = ""
    @State private var funding: FundingSource = .wallet
    @State private var error: String?

    private var you: FamilyPot.Member? { pot.members.first(where: \.isYou) }

    var body: some View {
        let currency = you?.currency ?? .GBP
        let amount = Decimal(userInput: amountText).map { Money($0, currency) }
        let rate = (try? store.engine.customerRate(from: currency, to: pot.currency).customer) ?? 0
        let adds = amount.map { Money($0.amount * rate, pot.currency, rounding: .down) }
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(currency.symbol).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                    }
                    if let adds {
                        LabeledContent("Adds to the pot", value: adds.formatted).monospacedDigit()
                    }
                    Button("Cover the rest (\(Self.amountToFinish(pot: pot, rate: rate, currency: currency).formatted))") {
                        amountText = SendDraft.text(Self.amountToFinish(pot: pot, rate: rate, currency: currency))
                    }
                } footer: {
                    Text("Converted at 1 \(currency.code) = \(MoneyFormatter.rate(rate)) \(pot.currency.code), our usual rate. No fee on contributions.")
                }
                Section("Pay with") {
                    Picker("Pay with", selection: $funding) {
                        ForEach(FundingSource.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let error {
                    Section { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Add my share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let amount else { return }
                        do {
                            try store.contribute(toPot: pot.id, amount: amount, funding: funding)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(amount == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    static func amountToFinish(pot: FamilyPot, rate: Decimal, currency: Currency) -> Money {
        guard rate > 0 else { return .zero(currency) }
        return Money(pot.remaining.amount / rate, currency, rounding: .up)
    }
}
