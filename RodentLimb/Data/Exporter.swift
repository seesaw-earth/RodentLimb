// Exporter.swift — CSV / text exports. Always English, independent of the interface language.

import Foundation

@MainActor
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

    static func sessionFiles(_ s: Session, result: AnalysisResult, track: PoseTrack?, store: SessionStore,
                             includePose: Bool, includeVideo: Bool) -> [URL] {
        let dir = exportDir()
        let base = safeName(s.displayName) + "_" + s.assay.code
        var urls: [URL] = []

        var summary = row(["field", "value", "unit"])
        for (k, v) in metadata(s) { summary += row([k, v, ""]) }
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
        }

        if let u = write(methods(s), dir.appendingPathComponent(base + "_methods.txt")) { urls.append(u) }
        if includeVideo, s.hasSkeletonVideo {
            let src = store.skeletonURL(s.id)
            let dst = dir.appendingPathComponent(base + "_skeleton.mp4")
            if (try? FileManager.default.copyItem(at: src, to: dst)) != nil { urls.append(dst) }
        }
        return urls
    }

    /// Frame-by-frame pose CSV, built off the main thread (can be tens of MB for long videos).
    static func poseFile(_ s: Session, track: PoseTrack, nextTo other: URL?) async -> URL? {
        let dir = other?.deletingLastPathComponent() ?? exportDir()
        let url = dir.appendingPathComponent(safeName(s.displayName) + "_" + s.assay.code + "_pose.csv")
        return await Task.detached(priority: .userInitiated) { write(poseCSV(track), url) }.value
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
        var header = ["frame", "time_s", "box_confidence"]
        for k in Kp.allCases { header += ["\(k.exportName)_x", "\(k.exportName)_y", "\(k.exportName)_confidence"] }
        var out = header.joined(separator: ",") + "\n"
        out.reserveCapacity(t.frameCount * 120)
        for i in 0..<t.frameCount {
            var r = ["\(i)", String(format: "%.4f", t.times[i]), String(format: "%.3f", t.boxConfidence[i])]
            for k in Kp.allCases {
                let x = t.x[k.rawValue][i], y = t.y[k.rawValue][i]
                r += x >= 0 ? [String(format: "%.2f", x), String(format: "%.2f", y)] : ["", ""]
                r.append(String(format: "%.3f", t.c[k.rawValue][i]))
            }
            out += r.joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: Group export (wide, one row per session)

    static func groupCSV(_ sessions: [Session], results: [UUID: AnalysisResult]) -> URL? {
        guard let assay = sessions.first?.assay else { return nil }
        var keys: [String] = [], units: [String: String] = [:]
        for s in sessions {
            for m in results[s.id]?.metrics ?? [] where !keys.contains(m.key) {
                keys.append(m.key); units[m.key] = m.unit
            }
        }
        var out = row(["subject", "group", "video", "created", "status"] + keys.map { k in
            let u = units[k] ?? ""
            return u.isEmpty ? k : "\(k) [\(u)]"
        })
        let iso = ISO8601DateFormatter()
        for s in sessions {
            let r = results[s.id]
            out += row([s.subject, s.group, s.originalName, iso.string(from: s.createdAt), s.status.rawValue] +
                       keys.map { k in r?.metric(k)?.exportValue ?? "" })
        }
        let dir = exportDir()
        let stamp = Date().formatted(.iso8601.year().month().day())
        return write(out, dir.appendingPathComponent("RodentLimb_\(assay.code)_\(sessions.count)_sessions_\(stamp).csv"))
    }

    // MARK: Methods paragraph

    static func methods(_ s: Session) -> String {
        let c = s.params.common
        var t = "RodentLimb — automated analysis methods (\(s.assay.name.en))\n\n"
        t += String(format: "Pose estimation: %@ (7 keypoints: left/right fore and hind paws, tail base, nose, mouth), run on-device with Core ML on every video frame. Keypoints with confidence < %.2f were treated as missing; gaps ≤ %.2f s were linearly interpolated, followed by a 3-point median filter and a %.2f s centered moving average. Distances are normalized to body length (BL, median nose–tail-base distance) unless a cm scale was calibrated.\n\n",
                    kPoseModelName, c.keypointThreshold, c.maxGap, c.smoothing)
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
        }
    }
}
