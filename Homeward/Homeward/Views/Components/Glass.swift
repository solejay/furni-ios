import SwiftUI

/// A light that travels the edge of a surface. Only for live states: a transfer on its way, sending.
struct BeamModifier: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    let turn = (timeline.date.timeIntervalSinceReferenceDate / 3.2).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AngularGradient(stops: [
                            Gradient.Stop(color: .clear, location: 0),
                            Gradient.Stop(color: .clear, location: 0.64),
                            Gradient.Stop(color: Theme.sun.opacity(0.9), location: 0.82),
                            Gradient.Stop(color: Color(red: 1, green: 0.95, blue: 0.85), location: 0.86),
                            Gradient.Stop(color: .clear, location: 0.9),
                            Gradient.Stop(color: .clear, location: 1),
                        ], center: .center, angle: .degrees(turn * 360)), lineWidth: 1.5)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func beam(active: Bool, cornerRadius: CGFloat = 24) -> some View { modifier(BeamModifier(active: active, cornerRadius: cornerRadius)) }
}

/// Deep navy (or warm paper by day) with slow vertical light folds and a marigold bloom low on the right.
struct AtmosphereBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .color(dark ? Color(red: 0.03, green: 0.03, blue: 0.08) : Color(red: 0.95, green: 0.95, blue: 0.93)))
                context.blendMode = dark ? .screen : .multiply
                for i in 0..<6 {
                    let phase = Double(i)
                    let x = size.width * (0.25 + phase * 0.13) + CGFloat(sin(t * 0.07 + phase * 1.3)) * size.width * 0.08
                    let w = size.width * (0.16 + CGFloat(i % 3) * 0.05)
                    let alpha = (dark ? 0.07 : 0.05) * (0.6 + 0.4 * sin(t * 0.11 + phase))
                    let rect = CGRect(x: x - w, y: 0, width: w * 2, height: size.height * 1.5)
                    context.fill(Path(ellipseIn: rect), with: .linearGradient(
                        Gradient(colors: [Theme.sun.opacity(0), Theme.sun.opacity(alpha * 0.5), Theme.sun.opacity(alpha * 1.6)]),
                        startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x, y: size.height)))
                }
                let corner = CGPoint(x: size.width * 0.92, y: size.height * 1.02)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [Theme.sun.opacity(dark ? 0.16 : 0.12), Theme.sun.opacity(0)]),
                    center: corner, startRadius: 0, endRadius: max(size.width, size.height) * 0.55))
            }
        }
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
