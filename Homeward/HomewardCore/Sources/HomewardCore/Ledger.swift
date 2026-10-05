import Foundation

/// Everything the customer owns, in one Codable value. The app persists this; the rules live here.
public struct Ledger: Codable, Hashable, Sendable {
    public var profile: Profile
    public var wallet: Wallet
    public var recipients: [Recipient]
    public var transfers: [Transfer]
    public var alerts: [RateAlert]
    public var scheduled: [ScheduledTransfer]
    public var pots: [FamilyPot]

    public struct Profile: Codable, Hashable, Sendable {
        public var firstName: String
        public var lastName: String
        public var homeCurrency: Currency
        public var favouriteTarget: Currency
        public var tier: VerificationTier

        public init(firstName: String, lastName: String, homeCurrency: Currency, favouriteTarget: Currency, tier: VerificationTier) {
            self.firstName = firstName
            self.lastName = lastName
            self.homeCurrency = homeCurrency
            self.favouriteTarget = favouriteTarget
            self.tier = tier
        }
    }

    public init(profile: Profile, wallet: Wallet = Wallet(), recipients: [Recipient] = [], transfers: [Transfer] = [],
                alerts: [RateAlert] = [], scheduled: [ScheduledTransfer] = [], pots: [FamilyPot] = []) {
        self.profile = profile
        self.wallet = wallet
        self.recipients = recipients
        self.transfers = transfers
        self.alerts = alerts
        self.scheduled = scheduled
        self.pots = pots
    }

