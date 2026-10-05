import SwiftUI
import HomewardCore

enum Theme {
    static let brand = Color(red: 0.03, green: 0.42, blue: 0.31)
    static let brandDeep = Color(red: 0.01, green: 0.24, blue: 0.18)
    static let sun = Color(red: 0.98, green: 0.69, blue: 0.24)
    static let hero = LinearGradient(colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let avatarPalette: [Color] = [
        Color(red: 0.93, green: 0.45, blue: 0.27), Color(red: 0.20, green: 0.55, blue: 0.85),
        Color(red: 0.55, green: 0.38, blue: 0.85), Color(red: 0.10, green: 0.62, blue: 0.52),
        Color(red: 0.86, green: 0.33, blue: 0.53), Color(red: 0.80, green: 0.58, blue: 0.10),
    ]
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(isEnabled ? Theme.brand : Color.gray.opacity(0.45), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

struct FlagBadge: View {
    let currency: Currency
    var size: CGFloat = 28

    var body: some View {
        Text(currency.flag)
            .font(.system(size: size * 0.62))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(.tertiarySystemFill)))
            .accessibilityHidden(true)
    }
}

struct RecipientAvatar: View {
    let recipient: Recipient
    var size: CGFloat = 44

    private var color: Color {
        let seed = recipient.fullName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Theme.avatarPalette[seed % Theme.avatarPalette.count]
    }

    var body: some View {
        Text(recipient.initials)
            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
            .overlay(alignment: .bottomTrailing) {
                Text(recipient.country.flag)
                    .font(.system(size: size * 0.3))
                    .offset(x: 2, y: 2)
            }
            .accessibilityHidden(true)
    }
}

extension TransferStatus {
    var color: Color {
        switch self {
        case .awaitingFunding, .processing, .sentToPartner: return .blue
        case .delivered: return .green
        case .cancelled: return .secondary
        case .failed: return .orange
        case .refunded: return .purple
        }
    }

    var symbol: String {
        switch self {
        case .awaitingFunding: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .sentToPartner: return "paperplane.fill"
        case .delivered: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .refunded: return "arrow.uturn.backward.circle.fill"
        }
    }

    /// Rough progress for list rows.
    var progress: Double {
        switch self {
        case .awaitingFunding: return 0.15
        case .processing: return 0.45
        case .sentToPartner: return 0.8
        default: return 1
        }
    }
}

struct StatusBadge: View {
    let status: TransferStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let action {
                Button(action.title, action: action.run).font(.subheadline.weight(.medium))
            }
        }
    }
}

/// "Rate locked · 29:41" countdown that ticks every second.
struct RateLockCountdown: View {
    let quote: Quote

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = quote.timeRemaining(at: context.date)
            let expired = remaining <= 0
            Label(expired ? "Rate expired: refresh for a new quote"
                          : "Rate locked for \(Self.format(remaining))",
                  systemImage: expired ? "lock.open" : "lock.fill")
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(expired ? .orange : Theme.brand)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
    var dayAndTime: String { formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
}
