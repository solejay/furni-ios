import Foundation
import Observation
import HomewardCore

/// The in-progress send. Lives for the duration of the send sheet.
@MainActor
@Observable
final class SendDraft {
    enum Entry { case send, receive }

    var source: Currency
    var target: Currency
    var sendText = ""
    var receiveText = ""
    var entry: Entry = .send
    var recipient: Recipient?
    var funding: FundingSource = .wallet
    var purpose: TransferPurpose = .familySupport
    var message = ""
    var repeatMonthly = false

    /// Live, unlocked quote shown while typing.
    private(set) var quote: Quote?
    private(set) var quoteError: String?
    /// Quote locked when the customer reaches the review step.
    var lockedQuote: Quote?

    init(source: Currency, target: Currency) {
        self.source = source
        self.target = target
    }

    func recalculate(with engine: QuoteEngine, now: Date = Date()) {
        do {
            switch entry {
            case .send:
                guard let amount = Decimal(userInput: sendText), amount > 0 else { return clear(keep: .send) }
                let quote = try engine.quote(sending: Money(amount, source), to: target, at: now)
                self.quote = quote
                receiveText = Self.text(quote.receiveAmount)
            case .receive:
                guard let amount = Decimal(userInput: receiveText), amount > 0 else { return clear(keep: .receive) }
                let quote = try engine.quote(receiving: Money(amount, target), from: source, at: now)
                self.quote = quote
                sendText = Self.text(quote.sendAmount)
            }
            quoteError = nil
        } catch let error as QuoteError {
            quote = nil
            quoteError = error.message
        } catch {
            quote = nil
            quoteError = error.localizedDescription
        }
    }

    private func clear(keep: Entry) {
        quote = nil
        quoteError = nil
        if keep == .send { receiveText = "" } else { sendText = "" }
    }

    func lockQuote(with engine: QuoteEngine) {
        recalculate(with: engine)
        lockedQuote = quote
    }

    nonisolated static func text(_ money: Money) -> String {
        MoneyFormatter.string(from: money.amount, fractionDigits: money.currency.minorUnitScale, dropZeroFraction: true)
    }
}
