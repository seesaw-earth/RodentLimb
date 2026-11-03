// SeizureAnalyzer.swift — behavioral seizure scoring after a convulsant (PTZ, kainate, …).
//
// Observers score seizures on a Racine-type scale (Racine 1972). For PTZ in mice the revised scale
// of Van Erum et al. (2019), extending Lüttjohann et al.'s (2009) rat scale, is:
//   0 whisker trembling · 1 sudden behavioral arrest / motionless staring · 2 facial jerking ·
//   3 neck jerks · 4 clonic seizure in a sitting position · 5 clonic / tonic-clonic seizure
//   lying on the belly · 6 lying on the side and/or wild jumping · 7 tonic extension
//   (stages 0–2 focal, 3–6 generalized). For kainate / pilocarpine a modified Racine scale is
// offered (1 immobility · 2 facial automatisms · 3 forelimb clonus · 4 rearing and falling ·
// 5 generalized tonic-clonic with lateral recumbency, jumping or wild running; Sharma et al. 2018).
// Reported: latencies to the first myoclonic jerk, the first generalized seizure and tonic
// hindlimb extension, the maximal stage, counts and durations.
//
// Candidate events from the bottom view (each is a first pass; reviewers confirm on video):
//   • behavioral arrest (only with `scoreArrest`) — overall movement < `arrestSpeed` for
//     ≥ `arrestMinDuration` right after the animal was moving, before the first generalized
//     seizure (later immobility is post-ictal). Off by default: an ordinary pause looks the same;
//   • myoclonic jerk — a whole-body twitch: most keypoints accelerate together above
//     `jerkSpeed` for ≤ `jerkMaxDuration`, from a quiet animal, without moving away (facial
//     jerks are not visible from below);
//   • clonic seizure — rhythmic fast movement of fore and hind limbs (≥ 3 body parts, each well
//     above its own jitter floor and `clonusEnergy`) while the body stays in place, for
//     ≥ `clonusMinDuration` (NINDS s.c. PTZ endpoint: clonus lasting ~3–5 s); relabel as
//     "on the belly" when the mouse is prone;
//   • convulsions on the side — left and right paws on the same side of the body axis (the
//     flank faces the camera) for ≥ `postureMinDuration` (loss of righting > 1 s);
//   • wild running / jumping — body speed > `runSpeed`, or the animal vanishes and reappears
//     > 1.5 BL away within 1 s;
//   • tonic hindlimb extension — both hind paws stretched behind the tail base and rigid for
//     ≥ `tonicMinDuration`.
// Overlaps are resolved toward the higher stage. Events before the injection are listed but not
// counted; their number is a built-in false-positive check.

import Foundation

enum SeizureAnalyzer {
    struct Kind {
        let key: String
        let en: String
        let zh: String
        let color: UInt32
        let ptz: Int
        let racine: Int
        func stage(_ scale: SeizureScale) -> Int { scale == .ptzMouse ? ptz : racine }
        func cls(_ scale: SeizureScale) -> EventClass {
            let g = stage(scale)
            return EventClass(key: key, label: LText("\(en) (\(g))", "\(zh)（\(g) 级）"), color: color)
        }
    }
    static let arrest = Kind(key: "arrest", en: "Behavioral arrest", zh: "行为停顿", color: 0x8E8E93, ptz: 1, racine: 1)
    static let jerk = Kind(key: "jerk", en: "Myoclonic jerk", zh: "肌阵挛抽动", color: 0xE69F00, ptz: 3, racine: 2)
    static let clonic = Kind(key: "clonic", en: "Clonic seizure, upright", zh: "直立阵挛发作", color: 0xD55E00, ptz: 4, racine: 3)
    static let prone = Kind(key: "clonic_prone", en: "Convulsions on the belly / falling", zh: "俯卧抽搐 / 跌倒", color: 0xC62828, ptz: 5, racine: 4)
    static let side = Kind(key: "tonic_clonic", en: "Convulsions on the side", zh: "侧卧抽搐", color: 0x8E24AA, ptz: 6, racine: 5)
    static let running = Kind(key: "running", en: "Wild running / jumping", zh: "狂奔 / 跳跃", color: 0x3949AB, ptz: 6, racine: 5)
    static let tonic = Kind(key: "tonic", en: "Tonic hindlimb extension", zh: "后肢强直伸展", color: 0x1A1A1A, ptz: 7, racine: 5)
    static let kinds = [arrest, jerk, clonic, prone, side, running, tonic]

