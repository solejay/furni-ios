import SwiftUI
import HomewardCore

/// Everything a transfer receipt shows, for a transfer that exists or one about to be sent.
struct ReceiptModel {
    enum Tone { case live, good, muted, bad }

    let title: String
    let status: String
    let tone: Tone
    let receive: String
    let recipientName: String
    let account: String
    let from: String
    let to: String
    let progress: Double
    let leftNote: String
    let rightNote: String
    let pay: String
    let fee: String
    let rate: String
    let purpose: String
    let paidWith: String
    let reference: String?
    let footerTitle: String?
    let footerValue: String?
    let footerNote: String?

    var isLive: Bool { tone == .live }

    init(transfer t: Transfer, now: Date = Date()) {
        let delayed = t.isDelayed(at: now)
        title = "Transfer receipt"
        switch t.status {
        case .awaitingFunding: status = delayed ? "Delayed" : "Waiting for payment"; tone = delayed ? .bad : .live
        case .processing: status = delayed ? "Delayed" : "Processing"; tone = delayed ? .bad : .live
        case .sentToPartner: status = delayed ? "Delayed" : "On its way"; tone = delayed ? .bad : .live
        case .delivered: status = "Delivered"; tone = .good
        case .cancelled: status = "Cancelled"; tone = .muted
        case .refunded: status = "Refunded"; tone = .muted
        case .failed: status = "Needs attention"; tone = .bad
        }
        receive = t.quote.receiveAmount.formatted
        recipientName = t.recipient.fullName
        account = t.recipient.payout.summary
        from = "\(t.quote.source.flag) \(Place.origin(for: t.quote.source).city)"
        to = "\(t.recipient.country.flag) \(Place.destination(for: t.recipient.country).city)"
        progress = (t.status == .cancelled || t.status == .refunded) ? 0 : t.status.progress
        leftNote = "Sent " + t.createdAt.dayAndTime
        if let delivered = t.date(of: .delivered) {
            rightNote = "Delivered " + delivered.shortTime
        } else {
            rightNote = t.status.isInFlight ? "Arrives by " + t.estimatedDelivery.shortTime : t.status.title
        }
        pay = t.quote.sendAmount.formatted
        fee = t.quote.fee.isZero ? "Free" : t.quote.fee.formatted
        rate = "1 \(t.quote.source.code) = \(MoneyFormatter.rate(t.quote.customerRate)) \(t.quote.target.code)"
        purpose = t.purpose.title
        paidWith = t.fundingSource.title
        reference = t.reference
        footerTitle = t.payoutReference == nil ? nil : "Bank payout reference"
        footerValue = t.payoutReference
        footerNote = t.payoutReference == nil ? nil : "Their bank can trace the payment with this number."
    }

    init(quote: Quote, recipient: Recipient, funding: FundingSource, purpose transferPurpose: TransferPurpose) {
        title = "Review"
        status = "Ready to send"
        tone = .live
        receive = quote.receiveAmount.formatted
        recipientName = recipient.fullName
        account = recipient.payout.summary
        from = "\(quote.source.flag) \(Place.origin(for: quote.source).city)"
        to = "\(recipient.country.flag) \(Place.destination(for: recipient.country).city)"
        progress = 0
        leftNote = "Sends when you slide"
        rightNote = DeliveryEstimate.for(recipient.payout, funding: funding).label
        pay = quote.sendAmount.formatted
        fee = quote.fee.isZero ? "Free" : quote.fee.formatted
        rate = "1 \(quote.source.code) = \(MoneyFormatter.rate(quote.customerRate)) \(quote.target.code)"
        purpose = transferPurpose.title
        paidWith = funding.title
        reference = nil
        footerTitle = recipient.verifiedName == nil ? nil : "Name check"
        footerValue = recipient.verifiedName.map { "✓ " + $0 }
        footerNote = recipient.verifiedName == nil ? nil : "The bank confirmed who owns this account."
    }
}

/// A plain receipt: how much arrives, who gets it, what you paid, the rate and the reference.
struct TransferReceiptView: View {
    let model: ReceiptModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.title.uppercased())
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(Theme.cream.opacity(0.6))
                    Spacer()
                    StatusPill(text: model.status, tone: model.tone, onDark: true)
                }
                Text(model.receive)
                    .font(.system(size: 38, weight: .medium).monospacedDigit())
                    .tracking(-1.6)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 4)
                (Text("to ") + Text(model.recipientName).foregroundColor(Theme.cream) + Text(" · \(model.account)"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.cream.opacity(0.7))
                HStack(spacing: 10) {
                    Text(model.from)
                    ProgressTrack(progress: model.progress, onDark: true)
                    Text(model.to)
                }
                .font(.caption)
                .padding(.top, 8)
                HStack {
                    Text(model.leftNote)
                    Spacer()
                    Text(model.rightNote)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.cream.opacity(0.6))
            }
            .padding(18)
            .foregroundStyle(Theme.cream)
            .background(Theme.night)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow { field("You pay", model.pay); field("Fee", model.fee) }
                GridRow { field("Exchange rate", model.rate); field("Purpose", model.purpose) }
                GridRow {
                    field("Paid with", model.paidWith)
                    VStack(alignment: .leading, spacing: 3) {
                        label("Reference")
                        if let reference = model.reference {
                            Button {
                                UIPasteboard.general.string = reference
                                copied = true
                            } label: {
                                Label(reference, systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .labelStyle(.titleAndIcon)
                                    .font(.subheadline.weight(.medium).monospaced())
                            }
                            .foregroundStyle(Theme.brand)
                            .accessibilityHint("Copies the reference")
                        } else {
                            Text("Issued when you send").font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let title = model.footerTitle, let value = model.footerValue {
                Perforation()
                VStack(alignment: .leading, spacing: 3) {
                    label(title)
                    Text(value).font(.subheadline.weight(.medium).monospaced())
                    if let note = model.footerNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentSurface(cornerRadius: 28)
        .beam(active: model.isLive, cornerRadius: 28)
        .accessibilityElement(children: .contain)
        .animation(.spring(duration: 0.8), value: model.progress)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .medium, design: .monospaced)).tracking(1.4)
            .foregroundStyle(.secondary)
    }

    private func field(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(key)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}

/// A straight track from the sender's city to the recipient's, filled as the transfer progresses.
struct ProgressTrack: View, Animatable {
    var progress: Double
    var onDark = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let t = CGFloat(min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                Capsule().fill(onDark ? Theme.cream.opacity(0.14) : Color.secondary.opacity(0.2)).frame(height: 4)
                Capsule().fill(Theme.sun).frame(width: geo.size.width * t, height: 4)
                Circle()
                    .fill(Theme.sun)
                    .frame(width: 12, height: 12)
                    .shadow(color: Theme.sun.opacity(0.4), radius: 4)
                    .offset(x: geo.size.width * t - 6)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let text: String
    let tone: ReceiptModel.Tone
    var onDark = false

    private var color: Color {
        switch tone {
        case .live: return onDark ? Theme.sun : Theme.brand
        case .good: return Theme.mint
        case .muted: return .secondary
        case .bad: return Theme.coral
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if tone == .live { Circle().fill(Theme.sun).frame(width: 6, height: 6) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

private struct Perforation: View {
    var body: some View {
        ZStack {
            Line().stroke(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])).frame(height: 1).padding(.horizontal, 18)
            HStack {
                Circle().fill(Color(.systemBackground)).frame(width: 22, height: 22).offset(x: -11)
                Spacer()
                Circle().fill(Color(.systemBackground)).frame(width: 22, height: 22).offset(x: 11)
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}