    // Decodes data saved before newer fields existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(Profile.self, forKey: .profile)
        wallet = try container.decode(Wallet.self, forKey: .wallet)
        recipients = try container.decode([Recipient].self, forKey: .recipients)
        transfers = try container.decode([Transfer].self, forKey: .transfers)
        alerts = try container.decodeIfPresent([RateAlert].self, forKey: .alerts) ?? []
        scheduled = try container.decodeIfPresent([ScheduledTransfer].self, forKey: .scheduled) ?? []
        pots = try container.decodeIfPresent([FamilyPot].self, forKey: .pots) ?? []
    }

    public enum SendError: Error, Equatable, Sendable {
        case quoteExpired
        case recipientCurrencyMismatch
        case invalidPayoutDetails(PayoutValidator.Issue)
        case insufficientFunds(available: Money)
        case overLimit(LimitUsage.Check)

        public var message: String {
            switch self {
            case .quoteExpired: return "Your locked rate expired. We've fetched a fresh quote."
            case .recipientCurrencyMismatch: return "This recipient can't receive that currency."
            case let .invalidPayoutDetails(issue): return issue.message
            case let .insufficientFunds(available): return "Your balance is \(available.formatted). Top up or pay by bank transfer or card."
            case let .overLimit(check):
                switch check {
                case let .exceedsDaily(remaining): return "That's over your daily limit. You can send up to $\(MoneyFormatter.string(from: remaining, fractionDigits: 0)) more today."
                case let .exceedsMonthly(remaining): return "That's over your monthly limit. You can send up to $\(MoneyFormatter.string(from: remaining, fractionDigits: 0)) more this month."
                case .allowed: return ""
                }
            }
        }
    }

    public func limitUsage(rates: any RateProvider, now: Date, calendar: Calendar) -> LimitUsage {
        LimitUsage.compute(transfers: transfers, tier: profile.tier, rates: rates, now: now, calendar: calendar)
    }

    /// Checks everything that could go wrong *before* any money moves, then creates the transfer.
    @discardableResult
    public mutating func send(quote: Quote, to recipient: Recipient, funding: FundingSource,
                              purpose: TransferPurpose = .familySupport, message: String? = nil,
                              rates: any RateProvider, now: Date, calendar: Calendar) throws -> Transfer {
        guard !quote.isExpired(at: now) else { throw SendError.quoteExpired }
        guard recipient.currency == quote.target else { throw SendError.recipientCurrencyMismatch }
        if let issue = PayoutValidator.validate(recipient.payout) { throw SendError.invalidPayoutDetails(issue) }

        let usd = quote.sendAmount.amount * (rates.midMarketRate(from: quote.source, to: .USD) ?? 0)
        let check = limitUsage(rates: rates, now: now, calendar: calendar).check(amountUSD: usd)
        guard check == .allowed else { throw SendError.overLimit(check) }

        if funding == .wallet {
            guard wallet.canAfford(quote.sendAmount) else {
                throw SendError.insufficientFunds(available: wallet.balance(quote.source))
            }
            try? wallet.debit(quote.sendAmount)
        }

        var transfer = Transfer(quote: quote, recipient: recipient, fundingSource: funding,
                                purpose: purpose, message: message, createdAt: now)
        if funding == .wallet {
            // Balance-funded transfers are paid the moment they're created.
            try? transfer.advance(to: .processing, at: now, note: "Paid from your balance")
        }
        transfers.insert(transfer, at: 0)
        return transfer
    }

    /// Cancels a transfer and returns any money already paid to the balance.
    public mutating func cancelTransfer(id: UUID, now: Date) throws {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        let wasPaid = transfers[index].status == .processing
        try transfers[index].cancel(at: now)
        if wasPaid && transfers[index].fundingSource == .wallet {
            try? wallet.credit(transfers[index].quote.sendAmount)
        }
    }

    public mutating func upsert(_ recipient: Recipient) {
        if let index = recipients.firstIndex(where: { $0.id == recipient.id }) {
            recipients[index] = recipient
        } else {
            recipients.insert(recipient, at: 0)
        }
    }

    /// Removes a recipient and any schedules paying them.
    public mutating func removeRecipient(id: UUID) {
        recipients.removeAll { $0.id == id }
        scheduled.removeAll { $0.recipientID == id }
    }

    /// Recipients ordered by how recently they were paid; new ones first if never paid.
    public var recentRecipients: [Recipient] {
        let lastPaid = Dictionary(transfers.map { ($0.recipient.id, $0.createdAt) }, uniquingKeysWith: max)
        return recipients.sorted { (lastPaid[$0.id] ?? $0.createdAt) > (lastPaid[$1.id] ?? $1.createdAt) }
    }

    /// Adds your share to a family pot. Balance-funded contributions are taken from the wallet.
    @discardableResult
    public mutating func contribute(toPot potID: UUID, amount: Money, funding: FundingSource,
                                    engine: QuoteEngine, now: Date) throws -> FamilyPot.Contribution {
        guard let index = pots.firstIndex(where: { $0.id == potID }),
              let you = pots[index].members.first(where: \.isYou) else { throw FamilyPot.PotError.unknownMember }
        if funding == .wallet && !wallet.canAfford(amount) {
            throw SendError.insufficientFunds(available: wallet.balance(amount.currency))
        }
        let contribution = try pots[index].contribute(memberID: you.id, amount: amount, engine: engine, at: now)
        if funding == .wallet { try? wallet.debit(amount) }
        return contribution
    }

    /// Total delivered to each recipient, in their currency.
    public func totalDelivered(to recipientID: UUID) -> Money? {
        let delivered = transfers.filter { $0.recipient.id == recipientID && $0.status == .delivered }
        guard let currency = delivered.first?.quote.target else { return nil }
        return delivered.map(\.quote.receiveAmount).reduce(.zero(currency), +)
    }
}

// MARK: - Demo data

