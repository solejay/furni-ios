import XCTest
@testable import HomewardCore

final class DelightTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let rates = USDCrossRates.sample(asOf: Date(timeIntervalSince1970: 1_790_000_000))
    var engine: QuoteEngine { QuoteEngine(rates: rates) }
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: Rate weather

    func testRateClimateConditions() {
        func points(_ rates: [Decimal]) -> [RateHistory.Point] {
            rates.enumerated().map { RateHistory.Point(date: now.addingTimeInterval(Double($0.offset) * 86_400), rate: $0.element) }
        }
        let sunny = RateClimate.from(points([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]))!
        XCTAssertEqual(sunny.daysBeaten, 10)
        XCTAssertEqual(sunny.percentile, 100)
        XCTAssertEqual(sunny.condition, .sunny)
        XCTAssertEqual(sunny.detail, "Today's rate beats 10 of the last 10 days.")

        XCTAssertEqual(RateClimate.from(points([5, 6, 7, 8, 1]))!.condition, .overcast)
        XCTAssertEqual(RateClimate.from(points([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 5.5]))!.condition, .mild)
        XCTAssertEqual(RateClimate.from(points([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 7.5]))!.condition, .bright)
        XCTAssertEqual(RateClimate.from(points([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 3.5]))!.condition, .cloudy)
        XCTAssertNil(RateClimate.from(points([5])))
    }

    func testRateClimateIgnoresTiesAsWins() {
        let flat = (0..<6).map { RateHistory.Point(date: now.addingTimeInterval(Double($0) * 86_400), rate: 100) }
        XCTAssertEqual(RateClimate.from(flat)!.daysBeaten, 0, "matching a past rate isn't beating it")
    }

    // MARK: Family pot

    func makePot() -> FamilyPot {
        FamilyPot(title: "Roof repairs", recipientID: UUID(), target: Money(1_000_000, .NGN),
                  members: [.init(name: "You", city: "London", currency: .GBP, isYou: true),
                            .init(name: "Dayo", city: "Houston", currency: .USD)],
                  createdAt: now)
    }

    func testPotConvertsEachCurrencyAtCustomerRate() throws {
        var pot = makePot()
        let usd = try pot.contribute(memberID: pot.members[1].id, amount: Money(100, .USD), engine: engine, at: now)
        let expectedRate = try engine.customerRate(from: .USD, to: .NGN).customer
        XCTAssertEqual(usd.rate, expectedRate)
        XCTAssertEqual(usd.added, Money(100 * expectedRate, .NGN, rounding: .down))
        XCTAssertEqual(pot.raised, usd.added)
        XCTAssertEqual(pot.total(for: pot.members[1].id), usd.added)
        XCTAssertEqual(pot.shares.first?.member.name, "Dayo")
        XCTAssertFalse(pot.isFunded)
        XCTAssertEqual(pot.remaining, pot.target - usd.added)
        XCTAssertEqual(pot.progress, (usd.added.amount / 1_000_000).doubleValue, accuracy: 0.0001)
    }

    func testPotRulesAndPayout() throws {
        var pot = makePot()
        XCTAssertThrowsError(try pot.contribute(memberID: UUID(), amount: Money(50, .GBP), engine: engine, at: now)) {
            XCTAssertEqual($0 as? FamilyPot.PotError, .unknownMember)
        }
        XCTAssertThrowsError(try pot.contribute(memberID: pot.members[0].id, amount: Money(2, .GBP), engine: engine, at: now)) {
            XCTAssertEqual($0 as? FamilyPot.PotError, .belowMinimum(Money(5, .GBP)))
        }
        XCTAssertThrowsError(try pot.payOut(at: now)) {
            guard case .notFunded? = $0 as? FamilyPot.PotError else { return XCTFail("\($0)") }
        }

        try pot.contribute(memberID: pot.members[0].id, amount: Money(300, .GBP), engine: engine, at: now)
        try pot.contribute(memberID: pot.members[1].id, amount: Money(400, .USD), engine: engine, at: now)
        XCTAssertTrue(pot.isFunded)
        XCTAssertEqual(pot.progress, 1)
        XCTAssertTrue(pot.remaining.isZero)

        try pot.payOut(at: now + 60)
        XCTAssertTrue(pot.isPaidOut)
        XCTAssertTrue(pot.payoutReference!.hasPrefix("POT-"))
        XCTAssertThrowsError(try pot.contribute(memberID: pot.members[0].id, amount: Money(10, .GBP), engine: engine, at: now)) {
            XCTAssertEqual($0 as? FamilyPot.PotError, .alreadyPaidOut)
        }
    }

    func testPotFeesAvoided() throws {
        var pot = makePot()
        try pot.contribute(memberID: pot.members[0].id, amount: Money(100, .GBP), engine: engine, at: now) // £0.99 fee avoided
        try pot.contribute(memberID: pot.members[1].id, amount: Money(500, .USD), engine: engine, at: now) // over waiver: no fee
        let gbpToUSD = rates.midMarketRate(from: .GBP, to: .USD)!
        XCTAssertEqual(pot.feesAvoidedUSD(policy: .standard, rates: rates), (Decimal(string: "0.99")! * gbpToUSD).rounded(scale: 2, mode: .plain))
    }

    func testLedgerContributionUsesWallet() throws {
        var ledger = Ledger.demo(now: now, rates: rates)
        let pot = ledger.pots[0]
        let before = ledger.wallet.balance(.GBP)
        try ledger.contribute(toPot: pot.id, amount: Money(100, .GBP), funding: .wallet, engine: engine, now: now)
        XCTAssertEqual(ledger.wallet.balance(.GBP), before - Money(100, .GBP))
        XCTAssertEqual(ledger.pots[0].contributions.count, pot.contributions.count + 1)
        XCTAssertThrowsError(try ledger.contribute(toPot: pot.id, amount: Money(50_000, .GBP), funding: .wallet, engine: engine, now: now))
    }

    func testOldSavedLedgerWithoutPotsStillDecodes() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Ledger.demo(now: now, rates: rates))) as! [String: Any]
        json.removeValue(forKey: "pots")
        json.removeValue(forKey: "alerts")
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.pots.isEmpty)
        XCTAssertTrue(decoded.alerts.isEmpty)
        XCTAssertEqual(decoded.recipients.count, 4)
    }

    // MARK: Year in review

    func testYearInReviewFromDemo() throws {
        let ledger = Ledger.demo(now: now, rates: rates)
        let review = try XCTUnwrap(YearInReview.compute(transfers: ledger.transfers, engine: engine, now: now, calendar: calendar))
        XCTAssertEqual(review.transferCount, 22)
        XCTAssertEqual(review.totalSent.currency, .GBP)
        XCTAssertEqual(review.totalSent, ledger.transfers.map(\.quote.sendAmount).reduce(.zero(.GBP), +))
        XCTAssertEqual(review.recipients.first?.recipient.nickname, "Mum")
        XCTAssertEqual(review.recipients.count, 4)
        XCTAssertEqual(Set(review.deliveredByCurrency.map(\.currency)), [.NGN, .GHS, .KES])
        XCTAssertTrue(review.savedVersusBank.isPositive)
        XCTAssertNotNil(review.busiestMonth)
        XCTAssertEqual(review.fastestDelivery, 212)
    }

    func testYearInReviewIgnoresOldAndUndelivered() throws {
        let quote = try engine.quote(sending: Money(100, .EUR), to: .KES, at: now)
        let recipient = Recipient(fullName: "W K", payout: .kenyaMpesa(phone: "0712345678"))
        let pending = Transfer(quote: quote, recipient: recipient, fundingSource: .bankTransfer, createdAt: now)
        var old = Transfer(quote: quote, recipient: recipient, fundingSource: .bankTransfer, createdAt: now.addingTimeInterval(-400 * 86_400))
        try old.advance(to: .processing, at: old.createdAt)
        try old.advance(to: .sentToPartner, at: old.createdAt)
        try old.advance(to: .delivered, at: old.createdAt + 60)
        XCTAssertNil(YearInReview.compute(transfers: [pending, old], engine: engine, now: now, calendar: calendar))
    }
}
