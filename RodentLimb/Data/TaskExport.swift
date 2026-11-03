// TaskExport.swift — export of one task (TASK_FIRST_SPEC §2.7), English, long format:
//
//   …_analyses_<date>.csv   summary: one row per session, design columns first (shared Exporter.groupCSV)
//   <task>_qc.csv           one row per video: pose model, QC measures, inclusion decision and reason
//   <task>_events.csv       behaviour segments / contacts / strides / immobility bouts, one row per event
//   <task>_time_bins.csv    binned time course per session (behaviour bins, TST per minute)
//   <task>_methods.txt      methods paragraph (naming the pose model used) and the study design (ARRIVE 2.0)
//   README.txt              what each file holds
//   manifest.json           every session with its video, pose model, decision and parameters
//
// While the task is blinded, animal IDs, groups and file names are left out (blind codes only).
// Foundation only.

import Foundation

@MainActor
enum TaskExport {
    static func files(store: SessionStore, task: TaskRef) async -> [URL] {
        guard let e = store.experiment(task.experimentID) else { return [] }
        let list = store.sessions(in: task)
        guard !list.isEmpty else { return [] }
        let results = await store.loadResults(list.map(\.id))
        let rows = store.exportRows(list, results: results)
        let models = list.map { s in s.recordingID.map { store.poseModel($0) } ?? .visible }
        let recs = list.map { store.recording(for: $0) }
        let taskName = store.taskName(task)
        let design = store.studyMethods(e)
        let blinded = e.blinded
        let version = AppInfo.version
        return await Task.detached(priority: .userInitiated) { () -> [URL] in
            guard let summary = Exporter.groupCSV(rows, name: taskName) else { return [] }
            let dir = summary.deletingLastPathComponent()
            let base = Exporter.safeName(taskName) + "_" + task.assay.code
            var urls = [summary]
            func put(_ text: String, _ file: String) {
                if let u = Exporter.write(text, dir.appendingPathComponent(file)) { urls.append(u) }
            }
            put(qcCSV(rows, recs: recs, models: models, blinded: blinded), base + "_qc.csv")
            if let ev = eventsCSV(rows, assay: task.assay, blinded: blinded) { put(ev, base + "_events.csv") }
            if let bins = binsCSV(rows, assay: task.assay, blinded: blinded) { put(bins, base + "_time_bins.csv") }
            put(methods(rows, models: models, design: design), base + "_methods.txt")
            put(readme(taskName: taskName, assay: task.assay, base: base, summary: summary.lastPathComponent,
                       blinded: blinded, count: rows.count), "README.txt")
            if let m = manifest(rows, recs: recs, models: models, taskName: taskName, assay: task.assay, blinded: blinded, version: version) {
                put(m, "manifest.json")
            }
            return urls
        }.value
    }

    // MARK: Identity columns

    nonisolated static let idHeader = ["animal_id", "blind_code", "group", "timepoint", "trial", "session_id"]

    nonisolated static func ids(_ r: ExportRow, blinded: Bool) -> [String] {
        [blinded ? "" : r.animal, r.blindCode, blinded ? "" : r.group, r.timepoint, "\(r.trial)", r.session.id.uuidString]
    }

    nonisolated static func f(_ v: Double?, _ d: Int = 3) -> String { Exporter.f(v, d) }

    // MARK: Files

    nonisolated static func qcCSV(_ rows: [ExportRow], recs: [Recording?], models: [PoseModelID], blinded: Bool) -> String {
        var out = Exporter.row(idHeader + ["video", "pose_model", "qc_verdict", "mouse_tracked_pct", "mouse_detected_pct",
                                           "longest_lost_s", "implausible_jumps_pct", "fps", "duration_s", "included", "exclusion_reason"])
        for (i, r) in rows.enumerated() {
            let qc = i < recs.count ? recs[i]?.qc : nil
            let model = i < models.count ? models[i] : .visible
            out += Exporter.row(ids(r, blinded: blinded) + [
                blinded ? "" : r.session.originalName, model.rawValue, r.qcVerdict,
                f(qc.map { $0.coreCoverage * 100 }, 1), f(qc.map { $0.detection * 100 }, 1), f(qc?.longestLost, 2),
                f(qc.map { $0.jumpRate * 100 }, 2), f(r.session.fps, 2), f(r.session.duration, 2), r.included, r.exclusionReason,
            ])
        }
        return out
    }

