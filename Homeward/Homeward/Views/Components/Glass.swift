import SwiftUI

/// A solid marigold edge on a surface that is live: a transfer on its way, or sending.
struct BeamModifier: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.sun.opacity(0.55), lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func beam(active: Bool, cornerRadius: CGFloat = 24) -> some View { modifier(BeamModifier(active: active, cornerRadius: cornerRadius)) }
}

/// The app background: one flat colour, deep navy at night and warm paper by day.
struct AtmosphereBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        (scheme == .dark ? Color(red: 0.03, green: 0.03, blue: 0.08) : Color(red: 0.95, green: 0.95, blue: 0.93))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// "01 AMOUNT · 02 WHO · 03 REVIEW": quiet mono progress for the send flow.
struct StepsHeader: View {
    let current: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(["01 AMOUNT", "02 WHO", "03 REVIEW"].enumerated()), id: \.offset) { index, label in
                Text(label)
                    .foregroundStyle(index + 1 == current ? Theme.brand : index + 1 < current ? Color.secondary : Color.secondary.opacity(0.5))
            }
        }
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .tracking(1.2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of 3")
    }
}
