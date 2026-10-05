import Foundation
import Observation
import UserNotifications
import HomewardCore

/// A request to open the send flow, optionally pre-filled ("Send again", "Send to Mum").
struct SendRequest: Identifiable {
    let id = UUID()
    var recipient: Recipient?
    var amount: Money?
    var target: Currency?
}

/// Single source of truth for the app. Business rules live in `HomewardCore.Ledger`;
/// this class adds persistence, the live-rate feed and the demo transfer simulator.
@MainActor
@Observable
final class AppStore {
    var ledger: Ledger {
        didSet { save() }
    }
    private(set) var rates: USDCrossRates
    var sendRequest: SendRequest?
    /// Shown as an in-app banner when a rate alert fires.
    var firedAlert: RateAlert?
    var notificationsEnabled = false

    let calendar = Calendar.current
    private let baseRates: USDCrossRates
    private let simulator = TransferSimulator()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ledger.json")
        fileURL = url
        let base = USDCrossRates.sample()
        baseRates = base
        rates = base

        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder.homeward.decode(Ledger.self, from: data) {
            ledger = saved
        } else {
            ledger = .demo(rates: base)
        }
    }

    var engine: QuoteEngine { QuoteEngine(rates: rates) }

    func midRate(_ source: Currency, _ target: Currency) -> Decimal {
        rates.midMarketRate(from: source, to: target) ?? 0
    }

    var limitUsage: LimitUsage {
        ledger.limitUsage(rates: rates, now: Date(), calendar: calendar)
    }

    func usd(_ money: Money) -> Decimal {
        money.amount * midRate(money.currency, .USD)
    }

    func transfer(id: UUID) -> Transfer? {
        ledger.transfers.first { $0.id == id }
    }

    func recipient(id: UUID) -> Recipient? {
        ledger.recipients.first { $0.id == id }
    }

    var inFlightTransfers: [Transfer] {
        ledger.transfers.filter { $0.status.isInFlight || $0.status == .failed }
    }

    // MARK: Live updates

    func start() {
        guard tickTask == nil else { return }
        tick()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
        Task { await refreshNotificationPermission() }
    }

    private func tick() {
        let now = Date()
        tickCount += 1

        // Advance in-flight demo transfers.
        var transfers = ledger.transfers
        var changed = false
        for index in transfers.indices where transfers[index].status.isInFlight {
            if simulator.catchUp(&transfers[index], now: now) {
                changed = true
                if transfers[index].status == .delivered {
                    notify(title: "Delivered to \(transfers[index].recipient.fullName)",
                           body: "\(transfers[index].quote.receiveAmount.formatted) has arrived. Ref \(transfers[index].reference).")
                }
            }
        }
        if changed { ledger.transfers = transfers }

        // Gently move rates every 5 seconds so the app feels live (sample data only).
        if tickCount % 5 == 1 {
            let t = now.timeIntervalSince1970
            var factors: [Currency: Double] = [:]
            for (offset, currency) in Currency.receiveCurrencies.enumerated() {
                factors[currency] = 1 + 0.0025 * sin(t / 47 + Double(offset) * 1.7)
            }
            rates = baseRates.nudged(by: factors, asOf: now)
            checkAlerts(now: now)
        }
    }

    private func checkAlerts(now: Date) {
        for index in ledger.alerts.indices {
            let alert = ledger.alerts[index]
            let rate = midRate(alert.source, alert.target)
            if alert.shouldNotify(rate: rate, at: now) {
                ledger.alerts[index].lastTriggeredAt = now
                firedAlert = ledger.alerts[index]
                notify(title: "Rate alert: \(alert.source.code) → \(alert.target.code)",
                       body: "1 \(alert.source.code) is now \(MoneyFormatter.rate(rate)) \(alert.target.code). Your target was \(MoneyFormatter.rate(alert.targetRate)).")
            }
        }
    }

    // MARK: Actions

    enum ActionError: LocalizedError {
        case send(Ledger.SendError)
        case other(String)
        var errorDescription: String? {
            switch self {
            case let .send(error): return error.message
            case let .other(message): return message
            }
        }
    }

    @discardableResult
    func send(quote: Quote, to recipient: Recipient, funding: FundingSource, purpose: TransferPurpose,
              message: String?, repeatMonthly: Bool) throws -> Transfer {
        do {
            let transfer = try ledger.send(quote: quote, to: recipient, funding: funding, purpose: purpose,
                                           message: message, rates: rates, now: Date(), calendar: calendar)
            ledger.upsert(recipient)
            if repeatMonthly {
                let day = calendar.component(.day, from: Date())
                ledger.scheduled.append(ScheduledTransfer(
                    title: "\(recipient.nickname ?? recipient.fullName.components(separatedBy: " ").first ?? "") monthly",
                    recipientID: recipient.id, sendAmount: quote.sendAmount, target: quote.target,
                    schedule: RecurringSchedule(frequency: .monthly(day: day),
                                                startDate: calendar.date(byAdding: .month, value: 1, to: Date())!),
                    fundingSource: funding))
            }
            return transfer
        } catch let error as Ledger.SendError {
            throw ActionError.send(error)
        }
    }

    func cancel(_ transfer: Transfer) throws {
        do {
            try ledger.cancelTransfer(id: transfer.id, now: Date())
        } catch {
            throw ActionError.other("This transfer is already with the payout partner and can't be cancelled.")
        }
    }

    func topUp(_ money: Money) {
        try? ledger.wallet.credit(money)
    }

    func save(_ recipient: Recipient) { ledger.upsert(recipient) }
    func deleteRecipient(_ id: UUID) { ledger.removeRecipient(id: id) }

    func resetDemo() {
        ledger = .demo(rates: baseRates)
    }

    // MARK: Account name lookup (demo)

    /// Simulates asking the receiving bank who owns an account. Banks usually return SURNAME FIRST in capitals.
    /// Demo rule: numbers containing "999" belong to someone else, to show the mismatch warning.
    func lookUpAccountName(for details: PayoutDetails, typedName: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(900))
        let known = ledger.recipients.first { $0.payout == details }?.verifiedName
        if let known { return known }
        let raw: String
        switch details {
        case let .nigeriaBank(_, account), let .ghanaBank(_, account), let .indiaBank(_, account): raw = account
        case let .ghanaMobileMoney(_, phone), let .kenyaMpesa(phone): raw = phone
        case let .indiaUPI(vpa): raw = vpa
        }
        if raw.contains("999") { return "MUSA IBRAHIM DANJUMA" }
        let words = typedName.uppercased().split(separator: " ").map(String.init)
        guard words.count > 1 else { return (words.first ?? "UNKNOWN") + " OKONKWO" }
        return ([words.last!] + words.dropLast()).joined(separator: " ")
    }

    // MARK: Notifications

    func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsEnabled = granted
    }

    private func refreshNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }

    private func notify(title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder.homeward.encode(ledger) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

extension JSONEncoder {
    static let homeward: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let homeward: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
