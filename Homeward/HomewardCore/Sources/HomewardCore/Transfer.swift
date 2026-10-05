import Foundation

public enum TransferStatus: String, Codable, CaseIterable, Sendable {
    /// Created; waiting for the sender's payment to arrive.
    case awaitingFunding
    /// Payment received; converting at the locked rate.
    case processing
    /// Handed to the local payout partner.
    case sentToPartner
    case delivered
    /// Stopped before any money was taken.
    case cancelled
    case failed
    /// Money returned to the sender.
    case refunded

    public var title: String {
        switch self {
        case .awaitingFunding: return "Waiting for your payment"
        case .processing: return "Converting your money"
        case .sentToPartner: return "On its way"
        case .delivered: return "Delivered"
        case .cancelled: return "Cancelled"
        case .failed: return "Needs attention"
        case .refunded: return "Refunded"
        }
    }

    public var isTerminal: Bool { [.delivered, .cancelled, .refunded].contains(self) }
    public var isInFlight: Bool { [.awaitingFunding, .processing, .sentToPartner].contains(self) }

    var allowedNext: Set<TransferStatus> {
        switch self {
        case .awaitingFunding: return [.processing, .cancelled, .failed]
        case .processing: return [.sentToPartner, .refunded, .failed]
        case .sentToPartner: return [.delivered, .failed]
        case .failed: return [.refunded, .processing]
        case .delivered, .cancelled, .refunded: return []
        }
    }
}

public enum FundingSource: String, Codable, CaseIterable, Sendable {
    case wallet, bankTransfer, debitCard

    public var title: String {
        switch self {
        case .wallet: return "Homeward balance"
        case .bankTransfer: return "Bank transfer"
        case .debitCard: return "Debit card"
        }
    }

    /// For use mid-sentence: "from your bank transfer", but "from your Homeward balance".
    public var inlineTitle: String { self == .wallet ? title : title.lowercased() }

    public var detail: String {
        switch self {
        case .wallet: return "Instant · no extra cost"
        case .bankTransfer: return "Usually arrives in minutes · no extra cost"
        case .debitCard: return "Instant · no extra cost"
        }
    }
}

public enum TransferPurpose: String, Codable, CaseIterable, Sendable {
    case familySupport, education, medical, savings, gift, bills, business

    public var title: String {
        switch self {
        case .familySupport: return "Family support"
        case .education: return "School fees"
        case .medical: return "Medical"
        case .savings: return "Savings"
        case .gift: return "Gift"
        case .bills: return "Bills & rent"
        case .business: return "Business"
        }
    }
}

public struct TransferEvent: Codable, Hashable, Sendable {
    public let status: TransferStatus
    public let date: Date
    public let note: String?

    public init(status: TransferStatus, date: Date, note: String? = nil) {
        self.status = status
        self.date = date
        self.note = note
    }
}

public enum TransferError: Error, Equatable, Sendable {
    case invalidTransition(from: TransferStatus, to: TransferStatus)
    case cannotCancel(TransferStatus)
}

public struct Transfer: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Short, human-readable reference to quote to support.
    public let reference: String
    public let quote: Quote
    /// Snapshot of the recipient at send time, so edits later don't rewrite history.
    public let recipient: Recipient
    public let fundingSource: FundingSource
    public let purpose: TransferPurpose
    public let message: String?
    public let createdAt: Date
    public let estimatedDelivery: Date
    public private(set) var status: TransferStatus
    public private(set) var events: [TransferEvent]
    /// Reference issued by the payout partner on delivery, as proof of payment.
    public private(set) var payoutReference: String?
    public private(set) var failureReason: String?

    public init(id: UUID = UUID(), reference: String? = nil, quote: Quote, recipient: Recipient,
                fundingSource: FundingSource, purpose: TransferPurpose = .familySupport, message: String? = nil,
                createdAt: Date) {
        self.id = id
        self.reference = reference ?? Transfer.makeReference(from: id)
        self.quote = quote
        self.recipient = recipient
        self.fundingSource = fundingSource
        self.purpose = purpose
        self.message = message
        self.createdAt = createdAt
        self.estimatedDelivery = createdAt.addingTimeInterval(
            DeliveryEstimate.for(recipient.payout, funding: fundingSource).typicalSeconds)
        self.status = .awaitingFunding
        self.events = [TransferEvent(status: .awaitingFunding, date: createdAt)]
    }

    /// "HW-3F9K2Q": unambiguous characters only (no 0/O, 1/I).
    public static func makeReference(from id: UUID) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var value = id.uuid
        let bytes = withUnsafeBytes(of: &value) { Array($0) }
        let code = bytes.prefix(6).map { alphabet[Int($0) % alphabet.count] }
        return "HW-" + String(code)
    }

    public mutating func advance(to next: TransferStatus, at date: Date, note: String? = nil) throws {
        guard status.allowedNext.contains(next) else {
            throw TransferError.invalidTransition(from: status, to: next)
        }
        status = next
        events.append(TransferEvent(status: next, date: date, note: note))
        if next == .delivered && payoutReference == nil {
            payoutReference = "PO" + reference.dropFirst(3) + String(Int(date.timeIntervalSince1970) % 100_000)
        }
        if next == .failed { failureReason = note }
    }

    /// Cancellation is free until the payout partner has the money.
    public var canCancel: Bool { status == .awaitingFunding || status == .processing }

    /// Cancels the transfer. Funds already received are refunded automatically; no form to fill in.
    public mutating func cancel(at date: Date) throws {
        switch status {
        case .awaitingFunding:
            try advance(to: .cancelled, at: date, note: "Cancelled before payment. Nothing was charged.")
        case .processing:
            try advance(to: .refunded, at: date, note: "Cancelled. \(quote.sendAmount.formatted) refunded to your \(fundingSource.inlineTitle).")
        default:
            throw TransferError.cannotCancel(status)
        }
    }

    public func date(of status: TransferStatus) -> Date? {
        events.last { $0.status == status }?.date
    }

    /// True when the transfer is still moving but has run past its promised delivery time.
    public func isDelayed(at now: Date) -> Bool {
        status.isInFlight && now > estimatedDelivery
    }
}

