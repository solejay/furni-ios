import XCTest
@testable import HomewardCore

final class QuoteTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let rates = USDCrossRates.sample(asOf: Date(timeIntervalSince1970: 1_790_000_000))
    var engine: QuoteEngine { QuoteEngine(rates: rates) }

    func testCrossRateViaUSD() {
        XCTAssertEqual(rates.midMarketRate(from: .GBP, to: .NGN), Decimal(string: "2056.91275168"))
        XCTAssertEqual(rates.midMarketRate(from: .GBP, to: .GBP), 1)
    }

    func testForwardQuoteShowsEveryCost() throws {
        let quote = try engine.quote(sending: Money(200, .GBP), to: .NGN, at: now)
        XCTAssertEqual(quote.fee, Money(Decimal(string: "0.99")!, .GBP))
        XCTAssertEqual(quote.amountConverted, Money(Decimal(string: "199.01")!, .GBP))
        XCTAssertEqual(quote.customerRate, Decimal(string: "2048.6851"))
        XCTAssertEqual(quote.receiveAmount, Money(Decimal(string: "407708.82")!, .NGN))
        XCTAssertEqual(quote.marginCost, Money(Decimal(string: "0.80")!, .GBP))
        XCTAssertEqual(quote.totalCost, Money(Decimal(string: "1.79")!, .GBP))
        XCTAssertEqual(quote.expiresAt, now.addingTimeInterval(30 * 60))
    }

    func testFeeWaivedAtThreshold() throws {
        let quote = try engine.quote(sending: Money(300, .GBP), to: .NGN, at: now)
        XCTAssertTrue(quote.fee.isZero)
        XCTAssertEqual(quote.receiveAmount, Money(Decimal(string: "614605.53")!, .NGN))
        XCTAssertEqual(quote.totalCostRate, Decimal(string: "0.004"))
    }

    func testRecipientNeverGetsMoreThanMidMarket() throws {
        for amount in [5, 49.99, 250, 1_000, 24_999] as [Decimal] {
            let quote = try engine.quote(sending: Money(amount, .GBP), to: .KES, at: now)
            XCTAssertLessThanOrEqual(quote.receiveAmount, quote.midMarketReceiveAmount)
            XCTAssertEqual(quote.sendAmount, quote.fee + quote.amountConverted)
        }
    }

    func testReverseQuoteDeliversAtLeastRequestedAmount() throws {
        for target in [Decimal(10_000), Decimal(string: "123456.78")!, Decimal(500_000), Decimal(511_000)] {
            let quote = try engine.quote(receiving: Money(target, .NGN), from: .GBP, at: now)
            XCTAssertGreaterThanOrEqual(quote.receiveAmount.amount, target)
            // ...and not wastefully more: one penny less must fall short, unless the fee waiver kicked in.
            if !quote.fee.isZero {
                let cheaper = try engine.quote(sending: quote.sendAmount - Money(Decimal(string: "0.01")!, .GBP), to: .NGN, at: now)
                XCTAssertLessThan(cheaper.receiveAmount.amount, target)
            }
        }
    }

    func testReverseQuoteJustUnderFeeThresholdIsWaived() throws {
        // Needs ~£249.50 converted: adding the £0.99 fee would cross £250, so the fee is waived instead.
        let rate = try engine.customerRate(from: .GBP, to: .NGN).customer
        let receive = Money(Decimal(string: "249.50")! * rate, .NGN, rounding: .down)
        let quote = try engine.quote(receiving: receive, from: .GBP, at: now)
        XCTAssertTrue(quote.fee.isZero)
        XCTAssertEqual(quote.sendAmount, Money(250, .GBP))
        XCTAssertGreaterThanOrEqual(quote.receiveAmount, receive)
    }

    func testLimitsAndCorridors() {
        XCTAssertThrowsError(try engine.quote(sending: Money(2, .GBP), to: .NGN, at: now)) {
            XCTAssertEqual($0 as? QuoteError, .belowMinimum(Money(5, .GBP)))
        }
        XCTAssertThrowsError(try engine.quote(sending: Money(30_000, .GBP), to: .NGN, at: now)) {
            XCTAssertEqual($0 as? QuoteError, .aboveMaximum(Money(25_000, .GBP)))
        }
        XCTAssertThrowsError(try engine.quote(sending: Money(100, .NGN), to: .GBP, at: now)) {
            XCTAssertEqual($0 as? QuoteError, .unsupportedCorridor(.NGN, .GBP))
        }
    }

    func testRateLockExpiry() throws {
        let quote = try engine.quote(sending: Money(100, .EUR), to: .GHS, at: now)
        XCTAssertFalse(quote.isExpired(at: now.addingTimeInterval(29 * 60)))
        XCTAssertTrue(quote.isExpired(at: now.addingTimeInterval(30 * 60)))
        XCTAssertEqual(quote.timeRemaining(at: now.addingTimeInterval(600)), 1200)
        XCTAssertEqual(quote.timeRemaining(at: now.addingTimeInterval(9999)), 0)
    }

    func testComparisonShowsSavings() throws {
        let quote = try engine.quote(sending: Money(500, .GBP), to: .NGN, at: now)
        let comparisons = engine.compare(quote)
        XCTAssertEqual(comparisons.count, 2)
        for comparison in comparisons {
            XCTAssertLessThan(comparison.receiveAmount, quote.receiveAmount)
            XCTAssertEqual(comparison.receiveAmount + comparison.extraWithHomeward, quote.receiveAmount)
        }
    }

    func testQuoteRoundTripsThroughJSON() throws {
        let quote = try engine.quote(sending: Money(200, .CAD), to: .INR, at: now)
        let decoded = try JSONDecoder().decode(Quote.self, from: JSONEncoder().encode(quote))
        XCTAssertEqual(decoded, quote)
    }
}

