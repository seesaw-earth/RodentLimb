// CalibrationTools.swift — helpers of the calibration sheet: the overlay drawn on the frame, the
// loupe that magnifies the point being dragged (with the rim / floor line / ruler drawn on top),
// and the auto-fit of the rim and the floor line from the tracked keypoints (the iPhone app's
// logic, made index-safe). The fits are pure functions, run off the main thread by the sheet.

import SwiftUI

/// What the calibration sheet marks, and which handle a drag holds.
enum CalibrationMode { case circle, floor, ruler }
enum CalibrationHandle { case move, resize, rulerA, rulerB, floor }

/// The rim circle (with the wall zone), floor line or ruler drawn over the video frame, plus the
/// keypoints of the frame shown.
struct CalibrationOverlay {
    var mode: CalibrationMode
    var circle: CircleCal
    var floorY: Double
    var ruler: ScaleCal
    var wallMargin: Double?
    var selected: CalibrationHandle?
    /// Pose to draw (nil = keypoints hidden), at this track time.
    var track: PoseTrack?
    var time: Double
    var videoSize: CGSize

    func draw(_ ctx: GraphicsContext, rect: CGRect) {
        let s = rect.width / max(1, videoSize.width)
        func v(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + CGFloat(x) * s, y: rect.minY + CGFloat(y) * s) }

        // Keypoints of the frame shown, to help placement.
        if let t = track, let i = t.frameIndex(at: time) {
            for k in Kp.allCases {
                guard let p = t.point(k, i, threshold: 0.3) else { continue }
                let c = v(Double(p.x), Double(p.y))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(KeypointColors.color(k)))
            }
        }

        let accent = Color.yellow
        switch mode {
        case .circle:
            let c = v(circle.cx, circle.cy), r = CGFloat(max(0, circle.r.finiteOr(0))) * s
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(accent), lineWidth: 2)
            if let m = wallMargin, m.isFinite {
                let ri = r * CGFloat(1 - m)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ri, y: c.y - ri, width: 2 * ri, height: 2 * ri)), with: .color(accent.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(accent))
            let h = CGPoint(x: c.x + r, y: c.y)
            ctx.fill(Path(ellipseIn: CGRect(x: h.x - 7, y: h.y - 7, width: 14, height: 14)), with: .color(accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: h.x - 7, y: h.y - 7, width: 14, height: 14)), with: .color(.black.opacity(0.5)), lineWidth: 1)
        case .floor:
            let y = rect.minY + CGFloat(floorY.finiteOr(0)) * s
            var p = Path(); p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - 7, y: y - 7, width: 14, height: 14)), with: .color(accent))
        case .ruler:
            let a = v(ruler.x1, ruler.y1), b = v(ruler.x2, ruler.y2)
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(accent), lineWidth: 2)
            for (q, which) in [(a, CalibrationHandle.rulerA), (b, CalibrationHandle.rulerB)] {
                let sel = selected == which
                let rr: CGFloat = sel ? 9 : 7
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(accent.opacity(0.35)))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(accent), lineWidth: sel ? 2.5 : 1.5)
                var cross = Path()
                cross.move(to: CGPoint(x: q.x - 4, y: q.y)); cross.addLine(to: CGPoint(x: q.x + 4, y: q.y))
                cross.move(to: CGPoint(x: q.x, y: q.y - 4)); cross.addLine(to: CGPoint(x: q.x, y: q.y + 4))
                ctx.stroke(cross, with: .color(.black), lineWidth: 1)
            }
        }
    }
}

// MARK: - Loupe

/// Circular magnifier (4× the on-screen scale) of the point being dragged, with the calibration
/// shape drawn on top and a crosshair.
@MainActor
struct CalibrationLoupe: View {
    enum Outline {
        case circle(CircleCal)
        case floor(Double)
        case ruler(ScaleCal)
    }

    let image: CGImage
    let videoSize: CGSize
    /// Points per video pixel of the frame on screen.
    let displayScale: CGFloat
    /// Video coordinates at the center of the loupe.
    let point: CGPoint
    let shape: Outline

