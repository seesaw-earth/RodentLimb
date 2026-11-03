// ItchAnalyzer.swift — scratching after a pruritogen (nape or cheek injection).
//
// What is scored: hind-paw scratching directed at the head, neck or body. Mice scratch in rapid
// series of strokes; a bout ends with a pause, licking or biting of the toes, or the paw placed
// back on the floor (Kuraishi et al. 1995; wording as in Valtcheva et al. 2015). Observers report the number of scratching bouts, the time spent
// scratching and the latency, usually over 30–60 min in 5-min bins.
//
// Detection
//   • Trained model (ScratchModel.json from the Colab notebook, trained on Scratch-AID,
//     Yu et al. 2022): per-frame probability from 12 keypoint features → the post-processing
//     tuned on held-out videos. Used automatically when the file is in the app.
//   • Keypoint rules (fallback): a hind paw moves back and forth fast relative to the body
//     (0.5-s mean high-frequency energy above `energyThreshold` and ≥ 2.5× this video's own
//     keypoint-jitter floor), comes close to the head
//     (< `headDistance` BL) while the body stays in place (< `maxBodySpeed`).
//   Bouts closer than `mergeGap` are joined; bouts shorter than `minBout` are dropped. The
//   scratching hind paw is the one with more high-frequency movement during the bout.
//
// Scratching trains (Scratch-AID): bouts closer than `trainGap` (2 s) are grouped, because
// scratching and paw licking alternate within one episode.
// Cheek model (Shimada & LaMotte 2008): hind-paw scratching of the cheek signals itch and
// unilateral forepaw wiping signals pain, so with `site = .cheek` wipes are scored separately:
// one forepaw at the face moving rapidly while the other stays clearly farther away (on the
// floor), head facing forward, body in place. Bilateral strokes are grooming and are not
// counted (Yamanoi et al. 2019).
//
// Every bout can be reviewed on the video and relabeled; edits persist.

import Foundation

enum ItchAnalyzer {
    static let scratch = EventClass(key: "scratch", label: LText("Scratching bout", "抓挠"), color: 0xB0306A)
    static let wipe = EventClass(key: "wipe", label: LText("Forepaw wiping (pain-like)", "前爪擦拭（痛样）"), color: 0x0072B2)
    static let classes = [scratch, wipe, EventClass.ignore]

