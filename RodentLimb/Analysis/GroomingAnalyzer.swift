// GroomingAnalyzer.swift — self-grooming amount and microstructure.
//
// Grooming runs head-to-tail in mice (cephalocaudal "syntax": paw licking → nose/face wash →
// head wash → body grooming → leg licking → tail/genital grooming; Kalueff et al. 2007, 2016).
// Reported: total time, number of bouts, latency, bout duration, time per body region,
// interrupted bouts and the share of incorrect (not head-to-tail) transitions.
//
// From the bottom view four regions can be told apart, each only while the body stays in place:
//   • face / head  — both forepaws (or one, the other hidden) within `faceDistance` of the mouth
//                    and moving rapidly (stroking: fast forepaw movement above `strokeEnergy` and
//                    above this video's own keypoint-jitter floor);
//   • body (flank) — head turned more than `headTurn` from the trunk axis, head moving;
//   • hind leg / paw — mouth within `legDistance` of a hind paw;
//   • tail / genitals — nose within `tailDistance` of the tail base (curled up).
// Scratching (fast hind-paw movement near the head) is excluded and reported separately.
// Region segments shorter than `minPhase` are dropped; a pause longer than `boutGap` (5 s;
// Estanislau 2012) ends a bout, and shorter pauses (≥ 1 s)
// make the bout "interrupted". A transition is incorrect when it does not move one region down
// the chain (face → body → leg → tail); % incorrect transitions and % interrupted bouts are the
// microstructure measures most sensitive to stress (Kalueff & Tuohimaa 2005).
// The four-region syntax is coarser than the observer scale; treat it as exploratory.

import Foundation

enum GroomingAnalyzer {
    static let groom = EventClass(key: "groom", label: LText("Grooming bout", "理毛"), color: 0x2E7D32)
    static let classes = [groom, EventClass.ignore]

    enum Region: Int, CaseIterable {
        case face, body, leg, tail
        var key: String { ["face", "body", "leg", "tail"][rawValue] }
        var label: LText {
            switch self {
            case .face: return LText("Face / head", "面部 / 头部")
            case .body: return LText("Body (flank)", "躯体（侧腹）")
            case .leg: return LText("Hind leg / paw", "后腿 / 后爪")
            case .tail: return LText("Tail / genitals", "尾部 / 生殖区")
            }
        }
        var color: UInt32 { [0x56B4E9, 0x009E73, 0xE69F00, 0xCC79A7][rawValue] }
        var short: String { ["face", "body", "leg", "tail"][rawValue] }
    }

    static func run(track: PoseTrack, series s: PoseSeries, params p: GroomingParams, overrides: [Int: String]) -> AnalysisResult {
        var notes: [Note] = []
        let n = s.n
        let bl = s.bodyLength
        let tl = Timeline(series: s, videoDuration: track.duration, origin: 0, start: p.windowStart, end: p.windowEnd, binSize: p.binSize)
        notes += tl.windowNotes(requestedEnd: p.windowEnd)

        let body = Kinematics.bodySpeed(s, window: 0.5)
        let fx = KinematicFeatures(track: track)
        let foreE = Kinematics.logged(fx?.perFrame("fore_e_max_m05") ?? [])
        let noseE = Kinematics.logged(fx?.perFrame("nose_e_m05") ?? [], floor: 1e-6)
        let hindE = Kinematics.logged(fx?.perFrame("hind_e_max_m05") ?? [])
        let hindHead = fx?.perFrame("hind_head_min_m05") ?? []
        if fx == nil {
            notes.append(Note(.warning, "Paw movement could not be measured (nose and tail base rarely tracked); grooming is scored from posture only.",
                              "无法计算爪部运动（鼻尖与尾根很少被跟踪），理毛仅按姿态判断。"))
        }
        func val(_ v: [Double], _ i: Int) -> Double { i < v.count ? v[i] : .nan }
        // Stroking threshold: at least `strokeEnergy`, and clearly above this video's jitter floor
        // (forepaws at rest on the floor while the body is still).
        var restMask = [Bool](repeating: false, count: n)
        for i in 0..<n where !(body[i] > 0.3) {
            if let h = Kinematics.head(s, i), let l = s.p(.lf, i), let r = s.p(.rf, i), min(h.dist(l), h.dist(r)) / bl > p.faceDistance + 0.05 { restMask[i] = true }
        }
        let foreFloor = Kinematics.noiseFloor(foreE, where: restMask)
        let strokeThr = max(p.strokeEnergy, (foreFloor ?? -.infinity) + 0.5)
        // Body licking moves the head less than face washing moves the paws, and the head turn
        // already makes it specific, so a smaller margin over the jitter floor is used.
        let noseThr = max(p.strokeEnergy - 0.5, (Kinematics.noiseFloor(noseE, where: restMask) ?? -.infinity) + 0.25)

        var raw = [[Bool]](repeating: [Bool](repeating: false, count: n), count: Region.allCases.count)
        var scratch = [Bool](repeating: false, count: n)
        var signal = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            signal[i] = val(foreE, i)
            guard body[i].isNaN || body[i] < p.maxBodySpeed else { continue }
            if val(hindE, i) > -2.6 && val(hindHead, i) < 0.65 { scratch[i] = true; continue }
            let h = Kinematics.head(s, i)
            let nose = s.p(.nose, i), tail = s.p(.tail, i)
            // Tail / genitals: curled up, nose at the tail base (the mouth is then also near a hind
            // paw, so this is tested first).
            if let a = nose, let b = tail, a.dist(b) / bl < p.tailDistance { raw[Region.tail.rawValue][i] = true; continue }
            // Hind leg / paw licking.
            if let h {
                let dl = s.p(.lh, i).map { h.dist($0) / bl } ?? .infinity
                let dr = s.p(.rh, i).map { h.dist($0) / bl } ?? .infinity
                if min(dl, dr) < p.legDistance { raw[Region.leg.rawValue][i] = true; continue }
            }
            // Face / head.
            if let h {
                let lf = s.p(.lf, i), rf = s.p(.rf, i)
                let nearL = lf.map { h.dist($0) / bl < p.faceDistance }, nearR = rf.map { h.dist($0) / bl < p.faceDistance }
                let near = (nearL == true && nearR != false) || (nearR == true && nearL != false)
                let stroking = foreE.isEmpty || val(foreE, i) > strokeThr || val(foreE, i).isNaN
                if near && stroking { raw[Region.face.rawValue][i] = true; continue }
            }
            // Body (flank): head turned away from the trunk axis.
            if let ang = Kinematics.headTurn(s, i) {
                let moving = noseE.isEmpty || val(noseE, i) > noseThr
                if ang > p.headTurn && moving { raw[Region.body.rawValue][i] = true }
            }
        }
        let regions = raw.map { Bouts.clean($0, fps: s.fps, gap: 0.3, minDuration: p.minPhase) }
        var any = [Bool](repeating: false, count: n)
        for r in regions { any = Bouts.or(any, r) }
        let boutMask = Bouts.clean(any, fps: s.fps, gap: p.boutGap, minDuration: p.minBout)

