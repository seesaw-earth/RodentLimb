// GapRepair.swift — what to do with frames where a keypoint was not tracked.
//
// Standard practice for markerless pose data (DeepLabCut, SLEAP, motion-capture software):
//  1. Drop low-confidence detections (likelihood / confidence threshold).
//  2. Remove implausible jumps (a keypoint that leaps away from where its neighbouring frames put
//     it — usually a wrong detection or a left/right swap) so they become gaps too.
//  3. Fill only SHORT gaps (≤ max gap). Long gaps are left missing and excluded from every measure:
//     reconstructing seconds of movement would invent behaviour that was never observed.
//  4. Report how much was missing (QC) so that animals or videos that fail a criterion set in
//     advance can be excluded, and use the poorly tracked frames to refine the model.
//
// Short-gap fill methods offered here:
//  • linear        straight line between the last and next tracked positions (default; the method
//                  the analyzers were validated with)
//  • cubic         shape-preserving cubic Hermite (PCHIP-like, Fritsch–Carlson): follows the
//                  direction of motion at both edges, never overshoots
//  • bodyRelative  "relational" fill: the paw's position relative to the body (tail base → nose
//                  axis) is interpolated and carried along with the body, so a paw that is briefly
//                  hidden while the mouse walks or turns moves with it instead of cutting across
//  • kalman        constant-velocity Kalman filter + Rauch–Tung–Striebel smoother; uses the motion
//                  on both sides of the gap (cf. the Ensemble Kalman Smoother of Lightning Pose)
//
// Foundation only (also compiled on Linux by Tools/validation).

import Foundation

enum GapFill: String, Codable, CaseIterable, Identifiable {
    case linear, cubic, bodyRelative, kalman
    var id: String { rawValue }

    var label: LText {
        switch self {
        case .linear: return LText("Linear", "线性插值")
        case .cubic: return LText("Cubic (shape-preserving)", "三次保形插值")
        case .bodyRelative: return LText("Body-relative (follows the body)", "身体相对坐标（随身体移动）")
        case .kalman: return LText("Kalman smoother", "Kalman 平滑")
        }
    }

    var help: LText {
        switch self {
        case .linear:
            return LText("Straight line between the frames before and after the gap. Validated default.",
                         "在缺口前后两帧之间连直线。经过验证的默认方法。")
        case .cubic:
            return LText("Smooth curve that keeps the direction of motion at both ends without overshooting.",
                         "平滑曲线，两端保持运动方向，不会过冲。")
        case .bodyRelative:
            return LText("Interpolates where the keypoint sits relative to the body (tail base → nose) and moves it with the body. Best for paws hidden briefly while the mouse walks or turns.",
                         "插补关键点相对身体（尾根→鼻尖）的位置并随身体移动。适合行走或转身时爪短暂被遮挡。")
        case .kalman:
            return LText("Constant-velocity Kalman smoother using the motion on both sides of the gap.",
                         "匀速 Kalman 平滑器，利用缺口两侧的运动。")
        }
    }

    /// Methods-text description (English, exports).
    var methods: String {
        switch self {
        case .linear: return "linearly interpolated"
        case .cubic: return "filled with a shape-preserving (Fritsch–Carlson) cubic Hermite interpolant"
        case .bodyRelative: return "filled by interpolating the keypoint's position in the body frame (tail base → nose axis) and transforming it back with the tracked body (relational gap fill; linear interpolation where the body was not tracked)"
        case .kalman: return "filled with a constant-velocity Kalman filter and Rauch–Tung–Striebel smoother fitted to each trajectory"
        }
    }
}