    private let size: CGFloat = 132
    private let zoom: CGFloat = 4

    var body: some View {
        let scale = max(0.05, (displayScale.isFinite ? displayScale : 1) * zoom)
        let w = videoSize.width * scale, h = videoSize.height * scale
        ZStack {
            Color.black
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: w, height: h)
                .offset(x: w / 2 - point.x * scale, y: h / 2 - point.y * scale)
                .frame(width: size, height: size)
                .clipped()
            Canvas { ctx, _ in draw(ctx, scale: scale) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 6)
    }

    private func draw(_ ctx: GraphicsContext, scale: CGFloat) {
        func map(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (CGFloat(x) - point.x) * scale + size / 2, y: (CGFloat(y) - point.y) * scale + size / 2)
        }
        let accent = Color.yellow
        switch shape {
        case .circle(let c):
            let center = map(c.cx, c.cy), r = CGFloat(max(0, c.r.finiteOr(0))) * scale
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(accent), lineWidth: 1.5)
        case .floor(let y):
            let p0 = map(0, y.finiteOr(0))
            var p = Path(); p.move(to: CGPoint(x: 0, y: p0.y)); p.addLine(to: CGPoint(x: size, y: p0.y))
            ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        case .ruler(let r):
            var p = Path(); p.move(to: map(r.x1, r.y1)); p.addLine(to: map(r.x2, r.y2))
            ctx.stroke(p, with: .color(accent), lineWidth: 1.5)
        }
        var cross = Path()
        cross.move(to: CGPoint(x: size / 2 - 10, y: size / 2)); cross.addLine(to: CGPoint(x: size / 2 + 10, y: size / 2))
        cross.move(to: CGPoint(x: size / 2, y: size / 2 - 10)); cross.addLine(to: CGPoint(x: size / 2, y: size / 2 + 10))
        ctx.stroke(cross, with: .color(.white.opacity(0.9)), lineWidth: 1)
    }
}

// MARK: - Auto-fit from the pose (same logic as the iPhone app)

enum CalibrationFit {
    static func percentile(_ v: [Double], _ q: Double) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted()
        let i = Int(safe: (Double(s.count - 1) * q).rounded(.down))
        return s[min(s.count - 1, max(0, i))]
    }

    /// Rim of the cylinder (bottom view): the box around every confident keypoint of the video
    /// (0.5–99.5th percentiles, every second frame), as a circle 2% larger.
    static func circle(_ t: PoseTrack) -> CircleCal? {
        var xs: [Double] = [], ys: [Double] = []
        for k in Kp.allCases {
            let ki = k.rawValue
            guard ki < t.x.count, ki < t.y.count, ki < t.c.count else { continue }
            let xk = t.x[ki], yk = t.y[ki], ck = t.c[ki]
            let n = min(t.frameCount, xk.count, yk.count, ck.count)
            var i = 0
            while i < n {
                let x = xk[i], y = yk[i]
                if ck[i] >= 0.5 && x >= 0 && y >= 0 && x.isFinite && y.isFinite {
                    xs.append(Double(x))
                    ys.append(Double(y))
                }
                i += 2
            }
        }
        guard let x0 = percentile(xs, 0.005), let x1 = percentile(xs, 0.995),
              let y0 = percentile(ys, 0.005), let y1 = percentile(ys, 0.995), x1 > x0, y1 > y0 else { return nil }
        return CircleCal(cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, r: max(x1 - x0, y1 - y0) / 2 * 1.02)
    }

    /// Floor line (side view): the 95th percentile of the confident hind-paw heights.
    static func floor(_ t: PoseTrack) -> Double? {
        var ys: [Double] = []
        for k in [Kp.lh, .rh] {
            let ki = k.rawValue
            guard ki < t.y.count, ki < t.c.count else { continue }
            let yk = t.y[ki], ck = t.c[ki]
            let n = min(t.frameCount, yk.count, ck.count)
            for i in 0..<max(0, n) where ck[i] >= 0.5 && yk[i] >= 0 && yk[i].isFinite {
                ys.append(Double(yk[i]))
            }
        }
        return percentile(ys, 0.95)
    }
}
