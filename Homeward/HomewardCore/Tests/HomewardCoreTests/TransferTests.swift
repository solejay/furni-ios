import XCTest
@testable import HomewardCore

final class TransferTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let rates = USDCrossRates.sample(asOf: Date(timeIntervalSince1970: 1_790_000_000))
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let mum = Recipient(fullName: "Folake Adeyemi",
                        payout: .nigeriaBank(bankCode: "058", accountNumber: "0123456785"))

    func makeTransfer(funding: FundingSource = .bankTransfer) throws -> Transfer {
        let quote = try QuoteEngine(rates: rates).quote(sending: Money(100, .GBP), to: .NGN, at: now)
        return Transfer(quote: quote, recipient: mum, fundingSource: funding, createdAt: now)
    }

    func testHappyPath() throws {
        var transfer = try makeTransfer()
        XCTAssertEqual(transfer.status, .awaitingFunding)
        XCTAssertTrue(transfer.reference.hasPrefix("HW-"))
        XCTAssertEqual(transfer.reference.count, 9)

        try transfer.advance(to: .processing, at: now + 60)
        try transfer.advance(to: .sentToPartner, at: now + 120)
        try transfer.advance(to: .delivered, at: now + 180)
        XCTAssertEqual(transfer.status, .delivered)
        XCTAssertNotNil(transfer.payoutReference)
        XCTAssertEqual(transfer.trackingSteps.map(\.state), [.done, .done, .done, .done])
        XCTAssertFalse(transfer.canCancel)
    }

    func testIllegalTransitionsAreRejected() throws {
        var transfer = try makeTransfer()
        XCTAssertThrowsError(try transfer.advance(to: .delivered, at: now)) {
            XCTAssertEqual($0 as? TransferError, .invalidTransition(from: .awaitingFunding, to: .delivered))
        }
        try transfer.advance(to: .processing, at: now)
        try transfer.advance(to: .sentToPartner, at: now)
        XCTAssertThrowsError(try transfer.cancel(at: now)) {
            XCTAssertEqual($0 as? TransferError, .cannotCancel(.sentToPartner))
        }
    }

    func testTrackingStepsMidway() throws {
        var transfer = try makeTransfer()
        XCTAssertEqual(transfer.trackingSteps.map(\.state), [.done, .current, .upcoming, .upcoming])
        try transfer.advance(to: .processing, at: now + 30)
        XCTAssertEqual(transfer.trackingSteps.map(\.state), [.done, .done, .current, .upcoming])
        try transfer.advance(to: .failed, at: now + 60, note: "Bank is offline")
        let steps = transfer.trackingSteps
        XCTAssertEqual(steps.map(\.state), [.done, .done, .problem, .upcoming])
        XCTAssertEqual(steps[2].detail, "Bank is offline")
    }

    func testCancelBeforeFundingAndAfter() throws {
        var unpaid = try makeTransfer()
        try unpaid.cancel(at: now + 10)
        XCTAssertEqual(unpaid.status, .cancelled)
        XCTAssertEqual(unpaid.trackingSteps.last?.title, "Cancelled")

        var paid = try makeTransfer()
        try paid.advance(to: .processing, at: now + 10)
        try paid.cancel(at: now + 20)
        XCTAssertEqual(paid.status, .refunded)
    }

    func testDelayDetection() throws {
        let transfer = try makeTransfer()
        XCTAssertFalse(transfer.isDelayed(at: now + 60))
        XCTAssertTrue(transfer.isDelayed(at: transfer.estimatedDelivery + 1))
    }

    func testSimulatorCatchesUp() throws {
        var transfer = try makeTransfer()
        let simulator = TransferSimulator(fundedAfter: 3, sentAfter: 7, deliveredAfter: 14)
        XCTAssertFalse(simulator.catchUp(&transfer, now: now + 1))
        XCTAssertTrue(simulator.catchUp(&transfer, now: now + 8))
        XCTAssertEqual(transfer.status, .sentToPartner)
        XCTAssertEqual(transfer.date(of: .processing), now + 3)
        simulator.catchUp(&transfer, now: now + 100)
        XCTAssertEqual(transfer.status, .delivered)
        XCTAssertEqual(transfer.date(of: .delivered), now + 14)
    }

    // MARK: Ledger

    func testSendFromWalletDebitsAndCancelRefunds() throws {
        var ledger = Ledger(profile: .init(firstName: "T", lastName: "A", homeCurrency: .GBP, favouriteTarget: .NGN, tier: .verified),
                            wallet: Wallet(balances: [.GBP: 500]), recipients: [mum])
        let quote = try QuoteEngine(rates: rates).quote(sending: Money(100, .GBP), to: .NGN, at: now)
        let transfer = try ledger.send(quote: quote, to: mum, funding: .wallet, rates: rates, now: now, calendar: calendar)
        XCTAssertEqual(transfer.status, .processing)
        XCTAssertEqual(ledger.wallet.balance(.GBP), Money(400, .GBP))

        try ledger.cancelTransfer(id: transfer.id, now: now + 5)
        XCTAssertEqual(ledger.transfers.first?.status, .refunded)
        XCTAssertEqual(ledger.wallet.balance(.GBP), Money(500, .GBP))
    }

    func testSendRejectsProblemsBeforeMoneyMoves() throws {
        var ledger = Ledger(profile: .init(firstName: "T", lastName: "A", homeCurrency: .GBP, favouriteTarget: .NGN, tier: .basic),
                            wallet: Wallet(balances: [.GBP: 50]))
        let engine = QuoteEngine(rates: rates)
        let quote = try engine.quote(sending: Money(100, .GBP), to: .NGN, at: now)

        XCTAssertThrowsError(try ledger.send(quote: quote, to: mum, funding: .wallet, rates: rates, now: now + 31 * 60, calendar: calendar)) {
            XCTAssertEqual($0 as? Ledger.SendError, .quoteExpired)
        }
        XCTAssertThrowsError(try ledger.send(quote: quote, to: mum, funding: .wallet, rates: rates, now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? Ledger.SendError, .insufficientFunds(available: Money(50, .GBP)))
        }
        let typo = Recipient(fullName: "Folake", payout: .nigeriaBank(bankCode: "058", accountNumber: "0123456786"))
        XCTAssertThrowsError(try ledger.send(quote: quote, to: typo, funding: .bankTransfer, rates: rates, now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? Ledger.SendError, .invalidPayoutDetails(.checksumFailed))
        }
        let kenyan = Recipient(fullName: "W K", payout: .kenyaMpesa(phone: "0712345678"))
        XCTAssertThrowsError(try ledger.send(quote: quote, to: kenyan, funding: .bankTransfer, rates: rates, now: now, calendar: calendar)) {
            XCTAssertEqual($0 as? Ledger.SendError, .recipientCurrencyMismatch)
        }
        // Basic tier: $500/day. £100 ≈ $134, so three transfers fit and the fourth does not.
        for _ in 0..<3 {
            try ledger.send(quote: quote, to: mum, funding: .bankTransfer, rates: rates, now: now, calendar: calendar)
        }
        XCTAssertThrowsError(try ledger.send(quote: quote, to: mum, funding: .bankTransfer, rates: rates, now: now, calendar: calendar)) {
            guard case .overLimit(.exceedsDaily)? = $0 as? Ledger.SendError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(ledger.wallet.balance(.GBP), Money(50, .GBP), "failed sends must not touch the balance")
    }

    func testLimitUsageIgnoresCancelled() throws {
        var ledger = Ledger(profile: .init(firstName: "T", lastName: "A", homeCurrency: .GBP, favouriteTarget: .NGN, tier: .basic))
        let quote = try QuoteEngine(rates: rates).quote(sending: Money(100, .GBP), to: .NGN, at: now)
        let transfer = try ledger.send(quote: quote, to: mum, funding: .bankTransfer, rates: rates, now: now, calendar: calendar)
        XCTAssertGreaterThan(ledger.limitUsage(rates: rates, now: now, calendar: calendar).usedTodayUSD, 0)
        try ledger.cancelTransfer(id: transfer.id, now: now)
        XCTAssertEqual(ledger.limitUsage(rates: rates, now: now, calendar: calendar).usedTodayUSD, 0)
    }

    func testDemoLedgerIsConsistent() throws {
        let ledger = Ledger.demo(now: now, rates: rates)
        XCTAssertEqual(ledger.recipients.count, 4)
        for recipient in ledger.recipients {
            XCTAssertNil(PayoutValidator.validate(recipient.payout), recipient.fullName)
            if let verified = recipient.verifiedName {
                XCTAssertEqual(NameMatcher.compare(entered: recipient.fullName, verified: verified), .match)
            }
        }
        XCTAssertTrue(ledger.transfers.allSatisfy { $0.status == .delivered })
        XCTAssertNotNil(ledger.totalDelivered(to: ledger.recipients[0].id))
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
    }
}

