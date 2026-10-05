import SwiftUI
import HomewardCore

struct TransferRow: View {
    let transfer: Transfer

    var body: some View {
        HStack(spacing: 12) {
            RecipientAvatar(recipient: transfer.recipient)
            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.recipient.fullName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: transfer.status.symbol)
                    Text(transfer.status.isInFlight ? transfer.status.title : transfer.createdAt.dayAndTime)
                }
                .font(.caption)
                .foregroundStyle(transfer.status.isInFlight || transfer.status == .failed ? transfer.status.color : .secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(transfer.quote.receiveAmount.formattedCompact)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .strikethrough(transfer.status == .cancelled || transfer.status == .refunded)
                Text("−" + transfer.quote.sendAmount.formatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Compact live card for a transfer that's still moving.
struct InFlightCard: View {
    let transfer: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RecipientAvatar(recipient: transfer.recipient, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(transfer.quote.receiveAmount.formattedCompact) to \(transfer.recipient.fullName.components(separatedBy: " ").first ?? "")")
                        .font(.subheadline.weight(.semibold))
                    Text(transfer.status.title)
                        .font(.caption)
                        .foregroundStyle(transfer.status.color)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if transfer.isDelayed(at: context.date) {
                        Text("Delayed").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    } else {
                        Text("ETA \(transfer.estimatedDelivery.shortTime)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: transfer.status.progress)
                .tint(transfer.status.color)
                .animation(.easeInOut, value: transfer.status)
        }
        .card()
    }
}
