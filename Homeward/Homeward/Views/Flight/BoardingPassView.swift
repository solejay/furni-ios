import SwiftUI
import HomewardCore

/// Everything a boarding pass shows, for a transfer that exists or one about to be sent.
struct PassModel {
    enum State {
        case ready, boarding, boarded, inFlight, landed, cancelled, refunded, attention

        var label: String {
            switch self {
            case .ready: return "Ready to board"
            case .boarding: return "Boarding"
            case .boarded: return "Boarded"
            case .inFlight: return "In flight"
            case .landed: return "Landed"
            case .cancelled: return "Cancelled"
            case .refunded: return "Refunded"
            case .attention: return "Attention"
            }
        }

        var colors: [Color] {
            switch self {
            case .ready: return [Color(red: 0.17, green: 0.14, blue: 0.44), Color(red: 0.05, green: 0.04, blue: 0.16)]
            case .boarding: return [Color(red: 0.23, green: 0.18, blue: 0.56), Color(red: 0.09, green: 0.07, blue: 0.24)]
            case .boarded, .inFlight: return [Color(red: 1.0, green: 0.54, blue: 0.30), Color(red: 0.65, green: 0.19, blue: 0.48)]
            case .landed: return [Color(red: 0.07, green: 0.63, blue: 0.48), Color(red: 0.04, green: 0.24, blue: 0.20)]
            case .cancelled: return [Color(red: 0.29, green: 0.28, blue: 0.40), Color(red: 0.14, green: 0.13, blue: 0.23)]
            case .refunded: return [Color(red: 0.48, green: 0.32, blue: 0.84), Color(red: 0.16, green: 0.09, blue: 0.40)]
            case .attention: return [Color(red: 0.84, green: 0.27, blue: 0.18), Color(red: 0.29, green: 0.06, blue: 0.06)]
            }
        }
    }

    let state: State
    let from: Place
    let to: Place
    let progress: Double
    let departs: String
    let lands: String
    let passenger: String
    let flight: String
    let cargo: String
    let fare: String
    let rate: String
    let travelClass: String
    let stubLabel: String
    let stubValue: String

    init(transfer t: Transfer) {
        switch t.status {
        case .awaitingFunding: state = .boarding
        case .processing: state = .boarded
        case .sentToPartner: state = .inFlight
        case .delivered: state = .landed
        case .cancelled: state = .cancelled
        case .refunded: state = .refunded
        case .failed: state = .attention
        }
        from = Place.origin(for: t.quote.source)
        to = Place.destination(for: t.recipient.country)
        progress = (t.status == .cancelled || t.status == .refunded) ? 0 : t.status.progress
        departs = "Departs " + t.createdAt.shortTime
        if let landed = t.date(of: .delivered) {
            lands = "Landed " + landed.shortTime
        } else {
            lands = t.status.isInFlight ? "Lands ~" + t.estimatedDelivery.shortTime : ""
        }
        passenger = t.recipient.fullName
        flight = t.reference
        cargo = t.quote.receiveAmount.formatted
        fare = t.quote.sendAmount.formatted + (t.quote.fee.isZero ? " · no fee" : "")
        rate = MoneyFormatter.rate(t.quote.customerRate)
        travelClass = t.purpose.title
        stubLabel = t.payoutReference == nil ? "Gate" : "Payout ref"
        stubValue = t.payoutReference ?? t.recipient.payout.summary
    }

    init(quote: Quote, recipient: Recipient, funding: FundingSource, purpose: TransferPurpose) {
        state = .ready
        from = Place.origin(for: quote.source)
        to = Place.destination(for: recipient.country)
        progress = 0
        departs = "Departs on your slide"
        lands = DeliveryEstimate.for(recipient.payout, funding: funding).label
        passenger = recipient.fullName
        flight = "HW-······"
        cargo = quote.receiveAmount.formatted
        fare = quote.sendAmount.formatted + (quote.fee.isZero ? " · no fee" : " incl. \(quote.fee.formatted) fee")
        rate = MoneyFormatter.rate(quote.customerRate)
        travelClass = purpose.title
        stubLabel = recipient.verifiedName == nil ? "Gate" : "Name check"
        stubValue = recipient.verifiedName.map { "✓ " + $0 } ?? recipient.payout.summary
    }
}

