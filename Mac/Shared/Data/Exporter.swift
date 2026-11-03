// Exporter.swift — CSV / text exports. Always English, independent of the interface language.

import Foundation

/// Not tied to the main actor: exports are built in background tasks (copying a skeleton video or
/// formatting tens of thousands of rows on the main thread froze the app).
enum Exporter {
    nonisolated static func exportDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RodentLimbExport-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    nonisolated static func row(_ fields: [String]) -> String { fields.map(csvField).joined(separator: ",") + "\n" }

    nonisolated static func f(_ v: Double?, _ d: Int = 4) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(d)f", v)
    }

    nonisolated static func safeName(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let out = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return out.isEmpty ? "session" : out
    }

    nonisolated static func write(_ text: String, _ url: URL) -> URL? {
        // UTF-8 with BOM so Excel opens non-ASCII subject IDs correctly.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    // MARK: Single session

    static func sessionFiles(_ s: Session, result: AnalysisResult, track: PoseTrack?, skeletonURL: URL?,
                             includePose: Bool, includeVideo: Bool, design: ExportRow? = nil) -> [URL] {
        let dir = exportDir()
        let base = safeName(s.displayName) + "_" + s.assay.code
        var urls: [URL] = []

        var summary = row(["field", "value", "unit"])
        let hideVideo = design?.blinded ?? false
        for (k, v) in metadata(s) where !(hideVideo && k == "video") { summary += row([k, v, ""]) }
        if let d = design { for (k, v) in d.designFields { summary += row([k, v, ""]) } }
        for m in result.metrics { summary += row([m.key, m.exportValue, m.unit]) }
        for n in result.notes { summary += row(["note_" + n.level.rawValue, n.text.en, ""]) }
        if let u = write(summary, dir.appendingPathComponent(base + "_summary.csv")) { urls.append(u) }

        switch s.assay {
        case .tailSuspension:
            if let d = result.tst {
                var b = row(["bout", "start_s", "end_s", "duration_s", "overlaps_window"])
                for (i, x) in d.bouts.enumerated() {
                    b += row(["\(i + 1)", f(x.start, 3), f(x.end, 3), f(x.duration, 3), (x.end > d.window.start && x.start < d.window.end) ? "1" : "0"])
                }
                if let u = write(b, dir.appendingPathComponent(base + "_immobility_bouts.csv")) { urls.append(u) }
                var m = row(["minute", "immobility_s"])
                for (i, v) in d.perMinute.enumerated() { m += row(["\(i + 1)", f(v, 2)]) }
                if let u = write(m, dir.appendingPathComponent(base + "_per_minute.csv")) { urls.append(u) }
            }
        case .cylinder:
            if let d = result.cylinder {
                var e = row(["event", "onset_s", "offset_s", "rear", "auto_label", "final_label", "edited", "counted"])
                for (i, x) in d.events.enumerated() {
                    e += row(["\(i + 1)", f(x.onset, 3), f(x.offset, 3), "\(x.rear)", x.auto.rawValue, x.label.rawValue,
                              x.edited ? "1" : "0", x.counted ? "1" : "0"])
                }
                if let u = write(e, dir.appendingPathComponent(base + "_contacts.csv")) { urls.append(u) }
            }
        case .gait:
            if let d = result.gait {
                var st = row(["paw", "start_s", "end_s", "stride_s", "stance_s", "swing_s", "duty", "stride_length_\(d.unit)", "speed_\(d.unit)_per_s"])
                for x in d.strides {
                    st += row([x.paw.code, f(x.start, 4), f(x.end, 4), f(x.end - x.start, 4), f(x.stance, 4), f(x.swing, 4),
                               f(x.duty, 4), f(x.length, 4), f(x.speed, 3)])
                }
                if let u = write(st, dir.appendingPathComponent(base + "_strides.csv")) { urls.append(u) }
                var fp = row(["paw", "strike_s", "x_px", "y_px"])
                for x in d.footprints { fp += row([x.paw.code, f(x.t, 4), f(x.x, 2), f(x.y, 2)]) }
                if let u = write(fp, dir.appendingPathComponent(base + "_footprints.csv")) { urls.append(u) }
            }
        case .itch, .pain, .grooming, .seizure:
            if let d = result.behavior { urls += behaviorFiles(d, dir: dir, base: base) }
        }

        if let u = write(methods(s, result: result), dir.appendingPathComponent(base + "_methods.txt")) { urls.append(u) }
        if includeVideo, s.hasSkeletonVideo, let src = skeletonURL {
            let dst = dir.appendingPathComponent(base + "_skeleton.mp4")
            if (try? FileManager.default.copyItem(at: src, to: dst)) != nil { urls.append(dst) }
        }
        return urls
    }

    /// Events, binned time course and ethogram intervals of a behavior assay. Times are in video
    /// seconds and, where useful, relative to the injection.
    nonisolated static func behaviorFiles(_ d: BehaviorDetail, dir: URL, base: String) -> [URL] {
        var urls: [URL] = []
        var e = row(["event", "onset_s", "offset_s", "duration_s", "onset_after_injection_s", "auto_label", "final_label", "edited", "counted", "info"])
        for (i, x) in d.events.enumerated() {
            e += row(["\(i + 1)", f(x.onset, 3), f(x.offset, 3), f(x.duration, 3), f(x.onset - d.origin, 3),
                      x.auto, x.label, x.edited ? "1" : "0", x.counted ? "1" : "0", x.info ?? ""])
        }
        if let u = write(e, dir.appendingPathComponent(base + "_events.csv")) { urls.append(u) }

        if !d.bins.isEmpty {
            var b = row(["bin", "start_after_injection_s", "end_after_injection_s"] + d.bins.map { $0.unit.isEmpty ? $0.key : "\($0.key) [\($0.unit)]" })
            let n = d.bins.map(\.values.count).max() ?? 0
            for i in 0..<n {
                let a = Double(i) * d.binSize
                b += row(["\(i + 1)", f(a, 1), f(a + d.binSize, 1)] + d.bins.map { i < $0.values.count ? f($0.values[i], 3) : "" })
            }
            if let u = write(b, dir.appendingPathComponent(base + "_time_bins.csv")) { urls.append(u) }
        }

        var g = row(["behavior", "start_s", "end_s", "duration_s"])
        for tr in d.tracks {
            for iv in tr.intervals { g += row([tr.key, f(iv.start, 3), f(iv.end, 3), f(iv.duration, 3)]) }
        }
        if let u = write(g, dir.appendingPathComponent(base + "_ethogram.csv")) { urls.append(u) }
        return urls
    }

    /// Frame-by-frame pose CSV, written off the main thread (can be tens of MB for long videos).
    static func poseFile(_ s: Session, track: PoseTrack, nextTo other: URL?) async -> URL? {
        let dir = other?.deletingLastPathComponent() ?? exportDir()
        let url = dir.appendingPathComponent(safeName(s.displayName) + "_" + s.assay.code + "_pose.csv")
        return await Task.detached(priority: .userInitiated) { writePoseCSV(track, to: url) ? url : nil }.value
    }

    /// Streams the pose CSV to disk in chunks instead of building one huge string (which needed
    /// several copies of tens of MB in memory at once).
    nonisolated static func writePoseCSV(_ t: PoseTrack, to url: URL) -> Bool {
        guard FileManager.default.createFile(atPath: url.path, contents: Data([0xEF, 0xBB, 0xBF])),
              let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            var chunk = poseCSVHeader()
            for i in 0..<t.frameCount {
                chunk += poseCSVRow(t, i)
                if i % 2000 == 1999 {
                    try handle.write(contentsOf: Data(chunk.utf8))
                    chunk = ""
                }
            }
            try handle.write(contentsOf: Data(chunk.utf8))
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    nonisolated static func poseCSVHeader() -> String {
        var header = ["frame", "time_s", "box_confidence"]
        for k in Kp.allCases { header += ["\(k.exportName)_x", "\(k.exportName)_y", "\(k.exportName)_confidence"] }
        return header.joined(separator: ",") + "\n"
    }

    nonisolated static func poseCSVRow(_ t: PoseTrack, _ i: Int) -> String {
        var r = ["\(i)", String(format: "%.4f", t.times[i]), String(format: "%.3f", t.boxConfidence[i])]
        for k in Kp.allCases {
            let x = t.x[k.rawValue][i], y = t.y[k.rawValue][i]
            r += x >= 0 ? [String(format: "%.2f", x), String(format: "%.2f", y)] : ["", ""]
            r.append(String(format: "%.3f", t.c[k.rawValue][i]))
        }
        return r.joined(separator: ",") + "\n"
    }

    static func metadata(_ s: Session) -> [(String, String)] {
        let iso = ISO8601DateFormatter()
        return [
            ("subject", s.subject), ("group", s.group), ("assay", s.assay.name.en),
            ("video", s.originalName), ("created", iso.string(from: s.createdAt)),
            ("fps", f(s.fps, 2)), ("duration_s", f(s.duration, 2)),
            ("model", kPoseModelName), ("model_version", s.modelVersion ?? ""),
            ("notes", s.notes),
        ]
    }

    nonisolated static func poseCSV(_ t: PoseTrack) -> String {
        var out = poseCSVHeader()
        for i in 0..<t.frameCount { out += poseCSVRow(t, i) }
        return out
    }

    // MARK: Group export (long / tidy format: one row per analysis, design columns first)

    /// One analysis with its design information, for CSV export. Long format — one row per
    /// animal × timepoint × task — goes straight into R (lme4, afex), Python or SPSS, and Prism
    /// can pivot it. While a study is blinded the group columns are left out.
    static func groupCSV(_ rows: [ExportRow], name: String? = nil) -> URL? {
        guard let assay = rows.first?.session.assay else { return nil }
        var keys: [String] = [], units: [String: String] = [:]
        for r in rows {
            for m in r.result?.metrics ?? [] where !keys.contains(m.key) {
                keys.append(m.key); units[m.key] = m.unit
            }
        }
        var factorNames: [String] = []
        for r in rows where !r.blinded {
            for (k, _) in r.factors where !factorNames.contains(k) { factorNames.append(k) }
        }
        let blinded = rows.contains { $0.blinded }
        var header = ["study", "animal_id", "blind_code", "sex", "cohort", "cage"]
        if !blinded { header += factorNames + ["group"] }
        header += ["timepoint", "trial", "video", "recorded", "qc_verdict", "qc_mouse_tracked_pct", "qc_longest_lost_s",
                   "included", "exclusion_reason", "status"]
        var out = row(header + keys.map { k in
            let u = units[k] ?? ""
            return u.isEmpty ? k : "\(k) [\(u)]"
        })
        let iso = ISO8601DateFormatter()
        for r in rows {
            let s = r.session
            var fields = [r.study, r.blinded ? "" : r.animal, r.blindCode, r.sex, r.cohort, r.cage]
            if !blinded {
                fields += factorNames.map { n in r.factors.first { $0.0 == n }?.1 ?? "" }
                fields.append(r.group)
            }
            // The file name often carries the animal ID, so it is left out while blinded.
            fields += [r.timepoint, "\(r.trial)", r.blinded ? "" : s.originalName, iso.string(from: r.recorded),
                       r.qcVerdict, f(r.qcCoverage.map { $0 * 100 }, 1), f(r.qcLongestLost, 1),
                       r.included, r.exclusionReason, s.status.rawValue]
            out += row(fields + keys.map { k in r.result?.metric(k)?.exportValue ?? "" })
        }
        let dir = exportDir()
        let stamp = Date().formatted(.iso8601.year().month().day())
        let file = name.map { safeName($0) + "_" } ?? ""
        return write(out, dir.appendingPathComponent("RodentLimb_\(file)\(assay.code)_\(rows.count)_analyses_\(stamp).csv"))
    }

    // MARK: Methods paragraph

    static func methods(_ s: Session, result: AnalysisResult? = nil) -> String {
        let c = s.params.common
        var t = "RodentLimb — automated analysis methods (\(s.assay.name.en))\n\n"
        t += String(format: "Pose estimation: %@ (7 keypoints: left/right fore and hind paws, tail base, nose, mouth), run on-device with Core ML on every video frame. Keypoints with confidence < %.2f were treated as missing. ",
                    kPoseModelName, c.keypointThreshold)
        if c.rejectJumps {
            t += String(format: "Implausible jumps (a keypoint more than %.2f BL from the median position of the tracked frames within ±0.1 s; twice that where tracked frames were on one side only) were also treated as missing. ", c.jumpThreshold)
        }
        t += String(format: "Gaps ≤ %.2f s were %@; longer gaps were left missing and excluded from all measures. Positions were then cleaned with a 3-point median filter and a %.2f s centered moving average. Distances are normalized to body length (BL, median nose–tail-base distance) unless a cm scale was calibrated.\n\n",
                    c.maxGap, c.gapFill.methods, c.smoothing)
        switch s.assay {
        case .tailSuspension:
            let p = s.params.tst
            t += String(format: "Tail suspension test (Steru et al., 1985; Can et al., 2012). Motion was the mean speed of the four paws and the nose (BL/s, %.2f s smoothing). Frames with motion < %.2f BL/s for at least %.1f s were scored as immobile. Immobility was summed over %.0f–%.0f s of the recording; latency is the start of the first immobility bout. Tail climbing was flagged when the nose–tail-base distance fell below %.2f BL. Hindlimb clasping during the first %.0f s was estimated from the lateral distance of each hind paw to the tail-base–nose axis (partial < %.2f BL, full < %.2f BL; score adapted from Guyenet et al., 2010).\n",
                         p.motionSmoothing, p.motionThreshold, p.minBout, p.windowStart, p.windowEnd, p.climbRatio, p.claspWindow, p.claspPartial, p.claspFull)
        case .cylinder:
            let p = s.params.cylinder
            let wall = p.view == .bottom
                ? String(format: "within %.0f%% of the radius from the calibrated cylinder rim (bottom view)", p.wallMargin * 100)
                : String(format: "raised ≥ %.2f BL above the calibrated floor line (side view)", p.elevation)
            t += String(format: "Cylinder test (Schallert et al., 2000). A forepaw wall contact was scored when the paw was %@ and moved slower than %.2f BL/s for ≥ %.2f s. Contacts separated by < %.2f s formed one rear. %@; left and right placements within %.2f s were scored as both. ",
                         wall, p.stillSpeed, p.minContact, p.rearGap,
                         p.scoring == .firstPerRear ? "The first placement of each rear was scored" : "Every placement was scored",
                         p.simultaneity)
            if p.lesion != .none {
                t += "Contralateral forelimb use = contra / (ipsi + contra) × 100; asymmetry index = (ipsi − contra) / (ipsi + contra + both) × 100, relative to the \(p.lesion.rawValue) lesioned hemisphere. "
            }
            t += "Automatically detected contacts were reviewed on video and corrected where necessary (\(s.overrides.count) edits).\n"
        case .gait:
            let p = s.params.gait
            t += String(format: "Gait analysis (bottom view). A paw was in stance when its frame-to-frame speed (smaller of backward and forward steps) was below max(%.2f BL/s, %.2f × body speed); phases shorter than %.0f ms were merged. Strides (foot strike to foot strike of the same paw, ≤ %.2f s) were analyzed only while the body moved ≥ %.2f BL/s ", p.stanceFloor, p.stanceRatio, p.minPhase * 1000, p.maxStride, p.minBodySpeed)
            t += String(format: "in a straight line (mean |angular velocity| ≤ %.0f °/s)%@ (Sheppard et al., 2022). Speed-matched values were obtained from each animal's linear regression of the hind-stride measure on stride speed, evaluated at %.1f BL/s. Gait pattern per hind stride followed Bellardita & Kiehn (2015): hind phase within 0.5 ± 0.15 = walk, or trot if the diagonal (LH→RF) phase was within 0 ± 0.15; hind phase within 0 ± 0.15 = bound; otherwise gallop. Nose and tail-base lateral displacement amplitude was the within-stride range of the perpendicular offset from the line joining the body centre at stride start and end. ", p.maxTurnRate, p.trimRunEnds ? ", excluding the first and last stride of each continuous run" : "", p.referenceSpeed)
            t += "Duty factor = stance / stride duration; stride length = distance between consecutive footprints; base of support = lateral distance between left and right footprints perpendicular to the heading; interlimb phase = (strike_target − strike_reference) / stride_reference, summarized by circular mean and resultant length R; regularity index = 4 × normal step sequence patterns / paw placements × 100 (Cheng et al., 1997). Gait parameters depend on speed (Batka et al., 2014), so per-stride speed is reported.\n"
            if let px = s.calibration.scale?.pxPerCm { t += String(format: "Spatial scale: %.2f px/cm.\n", px) }
        case .itch:
            let p = s.params.itch
            t += String(format: "Scratching (bottom view). Time zero was the injection at %.1f s of the video; scratching was counted from %.1f to %.1f min after it, in %.0f-min bins. ",
                         p.injectionTime, p.windowStart / 60, p.windowEnd / 60, p.binSize / 60)
            let usedModel = result?.behavior?.signalUnit == "p"
            if usedModel {
                let src = ScratchModel.bundled?.sourceName ?? "ScratchModel.json"
                t += "Scratching was detected frame by frame with a gradient-boosted decision-tree classifier (\(src)) trained on pose features of the Scratch-AID dataset (Yu et al., 2022), followed by the probability smoothing, threshold, gap filling and minimum duration tuned during training. "
            } else {
                t += String(format: "A frame was scored as scratching when the 0.5-s mean high-frequency energy of the faster hind paw (squared residual from a 0.2-s rolling median, BL²) exceeded max(10^%.2f, 2.5 × this video's still-paw jitter floor), the hind paw was within %.2f BL of the head and the body moved < %.2f BL/s. ",
                             p.energyThreshold, p.headDistance, p.maxBodySpeed)
            }
            if !usedModel {
                t += String(format: "Scratching separated by < %.2f s was merged into one bout and bouts < %.2f s were discarded, following the definition that a bout ends when the hind paw returns to the floor or pauses (Kuraishi et al., 1995). ",
                             p.mergeGap, p.minBout)
            }
            t += String(format: "Bouts < %.1f s apart were grouped into trains (Yu et al., 2022). The scratching hind paw (left/right) was taken from the larger high-frequency energy. ", p.trainGap)
            if p.site == .cheek {
                t += "Cheek model (Shimada & LaMotte, 2008): unilateral forepaw wiping (one forepaw within 0.22 BL of the head with stroking energy above the jitter floor, the other forepaw ≥ 0.12 BL farther away, head facing forward) was scored separately as pain-like behavior; bilateral forepaw strokes (grooming) were not counted (Yamanoi et al., 2019). "
            }
            t += "Automatically detected bouts were reviewed on video and relabeled where necessary (\(s.eventOverrides?.count ?? 0) edits).\n"
        case .pain:
            let p = s.params.pain
            t += String(format: "Spontaneous pain behavior after injection into the %@ at %.1f s of the video (time zero). Licking/biting was scored when the mouth (or nose) was within %.2f BL of the injected paw while the body moved < %.2f BL/s; gaps < %.1f s were merged and episodes < %.1f s discarded. Any contact of the mouth with the injected paw was counted (Wotton et al., 2020). Licking of the contralateral paw was recorded separately. ",
                         p.injectedPaw.en, p.injectionTime, p.lickDistance, p.maxBodySpeed, p.lickMergeGap, p.minLick)
            t += String(format: "Flinches were brief (≤ %.2f s) movements of the injected paw faster than %.1f BL/s (displacement over ~33 ms; threshold raised to 4 × the paw's median speed at rest when the track was noisy) while the body moved < %.1f BL/s for ±0.3 s, the contralateral paw was not moving equally fast and no licking occurred within 0.5 s. ",
                         p.flinchMaxDuration, p.flinchSpeed, p.flinchBodySpeed)
            t += String(format: "Phase I = 0–%.1f min and phase II = %.1f–%.1f min after injection (Mogil et al., 1999; Hunskaar & Hole, 1987); %.0f-min bins. ",
                         p.phase1End / 60, p.phase2Start / 60, p.phase2End / 60, p.binSize / 60)
            t += "Automatically detected events were reviewed on video and relabeled where necessary (\(s.eventOverrides?.count ?? 0) edits).\n"
        case .grooming:
            let p = s.params.grooming
            t += String(format: "Self-grooming was scored from %.1f to %.1f min of the recording in %.0f-min bins, by body region along the cephalo-caudal chain (Kalueff & Tuohimaa, 2004): face/head when both forepaws were within %.2f BL of the mouth and stroking (0.5-s high-frequency energy > max(10^%.2f, jitter floor × 3)); body/flank when the head was turned > %.0f° from the trunk axis and moving; hind leg/paw when the mouth was within %.2f BL of a hind paw; tail/genitals when the nose was within %.2f BL of the tail base; in all cases with the body moving < %.1f BL/s. Hind-paw scratching was excluded. ",
                         p.windowStart / 60, p.windowEnd / 60, p.binSize / 60, p.faceDistance, p.strokeEnergy, p.headTurn, p.legDistance, p.tailDistance, p.maxBodySpeed)
            t += String(format: "Region segments < %.1f s were dropped. A pause > %.1f s ended a bout (Estanislau, 2012); bouts < %.1f s were discarded; bouts containing a pause ≥ 1 s were interrupted. A transition between regions was correct when it followed the face → body → leg → tail order; %% incorrect transitions and %% interrupted bouts are reported as microstructure measures (Kalueff & Tuohimaa, 2005; Kalueff et al., 2007). ",
                         p.minPhase, p.boutGap, p.minBout)
            t += "Automatically detected bouts were reviewed on video and relabeled where necessary (\(s.eventOverrides?.count ?? 0) edits).\n"
        case .seizure:
            let p = s.params.seizure
            t += String(format: "Behavioral seizures were scored for %.0f min after the convulsant injection at %.1f s of the video, on the %@. ",
                         p.windowEnd / 60, p.injectionTime,
                         p.scale == .ptzMouse ? "revised Racine scale for PTZ in mice (Van Erum et al., 2019)" : "modified Racine scale for kainate / pilocarpine (Racine, 1972; Sharma et al., 2018)")
            t += String(format: "Myoclonic jerks: median keypoint speed (displacement over ~33 ms) > %.1f BL/s with ≥ 4 keypoints moving, lasting ≤ %.2f s, from a body moving < %.1f BL/s, with the body staying within 0.4 BL for the next 0.5 s. Clonic seizures: high-frequency energy of ≥ 3 body parts (including a forepaw and a hind paw) above max(10^%.2f, 5 × jitter floor) with the body in place, for ≥ %.1f s (NINDS s.c. PTZ endpoint). Convulsions on the side: all paws on one side of the body axis for ≥ %.1f s. Wild running/jumping: body speed > %.1f BL/s for ≥ %.1f s, or the animal reappearing > 1.5 BL away within 1 s. Tonic hindlimb extension: both hind paws behind the tail base and still for ≥ %.1f s. ",
                         p.jerkSpeed, p.jerkMaxDuration, p.jerkQuietSpeed, p.clonusEnergy, p.clonusMinDuration, p.postureMinDuration, p.runSpeed, p.runMinDuration, p.tonicMinDuration)
            if p.scoreArrest {
                t += String(format: "Behavioral arrest: overall movement < %.2f BL/s (or 1.5 × the track's jitter floor) for ≥ %.0f s immediately after movement, before the first generalized seizure. ", p.arrestSpeed, p.arrestMinDuration)
            } else {
                t += "Behavioral arrest (stage 1) was not scored. "
            }
            t += String(format: "Overlapping detections were assigned the higher stage; generalized events < %.0f s apart formed one episode. Detections before the injection were counted as a false-positive check. ", p.episodeGap)
            t += "Every event was reviewed on video and relabeled where necessary (\(s.eventOverrides?.count ?? 0) edits).\n"
        }
        t += "\nReferences\n" + references(s.assay).joined(separator: "\n") + "\n"
        return t
    }

    static func references(_ a: Assay) -> [String] {
        let common = ["Mathis A. et al. (2018) DeepLabCut: markerless pose estimation of user-defined body parts with deep learning. Nat Neurosci 21:1281–1289."]
        switch a {
        case .tailSuspension:
            return ["Steru L., Chermat R., Thierry B., Simon P. (1985) The tail suspension test: a new method for screening antidepressants in mice. Psychopharmacology 85:367–370.",
                    "Can A. et al. (2012) The tail suspension test. J Vis Exp 59:e3769.",
                    "Guyenet S.J. et al. (2010) A simple composite phenotype scoring system for evaluating mouse models of cerebellar ataxia. J Vis Exp 39:e1787."] + common
        case .cylinder:
            return ["Schallert T., Fleming S.M., Leasure J.L., Tillerson J.L., Bland S.T. (2000) CNS plasticity and assessment of forelimb sensorimotor outcome in unilateral rat models of stroke, cortical ablation, parkinsonism and spinal cord injury. Neuropharmacology 39:777–787.",
                    "Magno L.A.V. et al. (2019) Cylinder test to assess sensory-motor function in a mouse model of Parkinson's disease. Bio-protocol 9(16):e3337."] + common
        case .gait:
            return ["Hamers F.P. et al. (2001) Automated quantitative gait analysis during overground locomotion in the rat. J Neurotrauma 18:187–201.",
                    "Machado A.S. et al. (2015) A quantitative framework for whole-body coordination reveals specific deficits in freely walking ataxic mice. eLife 4:e07892.",
                    "Cheng H. et al. (1997) Gait analysis of adult paraplegic rats after spinal cord repair. Exp Neurol 148:544–557.",
                    "Batka R.J. et al. (2014) The need for speed in rodent locomotion analyses. Anat Rec 297:1839–1864.",
                    "Neckel N.D. (2015) Methods to quantify the velocity dependence of common gait measurements from automated rodent gait analysis devices. J Neurosci Methods 253:244–253.",
                    "Bellardita C., Kiehn O. (2015) Phenotypic characterization of speed-associated gait changes in mice reveals modular organization of locomotor networks. Curr Biol 25:1426–1436.",
                    "Sheppard K. et al. (2022) Stride-level analysis of mouse open field behavior using deep-learning-based pose estimation. Cell Rep 38:110231."] + common
        case .itch:
            return ["Kuraishi Y., Nagasawa T., Hayashi K., Satoh M. (1995) Scratching behavior induced by pruritogenic but not algesiogenic agents in mice. Eur J Pharmacol 275:229–233.",
                    "Shimada S.G., LaMotte R.H. (2008) Behavioral differentiation between itch and pain in mouse. Pain 139:681–687.",
                    "Akiyama T., Carstens M.I., Carstens E. (2010) Differential itch- and pain-related behavioral responses and µ-opioid modulation in mice. Acta Derm Venereol 90:575–581.",
                    "Yamanoi Y., Kittaka H., Tominaga M. (2019) Cheek injection model for simultaneous measurement of pain and itch-related behaviors. J Vis Exp 151:e58943.",
                    "Yu H. et al. (2022) Scratch-AID, a deep learning-based system for automatic detection of mouse scratching behavior with high accuracy. eLife 11:e84042.",
                    "Elliott P. et al. (2017) Automated acoustic detection of mouse scratching. PLoS ONE 12:e0179662."] + common
        case .pain:
            return ["Hunskaar S., Hole K. (1987) The formalin test in mice: dissociation between inflammatory and non-inflammatory pain. Pain 30:103–114.",
                    "Tjølsen A., Berge O.G., Hunskaar S., Rosland J.H., Hole K. (1992) The formalin test: an evaluation of the method. Pain 51:5–17.",
                    "Mogil J.S. et al. (1999) Heritability of nociception I: responses of 11 inbred mouse strains on 12 measures of nociception. Pain 80:67–82.",
                    "Wotton J.M. et al. (2020) Machine learning-based automated phenotyping of inflammatory nocifensive behavior in mice. Mol Pain 16:1744806920958596."] + common
        case .grooming:
            return ["Kalueff A.V., Tuohimaa P. (2004) Grooming analysis algorithm for neurobehavioural stress research. Brain Res Protoc 13:151–158.",
                    "Kalueff A.V., Tuohimaa P. (2005) Mouse grooming microstructure is a reliable anxiety marker bidirectionally sensitive to GABAergic drugs. Eur J Pharmacol 508:147–153.",
                    "Kalueff A.V., Aldridge J.W., LaPorte J.L., Murphy D.L., Tuohimaa P. (2007) Analyzing grooming microstructure in neurobehavioral experiments. Nat Protoc 2:2538–2544.",
                    "Kalueff A.V. et al. (2016) Neurobiology of rodent self-grooming and its value for translational neuroscience. Nat Rev Neurosci 17:45–59.",
                    "Estanislau C. (2012) Cues to the usefulness of grooming behavior in the evaluation of anxiety in the elevated plus-maze. Psychol Neurosci 5:105–112."] + common
        case .seizure:
            return ["Racine R.J. (1972) Modification of seizure activity by electrical stimulation. II. Motor seizure. Electroencephalogr Clin Neurophysiol 32:281–294.",
                    "Lüttjohann A., Fabene P.F., van Luijtelaar G. (2009) A revised Racine's scale for PTZ-induced seizures in rats. Physiol Behav 98:579–586.",
                    "Van Erum J., Van Dam D., De Deyn P.P. (2019) PTZ-induced seizures in mice require a revised Racine scale. Epilepsy Behav 95:51–55.",
                    "Ferraro T.N. et al. (1999) Mapping loci for pentylenetetrazol-induced seizure susceptibility in mice. J Neurosci 19:6733–6739.",
                    "Sharma S., Puttachary S., Thippeswamy A., Kanthasamy A.G., Thippeswamy T. (2018) Status epilepticus: behavioral and electroencephalography seizure correlates in kainate experimental models. Front Neurol 9:7.",
                    "Copping N.A., Silverman J.L. (2021) Abnormal electrophysiological phenotypes and sleep deficits in a mouse model of Angelman syndrome. Mol Autism 12. doi:10.1186/s13229-021-00416-y."] + common
        }
    }
}