    nonisolated static func eventsCSV(_ rows: [ExportRow], assay: Assay, blinded: Bool) -> String? {
        var out: String
        var any = false
        switch assay {
        case .itch, .pain, .grooming, .seizure:
            out = Exporter.row(idHeader + ["included", "event", "behavior", "onset_s", "offset_s", "duration_s", "onset_after_injection_s",
                                           "auto_label", "edited", "counted", "info"])
            for r in rows {
                guard let d = r.result?.behavior else { continue }
                for (i, x) in d.events.enumerated() {
                    any = true
                    out += Exporter.row(ids(r, blinded: blinded) + [r.included, "\(i + 1)", x.label, f(x.onset), f(x.offset), f(x.duration),
                                                                     f(x.onset - d.origin), x.auto, x.edited ? "1" : "0", x.counted ? "1" : "0", x.info ?? ""])
                }
            }
        case .cylinder:
            out = Exporter.row(idHeader + ["included", "contact", "onset_s", "offset_s", "rear", "auto_label", "final_label", "edited", "counted"])
            for r in rows {
                guard let d = r.result?.cylinder else { continue }
                for (i, x) in d.events.enumerated() {
                    any = true
                    out += Exporter.row(ids(r, blinded: blinded) + [r.included, "\(i + 1)", f(x.onset), f(x.offset), "\(x.rear)",
                                                                     x.auto.rawValue, x.label.rawValue, x.edited ? "1" : "0", x.counted ? "1" : "0"])
                }
            }
        case .gait:
            out = Exporter.row(idHeader + ["included", "paw", "start_s", "end_s", "stride_s", "stance_s", "swing_s", "duty",
                                           "stride_length", "speed", "unit"])
            for r in rows {
                guard let d = r.result?.gait else { continue }
                for x in d.strides {
                    any = true
                    out += Exporter.row(ids(r, blinded: blinded) + [r.included, x.paw.code, f(x.start, 4), f(x.end, 4), f(x.end - x.start, 4),
                                                                     f(x.stance, 4), f(x.swing, 4), f(x.duty, 4), f(x.length, 4), f(x.speed), d.unit])
                }
            }
        case .tailSuspension:
            out = Exporter.row(idHeader + ["included", "bout", "start_s", "end_s", "duration_s", "overlaps_window"])
            for r in rows {
                guard let d = r.result?.tst else { continue }
                for (i, x) in d.bouts.enumerated() {
                    any = true
                    let overlaps = x.end > d.window.start && x.start < d.window.end
                    out += Exporter.row(ids(r, blinded: blinded) + [r.included, "\(i + 1)", f(x.start), f(x.end), f(x.duration), overlaps ? "1" : "0"])
                }
            }
        }
        return any ? out : nil
    }

    nonisolated static func binsCSV(_ rows: [ExportRow], assay: Assay, blinded: Bool) -> String? {
        if assay == .tailSuspension {
            var out = Exporter.row(idHeader + ["included", "minute", "immobility_s"])
            var any = false
            for r in rows {
                guard let d = r.result?.tst else { continue }
                for (i, v) in d.perMinute.enumerated() {
                    any = true
                    out += Exporter.row(ids(r, blinded: blinded) + [r.included, "\(i + 1)", f(v, 2)])
                }
            }
            return any ? out : nil
        }
        var keys: [String] = [], units: [String: String] = [:]
        for r in rows {
            for b in r.result?.behavior?.bins ?? [] where !keys.contains(b.key) { keys.append(b.key); units[b.key] = b.unit }
        }
        guard !keys.isEmpty else { return nil }
        var out = Exporter.row(idHeader + ["included", "bin", "start_after_injection_s", "end_after_injection_s"]
                               + keys.map { k in (units[k] ?? "").isEmpty ? k : "\(k) [\(units[k] ?? "")]" })
        for r in rows {
            guard let d = r.result?.behavior, !d.bins.isEmpty else { continue }
            let n = d.bins.map(\.values.count).max() ?? 0
            for i in 0..<n {
                let a = Double(i) * d.binSize
                let values = keys.map { k -> String in
                    guard let b = d.bins.first(where: { $0.key == k }), i < b.values.count else { return "" }
                    return f(b.values[i])
                }
                out += Exporter.row(ids(r, blinded: blinded) + [r.included, "\(i + 1)", f(a, 1), f(a + d.binSize, 1)] + values)
            }
        }
        return out
    }