final class MoneyTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(Money(Decimal(string: "1250")!, .GBP).formatted, "£1,250.00")
        XCTAssertEqual(Money(Decimal(string: "1250")!, .GBP).formattedCompact, "£1,250")
        XCTAssertEqual(Money(Decimal(string: "407708.82")!, .NGN).formatted, "₦407,708.82")
        XCTAssertEqual(Money(Decimal(string: "-3.5")!, .EUR).formatted, "€-3.50")
        XCTAssertEqual(Money(Decimal(string: "0.005")!, .USD).formatted, "$0.00") // banker's rounding
        XCTAssertEqual(MoneyFormatter.rate(Decimal(string: "2048.6851")!), "2,048.69")
        XCTAssertEqual(MoneyFormatter.rate(Decimal(string: "0.000486")!), "0.000486")
        XCTAssertEqual(MoneyFormatter.percent(Decimal(string: "0.004")!), "0.40%")
    }

    func testParsingUserInput() {
        XCTAssertEqual(Decimal(userInput: "1,250.50"), Decimal(string: "1250.50"))
        XCTAssertEqual(Decimal(userInput: " 20 "), 20)
        XCTAssertNil(Decimal(userInput: ""))
        XCTAssertNil(Decimal(userInput: "1.2.3"))
        XCTAssertNil(Decimal(userInput: "12abc"))
    }

    func testRateHistoryEndsAtCurrentRate() {
        let end = Date(timeIntervalSince1970: 1_790_000_000)
        let points = RateHistory.sample(current: 2048, days: 30, endingAt: end, seed: 7)
        XCTAssertEqual(points.count, 30)
        XCTAssertEqual(points.last?.rate, 2048)
        XCTAssertEqual(points.last?.date, end)
        XCTAssertEqual(points, RateHistory.sample(current: 2048, days: 30, endingAt: end, seed: 7), "must be deterministic")
        let insight = RateHistory.insight(for: points)!
        XCTAssertLessThanOrEqual(insight.low, insight.average)
        XCTAssertGreaterThanOrEqual(insight.high, insight.average)
    }
}
