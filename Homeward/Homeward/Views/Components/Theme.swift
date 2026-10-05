import SwiftUI
import HomewardCore

/// "Money travels home the way you do": navy glass with ONE accent, marigold. `good` and `bad` are semantic only.
enum Theme {
    /// Accent for text and icons: marigold at night, a deeper amber by day so it stays readable on white.
    static let brand = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.00, green: 0.70, blue: 0.25, alpha: 1)
        : UIColor(red: 0.66, green: 0.37, blue: 0.00, alpha: 1) })
    /// Night indigo used behind the map, passes and the hero.
    static let brandDeep = Color(red: 0.07, green: 0.06, blue: 0.20)
    /// Marigold fill. Always pair with `ink` text.
    static let sun = Color(red: 1.00, green: 0.70, blue: 0.25)
    /// Semantic only: errors and attention.
    static let coral = Color(red: 1.00, green: 0.48, blue: 0.40)
    /// Semantic only: delivered and verified.
    static let mint = Color(red: 0.36, green: 0.89, blue: 0.69)
    static let ink = Color(red: 0.10, green: 0.07, blue: 0.02)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let night = LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.21), Color(red: 0.03, green: 0.03, blue: 0.09)],
                                      startPoint: .top, endPoint: .bottom)
    static let hero = night

    /// Plain solid colours for people without a photo. Deep enough to sit quietly next to real photos.
    static let solids: [Color] = [
        Color(red: 0.24, green: 0.31, blue: 0.56), Color(red: 0.48, green: 0.25, blue: 0.37),
        Color(red: 0.18, green: 0.42, blue: 0.37), Color(red: 0.54, green: 0.35, blue: 0.17),
        Color(red: 0.36, green: 0.26, blue: 0.57), Color(red: 0.29, green: 0.35, blue: 0.42),
        Color(red: 0.60, green: 0.29, blue: 0.24), Color(red: 0.17, green: 0.42, blue: 0.54),
    ]

    /// The same colour for the same person every time (a stable hash, unlike `hashValue`).
    static func solid(for seed: String) -> Color {
        let hash = seed.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
        return solids[Int(hash % UInt32(solids.count))]
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentSurface(cornerRadius: 24)
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
            .foregroundStyle(isEnabled ? Theme.ink : Color.secondary)
            .background(isEnabled ? Theme.sun : Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

/// The person's real photo, or a blank solid colour until one is added.
struct RecipientAvatar: View {
    let recipient: Recipient
    var size: CGFloat = 44
    @Environment(PhotoStore.self) private var photos

    var body: some View {
        PhotoCircle(image: photos.image(for: recipient.id), seed: recipient.id.uuidString, size: size)
    }
}

/// Your own photo, or a blank solid colour.
struct ProfileAvatar: View {
    var size: CGFloat = 44
    @Environment(PhotoStore.self) private var photos

    var body: some View {
        PhotoCircle(image: photos.image(for: PhotoStore.me), seed: PhotoStore.me, size: size)
    }
}

extension TransferStatus {
    var color: Color {
        switch self {
        case .awaitingFunding, .processing, .sentToPartner: return .blue
        case .delivered: return .green
        case .cancelled: return .secondary
        case .failed: return .orange
        case .refunded: return .secondary
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
