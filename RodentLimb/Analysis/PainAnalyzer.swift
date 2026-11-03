// PainAnalyzer.swift — spontaneous nocifensive behavior after an intraplantar injection
// (formalin, capsaicin, CFA, …).
//
// Scored as in the formalin test (Dubuisson & Dennis 1977; Hunskaar & Hole 1987): time spent
// licking / biting the injected paw and the number of flinches (rapid lifting / shaking of it),
// in an early phase I (direct activation of nociceptors) and a late phase II (inflammation and
// central sensitization), plus a binned time course.
//
// Detection from the bottom view
//   • Licking / biting: the mouth (or the nose if the mouth is not tracked) is within
//     `lickDistance` body lengths of the injected paw while the body stays in place. When both
//     paws are that close, the nearer one is credited. Bouts closer than `lickMergeGap` are
//     joined; shorter than `minLick` dropped. The same is measured for the contralateral paw
//     as a within-animal control (grooming also involves paw licking).
//   • Flinch: the injected paw's unsmoothed speed (displacement over ~33 ms) exceeds
//     `flinchSpeed` (raised to 4× the paw's resting median on noisy tracks) for at most
//     `flinchMaxDuration` while the body is still (< `flinchBodySpeed` for ±0.3 s), outside licking, and
//     the contralateral paw is not jumping at the same moment (a left/right label swap) and
//     the paw is not being lifted to or from the mouth (±0.5 s around licking).
// Guarding and weight bearing need paw contact area or pressure, which keypoints do not give;
// they are not scored.

import Foundation

enum PainAnalyzer {
    static let lick = EventClass(key: "lick", label: LText("Licking / biting injected paw", "舔咬注射爪"), color: 0xC62828)
    static let lickContra = EventClass(key: "lick_contra", label: LText("Licking the other paw", "舔对侧爪"), color: 0xE69F00)
    static let flinch = EventClass(key: "flinch", label: LText("Flinch / shake", "甩爪 / 抖爪"), color: 0x0072B2)
    static let classes = [lick, flinch, lickContra, EventClass.ignore]