final class AlertAndScheduleTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testRateAlert() {
        var alert = RateAlert(source: .GBP, target: .NGN, targetRate: 2100)
        let now = date(2026, 10, 5)
        XCTAssertFalse(alert.shouldNotify(rate: 2099.99, at: now))
        XCTAssertTrue(alert.shouldNotify(rate: 2100, at: now))
        alert.lastTriggeredAt = now
        XCTAssertFalse(alert.shouldNotify(rate: 2150, at: now.addingTimeInterval(3600)), "cooldown")
        XCTAssertTrue(alert.shouldNotify(rate: 2150, at: now.addingTimeInterval(13 * 3600)))
        alert.isActive = false
        XCTAssertFalse(alert.shouldNotify(rate: 2150, at: now.addingTimeInterval(13 * 3600)))

        let below = RateAlert(source: .GBP, target: .NGN, targetRate: 2000, direction: .atOrBelow)
        XCTAssertTrue(below.isMet(by: 1999))
        XCTAssertEqual(below.summary, "1 GBP ≤ 2,000.00 NGN")
    }

    func testMonthlyScheduleClampsToMonthEnd() {
        let schedule = RecurringSchedule(frequency: .monthly(day: 31), startDate: date(2027, 1, 1))
        let dates = schedule.nextDates(after: date(2026, 12, 1), count: 4, calendar: calendar)
        XCTAssertEqual(dates, [date(2027, 1, 31), date(2027, 2, 28), date(2027, 3, 31), date(2027, 4, 30)])
        XCTAssertEqual(RecurringSchedule.Frequency.monthly(day: 1).title, "Monthly on the 1st")
        XCTAssertEqual(RecurringSchedule.Frequency.monthly(day: 22).title, "Monthly on the 22nd")
        XCTAssertEqual(RecurringSchedule.Frequency.monthly(day: 13).title, "Monthly on the 13th")
    }

    func testMonthlyScheduleSkipsDaysBeforeStart() {
        let schedule = RecurringSchedule(frequency: .monthly(day: 1), startDate: date(2026, 10, 15))
        XCTAssertEqual(schedule.nextDates(after: date(2026, 10, 15), count: 1, calendar: calendar), [date(2026, 11, 1)])
    }

    func testWeeklyAndPaused() {
        let schedule = RecurringSchedule(frequency: .fortnightly, startDate: date(2026, 10, 2))
        XCTAssertEqual(schedule.nextDates(after: date(2026, 10, 5), count: 2, calendar: calendar),
                       [date(2026, 10, 16), date(2026, 10, 30)])
        var scheduled = ScheduledTransfer(title: "Rent", recipientID: UUID(), sendAmount: Money(50, .GBP), target: .NGN, schedule: schedule)
        XCTAssertEqual(scheduled.nextRun(after: date(2026, 10, 5), calendar: calendar), date(2026, 10, 16))
        scheduled.isPaused = true
        XCTAssertNil(scheduled.nextRun(after: date(2026, 10, 5), calendar: calendar))
    }

    func testWallet() throws {
        var wallet = Wallet(balances: [.GBP: 10])
        try wallet.credit(Money(5, .GBP))
        XCTAssertEqual(wallet.balance(.GBP), Money(15, .GBP))
        XCTAssertThrowsError(try wallet.debit(Money(20, .GBP))) {
            XCTAssertEqual($0 as? Wallet.WalletError, .insufficientFunds(available: Money(15, .GBP)))
        }
        XCTAssertThrowsError(try wallet.credit(Money(0, .GBP)))
        XCTAssertEqual(wallet.displayCurrencies.first, .GBP)
    }
}
