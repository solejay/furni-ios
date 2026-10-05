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
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.sun)
                    .frame(width: isBusy ? geo.size.width : offset + thumb + inset * 2)
                Text(isBusy ? "Sending…" : title)
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .opacity(isBusy ? 1 : 1 - Double(offset / max(maxOffset, 1)) * 0.9)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumb)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.sun)
                    .frame(width: thumb, height: thumb)
                    .overlay(Image(systemName: "airplane").font(.title3.weight(.bold)).foregroundStyle(Theme.ink))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
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

/// Full-screen "wheels up" moment after sending.
struct TakeoffView: View {
    let from: Place
    let to: Place
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    FlightPath(progress: progress).frame(height: 160).foregroundStyle(Theme.sun)
                }
                .padding(.horizontal, 30)
                HStack {
                    Text(from.code)
                    Spacer()
                    Text(to.code)
                }
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .padding(.horizontal, 30)
                Spacer()
                VStack(spacing: 6) {
                    Text("Wheels up").font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("to \(to.city)").font(.system(.title2, design: .serif).italic()).foregroundStyle(Theme.sun)
                }
                .padding(.bottom, 80)
            }
            .foregroundStyle(Theme.cream)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.5)) { progress = 1 } }
    }
}
