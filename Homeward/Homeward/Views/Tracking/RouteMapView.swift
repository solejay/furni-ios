import SwiftUI
import HomewardCore

/// Night-sky dot map with an arc from your city to everyone you send to. Sparks travel each route,
/// and a transfer on its way leaves a warm trail.
struct RouteMapView: View {
    let origin: Place
    let destinations: [Place]
    /// Destination codes with a transfer in the air, and how far along it is (0...1).
    let inFlight: [String: Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Map of your routes home from \(origin.city) to \(destinations.map(\.city).joined(separator: ", "))")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let lons = [origin.lon] + destinations.map(\.lon), lats = [origin.lat] + destinations.map(\.lat)
        let minLon = (lons.min() ?? 0) - 8, maxLon = (lons.max() ?? 0) + 8
        let minLat = (lats.min() ?? 0) - 6, maxLat = (lats.max() ?? 0) + 6
        let scale = min(size.width / (maxLon - minLon), size.height * 0.40 / (maxLat - minLat))
        let cx = (minLon + maxLon) / 2, cy = (minLat + maxLat) / 2
        func project(_ lon: Double, _ lat: Double) -> CGPoint {
            CGPoint(x: size.width / 2 + (lon - cx) * scale, y: size.height * 0.54 - (lat - cy) * scale)
        }

        let dot = max(1, scale * LandMask.step * 0.22)
        var land = Path()
        for point in LandMask.points {
            let p = project(point.lon, point.lat)
            guard p.x > -4, p.x < size.width + 4, p.y > -4, p.y < size.height + 4 else { continue }
            land.addEllipse(in: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2))
        }
        context.fill(land, with: .color(Theme.cream.opacity(0.16)))

        let a = project(origin.lon, origin.lat)
        for (index, destination) in destinations.enumerated() {
            let b = project(destination.lon, destination.lat)
            let distance = hypot(b.x - a.x, b.y - a.y)
            let control = CGPoint(x: (a.x + b.x) / 2 + (b.y - a.y) * 0.18, y: (a.y + b.y) / 2 - distance * 0.28 - 10)
            var arc = Path()
            arc.move(to: a)
            arc.addQuadCurve(to: b, control: control)
            context.stroke(arc, with: .linearGradient(Gradient(colors: [Theme.sun.opacity(0.08), Theme.sun.opacity(0.75)]), startPoint: a, endPoint: b), lineWidth: 1.6)

            func point(_ t: Double) -> CGPoint {
                CGPoint(x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * control.x + t * t * b.x,
                        y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * control.y + t * t * b.y)
            }
            if !reduceMotion {
                let s = (time * 0.22 + Double(index) * 0.31).truncatingRemainder(dividingBy: 1)
                let p = point(s)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6)),
                             with: .color(Color(red: 1, green: 0.84, blue: 0.55).opacity(0.9 * sin(s * .pi))))
            }
            if let progress = inFlight[destination.code] {
                for k in stride(from: 14, through: 0, by: -1) {
                    let p = point(max(0, progress - Double(k) * 0.012))
                    let r = 1 + (1 - Double(k) / 14) * 2.6
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Color(red: 1, green: 0.95, blue: 0.85).opacity(0.06 + (1 - Double(k) / 14) * 0.8)))
                }
            }
            let pulse = reduceMotion ? 0 : (time * 0.8 + Double(index) * 0.25).truncatingRemainder(dividingBy: 1)
            let ring = 3 + pulse * 12
            context.stroke(Path(ellipseIn: CGRect(x: b.x - ring, y: b.y - ring, width: ring * 2, height: ring * 2)),
                           with: .color(Theme.sun.opacity(0.55 * (1 - pulse))), lineWidth: 1.2)
            context.fill(Path(ellipseIn: CGRect(x: b.x - 2.6, y: b.y - 2.6, width: 5.2, height: 5.2)), with: .color(Theme.sun))
            context.draw(Text(destination.city).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundColor(Theme.cream.opacity(0.85)),
                         at: CGPoint(x: b.x + 6, y: b.y), anchor: .leading)
        }

        var glow = context
        glow.addFilter(.shadow(color: Theme.sun, radius: 7))
        glow.fill(Path(ellipseIn: CGRect(x: a.x - 4.5, y: a.y - 4.5, width: 9, height: 9)), with: .color(Theme.sun))
        context.draw(Text(origin.city).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Theme.cream),
                     at: CGPoint(x: a.x + 8, y: a.y - 8), anchor: .leading)
    }
}