    static func classes(_ scale: SeizureScale) -> [EventClass] { kinds.map { $0.cls(scale) } + [EventClass.ignore] }
    static func stage(_ key: String, _ scale: SeizureScale) -> Int { kinds.first { $0.key == key }?.stage(scale) ?? 0 }
    /// Stage from which a seizure counts as generalized (PTZ scale: ≥ 3 is generalized, but
    /// latency endpoints use the first clonic seizure, ≥ 4; modified Racine: ≥ 3).
    static func generalizedFrom(_ scale: SeizureScale) -> Int { scale == .ptzMouse ? 4 : 3 }

    static func run(track: PoseTrack, series s: PoseSeries, params p: SeizureParams, overrides: [Int: String]) -> AnalysisResult {
        var notes: [Note] = []
        let n = s.n
        let bl = s.bodyLength
        let tl = Timeline(series: s, videoDuration: track.duration, origin: p.injectionTime, start: 0, end: p.windowEnd, binSize: p.binSize)
        notes += tl.windowNotes(requestedEnd: p.windowEnd)

        // Overall movement: median speed of the tracked keypoints (BL/s), and how many move. Raw
        // (unsmoothed) speeds over ~33 ms, so ~100-ms twitches are not averaged away and jitter is
        // the same at 30 and 60 fps.
        let parts: [Kp] = [.lf, .rf, .lh, .rh, .nose, .tail]
        let speeds = parts.map { k in Kinematics.rawSpeed(track, k, threshold: s.keypointThreshold, bodyLength: bl, step: 1.0 / 30) }
        var global = [Double](repeating: .nan, count: n)
        var moving = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let v = speeds.compactMap { $0[i].isFinite ? $0[i] : nil }
            guard v.count >= 4 else { continue }
            global[i] = Signal.median(v) ?? .nan
            moving[i] = v.filter { $0 > 0.5 * p.jerkSpeed }.count
        }
        // Stillness is judged on the cleaned (smoothed) track: raw frame-to-frame speeds are
        // dominated by keypoint jitter when the animal is not moving.
        var globalSmooth = [Double](repeating: .nan, count: n)
        let smoothSpeeds = parts.map { k in s.speed(k).map { $0 / bl } }
        for i in 0..<n {
            let v = smoothSpeeds.compactMap { $0[i].isFinite ? $0[i] : nil }
            if v.count >= 4 { globalSmooth[i] = Signal.median(v) ?? .nan }
        }
        let calm = Signal.smooth(globalSmooth, window: s.samples(0.5))
        let bodyFast = Kinematics.bodySpeed(s, window: 0.1)
        let bodySlow = Kinematics.bodySpeed(s, window: 0.5)
        var cx = [Double](repeating: .nan, count: n), cy = cx
        for i in 0..<n { if let a = s.p(.nose, i), let b = s.p(.tail, i) { cx[i] = (a.x + b.x) / 2; cy[i] = (a.y + b.y) / 2 } }
        func meanIn(_ v: [Double], _ a: Int, _ b: Int) -> Double? {
            let lo = max(0, a), hi = min(n, b)
            guard hi > lo else { return nil }
            return Signal.mean(Array(v[lo..<hi]))
        }