        // Bouts → events, with region sequence.
        func regionAt(_ i: Int) -> Region? { Region.allCases.first { regions[$0.rawValue][i] } }
        var events: [BehaviorEvent] = []
        var boutInfo: [Int: (seq: [Region], interruptions: Int)] = [:]
        let pauseFrames = max(1, s.samples(1.0))
        for (r, iv) in tl.intervals(boutMask) {
            var seq: [Region] = []
            var gap = 0, interruptions = 0
            for i in r {
                if let g = regionAt(i) {
                    if seq.last != g { seq.append(g) }
                    if gap >= pauseFrames { interruptions += 1 }
                    gap = 0
                } else { gap += 1 }
            }
            boutInfo[r.lowerBound] = (seq, interruptions)
            events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: iv.end, auto: groom.key, label: groom.key,
                                        edited: false, counted: true, info: seq.map(\.short).joined(separator: "→")))
        }
        events = EventReview.apply(events, overrides: overrides, timeline: tl)
        let bouts = EventReview.counted(events, groom.key)
        let ignored = events.filter { $0.label == EventClass.ignore.key }.map { Interval(start: $0.onset, end: $0.offset) }
        func notIgnored(_ iv: Interval) -> Bool { !ignored.contains { iv.start < $0.end && iv.end > $0.start } }

        let regionIv = regions.map { m in tl.intervals(m).map(\.1).filter(notIgnored) }
        let regionS = regionIv.map { ivs in ivs.reduce(0) { $0 + tl.overlap($1) } }
        let groomS = regionS.reduce(0, +)
        let scratchIv = tl.intervals(Bouts.clean(scratch, fps: s.fps, gap: 0.5, minDuration: 0.3)).map(\.1)
        var transitions = 0, correct = 0, interrupted = 0
        for b in bouts {
            guard let info = boutInfo[b.id] else { continue }
            if info.interruptions > 0 { interrupted += 1 }
            for (a, c) in zip(info.seq, info.seq.dropFirst()) {
                transitions += 1
                if c.rawValue == a.rawValue + 1 { correct += 1 }
            }
        }
        let windowS = tl.window.duration
        let coverage = Kinematics.coverage(s, tl)
        let edited = events.filter { $0.edited }.count
        let durations = bouts.map { $0.duration }
        func share(_ x: Double) -> Double? { groomS > 0 ? x / groomS * 100 : nil }

        var metrics: [Metric] = [
            Metric(key: "groom_time_s", label: LText("Grooming time", "理毛时间"), value: groomS, unit: "s", decimals: 1, highlight: true),
            Metric(key: "groom_bouts_n", label: LText("Grooming bouts", "理毛次数"), value: Double(bouts.count), unit: "", decimals: 0, highlight: true),
            Metric(key: "latency_s", label: LText("Latency to first grooming", "首次理毛潜伏期"), value: bouts.first.map { $0.onset - tl.window.start }, unit: "s", decimals: 1, highlight: true),
            Metric(key: "groom_pct", label: LText("Grooming (% of window)", "理毛占窗口比例"), value: windowS > 0 ? groomS / windowS * 100 : nil, unit: "%", decimals: 1),
            Metric(key: "bout_mean_s", label: LText("Mean bout duration", "平均每次时长"), value: Signal.mean(durations), unit: "s", decimals: 1),
            Metric(key: "bout_max_s", label: LText("Longest bout", "最长一次"), value: durations.max(), unit: "s", decimals: 1),
            Metric(key: "face_s", label: LText("Face / head", "面部 / 头部"), value: regionS[Region.face.rawValue], unit: "s", decimals: 1),
            Metric(key: "body_s", label: LText("Body (flank)", "躯体（侧腹）"), value: regionS[Region.body.rawValue], unit: "s", decimals: 1),
            Metric(key: "leg_s", label: LText("Hind leg / paw", "后腿 / 后爪"), value: regionS[Region.leg.rawValue], unit: "s", decimals: 1),
            Metric(key: "tail_s", label: LText("Tail / genitals", "尾部 / 生殖区"), value: regionS[Region.tail.rawValue], unit: "s", decimals: 1),
            Metric(key: "face_pct", label: LText("Face share of grooming", "面部占理毛比例"), value: share(regionS[Region.face.rawValue]), unit: "%", decimals: 0),
            Metric(key: "interrupted_pct", label: LText("Interrupted bouts", "中断的理毛"), value: bouts.isEmpty ? nil : Double(interrupted) / Double(bouts.count) * 100, unit: "%", decimals: 0),
            Metric(key: "incorrect_transitions_pct", label: LText("Incorrect (non head-to-tail) transitions", "非头→尾顺序转换"), value: transitions > 0 ? Double(transitions - correct) / Double(transitions) * 100 : nil, unit: "%", decimals: 0),
            Metric(key: "transitions_n", label: LText("Region transitions", "部位转换次数"), value: Double(transitions), unit: "", decimals: 0),
            Metric(key: "scratch_time_s", label: LText("Scratching (excluded)", "抓挠（已排除）"), value: scratchIv.reduce(0) { $0 + tl.overlap($1) }, unit: "s", decimals: 1),
            Metric(key: "window_s", label: LText("Analysis window", "分析窗口"), value: windowS, unit: "s", decimals: 0),
            Metric(key: "edited_n", label: LText("Manually edited events", "人工修改事件"), value: Double(edited), unit: "", decimals: 0),
            Metric(key: "pose_coverage_pct", label: LText("Pose coverage", "姿态覆盖率"), value: coverage * 100, unit: "%", decimals: 0),
        ]
        metrics = metrics.grouped([
            (LText("Grooming", "理毛"), ["groom_time_s", "groom_bouts_n", "latency_s", "groom_pct", "bout_mean_s", "bout_max_s", "window_s"]),
            (LText("Body regions", "身体部位"), ["face_s", "body_s", "leg_s", "tail_s", "face_pct"]),
            (LText("Microstructure (exploratory)", "微结构（探索性）"), ["interrupted_pct", "incorrect_transitions_pct", "transitions_n", "scratch_time_s"]),
            (LText("Quality", "数据质量"), ["edited_n", "pose_coverage_pct"]),
        ])
        notes.append(Note(.info,
                          "Body-region scoring and transition analysis use four regions visible from below (face, body, hind leg, tail/genitals); the observer syntax has more stages. Treat the microstructure as exploratory.",
                          "部位与转换分析基于仰视可分辨的四个部位（面部、躯体、后腿、尾/生殖区），比人工评分的阶段少，微结构结果请视为探索性。"))
        notes += BehaviorNotes.quality(s, coverage: coverage)
        if !events.isEmpty { notes.append(BehaviorNotes.review(edited)) }

        var tracks = Region.allCases.map { r in
            BehaviorTrack(key: r.key, label: r.label, color: r.color, intervals: regionIv[r.rawValue])
        }
        tracks.append(BehaviorTrack(key: "scratch", label: LText("Scratching", "抓挠"), color: 0xB0306A, intervals: scratchIv))
        let detail = BehaviorDetail(
            classes: classes, events: events, tracks: tracks, binSize: tl.binSize,
            bins: [BinSeries(key: "groom_s", label: LText("Grooming time", "理毛时间"), unit: "s",
                             values: tl.binSeconds(regionIv.flatMap { $0 })),
                   BinSeries(key: "groom_bouts", label: LText("Grooming bouts", "理毛次数"), unit: "n", values: tl.binCounts(bouts.map(\.onset)))],
            signal: Signal.downsample(t: s.t, v: signal, maxPoints: 1500),
            signalLabel: LText("Forepaw stroking (log10 BL²)", "前爪擦拭运动（log10 BL²）"), signalUnit: "log10 BL²",
            signalThreshold: strokeThr, window: tl.window, origin: tl.origin)
        return AnalysisResult(metrics: metrics, notes: notes, tst: nil, cylinder: nil, gait: nil, analyzedAt: Date(),
                              poseCoverage: coverage, behavior: detail)
    }
}