    static func run(track: PoseTrack, series s: PoseSeries, params p: ItchParams, overrides: [Int: String],
                    model: ScratchModel? = ScratchModel.bundled) -> AnalysisResult {
        var notes: [Note] = []
        let n = s.n
        let tl = Timeline(series: s, videoDuration: track.duration, origin: p.injectionTime,
                          start: p.windowStart, end: p.windowEnd, binSize: p.binSize)
        notes += tl.windowNotes(requestedEnd: p.windowEnd)

        let wanted = p.method == .auto ? model : nil
        let fx = KinematicFeatures(track: track, constants: wanted?.constants ?? FeatureConstants())
        var mask = [Bool](repeating: false, count: n)
        var signal = [Double](repeating: .nan, count: n)
        var signalLabel = LText("Hind-paw fast movement (log10 BL²)", "后爪快速运动（log10 BL²）")
        var signalUnit = "log10 BL²"
        var threshold: Double? = p.energyThreshold
        var usedModel = false

        if let fx {
            if let m = wanted, let prob = m.probabilities(fx) {
                let pp = m.file.postprocess
                let thr = p.modelThreshold > 0 ? p.modelThreshold : pp.thr
                signal = PostProcess.smooth(prob, fps: fx.fps, seconds: pp.smooth_s)
                mask = PostProcess.binarize(signal, fps: fx.fps, threshold: thr, gap: pp.gap_s, minDuration: pp.min_s)
                threshold = thr
                signalLabel = LText("Scratching probability (trained model)", "抓挠概率（训练模型）")
                signalUnit = "p"
                usedModel = true
                var text = String(format: "Scratching was detected with the trained model %@ (Scratch-AID, held-out test F1 %@). Probability threshold %.2f.",
                                  m.sourceName, m.testF1.map { String(format: "%.2f", $0) } ?? "n/a", thr)
                var zh = String(format: "使用训练模型 %@ 检测抓挠（Scratch-AID 独立测试集 F1 %@），概率阈值 %.2f。",
                                m.sourceName, m.testF1.map { String(format: "%.2f", $0) } ?? "—", thr)
                if fx.fps < 25 { text += " The video is below 25 fps; the model was trained at 30 fps."; zh += " 视频低于 25 fps，模型训练于 30 fps。" }
                notes.append(Note(.info, text, zh))
            } else {
                if p.method == .auto {
                    if let m = wanted {
                        let miss = m.missingFeatures(fx)
                        notes.append(Note(.warning,
                                          "The installed scratch model needs features the app cannot compute (\(miss.joined(separator: ", "))); keypoint rules were used instead.",
                                          "已安装的抓挠模型需要 App 无法计算的特征（\(miss.joined(separator: "、"))），已改用关键点规则。"))
                    } else {
                        notes.append(Note(.info,
                                          "No trained scratch model is installed, so keypoint rules were used. Copy ScratchModel.json from the Colab notebook into the app for model-based detection (see README).",
                                          "未安装训练好的抓挠模型，已使用关键点规则。将 Colab notebook 导出的 ScratchModel.json 放入 App 即可使用模型检测（见 README）。"))
                    }
                }
                let energy = Kinematics.logged(fx.perFrame("hind_e_max_m05") ?? [])
                let head = fx.perFrame("hind_head_min_m05") ?? []
                let speed = fx.perFrame("speed_m05") ?? []
                // Threshold: at least `energyThreshold`, and well above this video's jitter floor
                // (hind paws while the mouse sits still with the paws away from the head).
                let rest = (0..<n).map { i in i < speed.count && i < head.count && speed[i] < 0.3 && head[i] > p.headDistance }
                let thr = max(p.energyThreshold, (Kinematics.noiseFloor(energy, where: rest) ?? -.infinity) + 0.4)
                threshold = thr
                for i in 0..<min(n, energy.count, head.count, speed.count) {
                    mask[i] = energy[i] > thr && head[i] < p.headDistance && (speed[i].isNaN || speed[i] < p.maxBodySpeed)
                }
                mask = Bouts.clean(mask, fps: s.fps, gap: p.mergeGap, minDuration: p.minBout)
                signal = energy
            }
        } else {
            notes.append(Note(.error,
                              "Nose and tail base were reliable in fewer than 50 frames, so body-relative paw movement cannot be measured. Check the camera view and lighting.",
                              "鼻尖和尾根可靠的帧少于 50 帧，无法计算相对身体的爪部运动。请检查拍摄视角和光照。"))
        }

        // Bouts → events.
        let le = fx?.perFrame("lh_e") ?? [], re = fx?.perFrame("rh_e") ?? []
        var events: [BehaviorEvent] = []
        for (r, iv) in tl.intervals(mask) {
            var side: String?
            if r.upperBound <= le.count, r.upperBound <= re.count {
                let l = Signal.mean(Array(le[r])) ?? .nan, rr = Signal.mean(Array(re[r])) ?? .nan
                if l.isFinite || rr.isFinite { side = (rr.isNaN || l > rr) ? "left hind" : "right hind" }
            }
            var info = side ?? ""
            if usedModel, r.upperBound <= signal.count, let pm = Signal.mean(Array(signal[r])) { info += (info.isEmpty ? "" : " · ") + String(format: "p %.2f", pm) }
            events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: iv.end, auto: scratch.key, label: scratch.key,
                                        edited: false, counted: true, info: info.isEmpty ? nil : info))
        }
        // Cheek model: unilateral forepaw wiping.
        if p.site == .cheek, let fx {
            let le = Kinematics.logged(fx.perFrame("lf_e_m05") ?? []), re = Kinematics.logged(fx.perFrame("rf_e_m05") ?? [])
            let speed = fx.perFrame("speed_m05") ?? []
            var rest = [Bool](repeating: false, count: n)
            var wipeMask = [Bool](repeating: false, count: n)
            var wipeSide = [Int](repeating: 0, count: n)
            var dL = [Double](repeating: .nan, count: n), dR = dL
            for i in 0..<n {
                guard let h = Kinematics.head(s, i) else { continue }
                if let a = s.p(.lf, i) { dL[i] = h.dist(a) / s.bodyLength }
                if let b = s.p(.rf, i) { dR[i] = h.dist(b) / s.bodyLength }
                rest[i] = i < speed.count && speed[i] < 0.3 && dL[i] > 0.24 && dR[i] > 0.24
            }
            let thrL = max(-3.0, (Kinematics.noiseFloor(le, where: rest) ?? -.infinity) + 0.5)
            let thrR = max(-3.0, (Kinematics.noiseFloor(re, where: rest) ?? -.infinity) + 0.5)
            for i in 0..<min(n, le.count, re.count, speed.count) where !mask[i] && !(speed[i] > p.maxBodySpeed) {
                // Cheek wiping is done with the head facing forward; a head turned to the flank
                // is body grooming.
                if let turn = Kinematics.headTurn(s, i), turn > 40 { continue }
                // One forepaw strokes the face; the other stays clearly farther away (on the floor).
                // Both paws near the face is bilateral face grooming, not a wipe.
                if dL[i] < 0.22 && le[i] > thrL && dR[i] > max(0.24, dL[i] + 0.12) { wipeMask[i] = true; wipeSide[i] = -1 }
                else if dR[i] < 0.22 && re[i] > thrR && dL[i] > max(0.24, dR[i] + 0.12) { wipeMask[i] = true; wipeSide[i] = 1 }
            }
            wipeMask = Bouts.clean(wipeMask, fps: s.fps, gap: 0.3, minDuration: 0.2)
            for (r, iv) in tl.intervals(wipeMask) {
                let side = r.map { wipeSide[$0] }.reduce(0, +)
                events.append(BehaviorEvent(id: r.lowerBound, onset: iv.start, offset: iv.end, auto: wipe.key, label: wipe.key,
                                            edited: false, counted: true, info: side < 0 ? "left fore" : (side > 0 ? "right fore" : nil)))
            }
            var seen = Set<Int>()
            events = events.sorted { $0.onset < $1.onset }.map { e in
                var e = e
                while seen.contains(e.id) { e.id += 1 }
                seen.insert(e.id)
                return e
            }
        }
        events = EventReview.apply(events, overrides: overrides, timeline: tl)
        let counted = EventReview.counted(events, scratch.key)
        let wipes = EventReview.counted(events, wipe.key)
        // Trains: bouts closer than `trainGap`.
        var trains: [Interval] = []
        for e in counted {
            if var last = trains.last, e.onset - last.end <= p.trainGap {
                last.end = max(last.end, e.offset); trains[trains.count - 1] = last
            } else { trains.append(Interval(start: e.onset, end: e.offset)) }
        }
        let ivs = counted.map { Interval(start: $0.onset, end: $0.offset) }
        let windowS = tl.window.duration
        let time = ivs.reduce(0) { $0 + tl.overlap($1) }
        let durations = counted.map { $0.duration }
        let left = counted.filter { $0.info?.hasPrefix("left") == true }.count
        let right = counted.filter { $0.info?.hasPrefix("right") == true }.count
        let coverage = Kinematics.coverage(s, tl)
        let edited = events.filter { $0.edited }.count

        var metrics: [Metric] = [
            Metric(key: "scratch_bouts_n", label: LText("Scratching bouts", "抓挠次数"), value: Double(counted.count), unit: "", decimals: 0, highlight: true),
            Metric(key: "scratch_time_s", label: LText("Scratching time", "抓挠时间"), value: time, unit: "s", decimals: 1, highlight: true),
            Metric(key: "latency_s", label: LText("Latency to first bout", "首次抓挠潜伏期"), value: counted.first.map { $0.onset - tl.origin }, unit: "s", decimals: 1, highlight: true),
            Metric(key: "scratch_pct", label: LText("Scratching (% of window)", "抓挠占窗口比例"), value: windowS > 0 ? time / windowS * 100 : nil, unit: "%", decimals: 1),
            Metric(key: "bouts_per_min", label: LText("Bouts per minute", "每分钟抓挠次数"), value: windowS > 0 ? Double(counted.count) / (windowS / 60) : nil, unit: "/min", decimals: 2),
            Metric(key: "bout_mean_s", label: LText("Mean bout duration", "平均每次时长"), value: Signal.mean(durations), unit: "s", decimals: 2),
            Metric(key: "bout_max_s", label: LText("Longest bout", "最长一次"), value: durations.max(), unit: "s", decimals: 1),
            Metric(key: "trains_n", label: LText("Scratching trains", "抓挠串数"), value: Double(trains.count), unit: "", decimals: 0),
            Metric(key: "train_mean_s", label: LText("Mean train duration", "平均每串时长"), value: Signal.mean(trains.map(\.duration)), unit: "s", decimals: 1),
            Metric(key: "left_bouts_n", label: LText("Bouts with the left hind paw", "左后爪抓挠次数"), value: Double(left), unit: "", decimals: 0),
            Metric(key: "right_bouts_n", label: LText("Bouts with the right hind paw", "右后爪抓挠次数"), value: Double(right), unit: "", decimals: 0),
            Metric(key: "side_index_pct", label: LText("Side index (L − R) / (L + R)", "侧别指数 (左−右)/(左+右)"), value: left + right > 0 ? Double(left - right) / Double(left + right) * 100 : nil, unit: "%", decimals: 0),
            Metric(key: "window_s", label: LText("Analysis window", "分析窗口"), value: windowS, unit: "s", decimals: 0),
            Metric(key: "edited_n", label: LText("Manually edited events", "人工修改事件"), value: Double(edited), unit: "", decimals: 0),
            Metric(key: "pose_coverage_pct", label: LText("Pose coverage", "姿态覆盖率"), value: coverage * 100, unit: "%", decimals: 0),
        ]
        if p.site == .cheek {
            metrics += [
                Metric(key: "wipe_bouts_n", label: LText("Forepaw wiping bouts", "前爪擦拭次数"), value: Double(wipes.count), unit: "", decimals: 0, highlight: true),
                Metric(key: "wipe_time_s", label: LText("Wiping time", "擦拭时间"), value: wipes.reduce(0) { $0 + tl.overlap(Interval(start: $1.onset, end: $1.offset)) }, unit: "s", decimals: 1),
                Metric(key: "wipe_left_n", label: LText("Wipes with the left forepaw", "左前爪擦拭"), value: Double(wipes.filter { $0.info == "left fore" }.count), unit: "", decimals: 0),
                Metric(key: "wipe_right_n", label: LText("Wipes with the right forepaw", "右前爪擦拭"), value: Double(wipes.filter { $0.info == "right fore" }.count), unit: "", decimals: 0),
            ]
            if let i = metrics.firstIndex(where: { $0.key == "latency_s" }) { metrics[i].highlight = false }
        }
        metrics = metrics.grouped([
            (LText("Scratching", "抓挠"), ["scratch_bouts_n", "scratch_time_s", "latency_s", "scratch_pct", "bouts_per_min", "bout_mean_s", "bout_max_s", "trains_n", "train_mean_s", "window_s"]),
            (LText("Wiping (cheek model)", "擦拭（面颊模型）"), ["wipe_bouts_n", "wipe_time_s", "wipe_left_n", "wipe_right_n"]),
            (LText("Which hind paw", "哪只后爪"), ["left_bouts_n", "right_bouts_n", "side_index_pct"]),
            (LText("Quality", "数据质量"), ["edited_n", "pose_coverage_pct"]),
        ])

        if !usedModel && fx != nil && s.fps < 50 {
            notes.append(Note(.info,
                              "Scratching strokes are faster than this frame rate, so the rules rely on the rapid jitter they leave in the hind-paw track. Record at ≥ 60 fps when possible, and review the bouts.",
                              "抓挠动作快于该帧率，规则依靠后爪轨迹中的快速抖动来识别。条件允许时请以 ≥ 60 fps 录制，并复核事件。"))
        }
        notes += BehaviorNotes.quality(s, coverage: coverage)
        if !events.isEmpty { notes.append(BehaviorNotes.review(edited)) }

        let detail = BehaviorDetail(
            classes: p.site == .cheek ? classes : [scratch, EventClass.ignore], events: events,
            tracks: [BehaviorTrack(key: scratch.key, label: scratch.label, color: scratch.color,
                                   intervals: EventReview.intervals(events, scratch.key))]
                + (p.site == .cheek ? [BehaviorTrack(key: wipe.key, label: wipe.label, color: wipe.color,
                                                     intervals: EventReview.intervals(events, wipe.key))] : []),
            binSize: tl.binSize,
            bins: [BinSeries(key: "scratch_s", label: LText("Scratching time", "抓挠时间"), unit: "s", values: tl.binSeconds(ivs)),
                   BinSeries(key: "scratch_bouts", label: LText("Scratching bouts", "抓挠次数"), unit: "n", values: tl.binCounts(counted.map(\.onset)))]
                + (p.site == .cheek ? [BinSeries(key: "wipe_bouts", label: LText("Wiping bouts", "擦拭次数"), unit: "n", values: tl.binCounts(wipes.map(\.onset)))] : []),
            signal: Signal.downsample(t: s.t, v: signal, maxPoints: 1500),
            signalLabel: signalLabel, signalUnit: signalUnit, signalThreshold: threshold,
            window: tl.window, origin: tl.origin)
        return AnalysisResult(metrics: metrics, notes: notes, tst: nil, cylinder: nil, gait: nil, analyzedAt: Date(),
                              poseCoverage: coverage, behavior: detail)
    }
}