extension Ledger {
    /// A realistic starting state so every screen has something to show.
    public static func demo(now: Date = Date(), rates: USDCrossRates = .sample()) -> Ledger {
        let engine = QuoteEngine(rates: rates)
        let mum = Recipient(fullName: "Folake Adeyemi", verifiedName: "ADEYEMI FOLAKE ABIOLA", nickname: "Mum",
                            payout: .nigeriaBank(bankCode: "058", accountNumber: PayoutValidator.makeNUBAN(bankCode: "058", serial: "012345678")!),
                            createdAt: now.addingTimeInterval(-90 * 86_400))
        let tunde = Recipient(fullName: "Tunde Bakare", verifiedName: "TUNDE BAKARE",
                              payout: .nigeriaBank(bankCode: "50515", accountNumber: "8123456789"),
                              createdAt: now.addingTimeInterval(-40 * 86_400))
        let ama = Recipient(fullName: "Ama Owusu", verifiedName: "AMA OWUSU", payout: .ghanaMobileMoney(network: .mtn, phone: "0241234567"),
                            createdAt: now.addingTimeInterval(-30 * 86_400))
        let wanjiru = Recipient(fullName: "Wanjiru Kamau", verifiedName: "WANJIRU KAMAU", payout: .kenyaMpesa(phone: "0712345678"),
                                createdAt: now.addingTimeInterval(-20 * 86_400))

        func delivered(_ amount: Decimal, to recipient: Recipient, daysAgo: Double) -> Transfer {
            let created = now.addingTimeInterval(-daysAgo * 86_400)
            let quote = try! engine.quote(sending: Money(amount, .GBP), to: recipient.currency, at: created)
            var transfer = Transfer(quote: quote, recipient: recipient, fundingSource: .bankTransfer, createdAt: created)
            try! transfer.advance(to: .processing, at: created.addingTimeInterval(95))
            try! transfer.advance(to: .sentToPartner, at: created.addingTimeInterval(140))
            try! transfer.advance(to: .delivered, at: created.addingTimeInterval(212))
            return transfer
        }

        // Eleven more months of history so "Your Year Home" has a year to tell.
        let olderHistory: [Transfer] = [
            delivered(200, to: mum, daysAgo: 64), delivered(450, to: tunde, daysAgo: 79),
            delivered(200, to: mum, daysAgo: 95), delivered(90, to: ama, daysAgo: 110),
            delivered(200, to: mum, daysAgo: 125), delivered(300, to: mum, daysAgo: 131),
            delivered(200, to: mum, daysAgo: 156), delivered(80, to: wanjiru, daysAgo: 170),
            delivered(200, to: mum, daysAgo: 186), delivered(650, to: mum, daysAgo: 201),
            delivered(200, to: mum, daysAgo: 217), delivered(120, to: tunde, daysAgo: 240),
            delivered(200, to: mum, daysAgo: 248), delivered(70, to: ama, daysAgo: 266),
            delivered(200, to: mum, daysAgo: 278), delivered(200, to: mum, daysAgo: 309),
            delivered(500, to: mum, daysAgo: 340),
        ]

        var pot = FamilyPot(
            title: "Mum's 70th birthday", recipientID: mum.id, target: Money(1_500_000, .NGN),
            members: [
                .init(name: "You", city: "London", currency: .GBP, isYou: true),
                .init(name: "Kemi", city: "Manchester", currency: .GBP),
                .init(name: "Dayo", city: "Houston", currency: .USD),
                .init(name: "Bisi", city: "Toronto", currency: .CAD),
            ],
            createdAt: now.addingTimeInterval(-6 * 86_400))
        try? pot.contribute(memberID: pot.members[1].id, amount: Money(150, .GBP), engine: engine, at: now.addingTimeInterval(-5 * 86_400))
        try? pot.contribute(memberID: pot.members[2].id, amount: Money(250, .USD), engine: engine, at: now.addingTimeInterval(-4 * 86_400))
        try? pot.contribute(memberID: pot.members[3].id, amount: Money(200, .CAD), engine: engine, at: now.addingTimeInterval(-2 * 86_400))

        let calendar = Calendar(identifier: .gregorian)
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!

        return Ledger(
            profile: Profile(firstName: "Tolu", lastName: "Adeyemi", homeCurrency: .GBP, favouriteTarget: .NGN, tier: .verified),
            wallet: Wallet(balances: [.GBP: Decimal(string: "1240.50")!, .EUR: 85, .USD: 0]),
            recipients: [mum, tunde, ama, wanjiru],
            transfers: [
                delivered(200, to: mum, daysAgo: 3),
                delivered(75, to: ama, daysAgo: 9),
                delivered(120, to: tunde, daysAgo: 16),
                delivered(60, to: wanjiru, daysAgo: 22),
                delivered(200, to: mum, daysAgo: 34),
            ] + olderHistory,
            alerts: [
                RateAlert(source: .GBP, target: .NGN,
                          targetRate: ((rates.midMarketRate(from: .GBP, to: .NGN) ?? 2000) * Decimal(string: "1.02")!).rounded(scale: 0, mode: .up)),
            ],
            scheduled: [
                ScheduledTransfer(title: "Mum's monthly allowance", recipientID: mum.id, sendAmount: Money(200, .GBP), target: .NGN,
                                  schedule: RecurringSchedule(frequency: .monthly(day: 1),
                                                              startDate: firstOfMonth.addingTimeInterval(9 * 3600))),
            ],
            pots: [pot]
        )
    }
}