        // Arrest.
        // "Motionless" means below `arrestSpeed`, or below 1.5× the track's own jitter floor (the
        // 10th percentile of overall movement) when the track is noisier than that allows.
        var arrestMask = [Bool](repeating: false, count: n)
        let calmSorted = calm.filter { $0.isFinite }.sorted()
        let jitter = calmSorted.count >= 30 ? calmSorted[calmSorted.count / 10] : 0
        let arrestThr = min(3 * p.arrestSpeed, max(p.arrestSpeed, 1.5 * jitter))
        let still = calm.map { $0.isFinite && $0 < arrestThr }
        for r in Signal.runs(still) where p.scoreArrest && Double(r.count) * s.dt >= p.arrestMinDuration {
            if let before = meanIn(globalSmooth, r.lowerBound - s.samples(2), r.lowerBound), before > 3 * arrestThr {
                for i in r { arrestMask[i] = true }
            }
        }

        // Myoclonic jerks.
        var jerkMask = [Bool](repeating: false, count: n)
        let spike = Bouts.fillGaps((0..<n).map { global[$0].isFinite && global[$0] > p.jerkSpeed && moving[$0] >= 4 }, maxFrames: 1)
        let pre = s.samples(0.5)
        for r in Signal.runs(spike) where Double(r.count) * s.dt <= p.jerkMaxDuration + 1e-9 {
            guard let before = meanIn(globalSmooth, r.lowerBound - pre, r.lowerBound), before < p.jerkQuietSpeed else { continue }
            // A twitch leaves the mouse where it was; moving off within 0.5 s is a dart or the
            // start of a walk.
            let a = max(0, r.lowerBound - 1), b = min(n - 1, r.upperBound + s.samples(0.5))
            guard cx[a].isFinite else { continue }
            let away = (a...b).contains { j in cx[j].isFinite && hypot(cx[j] - cx[a], cy[j] - cy[a]) / bl > 0.4 }
            if away { continue }
            for i in r { jerkMask[i] = true }
        }

        // Clonic activity: rhythmic fast movement of fore and hind limbs, body in place.
        let fx = KinematicFeatures(track: track)
        var clonicMask = [Bool](repeating: false, count: n)
        if let fx {
            let names = ["lf_e_m05", "rf_e_m05", "lh_e_m05", "rh_e_m05", "nose_e_m05"]
            let e = names.map { Kinematics.logged(fx.perFrame($0) ?? []) }
            // Per body part: at least `clonusEnergy` and ≥ 5× this video's jitter floor (still frames).
            let rest = calm.map { $0.isFinite && $0 < 0.3 }
            let thr = e.map { max(p.clonusEnergy, (Kinematics.noiseFloor($0, where: rest) ?? -.infinity) + 0.7) }
            for i in 0..<n {
                guard e.allSatisfy({ i < $0.count }) else { continue }
                let act = (0..<e.count).map { e[$0][i] > thr[$0] }
                let fore = act[0] || act[1], hind = act[2] || act[3]
                if act.filter({ $0 }).count >= 3 && fore && hind && (bodySlow[i].isNaN || bodySlow[i] < 1.5) { clonicMask[i] = true }
            }
            clonicMask = Bouts.clean(clonicMask, fps: s.fps, gap: 0.5, minDuration: p.clonusMinDuration)
        } else {
            notes.append(Note(.warning, "Limb movement could not be measured (nose and tail base rarely tracked); clonic seizures were not scored.",
                              "无法计算肢体运动（鼻尖和尾根很少被跟踪），未评估阵挛发作。"))
        }

