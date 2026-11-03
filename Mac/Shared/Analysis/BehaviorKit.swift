// BehaviorKit.swift — building blocks shared by the behavior assays: frame masks → bouts,
// analysis windows and time bins relative to the injection, reviewer edits, and a few
// kinematic helpers on the cleaned PoseSeries.

import Foundation

enum Bouts {
    /// Fills false-runs of at most `maxFrames` that lie between two true-runs.
    static func fillGaps(_ mask: [Bool], maxFrames: Int) -> [Bool] {
        guard maxFrames > 0 else { return mask }
        var b = mask
        let r = Signal.runs(mask)
        guard r.count > 1 else { return b }
        for i in 0..<(r.count - 1) where r[i + 1].lowerBound - r[i].upperBound <= maxFrames {
            for k in r[i].upperBound..<r[i + 1].lowerBound { b[k] = true }
        }
        return b
    }

    /// Removes true-runs shorter than `minFrames`.
    static func dropShort(_ mask: [Bool], minFrames: Int) -> [Bool] {
        guard minFrames > 1 else { return mask }
        var b = mask
        for r in Signal.runs(mask) where r.count < minFrames { for k in r { b[k] = false } }
        return b
    }

    /// Merge gaps ≤ `gap` s, then drop runs < `minDuration` s.
    static func clean(_ mask: [Bool], fps: Double, gap: Double, minDuration: Double) -> [Bool] {
        var b = mask
        if gap > 0 { b = fillGaps(b, maxFrames: max(1, Int(safe: (gap * fps).rounded()))) }
        if minDuration > 0 { b = dropShort(b, minFrames: max(1, Int(safe: (minDuration * fps).rounded()))) }
        return b
    }

    static func or(_ a: [Bool], _ b: [Bool]) -> [Bool] { zip(a, b).map { $0 || $1 } }
    static func and(_ a: [Bool], _ b: [Bool]) -> [Bool] { zip(a, b).map { $0 && $1 } }
    static func not(_ a: [Bool]) -> [Bool] { a.map { !$0 } }
}

/// Time bookkeeping for one video: frame times, the analysis window and the bins, all relative to
/// the injection time (`origin`).
struct Timeline {
    let t: [Double]
    let dt: Double
    let fps: Double
    let duration: Double
    let origin: Double
    let window: Interval
    let binSize: Double

    init(series s: PoseSeries, videoDuration: Double, origin: Double, start: Double, end: Double, binSize: Double) {
        t = s.t
        dt = s.dt
        fps = s.fps
        duration = max(videoDuration.finiteOr(0), ((s.t.last ?? 0) + s.dt).finiteOr(0))
        self.origin = max(0, origin)
        let a = min(max(0, self.origin + start), duration)
        let b = min(max(a, self.origin + end), duration)
        window = Interval(start: a, end: b)
        self.binSize = max(1, binSize)
    }

    var n: Int { t.count }

    func interval(_ r: Range<Int>) -> Interval {
        let lo = max(0, r.lowerBound), hi = min(t.count, r.upperBound)
        guard lo < hi else {
            // Empty run, or a mask longer than the timeline: zero length instead of an index trap.
            let t0 = t.isEmpty ? 0 : t[min(lo, t.count - 1)]
            return Interval(start: t0, end: t0)
        }
        return Interval(start: t[lo], end: t[hi - 1] + dt)
    }

    func intervals(_ mask: [Bool]) -> [(Range<Int>, Interval)] { Signal.runs(mask).map { ($0, interval($0)) } }

    func inWindow(_ time: Double) -> Bool { time >= window.start - 1e-9 && time < window.end }

    /// Seconds of `iv` inside the window.
    func overlap(_ iv: Interval, _ w: Interval? = nil) -> Double {
        let w = w ?? window
        return max(0, min(iv.end, w.end) - max(iv.start, w.start))
    }

    /// Number of bins covering the window (bins start at the origin).
    var binCount: Int {
        let span = window.end - origin
        // The cap (≥ 27 h even at 1-s bins) only matters for a corrupt duration or window, where
        // an enormous bin array would exhaust memory.
        return min(100_000, max(1, Int(safe: ceil(span / binSize - 1e-9), fallback: 1)))
    }

    func binInterval(_ i: Int) -> Interval {
        Interval(start: origin + Double(i) * binSize, end: origin + Double(i + 1) * binSize)
    }