/// How long a payout normally takes. Shown before sending and used to flag delays honestly.
public struct DeliveryEstimate: Hashable, Sendable {
    public let typicalSeconds: TimeInterval
    public let label: String

    public static func `for`(_ payout: PayoutDetails, funding: FundingSource) -> DeliveryEstimate {
        let fundingDelay: TimeInterval = funding == .bankTransfer ? 10 * 60 : 0
        switch payout {
        case .nigeriaBank, .kenyaMpesa, .ghanaMobileMoney, .indiaUPI:
            return DeliveryEstimate(typicalSeconds: 5 * 60 + fundingDelay,
                                    label: funding == .bankTransfer ? "Usually within 15 minutes" : "Usually within 5 minutes")
        case .ghanaBank:
            return DeliveryEstimate(typicalSeconds: 4 * 3600 + fundingDelay, label: "Usually within 4 hours")
        case .indiaBank:
            return DeliveryEstimate(typicalSeconds: 2 * 3600 + fundingDelay, label: "Usually within 2 hours")
        }
    }
}

/// A row in the tracking timeline.
public struct TrackingStep: Hashable, Sendable, Identifiable {
    public enum State: String, Sendable { case done, current, upcoming, problem }
    public let title: String
    public let detail: String?
    public let state: State
    public let date: Date?
    public var id: String { title }
}

extension Transfer {
    /// The steps shown in the tracker, including the ones still to come.
    public var trackingSteps: [TrackingStep] {
        let recipientFirstName = recipient.fullName.split(separator: " ").first.map(String.init) ?? recipient.fullName
        let happyPath: [(TransferStatus, String, String?)] = [
            (.awaitingFunding, "Transfer created", "Rate locked at \(MoneyFormatter.rate(quote.customerRate)) \(quote.target.code)"),
            (.processing, "Payment received", "\(quote.sendAmount.formatted) from your \(fundingSource.inlineTitle)"),
            (.sentToPartner, "Sent to \(recipient.payout.summary)", "Converted to \(quote.receiveAmount.formatted)"),
            (.delivered, "Delivered to \(recipientFirstName)", payoutReference.map { "Payout reference \($0)" }),
        ]

        switch status {
        case .cancelled, .refunded:
            var steps = happyPath.compactMap { status, title, detail -> TrackingStep? in
                guard let date = date(of: status) else { return nil }
                return TrackingStep(title: title, detail: detail, state: .done, date: date)
            }
            let final = events.last!
            steps.append(TrackingStep(title: status.title, detail: final.note, state: .done, date: final.date))
            return steps
        default:
            break
        }

        let order: [TransferStatus] = [.awaitingFunding, .processing, .sentToPartner, .delivered]
        let reached = events.filter { order.contains($0.status) }.map { order.firstIndex(of: $0.status)! }.max() ?? 0

        return happyPath.enumerated().map { index, step in
            let (stepStatus, title, detail) = step
            let state: TrackingStep.State
            if index <= reached {
                state = .done
            } else if index == reached + 1 {
                state = status == .failed ? .problem : .current
            } else {
                state = .upcoming
            }
            let problemDetail = state == .problem ? (failureReason ?? "We're looking into it.") : detail
            return TrackingStep(title: title, detail: problemDetail, state: state, date: date(of: stepStatus))
        }
    }
}
