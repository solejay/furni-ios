import SwiftUI

/// Slide to confirm: deliberate friction before money moves, so a stray tap never sends anything.
/// VoiceOver users get a single "Send" action instead of a drag.
struct SlideToSend: View {
    let title: String
    var isBusy = false
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var shimmer = false
    private let thumb: CGFloat = 58
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let maxOffset = max(0, geo.size.width - thumb - inset * 2)
            ZStack(alignment: .leading) {
                // Track stays plain, like the system slider; only the knob is glass (no glass on glass).
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Theme.sun.opacity(0.22))
                    .frame(width: isBusy ? geo.size.width : offset + thumb + inset * 2)
                Text(isBusy ? "Sending…" : title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .opacity(isBusy ? 1 : 1 - Double(offset / max(maxOffset, 1)) * 0.9)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumb)
                // Thumb: tinted, interactive glass; the one prominent element on the screen.
                Image(systemName: "paperplane.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: thumb, height: thumb)
                    .liquidGlass(Circle(), tint: Theme.sun, interactive: true)
                    .offset(x: inset + (isBusy ? maxOffset : offset))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isBusy else { return }
                                offset = min(maxOffset, max(0, value.translation.width))
                            }
                            .onEnded { _ in
                                guard !isBusy else { return }
                                if offset > maxOffset * 0.86 {
                                    offset = maxOffset
                                    action()
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: 68)
        .sensoryFeedback(.impact(weight: .medium), trigger: offset >= 1 && offset < 2)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isBusy { action() } }
        .onChange(of: isBusy) { if !isBusy { offset = 0 } }
    }
}

/// Full-screen confirmation after sending: a ring draws, then a checkmark.
struct SentView: View {
    let amount: String
    let recipientName: String
    let city: String
    @State private var ring: CGFloat = 0
    @State private var tick: CGFloat = 0

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.06).ignoresSafeArea()
            RadialGradient(colors: [Theme.sun.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 260).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Theme.sun.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: ring).stroke(Theme.sun, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Checkmark().trim(from: 0, to: tick).stroke(Theme.sun, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .padding(30)
                }
                .frame(width: 120, height: 120)
                Text("Sent").font(.system(size: 44, design: .serif).italic())
                Text("\(amount) is on its way to \(recipientName) in \(city).")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .padding(.horizontal, 40)
            }
            .foregroundStyle(Theme.cream)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.45).delay(0.6)) { tick = 1 }
        }
    }

    private struct Checkmark: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY - rect.height * 0.15))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15))
            }
        }
    }
}
