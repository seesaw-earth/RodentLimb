// QualityControl.swift — tracking quality of one video, computed once after pose detection and
// before the video is assigned to any task.
//
// The report answers: was the mouse found, which keypoints were tracked, how much of what is
// missing can be bridged by short-gap filling, how long are the stretches that cannot, are there
// implausible jumps, and is the video itself suitable (frame rate, regular timing). The verdict
// follows inclusion criteria set before analysis (per study, see Experiment.qc), as ARRIVE 2.0
// item 3 asks: criteria are stated in advance, and every exclusion is reported with its reason.
//
// Foundation only (also compiled on Linux by Tools/validation).

import Foundation

enum QCVerdict: String, Codable, CaseIterable {
    case pass, warn, fail

    var label: LText {
        switch self {
        case .pass: return LText("QC passed", "QC 通过")
        case .warn: return LText("QC warning", "QC 警告")
        case .fail: return LText("QC failed", "QC 未通过")
        }
    }
    var symbol: String {
        switch self {
        case .pass: return "checkmark.seal.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        }
    }
}

/// Inclusion criteria (set per study before scoring).
struct QCCriteria: Codable, Equatable {
    /// Share of frames in which the mouse (nose and tail base) is usable after short-gap filling.
    var passCoverage: Double = 0.90
    /// Below this the video fails (between the two: warning, needs a decision).
    var failCoverage: Double = 0.70
    /// Longest stretch without the mouse (s) that still passes.
    var maxLostSeconds: Double = 10
    /// Lowest frame rate that passes (fast behaviours need ≥ 60 fps; see the assay tips).
    var minFPS: Double = 25
    /// Share of frames with implausible jumps that still passes.
    var maxJumpRate: Double = 0.02

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = QCCriteria()
        passCoverage = (try? c.decodeIfPresent(Double.self, forKey: .passCoverage)) ?? d.passCoverage
        failCoverage = (try? c.decodeIfPresent(Double.self, forKey: .failCoverage)) ?? d.failCoverage
        maxLostSeconds = (try? c.decodeIfPresent(Double.self, forKey: .maxLostSeconds)) ?? d.maxLostSeconds
        minFPS = (try? c.decodeIfPresent(Double.self, forKey: .minFPS)) ?? d.minFPS
        maxJumpRate = (try? c.decodeIfPresent(Double.self, forKey: .maxJumpRate)) ?? d.maxJumpRate
    }

    /// One line for the methods text (English).
    var methods: String {
        String(format: "Videos were included when the mouse (nose and tail base) was tracked in ≥ %.0f%% of frames after short-gap filling, no untracked stretch exceeded %.0f s, implausible keypoint jumps affected ≤ %.1f%% of frames and the frame rate was ≥ %.0f fps; videos meeting every criterion were included automatically; every other video (coverage below %.0f%% was rated a QC failure) was reviewed on the video and included or excluded with a stated reason.",
               passCoverage * 100, maxLostSeconds, maxJumpRate * 100, minFPS, failCoverage * 100)
    }
}

struct QCReport: Codable, Equatable {
    var frames: Int
    var fps: Double
    var duration: Double
    /// Frames with the mouse detected at all (box found).
    var detection: Double
    /// Per keypoint (Kp order): share of frames above the confidence threshold.
    var rawCoverage: [Double]
    /// Per keypoint: share of frames usable after filling gaps ≤ max gap.
    var filledCoverage: [Double]
    /// Nose and tail base both usable after filling (the body: speed, body length, orientation).
    var coreCoverage: Double
    /// Share of missing keypoint samples that short-gap filling recovers.
    var recoverable: Double
    /// Longest stretch without the body (s), and the number of untracked stretches that are not
    /// filled (longer than max gap, or at the start or end of the video).
    var longestLost: Double
    var longGaps: Int
    /// Share of frames in which at least one keypoint jumps implausibly.
    var jumpRate: Double
    var bodyLength: Double?
    /// Coefficient of variation of the nose–tail-base distance (posture changes + tracking noise).
    var bodyLengthCV: Double?
    /// Irregularity of frame timing (CV of frame intervals; > 0.1 = variable frame rate).
    var timingCV: Double
    /// Untracked stretches of the body ≥ 0.5 s (video seconds; at most 500 listed).
    var lostSegments: [Interval]
    /// Share of frames with the body usable, in up to 240 equal bins across the video.
    var timeline: [Double]
    var verdict: QCVerdict
    var issues: [Note]
    var computedAt: Date
}