        // Posture: which side of the body axis the left paws are normally on (handles mirrored video).
        var lateral = [[Double]](repeating: [Double](repeating: .nan, count: n), count: 4)
        let pawList: [Kp] = [.lf, .lh, .rf, .rh]
        for i in 0..<n {
            guard let tail = s.p(.tail, i), let nose = s.p(.nose, i), let u = (nose - tail).unit else { continue }
            for (j, k) in pawList.enumerated() { if let q = s.p(k, i) { lateral[j][i] = u.cross(q - tail) / bl } }
        }
        var leftSign = 0.0
        for i in 0..<n {
            let l = [lateral[0][i], lateral[1][i]].filter { $0.isFinite && abs($0) > 0.05 }
            let r = [lateral[2][i], lateral[3][i]].filter { $0.isFinite && abs($0) > 0.05 }
            if !l.isEmpty && !r.isEmpty && (l[0] > 0) != (r[0] > 0) { leftSign += l[0] > 0 ? 1 : -1 }
        }
        var sideMask = [Bool](repeating: false, count: n)
        if leftSign != 0 {
            for i in 0..<n {
                let lv = [lateral[0][i], lateral[1][i]].filter { $0.isFinite }, rv = [lateral[2][i], lateral[3][i]].filter { $0.isFinite }
                guard !lv.isEmpty, !rv.isEmpty, lv.count + rv.count >= 3 else { continue }
                let all = lv + rv
                if all.allSatisfy({ abs($0) > 0.08 }) && (all.allSatisfy { $0 > 0 } || all.allSatisfy { $0 < 0 }) { sideMask[i] = true }
            }
        }
        sideMask = Bouts.clean(sideMask, fps: s.fps, gap: 0.3, minDuration: p.postureMinDuration)

        // Wild running / jumping.
        var runMask = Bouts.clean(bodyFast.map { $0.isFinite && $0 > p.runSpeed }, fps: s.fps, gap: 0.1, minDuration: p.runMinDuration)
        let lost = cx.map { $0.isNaN }
        for r in Signal.runs(lost) where r.lowerBound > 0 && r.upperBound < n && Double(r.count) * s.dt <= 1.0 {
            let a = r.lowerBound - 1, b = r.upperBound
            if hypot(cx[b] - cx[a], cy[b] - cy[a]) / bl > 1.5 { for i in a...b { runMask[i] = true } }
        }

        // Tonic hindlimb extension.
        var tonicMask = [Bool](repeating: false, count: n)
        let vl = s.speed(.lh), vr = s.speed(.rh)
        for i in 0..<n {
            guard let l = Kinematics.ego(s, .lh, i), let r = Kinematics.ego(s, .rh, i) else { continue }
            let rigid = (vl[i].isNaN || vl[i] / bl < 1.0) && (vr[i].isNaN || vr[i] / bl < 1.0)
            if l.x < 0 && r.x < 0 && rigid { tonicMask[i] = true }
        }
        tonicMask = Bouts.clean(tonicMask, fps: s.fps, gap: 0.2, minDuration: p.tonicMinDuration)