    static func run(track: PoseTrack, series s: PoseSeries, params p: PainParams, overrides: [Int: String]) -> AnalysisResult {
        var notes: [Note] = []
        let n = s.n
        let bl = s.bodyLength
        let end = max(p.phase2End, p.phase1End)
        let tl = Timeline(series: s, videoDuration: track.duration, origin: p.injectionTime, start: 0, end: end, binSize: p.binSize)
        notes += tl.windowNotes(requestedEnd: end)
        let paw = p.injectedPaw.kp, other = p.injectedPaw.contralateral.kp

        let body = Kinematics.bodySpeed(s, window: 0.5)
        func still(_ i: Int, _ limit: Double) -> Bool { body[i].isNaN || body[i] < limit }
        // Still for the surrounding ±0.3 s: paw movement at the start or end of a step is not a flinch.
        let around = s.samples(0.3)
        let bodyMax = (0..<n).map { i -> Double in
            let w = body[max(0, i - around)...min(n - 1, i + around)].filter { $0.isFinite }
            return w.max() ?? .nan
        }
        func stillAround(_ i: Int, _ limit: Double) -> Bool { bodyMax[i].isNaN || bodyMax[i] < limit }

        // Mouth–paw distances (BL).
        var dIpsi = [Double](repeating: .nan, count: n), dContra = dIpsi
        for i in 0..<n {
            guard let h = Kinematics.head(s, i) else { continue }
            if let q = s.p(paw, i) { dIpsi[i] = h.dist(q) / bl }
            if let q = s.p(other, i) { dContra[i] = h.dist(q) / bl }
        }
        var rawIpsi = [Bool](repeating: false, count: n), rawContra = rawIpsi
        for i in 0..<n where still(i, p.maxBodySpeed) {
            let a = dIpsi[i], b = dContra[i]
            let aNear = a.isFinite && a < p.lickDistance, bNear = b.isFinite && b < p.lickDistance
            if aNear && (!bNear || a <= b) { rawIpsi[i] = true } else if bNear { rawContra[i] = true }
        }
        let lickMask = Bouts.clean(rawIpsi, fps: s.fps, gap: p.lickMergeGap, minDuration: p.minLick)
        let contraMask = Bouts.and(Bouts.clean(rawContra, fps: s.fps, gap: p.lickMergeGap, minDuration: p.minLick), Bouts.not(lickMask))

        // Flinches.
        let thr = s.keypointThreshold
        let vPaw = Kinematics.rawSpeed(track, paw, threshold: thr, bodyLength: bl, step: 1.0 / 30)
        let vOther = Kinematics.rawSpeed(track, other, threshold: thr, bodyLength: bl, step: 1.0 / 30)
        // Lifting the paw to the mouth (or putting it down) is fast too: ignore ±0.5 s around licking.
        var nearLick = lickMask
        let pad = s.samples(0.5)
        for r in Signal.runs(Bouts.or(lickMask, contraMask)) {
            for i in max(0, r.lowerBound - pad)..<min(n, r.upperBound + pad) { nearLick[i] = true }
        }
        // Jitter guard: in a noisy track a still paw can "move" fast from frame to frame. The
        // threshold is raised to 4× the paw's median speed while the mouse sits still (for pure
        // jitter that is exceeded on ~1 frame in 10 000).
        let quiet = (0..<n).filter { vPaw[$0].isFinite && still($0, p.flinchBodySpeed) && !nearLick[$0] }.map { vPaw[$0] }
        let flinchThr = max(p.flinchSpeed, quiet.count >= 30 ? 4 * (Signal.median(quiet) ?? 0) : 0)
        if flinchThr > p.flinchSpeed * 1.05 {
            notes.append(Note(.info,
                              String(format: "The paw track is noisy, so the flinch speed threshold was raised from %.1f to %.1f BL/s; small flinches may be missed.", p.flinchSpeed, flinchThr),
                              String(format: "爪部轨迹抖动较大，甩爪速度阈值已从 %.1f 提高到 %.1f BL/s，幅度小的甩爪可能漏检。", p.flinchSpeed, flinchThr)))
        }
        var spike = [Bool](repeating: false, count: n)
        for i in 0..<n where vPaw[i].isFinite && vPaw[i] > flinchThr {
            let swap = vOther[i].isFinite && vOther[i] > flinchThr
            if !swap && stillAround(i, p.flinchBodySpeed) && !nearLick[i] { spike[i] = true }
        }
        // Frames of one flinch can be separated by a frame or two of slower movement.
        spike = Bouts.fillGaps(spike, maxFrames: max(1, s.samples(0.1)))
        var flinchRuns: [(Range<Int>, Interval)] = []
        for (r, iv) in tl.intervals(spike) where iv.duration <= p.flinchMaxDuration + 1e-9 {
            if let last = flinchRuns.last, iv.start - last.1.end < 0.2 { continue }   // ≥ 0.2 s between flinches
            flinchRuns.append((r, iv))
        }

        // Events.
        var events: [BehaviorEvent] = []
        for (r, iv) in tl.intervals(lickMask) {
            let d = Signal.mean(Array(dIpsi[r])).map { String(format: "mouth–paw %.2f BL", $0) }
            events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: iv.end, auto: lick.key, label: lick.key, edited: false, counted: true, info: d))
        }
        for (r, iv) in tl.intervals(contraMask) {
            events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: iv.end, auto: lickContra.key, label: lickContra.key, edited: false, counted: true, info: nil))
        }
        for (r, iv) in flinchRuns {
            let peak = vPaw[r].filter { $0.isFinite }.max()
            events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: max(iv.end, iv.start + 0.1), auto: flinch.key, label: flinch.key,
                                        edited: false, counted: true, info: peak.map { String(format: "peak %.1f BL/s", $0) }))
        }
        // Two events can start on the same frame only if a lick and a flinch coincide; keep ids unique.
        var seen = Set<Int>()
        events = events.sorted { $0.onset < $1.onset }.map { e in
            var e = e
            while seen.contains(e.id) { e.id += 1 }
            seen.insert(e.id)
            return e
        }
        events = EventReview.apply(events, overrides: overrides, timeline: tl)

        let licks = EventReview.counted(events, lick.key)
        let contra = EventReview.counted(events, lickContra.key)
        let flinches = EventReview.counted(events, flinch.key)
        let lickIv = licks.map { Interval(start: $0.onset, end: $0.offset) }
        let contraIv = contra.map { Interval(start: $0.onset, end: $0.offset) }
        let o = tl.origin
        let ph1 = Interval(start: o, end: min(o + p.phase1End, tl.window.end))
        let ph2 = Interval(start: min(o + p.phase2Start, tl.window.end), end: min(o + p.phase2End, tl.window.end))
        let inter = Interval(start: ph1.end, end: max(ph1.end, ph2.start))
        func seconds(_ ivs: [Interval], _ w: Interval) -> Double { ivs.reduce(0) { $0 + tl.overlap($1, w) } }
        func count(_ ev: [BehaviorEvent], _ w: Interval) -> Double { Double(ev.filter { $0.onset >= w.start && $0.onset < w.end }.count) }
        let total = seconds(lickIv, tl.window), totalContra = seconds(contraIv, tl.window)
        let r = s.indices(from: tl.window.start, to: tl.window.end)
        let pawVis = r.isEmpty ? 0 : Double(r.filter { s.p(paw, $0) != nil }.count) / Double(r.count)
        let coverage = Kinematics.coverage(s, tl)
        let edited = events.filter { $0.edited }.count
        let durations = licks.map { $0.duration }

        var metrics: [Metric] = [
            Metric(key: "lick_phase1_s", label: LText("Licking, phase I", "舔咬时间 · I 相"), value: seconds(lickIv, ph1), unit: "s", decimals: 1, highlight: true),
            Metric(key: "lick_phase2_s", label: LText("Licking, phase II", "舔咬时间 · II 相"), value: ph2.duration > 0 ? seconds(lickIv, ph2) : nil, unit: "s", decimals: 1, highlight: true),
            Metric(key: "flinch_n", label: LText("Flinches", "甩爪次数"), value: Double(flinches.count), unit: "", decimals: 0, highlight: true),
            Metric(key: "lick_interphase_s", label: LText("Licking, interphase", "舔咬时间 · 间期"), value: inter.duration > 0 ? seconds(lickIv, inter) : nil, unit: "s", decimals: 1),
            Metric(key: "lick_total_s", label: LText("Licking, whole window", "舔咬时间 · 全程"), value: total, unit: "s", decimals: 1),
            Metric(key: "lick_bouts_n", label: LText("Licking bouts", "舔咬次数"), value: Double(licks.count), unit: "", decimals: 0),
            Metric(key: "lick_latency_s", label: LText("Latency to first licking", "首次舔咬潜伏期"), value: licks.first.map { $0.onset - o }, unit: "s", decimals: 1),
            Metric(key: "lick_bout_mean_s", label: LText("Mean licking bout", "平均每次舔咬"), value: Signal.mean(durations), unit: "s", decimals: 1),
            Metric(key: "flinch_phase1_n", label: LText("Flinches, phase I", "甩爪 · I 相"), value: count(flinches, ph1), unit: "", decimals: 0),
            Metric(key: "flinch_phase2_n", label: LText("Flinches, phase II", "甩爪 · II 相"), value: ph2.duration > 0 ? count(flinches, ph2) : nil, unit: "", decimals: 0),
            Metric(key: "lick_contra_s", label: LText("Licking the other paw", "舔对侧爪时间"), value: totalContra, unit: "s", decimals: 1),
            Metric(key: "lick_ipsi_share_pct", label: LText("Injected paw share of paw licking", "注射爪占舔爪比例"),
                   value: total + totalContra > 0 ? total / (total + totalContra) * 100 : nil, unit: "%", decimals: 0),
            Metric(key: "paw_visibility_pct", label: LText("Injected paw visibility", "注射爪可见率"), value: pawVis * 100, unit: "%", decimals: 0),
            Metric(key: "edited_n", label: LText("Manually edited events", "人工修改事件"), value: Double(edited), unit: "", decimals: 0),
            Metric(key: "pose_coverage_pct", label: LText("Pose coverage", "姿态覆盖率"), value: coverage * 100, unit: "%", decimals: 0),
        ]
        metrics = metrics.grouped([
            (LText("Licking / biting", "舔咬"), ["lick_phase1_s", "lick_phase2_s", "lick_interphase_s", "lick_total_s", "lick_bouts_n", "lick_latency_s", "lick_bout_mean_s"]),
            (LText("Flinching", "甩爪"), ["flinch_n", "flinch_phase1_n", "flinch_phase2_n"]),
            (LText("Control", "对照"), ["lick_contra_s", "lick_ipsi_share_pct"]),
            (LText("Quality", "数据质量"), ["paw_visibility_pct", "edited_n", "pose_coverage_pct"]),
        ])

        if pawVis < 0.6 {
            notes.append(Note(.warning,
                              String(format: "The injected paw (%@) was visible in only %.0f%% of the window. Licking needs the paw and the mouth in view; check the camera angle.", p.injectedPaw.en, pawVis * 100),
                              String(format: "注射爪（%@）仅在窗口内 %.0f%% 的帧可见。识别舔咬需要爪和嘴都在画面中，请检查拍摄角度。", p.injectedPaw.label, pawVis * 100)))
        }
        if s.fps < 50 {
            notes.append(Note(.info, "Flinches are brief; at this frame rate some may be missed. ≥ 60 fps is recommended for flinch counts.",
                              "甩爪动作很短，此帧率下可能有遗漏。统计甩爪建议 ≥ 60 fps。"))
        }
        notes.append(Note(.info, "Guarding and weight bearing are not scored: they need paw contact area or pressure, which keypoints do not provide.",
                          "未评估护爪与负重：需要爪部接触面积或压力信息，关键点无法提供。"))
        notes += BehaviorNotes.quality(s, coverage: coverage)
        if !events.isEmpty { notes.append(BehaviorNotes.review(edited)) }

        let detail = BehaviorDetail(
            classes: classes, events: events,
            tracks: [BehaviorTrack(key: lick.key, label: lick.label, color: lick.color, intervals: EventReview.intervals(events, lick.key)),
                     BehaviorTrack(key: flinch.key, label: flinch.label, color: flinch.color, intervals: EventReview.intervals(events, flinch.key)),
                     BehaviorTrack(key: lickContra.key, label: lickContra.label, color: lickContra.color, intervals: EventReview.intervals(events, lickContra.key))],
            binSize: tl.binSize,
            bins: [BinSeries(key: "lick_s", label: LText("Licking / biting", "舔咬"), unit: "s", values: tl.binSeconds(lickIv)),
                   BinSeries(key: "flinch_n", label: LText("Flinches", "甩爪"), unit: "n", values: tl.binCounts(flinches.map(\.onset))),
                   BinSeries(key: "lick_contra_s", label: LText("Licking the other paw", "舔对侧爪"), unit: "s", values: tl.binSeconds(contraIv))],
            signal: Signal.downsample(t: s.t, v: dIpsi, maxPoints: 1500),
            signalLabel: LText("Mouth – injected paw distance (BL)", "嘴到注射爪距离（BL）"), signalUnit: "BL",
            signalThreshold: p.lickDistance, window: tl.window, origin: o,
            phases: [LabeledInterval(label: LText("Phase I", "I 相"), interval: ph1),
                     LabeledInterval(label: LText("Phase II", "II 相"), interval: ph2)].filter { $0.interval.duration > 0 })
        return AnalysisResult(metrics: metrics, notes: notes, tst: nil, cylinder: nil, gait: nil, analyzedAt: Date(),
                              poseCoverage: coverage, behavior: detail)
    }
}
