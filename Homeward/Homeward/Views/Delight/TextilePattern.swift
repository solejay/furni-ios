import SwiftUI
import HomewardCore

/// Generative patterns inspired by each recipient country's textile traditions. Every transfer gets its own
/// variation (seeded by its id), so no two postcards are the same.
struct TextilePattern: View {
    enum Style {
        /// Yoruba adire: indigo resist-dye with circles, ladders and dot rings.
        case adire
        /// Ghanaian kente: woven strips of gold, green, red and black blocks.
        case kente
        /// Maasai beadwork: bands of coloured beads on red.
        case beadwork
        /// Indian bandhani: tie-dye dot clusters on a deep ground.
        case bandhani

        init(country: Country) {
            switch country {
            case .nigeria: self = .adire
            case .ghana: self = .kente
            case .kenya: self = .beadwork
            case .india: self = .bandhani
            }
        }

        var name: String {
            switch self {
            case .adire: return "Adire"
            case .kente: return "Kente"
            case .beadwork: return "Maasai beadwork"
            case .bandhani: return "Bandhani"
            }
        }
    }

    let style: Style
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: seed)
            switch style {
            case .adire: Self.drawAdire(&context, size, &rng)
            case .kente: Self.drawKente(&context, size, &rng)
            case .beadwork: Self.drawBeadwork(&context, size, &rng)
            case .bandhani: Self.drawBandhani(&context, size, &rng)
            }
        }
        .accessibilityLabel("\(style.name)-inspired pattern")
    }

    static func seed(from id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { $0.load(as: UInt64.self) }
    }

    private static func random(_ rng: inout SplitMix64, _ upper: Int) -> Int { Int(rng.next() % UInt64(upper)) }

    // MARK: Adire

    private static func drawAdire(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SplitMix64) {
        let indigo = Color(red: 0.11, green: 0.16, blue: 0.42)
        let ink = Color(red: 0.80, green: 0.85, blue: 0.97)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(indigo))
        let cell: CGFloat = size.width / 4
        let rows = Int(ceil(size.height / cell))
        for row in 0..<rows {
            for column in 0..<4 {
                let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell).insetBy(dx: 6, dy: 6)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let stroke = StrokeStyle(lineWidth: 2.2, lineCap: .round)
                switch random(&rng, 4) {
                case 0: // concentric circles
                    for ring in 1...3 {
                        let r = rect.width / 2 * CGFloat(ring) / 3
                        context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(ink), style: stroke)
                    }
                case 1: // ring of dots around a dot
                    for i in 0..<10 {
                        let angle = Double(i) / 10 * 2 * .pi
                        let p = CGPoint(x: center.x + cos(angle) * rect.width * 0.36, y: center.y + sin(angle) * rect.width * 0.36)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(ink))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(ink))
                case 2: // ladder
                    var path = Path()
                    path.move(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.maxY))
                    for step in 0..<5 {
                        let y = rect.minY + rect.height * (CGFloat(step) + 0.5) / 5
                        path.move(to: CGPoint(x: rect.minX + rect.width * 0.25, y: y))
                        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.25, y: y))
                    }
                    context.stroke(path, with: .color(ink), style: stroke)
                default: // spiral
                    var path = Path()
                    for i in 0...60 {
                        let t = Double(i) / 60
                        let angle = t * 5 * .pi
                        let p = CGPoint(x: center.x + cos(angle) * rect.width * 0.45 * t, y: center.y + sin(angle) * rect.width * 0.45 * t)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(ink), style: stroke)
                }
            }
        }
    }

    // MARK: Kente

    private static func drawKente(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SplitMix64) {
        let gold = Color(red: 0.96, green: 0.73, blue: 0.13)
        let green = Color(red: 0.05, green: 0.50, blue: 0.27)
        let red = Color(red: 0.78, green: 0.13, blue: 0.13)
        let black = Color(red: 0.08, green: 0.07, blue: 0.06)
        let palette = [gold, green, red, black]
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(gold))
        let strip: CGFloat = size.width / 5
        for column in 0..<5 {
            var y: CGFloat = 0
            while y < size.height {
                let height = CGFloat(18 + random(&rng, 4) * 10)
                let block = CGRect(x: CGFloat(column) * strip, y: y, width: strip, height: height)
                context.fill(Path(block), with: .color(palette[random(&rng, palette.count)]))
                // Thin weft stripes across the block.
                if random(&rng, 2) == 0 {
                    for line in stride(from: block.minY + 4, to: block.maxY, by: 6) {
                        context.fill(Path(CGRect(x: block.minX, y: line, width: strip, height: 2)), with: .color(palette[random(&rng, palette.count)]))
                    }
                } else {
                    // Zigzag motif.
                    var path = Path()
                    path.move(to: CGPoint(x: block.minX, y: block.midY))
                    for i in 1...4 {
                        path.addLine(to: CGPoint(x: block.minX + strip * CGFloat(i) / 4, y: i % 2 == 0 ? block.midY : block.minY + 4))
                    }
                    context.stroke(path, with: .color(palette[random(&rng, palette.count)]), lineWidth: 3)
                }
                y += height
            }
            context.fill(Path(CGRect(x: CGFloat(column) * strip, y: 0, width: 1.5, height: size.height)), with: .color(black.opacity(0.5)))
        }
    }

    // MARK: Beadwork

    private static func drawBeadwork(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SplitMix64) {
        let red = Color(red: 0.74, green: 0.10, blue: 0.12)
        let beads = [Color.white, Color(red: 0.12, green: 0.36, blue: 0.75), Color(red: 0.98, green: 0.78, blue: 0.16),
                     Color(red: 0.09, green: 0.55, blue: 0.30), Color(red: 0.95, green: 0.45, blue: 0.10)]
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red))
        let bead: CGFloat = 9
        var y: CGFloat = 10
        while y < size.height {
            let rowsInBand = 2 + random(&rng, 3)
            let colorA = beads[random(&rng, beads.count)]
            let colorB = beads[random(&rng, beads.count)]
            for r in 0..<rowsInBand {
                let offset: CGFloat = r % 2 == 0 ? 0 : bead / 2
                var x = offset + bead / 2
                var index = 0
                while x < size.width {
                    let color = (index / 3) % 2 == 0 ? colorA : colorB
                    context.fill(Path(ellipseIn: CGRect(x: x - bead / 2 + 1, y: y + CGFloat(r) * bead, width: bead - 2, height: bead - 2)), with: .color(color))
                    x += bead
                    index += 1
                }
            }
            y += CGFloat(rowsInBand) * bead + 14
            // A row of triangles between bands.
            var triangles = Path()
            var x: CGFloat = 0
            while x < size.width {
                triangles.move(to: CGPoint(x: x, y: y - 4))
                triangles.addLine(to: CGPoint(x: x + 8, y: y - 12))
                triangles.addLine(to: CGPoint(x: x + 16, y: y - 4))
                triangles.closeSubpath()
                x += 20
            }
            context.fill(triangles, with: .color(Color.white.opacity(0.85)))
        }
    }

    // MARK: Bandhani

    private static func drawBandhani(_ context: inout GraphicsContext, _ size: CGSize, _ rng: inout SplitMix64) {
        let grounds = [Color(red: 0.62, green: 0.05, blue: 0.30), Color(red: 0.80, green: 0.18, blue: 0.10), Color(red: 0.10, green: 0.30, blue: 0.45)]
        let ground = grounds[random(&rng, grounds.count)]
        let dot = Color(red: 1.0, green: 0.93, blue: 0.75)
        let accent = Color(red: 0.98, green: 0.76, blue: 0.20)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
        let spacing: CGFloat = 34
        var row = 0
        var y: CGFloat = 12
        while y < size.height + spacing {
            var x: CGFloat = row % 2 == 0 ? 12 : 12 + spacing / 2
            while x < size.width + spacing {
                // A diamond-shaped cluster of small dots, like knots in tie-dye.
                let big = random(&rng, 5) == 0
                let pts: [(CGFloat, CGFloat)] = [(0, 0), (-5, 0), (5, 0), (0, -5), (0, 5)]
                for (dx, dy) in pts {
                    let r: CGFloat = dx == 0 && dy == 0 ? (big ? 3.4 : 2.4) : 1.8
                    context.fill(Path(ellipseIn: CGRect(x: x + dx - r, y: y + dy - r, width: r * 2, height: r * 2)),
                                 with: .color(dx == 0 && dy == 0 && big ? accent : dot))
                }
                x += spacing
            }
            y += spacing / 2
            row += 1
        }
    }
}
