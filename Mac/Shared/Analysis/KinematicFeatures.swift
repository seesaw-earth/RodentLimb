// KinematicFeatures.swift — per-frame keypoint features, ported line for line from the training
// notebook (RodentLimb_PublicDatasets_Behavior.ipynb, section 8 `_features_core`), so a model
// trained there (ScratchModel.json) sees exactly the numbers it was trained on.
//
// Differences from PoseSeries (used by the other analyzers): no median filter and no smoothing.
// Fast rhythmic paw movements (scratching strokes, clonus) live in the frame-to-frame jitter that
// smoothing would remove.
//
// Pipeline (all distances in body lengths, BL; all windows in seconds, so 30 and 60 fps match):
//   0. If the video fps differs from FEATURE_FPS by > 0.5, frames round(k·fps/FEATURE_FPS) are
//      used, features are computed at FEATURE_FPS and mapped back to every original frame.
//   1. Keypoint confidence < KPT_CONF or no detection → missing; interior gaps ≤ GAP_FILL_S are
//      linearly interpolated.
//   2. BL = median nose–tail-base distance (needs ≥ 50 frames).
//   3. Body frame: origin tail base, x axis tail base → nose. Paw "high-frequency energy" =
//      squared distance from its own centered 0.2-s rolling median (fast back-and-forth movement).
//   4. Rolling windows follow pandas `rolling(w, center=True, min_periods=max(1, w//3))`, NaN
//      skipped. Final values are rounded to Float32 as in the notebook.

import Foundation

struct FeatureConstants: Codable, Equatable {
    var KPT_CONF: Double = 0.35
    var GAP_FILL_S: Double = 0.25
    var HP_WIN_S: Double = 0.20
    var ZC_MIN_SPEED: Double = 1.0
    var FEATURE_FPS: Double? = 30
    var center_smooth_s: Double = 0.2

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureConstants()
        KPT_CONF = try c.decodeIfPresent(Double.self, forKey: .KPT_CONF) ?? d.KPT_CONF
        GAP_FILL_S = try c.decodeIfPresent(Double.self, forKey: .GAP_FILL_S) ?? d.GAP_FILL_S
        HP_WIN_S = try c.decodeIfPresent(Double.self, forKey: .HP_WIN_S) ?? d.HP_WIN_S
        ZC_MIN_SPEED = try c.decodeIfPresent(Double.self, forKey: .ZC_MIN_SPEED) ?? d.ZC_MIN_SPEED
        FEATURE_FPS = try c.decodeIfPresent(Double.self, forKey: .FEATURE_FPS)
        center_smooth_s = try c.decodeIfPresent(Double.self, forKey: .center_smooth_s) ?? d.center_smooth_s
    }
}

/// Python's `max(1, int(round(sec * fps)))` (round half to even).
@inline(__always) func nwin(_ seconds: Double, _ fps: Double) -> Int {
    max(1, Int(safe: (seconds * fps).rounded(.toNearestOrEven)))
}

/// pandas-compatible centered rolling statistics (window covers i − w/2 … i + (w − 1)/2, NaN
/// skipped, NaN when fewer than `minPeriods` finite values).
enum Rolling {
    @inline(__always) static func bounds(_ i: Int, _ w: Int, _ n: Int) -> (Int, Int) {
        let w = Swift.max(1, w)   // w < 1 would give b < a, and `a...b` traps
        return (Swift.max(0, i - w / 2), Swift.min(n - 1, i + (w - 1) / 2))
    }

    static func mean(_ v: [Double], _ w: Int, _ minPeriods: Int) -> [Double] {
        let n = v.count
        var sum = [Double](repeating: 0, count: n + 1), cnt = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            let ok = v[i].isFinite
            sum[i + 1] = sum[i] + (ok ? v[i] : 0)
            cnt[i + 1] = cnt[i] + (ok ? 1 : 0)
        }
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let (a, b) = bounds(i, w, n)
            let c = cnt[b + 1] - cnt[a]
            if c >= minPeriods && c > 0 { out[i] = (sum[b + 1] - sum[a]) / Double(c) }
        }
        return out
    }

    /// Sample standard deviation (ddof = 1).
    static func std(_ v: [Double], _ w: Int, _ minPeriods: Int) -> [Double] {
        let n = v.count
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let (a, b) = bounds(i, w, n)
            var s = 0.0, c = 0
            for k in a...b where v[k].isFinite { s += v[k]; c += 1 }
            guard c >= minPeriods, c >= 2 else { continue }
            let m = s / Double(c)
            var ss = 0.0
            for k in a...b where v[k].isFinite { ss += (v[k] - m) * (v[k] - m) }
            out[i] = (ss / Double(c - 1)).squareRoot()
        }
        return out
    }

    static func max(_ v: [Double], _ w: Int, _ minPeriods: Int) -> [Double] {
        let n = v.count
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let (a, b) = bounds(i, w, n)
            var m = -Double.infinity, c = 0
            for k in a...b where v[k].isFinite { m = Swift.max(m, v[k]); c += 1 }
            if c >= minPeriods && c > 0 { out[i] = m }
        }
        return out
    }

    static func median(_ v: [Double], _ w: Int, _ minPeriods: Int = 1) -> [Double] {
        let n = v.count
        var out = [Double](repeating: .nan, count: n)
        var buf: [Double] = []
        buf.reserveCapacity(Swift.max(0, Swift.min(w, n)))
        for i in 0..<n {
            let (a, b) = bounds(i, w, n)
            buf.removeAll(keepingCapacity: true)
            for k in a...b where v[k].isFinite { buf.append(v[k]) }
            guard buf.count >= minPeriods, !buf.isEmpty else { continue }
            buf.sort()
            let m = buf.count / 2
            out[i] = buf.count % 2 == 1 ? buf[m] : (buf[m - 1] + buf[m]) / 2
        }
        return out
    }
}