    nonisolated static func methods(_ rows: [ExportRow], models: [PoseModelID], design: String) -> String {
        guard let first = rows.first(where: { $0.result != nil }) ?? rows.first else { return design }
        let threshold = first.session.params.common.keypointThreshold
        var t = ExportFixes.methods(Exporter.methods(first.session, result: first.result), models: models, threshold: threshold)
        let distinct = Set(rows.map { r -> String in
            var p = r.session.params
            p.keepPerAnimal(from: AssayParams.defaults(for: r.session.assay))
            p.cylinder.lesion = .none
            return (try? String(decoding: JSONEncoder().encode(p), as: UTF8.self)) ?? ""
        })
        if distinct.count > 1 {
            t += "\nNote: \(distinct.count) different parameter sets were used across the \(rows.count) sessions of this task (see manifest.json for each session's parameters).\n"
        }
        return t + "\n\n" + design
    }

    nonisolated static func readme(taskName: String, assay: Assay, base: String, summary: String, blinded: Bool, count: Int) -> String {
        var t = "RodentLimb export — \(taskName) (\(assay.name.en)), \(count) sessions\n\n"
        t += "\(summary)\n  Summary: one row per session (animal × timepoint × trial), design columns first, then every measure. Long format for R (lme4, afex), Python, SPSS or Prism.\n"
        t += "\(base)_qc.csv\n  Tracking quality of every video, the pose model that tracked it, and the inclusion decision with its reason (ARRIVE 2.0 item 3).\n"
        t += "\(base)_events.csv\n  Every scored event (behaviour segments, wall contacts, strides or immobility bouts), one row per event.\n"
        t += "\(base)_time_bins.csv\n  Binned time course per session (times relative to the injection where the paradigm has one).\n"
        t += "\(base)_methods.txt\n  Methods paragraph with the parameters used, and the study design (groups, n, randomisation, blinding, exclusions).\n"
        t += "manifest.json\n  Every session with its video, pose model, decision and full parameter set.\n\n"
        t += "Column `included`: 1 = included, 0 = excluded, pending = not yet reviewed. Group results in the app use included sessions only; the animal is the experimental unit.\n"
        if blinded { t += "\nThe task was blinded when exported: animal IDs, groups and video file names are left out; animals are identified by blind codes.\n" }
        return t
    }

    private struct ManifestSession: Encodable {
        var session_id: String
        var recording_id: String
        var animal_id: String
        var blind_code: String
        var group: String
        var timepoint: String
        var trial: Int
        var video: String
        var pose_model: String
        var model_version: String
        var included: String
        var exclusion_reason: String
        var params: AssayParams
    }

    private struct Manifest: Encodable {
        var app: String
        var app_version: String
        var created: Date
        var task: String
        var paradigm: String
        var blinded: Bool
        var sessions: [ManifestSession]
    }

    nonisolated static func manifest(_ rows: [ExportRow], recs: [Recording?], models: [PoseModelID], taskName: String, assay: Assay,
                                     blinded: Bool, version: String) -> String? {
        let sessions = rows.enumerated().map { i, r in
            ManifestSession(session_id: r.session.id.uuidString,
                            recording_id: (i < recs.count ? recs[i]?.id.uuidString : nil) ?? "",
                            animal_id: blinded ? "" : r.animal, blind_code: r.blindCode, group: blinded ? "" : r.group,
                            timepoint: r.timepoint, trial: r.trial, video: blinded ? "" : r.session.originalName,
                            pose_model: (i < models.count ? models[i] : .visible).rawValue,
                            model_version: r.session.modelVersion ?? "", included: r.included,
                            exclusion_reason: r.exclusionReason, params: r.session.params)
        }
        let m = Manifest(app: "RodentLimb", app_version: version, created: Date(), task: taskName, paradigm: assay.name.en,
                         blinded: blinded, sessions: sessions)
        let enc = Coders.encoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(m) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
}