enum QualityControl {
    static func report(track: PoseTrack, params: CommonParams = CommonParams(), criteria: QCCriteria = QCCriteria()) -> QCReport {
        let n = track.safeFrameCount
        let k = Kp.allCases.count
        var fps = track.fps.isFinite && track.fps > 1 ? track.fps : 30
        var intervals: [Double] = []
        if n > 1 {
            intervals.reserveCapacity(min(n, 20_000))
            var i = 1
            let step = max(1, n / 20_000)
            while i < n {
                let d = track.times[i] - track.times[i - 1]
                if d.isFinite && d > 0 { intervals.append(d) }
                i += step
            }
        }
        if let md = Signal.median(intervals), md > 0 { fps = 1 / md }
        let dt = 1 / fps
        let timingCV: Double = {
            guard let m = Signal.mean(intervals), m > 0, let sd = Signal.sd(intervals) else { return 0 }
            return sd / m
        }()
        let duration = max(track.duration.finiteOr(0), Double(n) * dt)
        let maxGap = max(0, Int(safe: (params.maxGap / dt).rounded()))

        guard n > 0 else {
            return QCReport(frames: 0, fps: fps, duration: duration, detection: 0,
                            rawCoverage: Array(repeating: 0, count: k), filledCoverage: Array(repeating: 0, count: k),
                            coreCoverage: 0, recoverable: 0, longestLost: duration, longGaps: 0, jumpRate: 0,
                            bodyLength: nil, bodyLengthCV: nil, timingCV: timingCV, lostSegments: [], timeline: [],
                            verdict: .fail,
                            issues: [Note(.error, "No frames were tracked.", "没有追踪到任何帧。")], computedAt: Date())
        }

        // Tracked masks per keypoint (confidence filter), and after short-gap filling.
        var raw: [[Bool]] = []
        var filled: [[Bool]] = []
        var missingTotal = 0, recovered = 0
        for kp in Kp.allCases {
            var m = [Bool](repeating: false, count: n)
            for i in 0..<n where Double(track.c[kp.rawValue][i]) >= params.keypointThreshold
                && track.x[kp.rawValue][i] >= 0 && track.y[kp.rawValue][i] >= 0 {
                m[i] = true
            }
            var f = m
            var i = 0
            while i < n {
                if !m[i] {
                    var j = i
                    while j < n && !m[j] { j += 1 }
                    missingTotal += j - i
                    if i > 0 && j < n && j - i <= maxGap {
                        for q in i..<j { f[q] = true }
                        recovered += j - i
                    }
                    i = j
                } else {
                    i += 1
                }
            }
            raw.append(m)
            filled.append(f)
        }
        let rawCoverage = raw.map { Double($0.filter { $0 }.count) / Double(n) }
        let filledCoverage = filled.map { Double($0.filter { $0 }.count) / Double(n) }
        let nose = Kp.nose.rawValue, tail = Kp.tail.rawValue
        var core = [Bool](repeating: false, count: n)
        for i in 0..<n { core[i] = filled[nose][i] && filled[tail][i] }
        let coreCoverage = Double(core.filter { $0 }.count) / Double(n)
        let detection = Double(track.boxConfidence.prefix(n).filter { $0 > 0 }.count) / Double(n)

        // Lost stretches of the body.
        var lost: [Interval] = []
        var longest = 0.0, longGaps = 0
        var i = 0
        while i < n {
            if !core[i] {
                var j = i
                while j < n && !core[j] { j += 1 }
                let a = track.times[i].finiteOr(Double(i) * dt)
                let b = j < n ? track.times[j].finiteOr(Double(j) * dt) : duration
                let len = max(0, b - a)
                longest = max(longest, len)
                longGaps += 1
                if len >= 0.5 && lost.count < 500 { lost.append(Interval(start: a, end: b)) }
                i = j
            } else {
                i += 1
            }
        }

        // Body length (raw tracked frames) and its variability.
        var lengths: [Double] = []
        lengths.reserveCapacity(n)
        for i in 0..<n where raw[nose][i] && raw[tail][i] {
            let dx = Double(track.x[nose][i] - track.x[tail][i]), dy = Double(track.y[nose][i] - track.y[tail][i])
            lengths.append((dx * dx + dy * dy).squareRoot())
        }
        let bodyLength = lengths.count >= 10 ? Signal.median(lengths) : nil
        var bodyCV: Double?
        if let m = Signal.mean(lengths), m > 0, let sd = Signal.sd(lengths) { bodyCV = sd / m }

        // Implausible jumps: a keypoint moves more than max(0.5 BL, 15 BL/s) between frames and
        // comes back on the next frame (a wrong detection rather than real movement).
        var jumpFrames = 0
        if let bl = bodyLength, bl > 1, n > 2 {
            let thr = max(0.5 * bl, 15 * bl * dt)
            for i in 1..<(n - 1) {
                var jumped = false
                for kp in 0..<k where raw[kp][i] && raw[kp][i - 1] && raw[kp][i + 1] {
                    let x0 = Double(track.x[kp][i - 1]), y0 = Double(track.y[kp][i - 1])
                    let x1 = Double(track.x[kp][i]), y1 = Double(track.y[kp][i])
                    let x2 = Double(track.x[kp][i + 1]), y2 = Double(track.y[kp][i + 1])
                    let away = hypot(x1 - x0, y1 - y0), back = hypot(x2 - x1, y2 - y1), across = hypot(x2 - x0, y2 - y0)
                    if away > thr && back > thr && across < thr { jumped = true; break }
                }
                if jumped { jumpFrames += 1 }
            }
        }
        let jumpRate = Double(jumpFrames) / Double(n)

        // Coverage timeline.
        let bins = min(240, n)
        var timeline = [Double](repeating: 0, count: bins)
        var counts = [Int](repeating: 0, count: bins)
        for i in 0..<n {
            let b = min(bins - 1, i * bins / n)
            counts[b] += 1
            if core[i] { timeline[b] += 1 }
        }
        for b in 0..<bins where counts[b] > 0 { timeline[b] /= Double(counts[b]) }

        // Verdict and explanations.
        var issues: [Note] = []
        var verdict = QCVerdict.pass
        func worsen(_ v: QCVerdict) {
            if v == .fail || (v == .warn && verdict == .pass) { verdict = v }
        }
        if coreCoverage < criteria.failCoverage {
            worsen(.fail)
            issues.append(Note(.error,
                               String(format: "The mouse was usable in only %.0f%% of frames (criterion: ≥ %.0f%%). Exclude the video, or check the camera view and lower the detection threshold in Settings before re-running.", coreCoverage * 100, criteria.passCoverage * 100),
                               String(format: "仅 %.0f%% 的帧可用（标准：≥ %.0f%%）。建议排除该视频，或检查拍摄视角、在“设置”中降低检测阈值后重新识别。", coreCoverage * 100, criteria.passCoverage * 100)))
        } else if coreCoverage < criteria.passCoverage {
            worsen(.warn)
            issues.append(Note(.warning,
                               String(format: "The mouse was usable in %.0f%% of frames (criterion: ≥ %.0f%%). Check the untracked stretches on the video before deciding.", coreCoverage * 100, criteria.passCoverage * 100),
                               String(format: "%.0f%% 的帧可用（标准：≥ %.0f%%）。请在视频上查看丢失片段后再决定是否纳入。", coreCoverage * 100, criteria.passCoverage * 100)))
        }
        if longest > criteria.maxLostSeconds {
            worsen(.warn)
            issues.append(Note(.warning,
                               String(format: "The mouse was lost for %.1f s at a stretch (criterion: ≤ %.0f s). Behaviour in that stretch is not scored.", longest, criteria.maxLostSeconds),
                               String(format: "小鼠连续丢失 %.1f 秒（标准：≤ %.0f 秒），该时段的行为不计分。", longest, criteria.maxLostSeconds)))
        }
        if jumpRate > criteria.maxJumpRate {
            worsen(.warn)
            issues.append(Note(.warning,
                               String(format: "Implausible keypoint jumps in %.1f%% of frames (wrong detections or left/right swaps). Consider \"Remove implausible jumps\" in Parameters, and refining the model with these frames.", jumpRate * 100),
                               String(format: "%.1f%% 的帧出现不合理跳点（误检或左右互换）。可在“参数”中开启“剔除不合理跳点”，并用这些帧补充标注、重训模型。", jumpRate * 100)))
        }
        if fps < criteria.minFPS {
            worsen(.warn)
            issues.append(Note(.warning,
                               String(format: "%.0f fps is below the criterion (%.0f fps). Fast movements (steps, scratching, flinches) may be missed.", fps, criteria.minFPS),
                               String(format: "帧率 %.0f fps 低于标准（%.0f fps），快速动作（步态、抓挠、甩爪）可能漏检。", fps, criteria.minFPS)))
        }
        if timingCV > 0.1 {
            issues.append(Note(.info,
                               "Frame timing is irregular (variable frame rate). Timestamps are used, so durations stay correct; converting to constant frame rate is still recommended.",
                               "帧间隔不规则（可变帧率）。分析使用真实时间戳，时长仍正确；仍建议转为恒定帧率。"))
        }
        if bodyLength == nil {
            worsen(.fail)
            issues.append(Note(.error, "Nose and tail base were almost never tracked, so body size is unknown.",
                               "鼻尖和尾根几乎从未被追踪到，无法确定体长。"))
        } else if let cv = bodyCV, cv > 0.35 {
            issues.append(Note(.info,
                               String(format: "Body length varies a lot (CV %.0f%%): rearing, curling or unstable nose / tail-base tracking.", cv * 100),
                               String(format: "体长变化很大（CV %.0f%%）：竖立、蜷缩，或鼻尖/尾根追踪不稳定。", cv * 100)))
        }
        let missingShare = 1 - (rawCoverage.reduce(0, +) / Double(k))
        if missingShare > 0.01 {
            let rec = missingTotal > 0 ? Double(recovered) / Double(missingTotal) : 1
            issues.append(Note(.info,
                               String(format: "%.0f%% of keypoint samples are missing; %.0f%% of those lie in gaps ≤ %.2f s and are filled, the rest stay missing and are excluded.", missingShare * 100, rec * 100, params.maxGap),
                               String(format: "%.0f%% 的关键点样本缺失，其中 %.0f%% 位于 ≤ %.2f 秒的短缺口内会被填补，其余保持缺失、不参与计算。", missingShare * 100, rec * 100, params.maxGap)))
        }

        return QCReport(frames: n, fps: fps, duration: duration, detection: detection,
                        rawCoverage: rawCoverage, filledCoverage: filledCoverage, coreCoverage: coreCoverage,
                        recoverable: missingTotal > 0 ? Double(recovered) / Double(missingTotal) : 1,
                        longestLost: longest, longGaps: max(0, longGaps), jumpRate: jumpRate,
                        bodyLength: bodyLength, bodyLengthCV: bodyCV, timingCV: timingCV,
                        lostSegments: lost, timeline: timeline, verdict: verdict, issues: issues, computedAt: Date())
    }

