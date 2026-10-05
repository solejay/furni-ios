import SwiftUI
import HomewardCore

/// Airport departures-board styling for transfer history. The board is a physical object, so it stays dark.
enum Board {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.08)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.36)
    static let dim = Color(red: 0.66, green: 0.64, blue: 0.78)
}

struct DepartureRow: View {
    let transfer: Transfer

    private var timeLabel: String {
        Calendar.current.isDateInToday(transfer.createdAt)
            ? transfer.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : transfer.createdAt.formatted(.dateTime.day(.twoDigits).month(.abbreviated)).uppercased()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(timeLabel).frame(width: 52, alignment: .leading)
            Text(Place.destination(for: transfer.recipient.country).code)
                .fontWeight(.bold)
                .foregroundStyle(Theme.cream)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(transfer.recipient.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text("\(transfer.quote.receiveAmount.formattedCompact) · \(transfer.quote.sendAmount.formatted)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Board.dim)
            }
            Spacer(minLength: 4)
            DepartureStatus(transfer: transfer)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .foregroundStyle(Board.amber)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct DepartureStatus: View {
    let transfer: Transfer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let look = style(at: context.date)
            Text(look.label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(look.fg)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(look.bg, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private func style(at date: Date) -> (label: String, fg: Color, bg: Color) {
        switch transfer.status {
        case .delivered: return ("LANDED", Theme.mint, Theme.mint.opacity(0.12))
        case .cancelled: return ("CANCELLED", Board.dim, Board.dim.opacity(0.12))
        case .refunded: return ("REFUNDED", Board.dim, Board.dim.opacity(0.12))
        case .failed: return ("ATTENTION", Theme.coral, Theme.coral.opacity(0.15))
        case .awaitingFunding, .processing, .sentToPartner:
            if transfer.isDelayed(at: date) { return ("DELAYED", Theme.coral, Theme.coral.opacity(0.15)) }
            return (transfer.status == .awaitingFunding ? "BOARDING" : "IN FLIGHT", Board.background, Board.amber)
        }
    }
}

/// Split-flap style heading.
struct FlapText: View {
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Board.amber)
                    .frame(width: 17, height: 24)
                    .background(Color(red: 0.10, green: 0.09, blue: 0.19), in: RoundedRectangle(cornerRadius: 3))
                    .overlay(Rectangle().fill(.black.opacity(0.6)).frame(height: 1))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
