import SwiftUI
import WatchKit

/// **The question's state is the edge of the glass**, drawn the way StatusHub's watch draws a command's
/// (status-hub/apps/Watch/WatchUI.swift, `CommandBorder`), with that app's default colours and thickness.
///
/// | state | edge |
/// |---|---|
/// | recording (only a press ends it) | red — StatusHub's colour for a recording held open |
/// | transcribing or answering | white, a sweep travelling round |
/// | idle | none |
struct VoiceBorder: View {
    enum State { case idle, recording, working }
    let state: State

    /// Wrist down: the system redraws too seldom to animate, so a sweep would freeze mid-way.
    @Environment(\.isLuminanceReduced) private var lowered

    /// StatusHub's red for a recording held open; the cancel X uses it too.
    static let red = Color(red: 0xe5 / 255, green: 0x48 / 255, blue: 0x4d / 255)
    private static let recording = red
    private static let working = Color.white
    private static let ring = Color(white: 0x40 / 255)
    /// Thickness of the line and of the opaque black band just inside it, in PIXELS.
    private static let px: CGFloat = 3
    private static let bandPx: CGFloat = 2

    var body: some View {
        edge
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }

    @ViewBuilder private var edge: some View {
        switch state {
        case .idle: EmptyView()
        case .recording: line(Self.recording)
        case .working where lowered: line(Self.working)
        case .working:
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                ZStack {
                    line(Self.ring)
                    GlassEdge(inset: 0).trimmedPath(t, 0.18)
                        .stroke(Self.working, lineWidth: width * 2)
                }
            }
        }
    }

    /// The line, with the black band just inside it so text scrolling up to the edge disappears before
    /// reaching the line instead of running under it.
    private func line(_ color: Color) -> some View {
        ZStack {
            GlassEdge(inset: width + band / 2).stroke(Color.black, lineWidth: band)
            BeyondEdge(inset: width).fill(color, style: FillStyle(eoFill: true))
        }
    }

    private var scale: CGFloat { WKInterfaceDevice.current().screenScale }
    private var width: CGFloat { Self.px / scale }
    private var band: CGFloat { Self.bandPx / scale }
}

/// The outline of the glass, inset by `inset`. The corners are the 46mm display's own continuous corner
/// (its framebuffer mask's three cubic curves, in units of the corner radius), not a circular arc, which
/// would leave the bezel at every corner. Copied from StatusHub's watch app.
struct GlassEdge: Shape {
    let inset: CGFloat
    /// The 46mm display's corner radius in points (`DeviceCornerRadius` in its device profile).
    static let radius: CGFloat = 50

    func path(in r: CGRect) -> Path {
        let rect = r.insetBy(dx: inset, dy: inset)
        let R = Self.radius - inset
        let k: [(CGFloat, CGFloat)] = [
            (0, 1.307581),
            (0, 0.852907), (0.04734106, 0.6880309), (0.1362377, 0.5218087),
            (0.2251343, 0.3555865), (0.3555865, 0.2251343), (0.5218087, 0.1362377),
            (0.6880309, 0.04734106), (0.852907, 0), (1.307581, 0),
        ]
        let corners: [(CGPoint, CGVector, CGVector)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
        ]
        var p = Path()
        for (i, (c, a, b)) in corners.enumerated() {
            func pt(_ u: (CGFloat, CGFloat)) -> CGPoint {
                CGPoint(x: c.x + (u.1 * a.dx + u.0 * b.dx) * R, y: c.y + (u.1 * a.dy + u.0 * b.dy) * R)
            }
            if i == 0 { p.move(to: pt(k[0])) } else { p.addLine(to: pt(k[0])) }
            for j in stride(from: 1, to: k.count, by: 3) {
                p.addCurve(to: pt(k[j + 2]), control1: pt(k[j]), control2: pt(k[j + 1]))
            }
        }
        p.closeSubpath()
        return p
    }

    /// A stretch of the outline `length` long (as a fraction of it) starting at `from`, wrapping round.
    func trimmedPath(_ from: Double, _ length: Double) -> Path {
        var out = Path()
        let whole = path(in: CGRect(origin: .zero, size: WKInterfaceDevice.current().screenBounds.size))
        let to = from + length
        out.addPath(whole.trimmedPath(from: from, to: min(1, to)))
        if to > 1 { out.addPath(whole.trimmedPath(from: 0, to: to - 1)) }
        return out
    }
}

/// Everything from `inset` inside the glass's outline outward: the line is this filled rather than a
/// stroke, because the real glass is not exactly the curve, and a stroke leaves slivers outside it.
struct BeyondEdge: Shape {
    let inset: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path(r.insetBy(dx: -20, dy: -20))
        p.addPath(GlassEdge(inset: inset).path(in: r))
        return p
    }
}
