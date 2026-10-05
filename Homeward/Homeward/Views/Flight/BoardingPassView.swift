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

        /// How warm the pass glows: brighter while money is moving.
        var warmth: Double {
            switch self {
            case .ready: return 0.26
            case .boarding: return 0.22
            case .boarded: return 0.34
            case .inFlight: return 0.42
            case .landed: return 0.16
            case .cancelled: return 0.04
            case .refunded: return 0.06
            case .attention: return 0.1
            }
        }

        var isLive: Bool { self == .boarding || self == .boarded || self == .inFlight }

        var dot: Color {
            switch self {
            case .landed: return Theme.mint
            case .cancelled, .refunded: return .secondary
            case .attention: return Theme.coral
            default: return Theme.sun
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
                    HStack(spacing: 6) {
                        Circle().fill(model.state.dot).frame(width: 7, height: 7)
                        Text(model.state.label.uppercased())
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                }
                .opacity(0.9)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.from.code).font(.system(size: 40, weight: .medium)).tracking(-1.6)
                        Text(model.from.city).font(.caption).opacity(0.75)
                    }
                    FlightPath(progress: model.progress).frame(height: 44)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.to.code).font(.system(size: 40, weight: .medium)).tracking(-1.6)
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
            .background {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.24), Color(red: 0.035, green: 0.04, blue: 0.11)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Theme.sun.opacity(model.state.warmth), .clear], center: UnitPoint(x: 0.9, y: -0.1), startRadius: 0, endRadius: 280)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow { field("01", "Passenger", model.passenger); field("02", "Flight", model.flight) }
                GridRow { field("03", "Cargo", model.cargo, big: true); field("04", "Fare", model.fare) }
                GridRow { field("05", "Rate", model.rate); field("06", "Class", model.travelClass) }
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
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassSurface(cornerRadius: 28)
        .beam(active: model.state.isLive, cornerRadius: 28)
        .accessibilityElement(children: .combine)
        .animation(.spring(duration: 0.8), value: model.progress)
    }

    private func field(_ number: String, _ key: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(number + "  ").foregroundColor(.secondary) + Text(key.uppercased()).foregroundColor(Color.secondary.opacity(0.7)))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced)).tracking(1.4)
            Text(value)
                .font(big ? .system(size: 19, weight: .medium).monospacedDigit() : .subheadline.weight(.medium))
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
                arc.trim(from: 0, to: t).stroke(Theme.sun, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(Theme.sun).frame(width: 6, height: 6).position(p0)
                Circle().stroke(.white, lineWidth: 1.5).frame(width: 6, height: 6).position(p2)
                Image(systemName: "airplane")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.6))
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