/// NaN-ignoring min / max (numpy fmin / fmax).
@inline(__always) func fmin2(_ a: Double, _ b: Double) -> Double { a.isNaN ? b : (b.isNaN ? a : Swift.min(a, b)) }
@inline(__always) func fmax2(_ a: Double, _ b: Double) -> Double { a.isNaN ? b : (b.isNaN ? a : Swift.max(a, b)) }
@inline(__always) func f32(_ v: Double) -> Double { Double(Float(v)) }

final class KinematicFeatures {
    /// Original frame count and fps.
    let n: Int
    let fps: Double
    /// Rate the features are computed at, and the feature-frame index of every original frame.
    let featureFps: Double
    let back: [Int]
    /// Body length in pixels.
    let bodyLength: Double
    let constants: FeatureConstants

    private var base: [String: [Double]] = [:]
    private var cache: [String: [Double]] = [:]

    /// Base signals (per feature frame).
    static let baseNames: [String] = {
        var names = ["speed", "turn", "blen", "hind_head_min", "fore_mouth_min", "hind_sep", "fore_sep", "nose_e",
                     "hind_e_max", "hind_e_min", "fore_e_max", "hind_v_max", "fore_v_max", "hind_zc_max",
                     "fore_zc_max", "hind_e_asym", "hind_c_min", "n_conf", "det"]
        for p in ["lf", "lh", "rf", "rh"] { names += ["\(p)_ex", "\(p)_ey", "\(p)_v", "\(p)_e", "\(p)_zc", "\(p)_c"] }
        return names
    }()

