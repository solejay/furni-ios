import SwiftUI
import HomewardCore

/// One transfer in a list: who, when, where, how much arrived and its status in plain words.
struct ActivityRow: View {
    let transfer: Transfer

    var body: some View {
        HStack(spacing: 12) {
            RecipientAvatar(recipient: transfer.recipient)
            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.recipient.fullName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(transfer.createdAt.formatted(.dateTime.day().month(.abbreviated))) · \(transfer.recipient.country.flag) \(Place.destination(for: transfer.recipient.country).city)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(transfer.quote.receiveAmount.formattedCompact)
                    .font(.body.weight(.medium).monospacedDigit())
                    .strikethrough(transfer.status == .cancelled || transfer.status == .refunded)
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    let model = ReceiptModel(transfer: transfer, now: context.date)
                    StatusPill(text: model.status, tone: model.tone)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