    /// Seconds of the intervals in each bin (clipped to the window).
    func binSeconds(_ ivs: [Interval]) -> [Double] {
        (0..<binCount).map { i in
            let b = binInterval(i)
            let w = Interval(start: max(b.start, window.start), end: min(b.end, window.end))
            guard w.end > w.start else { return 0 }
            return ivs.reduce(0) { $0 + overlap($1, w) }
        }
    }

    /// Number of event onsets in each bin (inside the window).
    func binCounts(_ onsets: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: binCount)
        for o in onsets where inWindow(o) {
            let i = Int(safe: floor((o - origin) / binSize), fallback: -1)
            if i >= 0 && i < out.count { out[i] += 1 }
        }
        return out
    }

    /// Notes about the window (video too short, injection after the video end…).
    func windowNotes(requestedEnd: Double) -> [Note] {
        var notes: [Note] = []
        if origin >= duration - 1 {
            notes.append(Note(.error, String(format: "The injection time (%.0f s) is after the end of the video.", origin),
                              String(format: "注射时刻（%.0f 秒）晚于视频结束。", origin)))
        } else if origin + requestedEnd > duration + 0.5 {
            notes.append(Note(.warning,
                              String(format: "The video ends %.1f min after the injection, before the end of the analysis window (%.1f min). Totals cover the recorded part only.", (duration - origin) / 60, requestedEnd / 60),
                              String(format: "视频在注射后 %.1f 分钟结束，早于分析窗口终点（%.1f 分钟），总量只包含已录制部分。", (duration - origin) / 60, requestedEnd / 60)))
        }
        return notes
    }
}

/// Applies reviewer edits and the window to detected events.
enum EventReview {
    static func apply(_ events: [BehaviorEvent], overrides: [Int: String], timeline: Timeline) -> [BehaviorEvent] {
        events.map { e in
            var e = e
            if let o = overrides[e.id] {
                e.label = o
                e.edited = o != e.auto
            }
            e.counted = e.label != EventClass.ignore.key && timeline.inWindow(e.onset)
            return e
        }
    }

    static func counted(_ events: [BehaviorEvent], _ key: String) -> [BehaviorEvent] {
        events.filter { $0.counted && $0.label == key }
    }

    static func intervals(_ events: [BehaviorEvent], _ key: String, countedOnly: Bool = false) -> [Interval] {
        events.filter { $0.label == key && (!countedOnly || $0.counted) }.map { Interval(start: $0.onset, end: $0.offset) }
    }
}

enum Kinematics {
    /// Body centre (midpoint of nose and tail base) speed in BL/s, smoothed over `window` s.
    static func bodySpeed(_ s: PoseSeries, window: Double) -> [Double] {
        let n = s.n
        var cx = [Double](repeating: .nan, count: n), cy = cx
        for i in 0..<n {
            if let a = s.p(.nose, i), let b = s.p(.tail, i) { cx[i] = (a.x + b.x) / 2; cy[i] = (a.y + b.y) / 2 }
        }
        let vx = Signal.derivative(cx, t: s.t), vy = Signal.derivative(cy, t: s.t)
        let sp = zip(vx, vy).map { hypot($0, $1) / s.bodyLength }
        return Signal.smooth(sp, window: s.samples(window))
    }

    /// Unsmoothed frame-to-frame speed of one keypoint (BL/s) from the raw track, so brief spikes
    /// (flinches, jerks) are not averaged away. NaN where the keypoint is missing in either frame.
    static func rawSpeed(_ track: PoseTrack, _ k: Kp, threshold: Double, bodyLength: Double, step seconds: Double = 0) -> [Double] {
        let n = track.frameCount
        var out = [Double](repeating: .nan, count: n)
        // A damaged track (keypoint arrays shorter than `times`) yields no speeds rather than a trap.
        guard n > 1, track.safeFrameCount == n else { return out }
        // With `seconds` > 0 the displacement is taken over that time (≥ 1 frame), so keypoint
        // jitter gives the same speed noise at 30 and 60 fps.
        let fps = track.fps > 0 ? track.fps : 30
        let step = seconds > 0 ? max(1, Int(safe: (seconds * fps).rounded())) : 1
        func p(_ i: Int) -> P? {
            guard Double(track.c[k.rawValue][i]) >= threshold, track.x[k.rawValue][i] >= 0 else { return nil }
            return P(x: Double(track.x[k.rawValue][i]), y: Double(track.y[k.rawValue][i]))
        }
        let pts = (0..<n).map(p)
        for i in step..<max(step, n) {
            let dt = track.times[i] - track.times[i - step]
            if let a = pts[i - step], let b = pts[i], dt > 0 { out[i] = a.dist(b) / dt / bodyLength }
        }
        return out
    }