    /// Returns nil when the body length cannot be estimated (nose and tail base reliable in < 50
    /// frames) — the notebook then falls back to detection boxes, which the app does not store.
    init?(track: PoseTrack, constants: FeatureConstants = FeatureConstants()) {
        self.constants = constants
        let T = track.frameCount
        n = T
        var f = track.fps
        if !(f > 1), T > 1, let last = track.times.last, last > 0 { f = Double(T - 1) / last }
        fps = f > 1 && f.isFinite ? f : 30
        guard T > 1 else { return nil }
        // A damaged track whose arrays disagree in length would index out of range below.
        guard track.boxConfidence.count >= T, track.safeFrameCount == T else { return nil }

        // 0. Resampling.
        var idx: [Int] = Array(0..<T)
        var ffps = fps
        var backMap: [Int] = Array(0..<T)
        if let target = constants.FEATURE_FPS, target > 0, target.isFinite, abs(fps - target) > 0.5 {
            let step = fps / target
            var sel: [Int] = []
            var k = 0
            while Double(k) * step < Double(T) {
                let r = Int(safe: (Double(k) * step).rounded(.toNearestOrEven))
                let c = Swift.min(Swift.max(r, 0), T - 1)
                if sel.last != c { sel.append(c) }   // np.unique on a non-decreasing sequence
                k += 1
            }
            guard !sel.isEmpty else { return nil }
            idx = sel
            ffps = target
            backMap = (0..<T).map { t in Swift.min(Swift.max(Int(safe: (Double(t) / step).rounded(.toNearestOrEven)), 0), sel.count - 1) }
        }
        featureFps = ffps
        back = backMap
        let m = idx.count

        // 1. Keypoints.
        let K = Kp.allCases.count
        var det = [Bool](repeating: false, count: m)
        var conf = [[Double]](repeating: [Double](repeating: 0, count: m), count: K)
        var px = [[Double]](repeating: [Double](repeating: .nan, count: m), count: K)
        var py = px
        var nConf = [Double](repeating: 0, count: m)
        for (j, i) in idx.enumerated() {
            det[j] = track.boxConfidence[i] > 0
            for k in 0..<K {
                let c = Double(track.c[k][i])
                let cc = c.isFinite ? c : 0
                conf[k][j] = det[j] ? cc : 0
                let x = Double(track.x[k][i]), y = Double(track.y[k][i])
                if det[j] && cc >= constants.KPT_CONF && x >= 0 && y >= 0 {
                    px[k][j] = x; py[k][j] = y
                    nConf[j] += 1
                }
            }
        }
        let g = nwin(constants.GAP_FILL_S, ffps)
        for k in 0..<K {
            px[k] = Signal.fillGaps(px[k], maxGap: g)
            py[k] = Signal.fillGaps(py[k], maxGap: g)
        }

        // 2. Body length.
        let NO = Kp.nose.rawValue, TB = Kp.tail.rawValue, MO = Kp.mouth.rawValue
        var blv = [Double](repeating: .nan, count: m)
        for j in 0..<m { blv[j] = hypot(px[NO][j] - px[TB][j], py[NO][j] - py[TB][j]) }
        guard blv.filter({ $0.isFinite }).count >= 50, let BL = Signal.median(blv), BL >= 2 else { return nil }
        bodyLength = BL

        // 3. Signals.
        var S: [String: [Double]] = [:]
        let hpw = nwin(constants.HP_WIN_S, ffps)
        var ux = [Double](repeating: .nan, count: m), uy = ux
        var headX = ux, headY = ux
        for j in 0..<m {
            ux[j] = (px[NO][j] - px[TB][j]) / blv[j]
            uy[j] = (py[NO][j] - py[TB][j]) / blv[j]
            if px[MO][j].isFinite { headX[j] = px[MO][j]; headY[j] = py[MO][j] } else { headX[j] = px[NO][j]; headY[j] = py[NO][j] }
        }
        // Body centre: midpoint of nose and tail base, smoothed by a centered rolling median.
        var cxr = [Double](repeating: .nan, count: m), cyr = cxr
        for j in 0..<m { cxr[j] = (px[NO][j] + px[TB][j]) / 2; cyr[j] = (py[NO][j] + py[TB][j]) / 2 }
        let csw = nwin(constants.center_smooth_s, ffps)
        let cxs = Rolling.median(cxr, csw), cys = Rolling.median(cyr, csw)
        var speed = [Double](repeating: .nan, count: m)
        for j in 0..<m {
            let a = j == 0 ? 0 : j - 1
            speed[j] = hypot(cxs[j] - cxs[a], cys[j] - cys[a]) * ffps / BL
        }
        S["speed"] = speed
        var turn = [Double](repeating: .nan, count: m)
        for j in 1..<m {
            let cr = ux[j - 1] * uy[j] - uy[j - 1] * ux[j]
            let dt = ux[j] * ux[j - 1] + uy[j] * uy[j - 1]
            turn[j] = abs(atan2(cr, dt)) * ffps
        }
        S["turn"] = turn
        S["blen"] = blv.map { $0 / BL }

        func dist(_ a: Int, _ bx: [Double], _ by: [Double]) -> [Double] {
            (0..<m).map { j in hypot(px[a][j] - bx[j], py[a][j] - by[j]) / BL }
        }
        let paws: [(String, Kp)] = [("lf", .lf), ("lh", .lh), ("rf", .rf), ("rh", .rh)]
        for (name, kp) in paws {
            let k = kp.rawValue
            var ex = [Double](repeating: .nan, count: m), ey = ex
            for j in 0..<m {
                let dx = (px[k][j] - px[TB][j]) / BL, dy = (py[k][j] - py[TB][j]) / BL
                ex[j] = dx * ux[j] + dy * uy[j]
                ey[j] = dx * (-uy[j]) + dy * ux[j]
            }
            var vx = [Double](repeating: .nan, count: m), vy = vx
            for j in 1..<m { vx[j] = ex[j] - ex[j - 1]; vy[j] = ey[j] - ey[j - 1] }
            let spd = (0..<m).map { hypot(vx[$0], vy[$0]) * ffps }
            let mx = Rolling.median(ex, hpw), my = Rolling.median(ey, hpw)
            var e = [Double](repeating: .nan, count: m), zc = e
            func sgn(_ v: Double) -> Double { v.isNaN ? .nan : (v > 0 ? 1 : (v < 0 ? -1 : 0)) }
            for j in 0..<m {
                let dx = ex[j] - mx[j], dy = ey[j] - my[j]
                e[j] = dx * dx + dy * dy
                if spd[j].isFinite {
                    var flip = false
                    if j > 0 {
                        flip = sgn(vx[j]) * sgn(vx[j - 1]) < 0 || sgn(vy[j]) * sgn(vy[j - 1]) < 0
                    }
                    zc[j] = (flip && spd[j] > constants.ZC_MIN_SPEED) ? 1 : 0
                }
            }
            S["\(name)_ex"] = ex; S["\(name)_ey"] = ey; S["\(name)_v"] = spd
            S["\(name)_e"] = e; S["\(name)_zc"] = zc; S["\(name)_c"] = conf[k]
        }
        S["hind_head_min"] = zip(dist(Kp.lh.rawValue, headX, headY), dist(Kp.rh.rawValue, headX, headY)).map { fmin2($0, $1) }
        S["fore_mouth_min"] = zip(dist(Kp.lf.rawValue, headX, headY), dist(Kp.rf.rawValue, headX, headY)).map { fmin2($0, $1) }
        S["hind_sep"] = dist(Kp.lh.rawValue, px[Kp.rh.rawValue], py[Kp.rh.rawValue])
        S["fore_sep"] = dist(Kp.lf.rawValue, px[Kp.rf.rawValue], py[Kp.rf.rawValue])
        let nmx = Rolling.median(px[NO], hpw), nmy = Rolling.median(py[NO], hpw)
        S["nose_e"] = (0..<m).map { j in
            let dx = px[NO][j] - nmx[j], dy = py[NO][j] - nmy[j]
            return (dx * dx + dy * dy) / (BL * BL)
        }
        func pair(_ a: String, _ b: String, _ f: (Double, Double) -> Double) -> [Double] {
            zip(S[a]!, S[b]!).map { f($0, $1) }
        }
        S["hind_e_max"] = pair("lh_e", "rh_e", fmax2)
        S["hind_e_min"] = pair("lh_e", "rh_e", fmin2)
        S["fore_e_max"] = pair("lf_e", "rf_e", fmax2)
        S["hind_v_max"] = pair("lh_v", "rh_v", fmax2)
        S["fore_v_max"] = pair("lf_v", "rf_v", fmax2)
        S["hind_zc_max"] = pair("lh_zc", "rh_zc", fmax2)
        S["fore_zc_max"] = pair("lf_zc", "rf_zc", fmax2)
        S["hind_e_asym"] = pair("lh_e", "rh_e") { abs($0 - $1) }
        S["hind_c_min"] = pair("lh_c", "rh_c", fmin2)
        S["n_conf"] = nConf
        S["det"] = det.map { $0 ? 1 : 0 }
        base = S
    }