struct BoardingPassView: View {
    let model: PassModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("HOMEWARD ✦ BOARDING PASS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.6)
                    Spacer()
                    Text(model.state.label.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                }
                .opacity(0.9)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.from.code).font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text(model.from.city).font(.caption).opacity(0.75)
                    }
                    FlightPath(progress: model.progress).frame(height: 44)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.to.code).font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text(model.to.city).font(.caption).opacity(0.75)
                    }
                }
                HStack {
                    Text(model.departs)
                    Spacer()
                    Text(model.lands)
                }
                .font(.caption.monospacedDigit())
                .opacity(0.85)
            }
            .padding(18)
            .foregroundStyle(Theme.cream)
            .background(LinearGradient(colors: model.state.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow { field("Passenger", model.passenger); field("Flight", model.flight) }
                GridRow { field("Cargo", model.cargo, big: true); field("Fare", model.fare) }
                GridRow { field("Rate", model.rate); field("Class", model.travelClass) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Perforation()

            HStack(spacing: 14) {
                Barcode(seed: model.flight).frame(height: 44)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.stubLabel).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Text(model.stubValue).font(.system(size: 12, weight: .bold, design: .monospaced)).multilineTextAlignment(.trailing)
                }
            }
            .padding(18)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .animation(.spring(duration: 0.8), value: model.progress)
    }

    private func field(_ key: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased()).font(.system(size: 9.5, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary)
            Text(value)
                .font(big ? .system(size: 18, weight: .bold, design: .rounded).monospacedDigit() : .subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Dashed arc with a solid section and a plane at `progress`.
struct FlightPath: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let p0 = CGPoint(x: 6, y: h * 0.86), p1 = CGPoint(x: w / 2, y: -h * 0.2), p2 = CGPoint(x: w - 6, y: h * 0.86)
            let t = min(1, max(0, progress))
            let point = CGPoint(x: (1 - t) * (1 - t) * p0.x + 2 * (1 - t) * t * p1.x + t * t * p2.x,
                                y: (1 - t) * (1 - t) * p0.y + 2 * (1 - t) * t * p1.y + t * t * p2.y)
            let dx = 2 * (1 - t) * (p1.x - p0.x) + 2 * t * (p2.x - p1.x), dy = 2 * (1 - t) * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
            let arc = Path { path in
                path.move(to: p0)
                path.addQuadCurve(to: p2, control: p1)
            }
            ZStack {
                arc.stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.6, dash: [3, 4]))
                arc.trim(from: 0, to: t).stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(.white).frame(width: 6, height: 6).position(p0)
                Circle().stroke(.white, lineWidth: 1.5).frame(width: 6, height: 6).position(p2)
                Image(systemName: "airplane")
                    .font(.system(size: 15, weight: .bold))
                    .rotationEffect(.radians(atan2(dy, dx)))
                    .position(point)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Perforation: View {
    var body: some View {
        ZStack {
            Line().stroke(Color(.separator), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])).frame(height: 1).padding(.horizontal, 18)
            HStack {
                Circle().fill(Color(.systemGroupedBackground)).frame(width: 24, height: 24).offset(x: -12)
                Spacer()
                Circle().fill(Color(.systemGroupedBackground)).frame(width: 24, height: 24).offset(x: 12)
            }
        }
        .frame(height: 24)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

private struct Barcode: View {
    let seed: String

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: UInt64(seed.unicodeScalars.reduce(7) { $0 &* 31 &+ UInt64($1.value) }))
            var x: CGFloat = 0
            var draw = true
            while x < size.width {
                let width = CGFloat(1 + rng.next() % 4)
                if draw { context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(.primary)) }
                x += width + 1
                draw.toggle()
            }
        }
        .accessibilityHidden(true)
    }
}