    /// Frames worth labelling to refine the model (DeepLabCut "outlier frames" idea): the middle
    /// frame of every untracked stretch plus, per keypoint, at most one low-confidence frame per
    /// second. Frames with several reasons are listed once; long lists are thinned evenly over the
    /// whole video so the sample is not taken from the start only.
    static func refinementCSV(track: PoseTrack, report: QCReport, threshold: Double = 0.3, maxRows: Int = 1500) -> String {
        var out = "frame,time_s,reason\n"
        let n = min(track.safeFrameCount, track.times.count)
        guard n > 0 else { return out }
        var reasons: [Int: [String]] = [:]
        for seg in report.lostSegments {
            if let i = track.frameIndex(at: (seg.start + seg.end) / 2), i < n { reasons[i, default: []].append("body_not_tracked") }
        }
        let spacing = max(1, Int(safe: report.fps.rounded()))
        for kp in Kp.allCases where kp.rawValue < track.c.count {
            let conf = track.c[kp.rawValue]
            var lastAdded = -spacing - 1
            for i in 0..<min(n, conf.count) where Double(conf[i]) < threshold && i - lastAdded > spacing {
                reasons[i, default: []].append("low_confidence_" + kp.exportName)
                lastAdded = i
            }
        }
        var frames = reasons.keys.sorted()
        if frames.count > maxRows, maxRows > 0 {
            let step = Double(frames.count) / Double(maxRows)
            frames = (0..<maxRows).map { frames[min(frames.count - 1, Int(Double($0) * step))] }
        }
        for i in frames {
            out += "\(i),\(String(format: "%.4f", track.times[i])),\((reasons[i] ?? []).joined(separator: ";"))\n"
        }
        return out
    }
}