        // Resolve overlaps toward the higher stage, then build events.
        let sc = p.scale
        func stage(_ key: String) -> Int { SeizureAnalyzer.stage(key, sc) }
        // Priority uses the PTZ order (finer); ties go to the later layer.
        var label = [Kind?](repeating: nil, count: n)
        let layers: [([Bool], Kind)] = [(arrestMask, arrest), (jerkMask, jerk), (clonicMask, clonic), (runMask, running), (sideMask, side), (tonicMask, tonic)]
        for (m, k) in layers { for i in 0..<n where m[i] { if (label[i]?.ptz ?? 0) <= k.ptz { label[i] = k } } }
        // Overlap resolution can leave slivers of a lower stage at the edges of a higher one (the
        // clonic mask continues for a few frames after the mouse rolls on its side). Slivers
        // shorter than 1 s that touch another event are absorbed into it.
        var segs: [(Range<Int>, Kind?)] = []
        var segStart = 0
        while segStart < n {
            var j = segStart + 1
            while j < n && label[j]?.key == label[segStart]?.key { j += 1 }
            segs.append((segStart..<j, label[segStart])); segStart = j
        }
        let sliver = s.samples(1.0)
        for (idx, seg) in segs.enumerated() where seg.1 != nil && seg.1!.key != jerk.key && seg.0.count < sliver {
            let prev = idx > 0 ? segs[idx - 1].1 : nil, next = idx + 1 < segs.count ? segs[idx + 1].1 : nil
            let candidates = [prev, next].compactMap { $0 }.filter { $0.key != jerk.key && $0.ptz > seg.1!.ptz }
            if let into = candidates.max(by: { $0.ptz < $1.ptz }) { for i in seg.0 { label[i] = into } }
        }
        var events: [BehaviorEvent] = []
        for k in kinds {
            let m = label.map { $0?.key == k.key }
            for (r, iv) in tl.intervals(m) {
                var info: String?
                if k.key == jerk.key, let pk = global[r].filter({ $0.isFinite }).max() { info = String(format: "peak %.1f BL/s", pk) }
                if k.key == side.key, r.contains(where: { clonicMask[$0] }) { info = "with clonus" }
                events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: iv.end, auto: k.key, label: k.key,
                                            edited: false, counted: true, info: info))
            }
        }
        events.sort { $0.onset < $1.onset }
        // Stage 1 is the first sign of a seizure; immobility after a generalized seizure is
        // post-ictal, not a behavioral arrest. Twitches within 1 s of a convulsive event belong to it.
        let gen = generalizedFrom(sc)
        if let g = events.first(where: { $0.onset >= tl.origin && stage($0.auto) >= gen }) {
            events.removeAll { $0.auto == arrest.key && $0.onset > g.onset }
        }
        let convulsive = events.filter { stage($0.auto) >= gen }
        events.removeAll { e in
            e.auto == jerk.key && convulsive.contains { e.onset < $0.offset + 1 && e.offset > $0.onset - 1 }
        }
        events = EventReview.apply(events, overrides: overrides, timeline: tl)

        // Measures.
        let o = tl.origin
        let counted = events.filter { $0.counted }
        let maxStage = counted.map { stage($0.label) }.max() ?? 0
        func first(_ minStage: Int, _ maxS: Int = 99) -> BehaviorEvent? {
            counted.first { let g = stage($0.label); return g >= minStage && g <= maxS }
        }
        let jerks = counted.filter { $0.label == jerk.key }
        let generalized = counted.filter { stage($0.label) >= gen }
        let seizureIv = generalized.map { Interval(start: $0.onset, end: $0.offset) }
        var episodes: [Interval] = []
        for iv in seizureIv.sorted(by: { $0.start < $1.start }) {
            if var last = episodes.last, iv.start - last.end <= p.episodeGap {
                last.end = max(last.end, iv.end); episodes[episodes.count - 1] = last
            } else { episodes.append(iv) }
        }
        let baseline = events.filter { $0.onset < o && $0.label != EventClass.ignore.key }
        let arrests = counted.filter { $0.label == arrest.key }
        let coverage = Kinematics.coverage(s, tl)
        let edited = events.filter { $0.edited }.count
        let topEvent = counted.filter { stage($0.label) == maxStage && maxStage > 0 }.first
        let top = sc == .ptzMouse ? 7 : 5
        // Possible death after tonic extension: no movement for the rest of the video (≥ 60 s).
        var deathAt: Double?
        if let t = counted.last(where: { $0.label == tonic.key }) {
            let i0 = s.indices(from: t.offset, to: tl.duration)
            if i0.count > s.samples(60), let mv = Signal.mean(Array(calm[i0])), mv < arrestThr {
                deathAt = t.offset
                notes.append(Note(.warning,
                                  String(format: "No movement for the %.0f s after the tonic extension at %.1f s — check whether the animal died.", Double(i0.count) * s.dt, t.onset),
                                  String(format: "%.1f 秒的强直伸展之后 %.0f 秒内无任何运动——请确认动物是否死亡。", t.onset, Double(i0.count) * s.dt)))
            }
        }

        var metrics: [Metric] = [
            Metric(key: "max_stage", label: LText("Maximal stage (est.)", "最高分级（估计）"), value: Double(maxStage), unit: "/\(top)", decimals: 0, highlight: true),
            Metric(key: "latency_jerk_s", label: LText("Latency to first myoclonic jerk", "首次肌阵挛潜伏期"), value: jerks.first.map { $0.onset - o }, unit: "s", decimals: 1, highlight: true),
            Metric(key: "latency_generalized_s", label: LText("Latency to first generalized seizure (≥ \(gen))", "首次全面性发作潜伏期（≥\(gen) 级）"), value: first(gen).map { $0.onset - o }, unit: "s", decimals: 1, highlight: true),
            Metric(key: "latency_side_s", label: LText("Latency to convulsions on the side / jumping", "侧卧抽搐/跳跃潜伏期"), value: counted.first { $0.label == side.key || $0.label == running.key }.map { $0.onset - o }, unit: "s", decimals: 1),
            Metric(key: "latency_tonic_s", label: LText("Latency to tonic hindlimb extension", "后肢强直伸展潜伏期"), value: counted.first { $0.label == tonic.key }.map { $0.onset - o }, unit: "s", decimals: 1),
            Metric(key: "time_to_max_s", label: LText("Time to maximal stage", "达到最高分级用时"), value: topEvent.map { $0.onset - o }, unit: "s", decimals: 1),
            Metric(key: "jerks_n", label: LText("Myoclonic jerks", "肌阵挛次数"), value: Double(jerks.count), unit: "", decimals: 0),
            Metric(key: "clonic_n", label: LText("Clonic seizures, upright", "直立阵挛发作"), value: Double(counted.filter { $0.label == clonic.key }.count), unit: "", decimals: 0),
            Metric(key: "convulsive_n", label: LText("Convulsions with loss of posture, jumping or tonic extension", "失去姿态的抽搐、跳跃或强直伸展"), value: Double(counted.filter { [prone.key, side.key, running.key, tonic.key].contains($0.label) }.count), unit: "", decimals: 0),
            Metric(key: "seizure_time_s", label: LText("Time in generalized seizures", "全面性发作总时长"), value: seizureIv.reduce(0) { $0 + tl.overlap($1) }, unit: "s", decimals: 1),
            Metric(key: "episodes_n", label: LText("Seizure episodes", "发作次数（合并后）"), value: Double(episodes.count), unit: "", decimals: 0),
            Metric(key: "episode_max_s", label: LText("Longest episode", "最长一次发作"), value: episodes.map(\.duration).max(), unit: "s", decimals: 1),
            Metric(key: "arrest_n", label: LText("Behavioral arrests", "行为停顿次数"), value: p.scoreArrest ? Double(arrests.count) : nil, unit: "", decimals: 0),
            Metric(key: "death_suspected", label: LText("Suspected death (no movement after tonic extension)", "疑似死亡（强直伸展后无运动）"), value: deathAt != nil ? 1 : 0, unit: "", decimals: 0),
            Metric(key: "baseline_events_n", label: LText("Detections before injection", "注射前检出（基线）"), value: o > 1 ? Double(baseline.count) : nil, unit: "", decimals: 0),
            Metric(key: "window_s", label: LText("Observation after injection", "注射后观察时长"), value: tl.window.duration, unit: "s", decimals: 0),
            Metric(key: "edited_n", label: LText("Manually edited events", "人工修改事件"), value: Double(edited), unit: "", decimals: 0),
            Metric(key: "pose_coverage_pct", label: LText("Pose coverage", "姿态覆盖率"), value: coverage * 100, unit: "%", decimals: 0),
        ]
        metrics = metrics.grouped([
            (LText("Severity & latency", "严重程度与潜伏期"), ["max_stage", "latency_jerk_s", "latency_generalized_s", "latency_side_s", "latency_tonic_s", "time_to_max_s"]),
            (LText("Counts & durations", "次数与时长"), ["jerks_n", "clonic_n", "convulsive_n", "seizure_time_s", "episodes_n", "episode_max_s", "arrest_n", "death_suspected", "window_s"]),
            (LText("Quality", "数据质量"), ["baseline_events_n", "edited_n", "pose_coverage_pct"]),
        ])

        if o > 1 && !baseline.isEmpty {
            notes.append(Note(.warning,
                              String(format: "%d seizure-like events were detected before the injection. These are false positives of the detector in this video; review events after the injection with that in mind.", baseline.count),
                              String(format: "注射前检出 %d 个类似发作的事件，属于该视频中的假阳性；复核注射后的事件时请留意。", baseline.count)))
        } else if o <= 1 {
            notes.append(Note(.info, "Set the injection time in Parameters (record a few minutes before injecting) to get latencies from the injection and a baseline false-positive check.",
                              "在“参数”中设置注射时刻（建议注射前先录几分钟），即可得到从注射起的潜伏期和基线假阳性检查。"))
        }
        notes.append(Note(.info,
                          sc == .ptzMouse
                          ? "Stages follow the revised Racine scale for PTZ in mice (Van Erum et al. 2019), estimated from posture and movement seen from below. Whisker trembling (0), facial jerks (2) and convulsions on the belly (5) cannot be told apart automatically. Confirm each event on the video and relabel it if needed."
                          : "Stages follow a modified Racine scale for kainate / pilocarpine, estimated from posture and movement seen from below. Facial automatisms cannot be seen from below. Confirm each event on the video and relabel it if needed.",
                          sc == .ptzMouse
                          ? "分级采用小鼠 PTZ 修订 Racine 量表（Van Erum 等 2019），根据仰视下的姿态和运动估计。胡须颤动（0 级）、面部抽动（2 级）和俯卧抽搐（5 级）无法自动区分。请在视频上逐个确认事件，必要时修改标签。"
                          : "分级采用海人酸/毛果芸香碱改良 Racine 量表，根据仰视下的姿态和运动估计，仰视看不到面部自动症。请在视频上逐个确认事件，必要时修改标签。"))
        if !p.scoreArrest {
            notes.append(Note(.info,
                              "Behavioral arrest (stage 1) is not scored: from below it looks like an ordinary pause. Turn it on in Parameters if the baseline is active and pauses are rare.",
                              "未评分行为停顿（1 级）：仰视下它与普通的停歇无法区分。若基线期动物很活跃、很少停歇，可在“参数”中开启。"))
        }
        notes += BehaviorNotes.quality(s, coverage: coverage)
        if !events.isEmpty { notes.append(BehaviorNotes.review(edited)) }

        let bins = tl.binCount
        var maxPerBin = [Double](repeating: 0, count: bins)
        for e in counted {
            let i = Int(safe: floor((e.onset - o) / tl.binSize), fallback: -1)
            if i >= 0 && i < bins { maxPerBin[i] = max(maxPerBin[i], Double(stage(e.label))) }
        }
        let tracks = kinds.reversed().map { k in
            BehaviorTrack(key: k.key, label: k.cls(sc).label, color: k.color, intervals: EventReview.intervals(events, k.key))
        }
        let detail = BehaviorDetail(
            classes: classes(sc), events: events, tracks: tracks, binSize: tl.binSize,
            bins: [BinSeries(key: "max_stage", label: LText("Maximal stage", "最高分级"), unit: "stage", values: maxPerBin),
                   BinSeries(key: "jerks_n", label: LText("Myoclonic jerks", "肌阵挛"), unit: "n", values: tl.binCounts(jerks.map(\.onset))),
                   BinSeries(key: "seizure_s", label: LText("Generalized seizure time", "全面性发作时长"), unit: "s", values: tl.binSeconds(seizureIv))],
            signal: Signal.downsample(t: s.t, v: global, maxPoints: 2000),
            signalLabel: LText("Overall movement (BL/s)", "整体运动（BL/s）"), signalUnit: "BL/s",
            signalThreshold: p.jerkSpeed, window: tl.window, origin: o)
        return AnalysisResult(metrics: metrics, notes: notes, tst: nil, cylinder: nil, gait: nil, analyzedAt: Date(),
                              poseCoverage: coverage, behavior: detail)
    }
}