    /// Distance between two keypoints in BL (NaN if either is missing).
    static func distance(_ s: PoseSeries, _ a: Kp, _ b: Kp) -> [Double] {
        (0..<s.n).map { i in
            guard let p = s.p(a, i), let q = s.p(b, i) else { return .nan }
            return p.dist(q) / s.bodyLength
        }
    }

    /// Mouth position, falling back to the nose.
    static func head(_ s: PoseSeries, _ i: Int) -> P? { s.p(.mouth, i) ?? s.p(.nose, i) }

    /// Angle (degrees) between the trunk (tail base → midpoint of the forepaws) and the head
    /// (that midpoint → nose); near 0 when the head points forward, large when it is turned to
    /// the flank. nil when a keypoint is missing.
    static func headTurn(_ s: PoseSeries, _ i: Int) -> Double? {
        guard let a = s.p(.nose, i), let b = s.p(.tail, i), let lf = s.p(.lf, i), let rf = s.p(.rf, i) else { return nil }
        let shoulder = (lf + rf) * 0.5
        guard let hv = (a - shoulder).unit, let tv = (shoulder - b).unit else { return nil }
        return acos(max(-1, min(1, hv.dot(tv)))) * 180 / .pi
    }

    /// Position of a keypoint in the body frame (origin tail base, x toward the nose), in BL.
    static func ego(_ s: PoseSeries, _ k: Kp, _ i: Int) -> P? {
        guard let p = s.p(k, i), let tail = s.p(.tail, i), let nose = s.p(.nose, i), let u = (nose - tail).unit else { return nil }
        let d = (p - tail) * (1 / s.bodyLength)
        return P(x: d.dot(u), y: d.dot(P(x: -u.y, y: u.x)))
    }

    /// log10 of a per-frame feature (NaN stays NaN).
    static func logged(_ v: [Double], floor: Double = 1e-5) -> [Double] { v.map { $0.isFinite ? log10($0 + floor) : .nan } }

    /// Median of a (log) movement-energy signal over the frames in `mask` — the keypoint-jitter
    /// floor of this particular video. Thresholds are raised to floor + margin so noisier
    /// cameras do not turn jitter into behavior.
    static func noiseFloor(_ v: [Double], where mask: [Bool]) -> Double? {
        let sel = zip(v, mask).compactMap { $1 && $0.isFinite ? $0 : nil }
        return sel.count >= 30 ? Signal.median(sel) : nil
    }

    /// Fraction of window frames in which the mouse (nose and tail base) was tracked.
    static func coverage(_ s: PoseSeries, _ tl: Timeline) -> Double {
        let r = s.indices(from: tl.window.start, to: tl.window.end)
        guard !r.isEmpty else { return 0 }
        var c = 0
        for i in r where s.p(.nose, i) != nil && s.p(.tail, i) != nil { c += 1 }
        return Double(c) / Double(r.count)
    }
}

/// Common quality notes for the behavior assays.
enum BehaviorNotes {
    static func quality(_ s: PoseSeries, coverage: Double) -> [Note] {
        var notes: [Note] = []
        if s.bodyLengthEstimated {
            notes.append(Note(.warning,
                              "Nose and tail base were rarely detected, so body length was estimated from the frame size. Thresholds may not fit this video.",
                              "鼻尖和尾根很少被检测到，体长按画面尺寸估算，阈值可能不适合该视频。"))
        }
        if coverage < 0.8 {
            notes.append(Note(.warning,
                              String(format: "The mouse was tracked in only %.0f%% of the analysis window; behavior in untracked frames is not counted.", coverage * 100),
                              String(format: "分析窗口内仅 %.0f%% 的帧跟踪到小鼠，未跟踪帧中的行为不计入。", coverage * 100)))
        }
        return notes
    }

    static func review(_ edited: Int) -> Note {
        Note(.info,
             edited > 0
             ? String(format: "%d events were corrected on the video. Automated detection is a first pass; reviewing events is recommended before reporting.", edited)
             : "Automated detection is a first pass. Review the events on the video (Review tab) and relabel any that are wrong; edits are kept.",
             edited > 0
             ? String(format: "已在视频上修正 %d 个事件。自动检测仅为初筛，报告前建议复核事件。", edited)
             : "自动检测仅为初筛。请在“回放”页逐个复核事件，判断有误的可改标签，修改会保留。")
    }
}