    var featureFrames: Int { base["det"]?.count ?? 0 }

    /// A notebook feature column at feature frames (Float32-rounded, as `X.astype(np.float32)`),
    /// or nil if it cannot be computed in the app (e.g. detection-box features).
    func column(_ name: String) -> [Double]? {
        if let c = cache[name] { return c }
        guard let o = raw(name) else { return nil }
        let r = o.map(f32)
        cache[name] = r
        return r
    }

    /// Unrounded values (the notebook rounds only once, at the very end).
    private var rawCache: [String: [Double]] = [:]

    private func raw(_ name: String) -> [Double]? {
        if let b = base[name] { return b }
        if let c = rawCache[name] { return c }
        var out: [Double]?
        if name.hasPrefix("P_") {
            let fp = featureFps
            switch name {
            case "P_log_hind_e": out = raw("hind_e_max_m05")?.map { log10($0 + 1e-5) }
            case "P_hind_head": out = raw("hind_head_min_m05")
            case "P_log_speed": out = raw("speed_m05")?.map { log10($0 + 1e-3) }
            case "P_blen": out = raw("blen_m05")
            case "P_hind_zc_hz": out = raw("hind_zc_max_m05")?.map { $0 * fp }
            case "P_conf": out = raw("n_conf_m05")?.map { $0 / Double(Kp.allCases.count) }
            default: out = nil
            }
        } else {
            let windows: [(String, Double, String)] = [("_m05", 0.5, "mean"), ("_m2", 2.0, "mean"), ("_s05", 0.5, "std"), ("_x1", 1.0, "max")]
            if let (suffix, sec, how) = windows.first(where: { name.hasSuffix($0.0) }),
               let v = base[String(name.dropLast(suffix.count))] {
                let w = nwin(sec, featureFps), mp = Swift.max(1, w / 3)
                switch how {
                case "mean": out = Rolling.mean(v, w, mp)
                case "std": out = Rolling.std(v, w, mp)
                default: out = Rolling.max(v, w, mp)
                }
            }
        }
        if let o = out { rawCache[name] = o }
        return out
    }

    /// A feature column mapped back to every original video frame.
    func perFrame(_ name: String) -> [Double]? {
        guard let c = column(name) else { return nil }
        return back.map { c[$0] }
    }
}
