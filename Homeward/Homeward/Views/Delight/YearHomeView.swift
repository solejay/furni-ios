import SwiftUI
import HomewardCore

/// A story-style recap of twelve months of sending home. Tap or swipe through.
struct YearHomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        let review = YearInReview.compute(transfers: store.ledger.transfers, engine: store.engine, now: Date(), calendar: store.calendar)
        ZStack(alignment: .top) {
            if let review {
                let pages = slides(review)
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pages[index].tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .onTapGesture { withAnimation { page = min(page + 1, pages.count - 1) } }

                HStack(spacing: 4) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule().fill(.white.opacity(index <= page ? 0.95 : 0.35)).frame(height: 3)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            } else {
                ContentUnavailableView("Your year starts with one transfer", systemImage: "sparkles",
                                       description: Text("Send money home and your recap will appear here."))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 20)
            .padding(.trailing)
            .accessibilityLabel("Close")
        }
        .preferredColorScheme(.dark)
    }

    private func slides(_ r: YearInReview) -> [AnyView] {
        let first = store.ledger.profile.firstName
        var result: [AnyView] = []
        result.append(AnyView(Slide(colors: [Theme.brand, Theme.brandDeep], eyebrow: "Your year home", big: "\(first), you sent love home \(r.transferCount) times.",
                                    detail: "Here's what that looked like over the last twelve months.")))
        result.append(AnyView(Slide(colors: [Color(red: 0.11, green: 0.16, blue: 0.42), .black], eyebrow: "In total", big: r.totalSent.formattedCompact,
                                    detail: "arrived as " + r.deliveredByCurrency.map(\.formattedCompact).joined(separator: " + "))))
        if let top = r.recipients.first {
            let name = top.recipient.nickname ?? top.recipient.fullName.components(separatedBy: " ").first ?? ""
            result.append(AnyView(Slide(colors: [Color(red: 0.86, green: 0.33, blue: 0.43), Color(red: 0.35, green: 0.08, blue: 0.18)], eyebrow: "Your number one",
                                        big: name, detail: "\(top.transfers) transfers · \(top.delivered.formattedCompact) delivered. \(r.recipients.count) people supported in all.")))
        }
        if r.savedVersusBank.isPositive {
            result.append(AnyView(Slide(colors: [Theme.sun, Color(red: 0.62, green: 0.32, blue: 0.02)], eyebrow: "Kept in the family", big: r.savedVersusBank.formattedCompact,
                                        detail: "more reached your family than if you'd used a typical bank (3.5% margin + $15 fee each time).")))
        }
        if let busiest = r.busiestMonth {
            let month = store.calendar.monthSymbols[busiest.month - 1]
            result.append(AnyView(Slide(colors: [Color(red: 0.20, green: 0.45, blue: 0.80), Color(red: 0.05, green: 0.12, blue: 0.30)], eyebrow: "Most generous month",
                                        big: month, detail: "You sent \(busiest.sent.formattedCompact) in \(month).")))
        }
        if let fastest = r.fastestDelivery {
            result.append(AnyView(Slide(colors: [Color(red: 0.45, green: 0.30, blue: 0.80), Color(red: 0.12, green: 0.06, blue: 0.28)], eyebrow: "Fastest delivery",
                                        big: TransferDetailView.duration(fastest), detail: "From your tap to their account.")))
        }
        result.append(AnyView(Slide(colors: [Theme.brand, .black], eyebrow: "Thank you", big: "Home is closer than it looks.",
                                    detail: "Here's to another year of looking after the people you love.")))
        return result
    }
}

private struct Slide: View {
    let colors: [Color]
    let eyebrow: String
    let big: String
    let detail: String
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 420)
                .offset(x: 160, y: -380)
            VStack(alignment: .leading, spacing: 16) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .opacity(0.8)
                Text(big)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(4)
                    .offset(y: appeared ? 0 : 24)
                    .opacity(appeared ? 1 : 0)
                Text(detail)
                    .font(.title3)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(28)
            .padding(.bottom, 60)
        }
        .onAppear { withAnimation(.spring(duration: 0.7).delay(0.1)) { appeared = true } }
        .onDisappear { appeared = false }
    }
}

/// Entry card on Home.
struct YearHomeCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.sun)
                    .frame(width: 44, height: 44)
                    .background(Theme.sun.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your year home").font(.subheadline.weight(.semibold))
                    Text("Twelve months of sending love, in one story").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Theme.brand)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}
