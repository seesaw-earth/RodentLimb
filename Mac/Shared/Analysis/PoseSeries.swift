// PoseSeries.swift — cleaned keypoint trajectories shared by all analyzers.
//
// Pipeline per keypoint: confidence filter → optional removal of implausible jumps (Hampel-style,
// see GapRepair.rejectJumps) → filling of short gaps (≤ maxGap; linear by default, or cubic,
// body-relative or Kalman, see GapRepair) → 3-point median (removes single-frame jumps) →
// centered moving average (NaN-aware). Longer gaps stay missing.
// Missing samples are NaN. Body length = median nose–tail-base distance, the scale every
// threshold in the app is expressed in, so parameters transfer between cameras and zoom levels.

import Foundation

struct P: Hashable {
    var x: Double
    var y: Double
    static func + (a: P, b: P) -> P { P(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: P, b: P) -> P { P(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: P, s: Double) -> P { P(x: a.x * s, y: a.y * s) }
    var length: Double { hypot(x, y) }
    func dist(_ o: P) -> Double { hypot(x - o.x, y - o.y) }
    var unit: P? { let l = length; return l > 1e-9 ? P(x: x / l, y: y / l) : nil }
    func dot(_ o: P) -> Double { x * o.x + y * o.y }
    func cross(_ o: P) -> Double { x * o.y - y * o.x }
}

enum Signal {
    /// Linear interpolation across NaN runs no longer than `maxGap` samples (interior only).
    static func fillGaps(_ v: [Double], maxGap: Int) -> [Double] {
        guard maxGap > 0, v.count > 2 else { return v }
        var out = v
        var i = 0
        let n = v.count
        while i < n {
            if out[i].isNaN {
                var j = i
                while j < n && out[j].isNaN { j += 1 }
                let gap = j - i
                if i > 0 && j < n && gap <= maxGap {
                    let a = out[i - 1], b = out[j]
                    for k in i..<j {
                        let f = Double(k - i + 1) / Double(gap + 1)
                        out[k] = a + (b - a) * f
                    }
                }
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    /// 3-point median, NaN-aware (needs all three finite to change a value).
    static func median3(_ v: [Double]) -> [Double] {
        guard v.count >= 3 else { return v }
        var out = v
        for i in 1..<(v.count - 1) {
            let a = v[i - 1], b = v[i], c = v[i + 1]
            guard a.isFinite, b.isFinite, c.isFinite else { continue }
            out[i] = max(min(a, b), min(max(a, b), c))
        }
        return out
    }

    /// Centered moving average over `window` samples (odd), ignoring NaN; NaN stays NaN.
    static func smooth(_ v: [Double], window: Int) -> [Double] {
        let w = max(1, window | 1)
        guard w > 1, v.count > 2 else { return v }
        let h = w / 2
        let n = v.count
        var sum = [Double](repeating: 0, count: n + 1)
        var cnt = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            let ok = v[i].isFinite
            sum[i + 1] = sum[i] + (ok ? v[i] : 0)
            cnt[i + 1] = cnt[i] + (ok ? 1 : 0)
        }
        var out = v
        for i in 0..<n where v[i].isFinite {
            let lo = max(0, i - h), hi = min(n, i + h + 1)
            let c = cnt[hi] - cnt[lo]
            if c > 0 { out[i] = (sum[hi] - sum[lo]) / Double(c) }
        }
        return out
    }

    /// Central-difference derivative using real timestamps.
    static func derivative(_ v: [Double], t: [Double]) -> [Double] {
        let n = v.count
        guard n > 1, t.count >= n else { return [Double](repeating: .nan, count: n) }
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let a = max(0, i - 1), b = min(n - 1, i + 1)
            let dt = t[b] - t[a]
            if dt > 0, v[a].isFinite, v[b].isFinite { out[i] = (v[b] - v[a]) / dt }
        }
        return out
    }

    static func median(_ v: [Double]) -> Double? {
        let f = v.filter { $0.isFinite }.sorted()
        guard !f.isEmpty else { return nil }
        let m = f.count / 2
        return f.count % 2 == 1 ? f[m] : (f[m - 1] + f[m]) / 2
    }

    static func mean(_ v: [Double]) -> Double? {
        let f = v.filter { $0.isFinite }
        guard !f.isEmpty else { return nil }
        return f.reduce(0, +) / Double(f.count)
    }

    static func sd(_ v: [Double]) -> Double? {
        let f = v.filter { $0.isFinite }
        guard f.count > 1, let m = mean(f) else { return nil }
        return sqrt(f.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(f.count - 1))
    }

    /// Runs of `true` as half-open index ranges.
    static func runs(_ mask: [Bool]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for (i, m) in mask.enumerated() {
            if m, start == nil { start = i }
            if !m, let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<mask.count) }
        return out
    }

    /// Down-sample a series to at most `maxPoints` points (bin means) for charts.
    static func downsample(t: [Double], v: [Double], maxPoints: Int) -> [SeriesPoint] {
        let n = min(t.count, v.count)
        guard n > 0 else { return [] }
        let step = max(1, Int(safe: ceil(Double(n) / Double(maxPoints)), fallback: 1))
        var out: [SeriesPoint] = []
        out.reserveCapacity(n / step + 1)
        var i = 0
        while i < n {
            let j = min(n, i + step)
            var s = 0.0, c = 0
            for k in i..<j where v[k].isFinite { s += v[k]; c += 1 }
            if c > 0 { out.append(SeriesPoint(t: t[i], v: s / Double(c))) }
            i = j
        }
        return out
    }

    /// Circular mean of phases in [0, 1) and the resultant length R (0 = random, 1 = locked).
    static func circular(_ phases: [Double]) -> (mean: Double, r: Double)? {
        let f = phases.filter { $0.isFinite }
        guard !f.isEmpty else { return nil }
        var s = 0.0, c = 0.0
        for p in f { s += sin(2 * .pi * p); c += cos(2 * .pi * p) }
        s /= Double(f.count); c /= Double(f.count)
        var m = atan2(s, c) / (2 * .pi)
        if m < 0 { m += 1 }
        return (m, hypot(s, c))
    }
}

extension PoseTrack {
    /// Frames for which `times` and every keypoint array have a value. Equals `frameCount` for
    /// every track the app writes; smaller only for a damaged file (arrays of different lengths,
    /// keypoint arrays missing), so the analysis never indexes past the end of one of them.
    var safeFrameCount: Int {
        let k = Kp.allCases.count
        guard x.count >= k, y.count >= k, c.count >= k else { return 0 }
        var m = times.count
        for j in 0..<k { m = Swift.min(m, x[j].count, y[j].count, c[j].count) }
        return m
    }
}

struct PoseSeries {
    let n: Int
    let t: [Double]
    let fps: Double
    let dt: Double
    private(set) var x: [[Double]]
    private(set) var y: [[Double]]
    /// Fraction of frames where the keypoint passed the confidence threshold (before filling).
    let visibility: [Double]
    let bodyLength: Double
    let bodyLengthEstimated: Bool
    /// Keypoint confidence threshold used to build the series.
    let keypointThreshold: Double
    /// `t` is non-decreasing (no NaN), so frame lookups can bisect instead of scanning.
    private let timesSorted: Bool
    /// Samples removed as implausible jumps (0 unless `CommonParams.rejectJumps`).
    let jumpsRemoved: Int

    init(track: PoseTrack, params: CommonParams) {
        // Equals track.frameCount for every track the app writes; smaller only for a damaged
        // file whose arrays disagree in length, so the loops below never index out of range.
        n = track.safeFrameCount
        keypointThreshold = params.keypointThreshold
        t = n == track.times.count ? track.times : Array(track.times.prefix(n))
        var sorted = true
        for i in 1..<max(1, n) where !(track.times[i] >= track.times[i - 1]) { sorted = false; break }
        timesSorted = sorted
        let rawFps = track.fps > 1 && track.fps.isFinite ? track.fps : 30
        var diffs: [Double] = []
        if n > 1 { for i in 1..<min(n, 600) { diffs.append(track.times[i] - track.times[i - 1]) } }
        let mdt = Signal.median(diffs.filter { $0 > 0 }) ?? (1 / rawFps)
        dt = mdt
        fps = 1 / mdt
        let gap = Int(safe: (params.maxGap / mdt).rounded())
        let win = Int(safe: (params.smoothing / mdt).rounded())
        // 1. Confidence filter.
        var rawX: [[Double]] = [], rawY: [[Double]] = [], vis: [Double] = []
        for k in Kp.allCases {
            var vx = [Double](repeating: .nan, count: n)
            var vy = [Double](repeating: .nan, count: n)
            var seen = 0
            for i in 0..<n {
                let c = Double(track.c[k.rawValue][i])
                let px = Double(track.x[k.rawValue][i]), py = Double(track.y[k.rawValue][i])
                if c >= params.keypointThreshold, px >= 0, py >= 0 {
                    vx[i] = px; vy[i] = py; seen += 1
                }
            }
            vis.append(n > 0 ? Double(seen) / Double(n) : 0)
            rawX.append(vx); rawY.append(vy)
        }
        // 2. Optional: implausible jumps become gaps (threshold in body lengths of the raw track).
        var jumps = 0
        if params.rejectJumps, n > 4 {
            var raw: [Double] = []
            let no = Kp.nose.rawValue, tb = Kp.tail.rawValue
            for i in 0..<n where rawX[no][i].isFinite && rawX[tb][i].isFinite {
                raw.append(hypot(rawX[no][i] - rawX[tb][i], rawY[no][i] - rawY[tb][i]))
            }
            let rawBL = Signal.median(raw) ?? max(1, Double(min(track.width, track.height)) / 8)
            let half = min(60, max(1, Int(safe: (0.1 / mdt).rounded())))   // ±0.1 s, capped for damaged timelines
            for k in 0..<rawX.count {
                jumps += GapRepair.rejectJumps(x: &rawX[k], y: &rawY[k], threshold: params.jumpThreshold * rawBL, half: half)
            }
        }
        jumpsRemoved = jumps
        // 3. Short gaps filled with the chosen method; 4. 3-point median; 5. moving average.
        let (filledX, filledY) = GapRepair.fill(xs: rawX, ys: rawY, maxGap: gap, method: params.gapFill)
        let xs = filledX.map { Signal.smooth(Signal.median3($0), window: win) }
        let ys = filledY.map { Signal.smooth(Signal.median3($0), window: win) }
        x = xs; y = ys; visibility = vis

        var lengths: [Double] = []
        lengths.reserveCapacity(n)
        let nose = Kp.nose.rawValue, tail = Kp.tail.rawValue
        for i in 0..<n where xs[nose][i].isFinite && xs[tail][i].isFinite {
            lengths.append(hypot(xs[nose][i] - xs[tail][i], ys[nose][i] - ys[tail][i]))
        }
        if lengths.count >= max(10, n / 20), let m = Signal.median(lengths), m > 5 {
            bodyLength = m
            bodyLengthEstimated = false
        } else {
            // Fallback: 1/8 of the shorter frame side — flagged in the result notes. Never below
            // 1 px: every analyzer divides by it.
            bodyLength = max(1, Double(min(track.width, track.height)) / 8)
            bodyLengthEstimated = true
        }
    }

    func p(_ k: Kp, _ i: Int) -> P? {
        guard i >= 0, i < n else { return nil }
        let vx = x[k.rawValue][i], vy = y[k.rawValue][i]
        return vx.isFinite && vy.isFinite ? P(x: vx, y: vy) : nil
    }

    /// Speed magnitude in px/s (NaN where unknown).
    func speed(_ k: Kp) -> [Double] {
        let vx = Signal.derivative(x[k.rawValue], t: t)
        let vy = Signal.derivative(y[k.rawValue], t: t)
        return zip(vx, vy).map { hypot($0, $1) }
    }

    /// Per-frame paw displacement speed using the smaller of the backward and forward steps
    /// (px/s). A frame at touch-down or lift-off is then still counted as stationary, which
    /// removes the systematic stance under-estimate of a central difference.
    func stepSpeed(_ k: Kp) -> [Double] {
        var out = [Double](repeating: .nan, count: n)
        let xs = x[k.rawValue], ys = y[k.rawValue]
        for i in 0..<n where xs[i].isFinite {
            var best = Double.infinity
            for j in [i - 1, i + 1] where j >= 0 && j < n && xs[j].isFinite {
                let dt = abs(t[j] - t[i])
                if dt > 0 { best = min(best, hypot(xs[j] - xs[i], ys[j] - ys[i]) / dt) }
            }
            if best.isFinite { out[i] = best }
        }
        return out
    }

    func samples(_ seconds: Double) -> Int { max(1, Int(safe: (seconds / dt).rounded())) }

    /// First frame with t ≥ a (n if none). Same result as `t.firstIndex { $0 >= a } ?? n`; on a
    /// sorted timeline it bisects (O(log n)), which matters when it is called once per stride or
    /// event on long videos.
    private func firstFrame(atOrAfter a: Double) -> Int {
        guard timesSorted else { return t.firstIndex { $0 >= a } ?? n }
        var lo = 0, hi = t.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if t[mid] >= a { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    /// Frame range covering [a, b) seconds.
    func indices(from a: Double, to b: Double) -> Range<Int> {
        let lo = firstFrame(atOrAfter: a)
        let hi = firstFrame(atOrAfter: b)
        return lo..<max(lo, hi)
    }

    /// Converts a run of frames to a time interval (end = start of the following frame).
    func interval(_ r: Range<Int>) -> Interval {
        let lo = max(0, r.lowerBound), hi = min(n, r.upperBound)
        guard lo < hi else {
            // Empty or out-of-range run (degenerate input): zero length instead of an index trap.
            let t0 = n > 0 ? t[min(lo, n - 1)] : 0
            return Interval(start: t0, end: t0)
        }
        return Interval(start: t[lo], end: t[hi - 1] + dt)
    }
}
