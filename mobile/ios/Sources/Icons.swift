import SwiftUI

/// The mockups' Lucide line icons that SF Symbols lacks, drawn in Lucide's 24-point box and scaled to `size`.
struct LineIcon: View {
    var size: CGFloat = 22
    var width: CGFloat = 1.75
    var dash: [CGFloat] = []
    let stroke: (inout Path) -> Void
    var fill: ((inout Path) -> Void)?

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 24
            ctx.scaleBy(x: k, y: k)
            var p = Path()
            stroke(&p)
            ctx.stroke(p, with: .foreground,
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
            if let fill {
                var f = Path()
                fill(&f)
                ctx.fill(f, with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum Icons {
    /// ChatGPT's menu button: two lines, the lower one shorter
    static func menu(size: CGFloat = 22) -> LineIcon {
        LineIcon(size: size, width: 2) { p in
            p.move(to: CGPoint(x: 4, y: 8.5)); p.addLine(to: CGPoint(x: 20, y: 8.5))
            p.move(to: CGPoint(x: 4, y: 15.5)); p.addLine(to: CGPoint(x: 14, y: 15.5))
        }
    }

    /// the temporary chat's dashed bubble (a tick inside while it's on)
    static func temporary(on: Bool, size: CGFloat = 22) -> some View {
        ZStack {
            LineIcon(size: size, width: 1.8, dash: [2.9, 2.6]) { p in
                p.addArc(center: CGPoint(x: 12, y: 12), radius: 9, startAngle: .degrees(150), endAngle: .degrees(480),
                         clockwise: false)
            }
            LineIcon(size: size, width: 1.8) { p in
                p.move(to: CGPoint(x: 3.6, y: 17)); p.addLine(to: CGPoint(x: 2, y: 22)); p.addLine(to: CGPoint(x: 7, y: 20.4))
                if on {
                    p.move(to: CGPoint(x: 8.5, y: 12)); p.addLine(to: CGPoint(x: 11, y: 14.5))
                    p.addLine(to: CGPoint(x: 15.5, y: 9.5))
                }
            }
        }
    }

    /// Lucide's bot, for Gup Bot
    static func bot(size: CGFloat = 22) -> LineIcon {
        LineIcon(size: size, width: 1.7) { p in
            p.move(to: CGPoint(x: 12, y: 8)); p.addLine(to: CGPoint(x: 12, y: 4)); p.addLine(to: CGPoint(x: 8, y: 4))
            p.addRoundedRect(in: CGRect(x: 4, y: 8, width: 16, height: 12), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 2, y: 14)); p.addLine(to: CGPoint(x: 4, y: 14))
            p.move(to: CGPoint(x: 20, y: 14)); p.addLine(to: CGPoint(x: 22, y: 14))
            p.move(to: CGPoint(x: 15, y: 13)); p.addLine(to: CGPoint(x: 15, y: 15))
            p.move(to: CGPoint(x: 9, y: 13)); p.addLine(to: CGPoint(x: 9, y: 15))
        }
    }

    /// "/" in a rounded square: the commands
    static func slash(size: CGFloat = 21) -> LineIcon {
        LineIcon(size: size) { p in
            p.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 2, height: 2))
            p.move(to: CGPoint(x: 9, y: 15)); p.addLine(to: CGPoint(x: 15, y: 9))
        }
    }

    /// six dots: a pinned row's drag handle while sorting
    static func grip(size: CGFloat = 20) -> LineIcon {
        LineIcon(size: size, width: 0, stroke: { _ in }, fill: { p in
            for x in [9.0, 15.0] {
                for y in [6.0, 12.0, 18.0] {
                    p.addEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
                }
            }
        })
    }

    /// Lucide's gauge with its needle on the effort: low far left, high straight up, max far right
    static func gauge(_ effort: String?, size: CGFloat = 23, width: CGFloat = 1.75) -> LineIcon {
        let a = Angle.degrees(needle(effort)).radians
        let tip = CGPoint(x: 12 + 6.2 * sin(a), y: 14 - 6.2 * cos(a))
        return LineIcon(size: size, width: width, stroke: { p in
            p.addArc(center: CGPoint(x: 12, y: 14), radius: 10, startAngle: .degrees(150), endAngle: .degrees(390),
                     clockwise: false)
            p.move(to: CGPoint(x: 12, y: 14)); p.addLine(to: tip)
        }, fill: { p in
            p.addEllipse(in: CGRect(x: 10.9, y: 12.9, width: 2.2, height: 2.2))
        })
    }

    /// the needle's angle from straight up, in degrees
    static func needle(_ effort: String?) -> Double {
        switch effort {
        case "none": return -110
        case "low": return -90
        case "medium": return -45
        case "high": return 0
        case "xhigh": return 45
        case "max": return 90
        default: return -45
        }
    }
}

/// The three usage rings, outside in: context (blue), the 5-hour limit (violet), the week (green), on grey tracks.
struct UsageRings: View {
    let percents: [Double?]   // context, 5-hour, week
    var size: CGFloat = 27
    var width: CGFloat = 2.2

    static let colors = [Theme.blue, Theme.violet, Color(hex: 0x7FD17F)]
    static let track = Color(hex: 0x3A3A3C)

    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 28
            ctx.scaleBy(x: k, y: k)
            let c = CGPoint(x: 14, y: 14)
            for i in 0..<3 {
                let r = 12.4 - Double(i) * 4.1
                let ring = Path { $0.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false) }
                ctx.stroke(ring, with: .color(Self.track), lineWidth: width)
                let pct = max(0, min(100, (i < percents.count ? percents[i] : nil) ?? 0))
                if pct > 0 {
                    let arc = Path {
                        $0.addArc(center: c, radius: r, startAngle: .degrees(-90),
                                  endAngle: .degrees(-90 + 360 * max(pct, 1.5) / 100), clockwise: false)
                    }
                    ctx.stroke(arc, with: .color(Self.colors[i]), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