enum GapRepair {
    /// Interior runs of missing samples no longer than `maxGap` samples (half-open ranges).
    static func fillableGaps(_ v: [Double], maxGap: Int) -> [Range<Int>] {
        guard maxGap > 0, v.count > 2 else { return [] }
        var out: [Range<Int>] = []
        let n = v.count
        var i = 0
        while i < n {
            if v[i].isNaN {
                var j = i
                while j < n && v[j].isNaN { j += 1 }
                if i > 0 && j < n && j - i <= maxGap { out.append(i..<j) }
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    /// Fills short gaps of every keypoint with `method`. `xs` / `ys` are [keypoint][frame], NaN =
    /// missing (x and y are missing together).
    static func fill(xs: [[Double]], ys: [[Double]], maxGap: Int, method: GapFill) -> ([[Double]], [[Double]]) {
        switch method {
        case .linear:
            return (xs.map { Signal.fillGaps($0, maxGap: maxGap) }, ys.map { Signal.fillGaps($0, maxGap: maxGap) })
        case .cubic:
            return (xs.map { fillCubic($0, maxGap: maxGap) }, ys.map { fillCubic($0, maxGap: maxGap) })
        case .kalman:
            return (xs.map { fillKalman($0, maxGap: maxGap) }, ys.map { fillKalman($0, maxGap: maxGap) })
        case .bodyRelative:
            return fillBodyRelative(xs: xs, ys: ys, maxGap: maxGap)
        }
    }

    // MARK: Cubic

    /// Shape-preserving cubic Hermite fill (slopes from the samples just outside the gap, limited
    /// with the Fritsch–Carlson condition so the curve stays between the edge values).
    static func fillCubic(_ v: [Double], maxGap: Int) -> [Double] {
        var out = v
        let n = v.count
        for g in fillableGaps(v, maxGap: maxGap) {
            let a = g.lowerBound - 1, b = g.upperBound
            let ya = v[a], yb = v[b]
            let span = Double(b - a)
            let secant = (yb - ya) / span
            var ma = (a >= 1 && v[a - 1].isFinite) ? ya - v[a - 1] : secant
            var mb = (b + 1 < n && v[b + 1].isFinite) ? v[b + 1] - yb : secant
            if secant == 0 {
                ma = 0; mb = 0
            } else {
                if ma * secant <= 0 { ma = 0 }
                if mb * secant <= 0 { mb = 0 }
                let alpha = ma / secant, beta = mb / secant
                let s = alpha * alpha + beta * beta
                if s > 9 {
                    let tau = 3 / s.squareRoot()
                    ma = tau * alpha * secant
                    mb = tau * beta * secant
                }
            }
            for k in g {
                let t = Double(k - a) / span
                let t2 = t * t, t3 = t2 * t
                let h00 = 2 * t3 - 3 * t2 + 1
                let h10 = t3 - 2 * t2 + t
                let h01 = -2 * t3 + 3 * t2
                let h11 = t3 - t2
                let value = h00 * ya + h10 * span * ma + h01 * yb + h11 * span * mb
                out[k] = value.isFinite ? value : ya + secant * Double(k - a)
            }
        }
        return out
    }

    // MARK: Body-relative

    /// Relational fill: nose and tail base are filled linearly; every other keypoint is
    /// interpolated in the body frame and carried with the body. Gaps where the body itself is not
    /// known fall back to linear interpolation.
    static func fillBodyRelative(xs: [[Double]], ys: [[Double]], maxGap: Int) -> ([[Double]], [[Double]]) {
        let nose = Kp.nose.rawValue, tail = Kp.tail.rawValue
        guard xs.count > max(nose, tail), ys.count == xs.count else {
            return (xs.map { Signal.fillGaps($0, maxGap: maxGap) }, ys.map { Signal.fillGaps($0, maxGap: maxGap) })
        }
        var ox = xs, oy = ys
        ox[nose] = Signal.fillGaps(xs[nose], maxGap: maxGap); oy[nose] = Signal.fillGaps(ys[nose], maxGap: maxGap)
        ox[tail] = Signal.fillGaps(xs[tail], maxGap: maxGap); oy[tail] = Signal.fillGaps(ys[tail], maxGap: maxGap)
        let nx = ox[nose], ny = oy[nose], tx = ox[tail], ty = oy[tail]
        let n = nx.count

        /// Body frame at frame i: origin (tail), unit axis (ux, uy) toward the nose, length L.
        func frame(_ i: Int) -> (Double, Double, Double, Double, Double)? {
            guard i >= 0, i < n, i < tx.count, i < ny.count, i < ty.count else { return nil }
            let dx = nx[i] - tx[i], dy = ny[i] - ty[i]
            let l = (dx * dx + dy * dy).squareRoot()
            guard l.isFinite, l > 1e-6 else { return nil }
            return (tx[i], ty[i], dx / l, dy / l, l)
        }

        for k in 0..<xs.count where k != nose && k != tail {
            let vx = xs[k], vy = ys[k]
            guard vx.count == n, vy.count == n else {
                ox[k] = Signal.fillGaps(vx, maxGap: maxGap); oy[k] = Signal.fillGaps(vy, maxGap: maxGap)
                continue
            }
            var fx = vx, fy = vy
            for g in fillableGaps(vx, maxGap: maxGap) {
                let a = g.lowerBound - 1, b = g.upperBound
                guard vy[a].isFinite, vy[b].isFinite else { continue }
                var frames: [(Double, Double, Double, Double, Double)] = []
                frames.reserveCapacity(g.count)
                var ok = true
                for i in g { if let f = frame(i) { frames.append(f) } else { ok = false; break } }
                if ok, let fa = frame(a), let fb = frame(b) {
                    // Body-frame coordinates (in body lengths) at both edges.
                    func ego(_ px: Double, _ py: Double, _ f: (Double, Double, Double, Double, Double)) -> (Double, Double) {
                        let rx = px - f.0, ry = py - f.1
                        return ((rx * f.2 + ry * f.3) / f.4, (-rx * f.3 + ry * f.2) / f.4)
                    }
                    let ea = ego(vx[a], vy[a], fa), eb = ego(vx[b], vy[b], fb)
                    let span = Double(b - a)
                    for (j, i) in g.enumerated() {
                        let t = Double(i - a) / span
                        let ex = ea.0 + (eb.0 - ea.0) * t, ey = ea.1 + (eb.1 - ea.1) * t
                        let f = frames[j]
                        fx[i] = f.0 + (ex * f.2 - ey * f.3) * f.4
                        fy[i] = f.1 + (ex * f.3 + ey * f.2) * f.4
                    }
                } else {
                    // Body not known throughout the gap: plain linear interpolation.
                    let span = Double(b - a)
                    for i in g {
                        let t = Double(i - a) / span
                        fx[i] = vx[a] + (vx[b] - vx[a]) * t
                        fy[i] = vy[a] + (vy[b] - vy[a]) * t
                    }
                }
            }
            ox[k] = fx; oy[k] = fy
        }
        return (ox, oy)
    }

    // MARK: Kalman

    /// Constant-velocity Kalman filter + RTS smoother over the tracked span of one coordinate;
    /// only the short gaps are replaced by the smoothed estimate (tracked samples keep their
    /// values, so the usual median / moving-average cleaning still applies afterwards).
    static func fillKalman(_ v: [Double], maxGap: Int) -> [Double] {
        let gaps = fillableGaps(v, maxGap: maxGap)
        guard !gaps.isEmpty,
              let first = v.firstIndex(where: { $0.isFinite }),
              let last = v.lastIndex(where: { $0.isFinite }), last > first + 1 else { return v }

        // Noise levels from the data: robust variance of the second difference of tracked samples.
        var d2: [Double] = []
        d2.reserveCapacity(last - first)
        for i in (first + 1)..<last where v[i - 1].isFinite && v[i].isFinite && v[i + 1].isFinite {
            d2.append(abs(v[i + 1] - 2 * v[i] + v[i - 1]))
        }
        let mad = Signal.median(d2) ?? 1
        let s2 = max(1e-6, (1.4826 * mad) * (1.4826 * mad))
        let r = s2 / 12          // measurement noise (px²)
        let q = s2 / 2           // acceleration noise per frame² (px²)

        let m = last - first + 1
        var pred0 = [Double](repeating: 0, count: m), pred1 = pred0
        var pp00 = pred0, pp01 = pred0, pp11 = pred0
        var f0 = pred0, f1 = pred0, pf00 = pred0, pf01 = pred0, pf11 = pred0

        var x0 = v[first], x1 = 0.0
        var p00 = r, p01 = 0.0, p11 = s2 * 10
        for j in 0..<m {
            let i = first + j
            if j > 0 {
                // x ← F x, P ← F P Fᵀ + Q with F = [[1, 1], [0, 1]], Q = q·[[¼, ½], [½, 1]].
                x0 += x1
                let n00 = p00 + 2 * p01 + p11 + q / 4
                let n01 = p01 + p11 + q / 2
                let n11 = p11 + q
                p00 = n00; p01 = n01; p11 = n11
            }
            pred0[j] = x0; pred1[j] = x1; pp00[j] = p00; pp01[j] = p01; pp11[j] = p11
            let z = v[i]
            if z.isFinite {
                let s = p00 + r
                let k0 = p00 / s, k1 = p01 / s
                let innovation = z - x0
                x0 += k0 * innovation
                x1 += k1 * innovation
                let n00 = (1 - k0) * p00
                let n01 = (1 - k0) * p01
                let n11 = p11 - k1 * p01
                p00 = n00; p01 = n01; p11 = n11
            }
            f0[j] = x0; f1[j] = x1; pf00[j] = p00; pf01[j] = p01; pf11[j] = p11
        }

        // Rauch–Tung–Striebel backward pass (means only).
        var s0 = f0, s1 = f1
        if m >= 2 {
            for j in stride(from: m - 2, through: 0, by: -1) {
                let a = pf00[j], b = pf01[j], c = pf11[j]
                let d = pp00[j + 1], e = pp01[j + 1], f = pp11[j + 1]
                let det = d * f - e * e
                guard det.isFinite, abs(det) > 1e-12 else { continue }
                // C = Pf · Fᵀ · Pp⁻¹
                let c00 = ((a + b) * f - b * e) / det
                let c01 = (-(a + b) * e + b * d) / det
                let c10 = ((b + c) * f - c * e) / det
                let c11 = (-(b + c) * e + c * d) / det
                let r0 = s0[j + 1] - pred0[j + 1], r1 = s1[j + 1] - pred1[j + 1]
                s0[j] = f0[j] + c00 * r0 + c01 * r1
                s1[j] = f1[j] + c10 * r0 + c11 * r1
            }
        }

        var out = v
        for g in gaps {
            for i in g {
                let j = i - first
                guard j >= 0, j < m else { continue }
                let value = s0[j]
                out[i] = value.isFinite ? value : v[g.lowerBound - 1]
            }
        }
        return out
    }

    // MARK: Jumps

    /// Removes implausible jumps (Hampel-style): a sample farther than `threshold` (px) from the
    /// median position of the tracked samples within ±`half` frames (itself excluded) is set
    /// missing. Where the window has tracked samples on one side only (start or end of the video,
    /// next to a gap) the median lags behind a fast-moving keypoint, so twice the threshold is
    /// used there; this keeps fast swing-phase paws next to a gap. Returns the number removed.
    @discardableResult
    static func rejectJumps(x: inout [Double], y: inout [Double], threshold: Double, half: Int) -> Int {
        let n = min(x.count, y.count)
        guard threshold > 0, threshold.isFinite, half > 0, n > 2 else { return 0 }
        let h = min(half, n)
        var removed: [Int] = []
        var bx: [Double] = [], by: [Double] = []
        bx.reserveCapacity(2 * h + 1)
        by.reserveCapacity(2 * h + 1)
        for i in 0..<n where x[i].isFinite && y[i].isFinite {
            bx.removeAll(keepingCapacity: true)
            by.removeAll(keepingCapacity: true)
            var before = 0, after = 0
            let lo = max(0, i - h), hi = min(n - 1, i + h)
            for j in lo...hi where j != i && x[j].isFinite && y[j].isFinite {
                bx.append(x[j]); by.append(y[j])
                if j < i { before += 1 } else { after += 1 }
            }
            guard bx.count >= 2 else { continue }
            bx.sort(); by.sort()
            let c = bx.count
            let mx = c % 2 == 1 ? bx[c / 2] : (bx[c / 2 - 1] + bx[c / 2]) / 2
            let my = c % 2 == 1 ? by[c / 2] : (by[c / 2 - 1] + by[c / 2]) / 2
            let dx = x[i] - mx, dy = y[i] - my
            let limit = before > 0 && after > 0 ? threshold : 2 * threshold
            if (dx * dx + dy * dy).squareRoot() > limit { removed.append(i) }
        }
        for i in removed { x[i] = .nan; y[i] = .nan }
        return removed.count
    }
}
