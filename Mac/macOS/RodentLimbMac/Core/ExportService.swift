// ExportService.swift — batch export of analyses, behavior segments, QC and pose, organised so it can
// go straight into R / Python / Prism / SPSS, and into other behavior tools.
//
// One folder per export:
//   RodentLimb_<scope>_<yyyy-MM-dd_HHmm>/
//     README.txt                 what every file and column is (data dictionary)
//     export_manifest.json       app and model version, date, options, every analysis with its parameters
//     qc_videos.csv              tracking quality and the include / exclude decision of every video (ARRIVE item 3)
//     study_<name>_design.txt    design & methods text of each study involved
//     <TASK>/                    one folder per task (e.g. ITCH_Itch_scratching)
//       <TASK>_summary.csv          one row per analysis: design columns + every measure (long / tidy format)
//       <TASK>_segments.csv         behavior segments of all videos: every event / bout with onset, offset, duration,
//                                   automatic and final label, reviewer edits (TST: immobility bouts; cylinder: contacts)
//       <TASK>_ethogram.csv         behavior intervals per track (all videos)
//       <TASK>_time_bins.csv        time course from the injection, long format (analysis × bin × measure)
//       <TASK>_per_minute.csv, _strides.csv, _footprints.csv   task-specific detail tables
//       <TASK>_boris_events.tsv     (option) BORIS "aggregated events" table
//       <TASK>_methods.txt          methods paragraph with the parameters and references
//       frame_labels/…_labels.csv   (option) per video, one row per frame, 0/1 per behavior (DeepEthogram / daart layout)
//       per_video/<animal>_<id>/    (option) the iPhone app's single-analysis files
//     pose/…_pose.csv, pose_dlc/…_DLC.csv   (option) frame-by-frame keypoints (RodentLimb / DeepLabCut layout)
//
// Every combined table starts with the same identification columns (analysis_id, study, animal_id,
// blind_code, sex, group, timepoint, trial, video, included), so tables join on analysis_id.
// While a study is blinded, animal IDs, groups and file names are left out, exactly as in the
// iPhone app. All files are UTF-8 (with BOM, for Excel), comma-separated, English.
//
// Snapshot on the main actor, everything else off it. Foundation only (tested on Linux).

import Foundation

enum ExportError: LocalizedError {
    case nothingToExport
    case cannotCreateFolder(String)

    var errorDescription: String? {
        switch self {
        case .nothingToExport:
            return L("Nothing to export: the selection has no analyses or videos.", "没有可导出的内容：所选范围内没有分析或视频。")
        case .cannotCreateFolder(let d):
            return L("Cannot create the export folder: ", "无法创建导出文件夹：") + d
        }
    }
}

enum ExportService {
    // MARK: Plan (main actor)

    private struct Item {
        var row: ExportRow
        var recordingID: UUID?
        var recordingFolder: URL?
        /// Pose model that tracked the video (written to the QC table, methods, manifest).
        var poseModel: PoseModelID = .visible
    }

    private struct VideoItem {
        var recording: Recording
        var study: String
        var animal: String
        var blindCode: String
        var sex: String
        var group: String
        var blinded: Bool
        var tasks: [String]
        var poseModel: PoseModelID = .visible
    }

    private struct Plan {
        var name: String
        var items: [Item]
        var videos: [VideoItem]
        var studies: [(String, String)]
        var scopeText: String
    }

    @MainActor
    private static func resolve(_ scope: ExportScope, store: SessionStore) -> (sessions: [Session], recordings: [Recording], name: String) {
        switch scope {
        case .selection(let a, let r):
            var ids = a
            for rid in r { for s in store.sessions(of: rid) { ids.insert(s.id) } }
            let sessions = store.sessions.filter { ids.contains($0.id) }
            var recIDs = r
            for s in sessions { if let rid = s.recordingID { recIDs.insert(rid) } }
            return (sessions, store.recordings.filter { recIDs.contains($0.id) }, "selection")
        case .assay(let a):
            let sessions = store.sessions.filter { $0.assay == a }
            let recIDs = Set(sessions.compactMap(\.recordingID))
            return (sessions, store.recordings.filter { recIDs.contains($0.id) }, a.code)
        case .task(let t):
            let sessions = store.sessions(in: t)
            let recIDs = Set(sessions.compactMap(\.recordingID))
            return (sessions, store.recordings.filter { recIDs.contains($0.id) }, Exporter.safeName("\(store.taskTitle(t))_\(t.assay.code)"))
        case .study(let id):
            let recs = store.recordings(in: id)
            let recIDs = Set(recs.map(\.id))
            let sessions = store.sessions.filter { $0.recordingID.map { recIDs.contains($0) } ?? false }
            return (sessions, recs, Exporter.safeName(store.experiment(id)?.name ?? "study"))
        case .library:
            return (store.sessions, store.recordings, "library")
        }
    }

    /// Analyses and videos a scope covers (for the export sheet).
    @MainActor
    static func preview(_ scope: ExportScope, options: ExportOptions, store: SessionStore) -> (analyses: Int, recordings: Int, assays: [Assay]) {
        let r = resolve(scope, store: store)
        let sessions = options.includeNotIncluded ? r.sessions
            : r.sessions.filter { store.recording(for: $0)?.decision == .included }
        let assays = Assay.allCases.filter { a in sessions.contains { $0.assay == a } }
        return (sessions.count, r.recordings.count, assays)
    }

    @MainActor
    private static func plan(_ scope: ExportScope, options: ExportOptions, store: SessionStore) -> Plan {
        let r = resolve(scope, store: store)
        var sessions = r.sessions
        if !options.includeNotIncluded {
            sessions = sessions.filter { store.recording(for: $0)?.decision == .included }
        }
        // Stable order: study, (group unless blinded), animal, timepoint order, trial.
        func key(_ s: Session) -> [String] {
            guard let rec = store.recording(for: s) else { return ["~", s.subject] }
            let e = store.experiment(for: rec)
            let a = e?.animal(rec.animalID)
            let tp = e.map { $0.timepoints.firstIndex(of: rec.timepoint) ?? $0.timepoints.count } ?? 0
            let group = (e?.blinded ?? false) ? "" : (a.flatMap { e?.groupLabel($0) } ?? rec.group)
            let who = a.flatMap { e?.displayCode($0) } ?? rec.subject
            return [e?.name ?? "", group, who, String(format: "%04d", tp), rec.timepoint, String(format: "%04d", rec.trial)]
        }
        sessions.sort { key($0).lexicographicallyPrecedes(key($1)) }
        let items = sessions.map { s -> Item in
            Item(row: store.exportRow(s, result: nil), recordingID: s.recordingID,
                 recordingFolder: s.recordingID.map { store.recordingFolder($0) },
                 poseModel: s.recordingID.map { store.poseModel($0) } ?? .visible)
        }
        let videos = r.recordings.sorted { a, b in
            let ka = [store.experiment(for: a)?.name ?? "", store.subjectLabel(a), a.timepoint, String(format: "%04d", a.trial)]
            let kb = [store.experiment(for: b)?.name ?? "", store.subjectLabel(b), b.timepoint, String(format: "%04d", b.trial)]
            return ka.lexicographicallyPrecedes(kb)
        }.map { rec -> VideoItem in
            let e = store.experiment(for: rec)
            let a = e?.animal(rec.animalID)
            let blinded = e?.blinded ?? false
            return VideoItem(recording: rec, study: e?.name ?? "",
                             animal: blinded ? "" : (a?.code ?? rec.subject), blindCode: a?.blindCode ?? "",
                             sex: a?.sex.exportName ?? "",
                             group: blinded ? "" : (e != nil && a != nil ? (a.map { e?.groupLabel($0) ?? "" } ?? "") : rec.group),
                             blinded: blinded,
                             tasks: store.sessions(of: rec.id).map(\.assay.code),
                             poseModel: store.poseModel(rec.id))
        }
        var studyIDs: [UUID] = []
        for v in r.recordings { if let id = v.experimentID, !studyIDs.contains(id) { studyIDs.append(id) } }
        let studies = studyIDs.compactMap { id in store.experiment(id).map { ($0.name, store.studyMethods($0)) } }
        let scopeText: String
        switch scope {
        case .selection: scopeText = "selection (\(sessions.count) analyses, \(r.recordings.count) videos)"
        case .assay(let a): scopeText = "task \(a.name.en)"
        case .study(let id): scopeText = "study \(store.experiment(id)?.name ?? "")"
        case .task(let t): scopeText = "task \(store.taskTitle(t)) (\(t.assay.name.en))"
        case .library: scopeText = "whole library"
        }
        return Plan(name: r.name, items: items, videos: videos, studies: studies, scopeText: scopeText)
    }

    // MARK: Run

    /// Writes the export into a new folder inside `parent` and returns what was written.
    @MainActor
    static func run(_ scope: ExportScope, options: ExportOptions, into parent: URL, store: SessionStore,
                    progress: @escaping @MainActor (ExportProgress) -> Void) async throws -> ExportReport {
        progress(ExportProgress(fraction: 0, step: L("Collecting analyses…", "正在收集分析…")))
        var p = plan(scope, options: options, store: store)
        guard !p.items.isEmpty || !p.videos.isEmpty else { throw ExportError.nothingToExport }
        let results = await store.loadResults(p.items.map(\.row.session.id))
        for i in p.items.indices { p.items[i].row.result = results[p.items[i].row.session.id] }
        let plan = p
        let report = try await Task.detached(priority: .userInitiated) { () throws -> ExportReport in
            try write(plan, options: options, parent: parent) { f, step in
                Task { @MainActor in progress(ExportProgress(fraction: f, step: step)) }
            }
        }.value
        progress(ExportProgress(fraction: 1, step: L("Done", "完成")))
        store.log.write("Exported \(report.analyses) analyses / \(report.recordings) videos to \(report.folder.path)")
        return report
    }

    // MARK: Writing (off the main actor)

    static let idHeader = ["analysis_id", "study", "animal_id", "blind_code", "sex", "group", "timepoint", "trial", "video", "included"]

    private static func ids(_ r: ExportRow) -> [String] {
        [String(r.session.id.uuidString.prefix(8)).lowercased(), r.study, r.blinded ? "" : r.animal, r.blindCode, r.sex,
         r.blinded ? "" : r.group, r.timepoint, "\(r.trial)", r.blinded ? "" : r.session.originalName, r.included]
    }

    private static func f(_ v: Double?, _ d: Int = 4) -> String { Exporter.f(v, d) }

    private static func stamp() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HHmm"
        return df.string(from: Date())
    }

    private static func uniqueFolder(_ parent: URL, _ name: String) -> URL {
        let fm = FileManager.default
        var url = parent.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(name)_\(n)", isDirectory: true)
            n += 1
        }
        return url
    }

    private static func fileStem(_ r: ExportRow) -> String {
        let who = r.blinded ? (r.blindCode.isEmpty ? "animal" : r.blindCode) : (r.animal.isEmpty ? r.session.subject : r.animal)
        var parts = [who]
        if !r.timepoint.isEmpty { parts.append(r.timepoint) }
        if r.trial > 1 { parts.append("T\(r.trial)") }
        parts.append(String(r.session.id.uuidString.prefix(6)).lowercased())
        return Exporter.safeName(parts.joined(separator: "_"))
    }

    private static func write(_ plan: Plan, options o: ExportOptions, parent: URL,
                              progress: (Double, String) -> Void) throws -> ExportReport {
        let fm = FileManager.default
        let root = uniqueFolder(parent, "RodentLimb_\(Exporter.safeName(plan.name))_\(stamp())")
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true) } catch {
            throw ExportError.cannotCreateFolder(error.localizedDescription)
        }
        var report = ExportReport(folder: root)
        report.analyses = plan.items.count
        report.recordings = plan.videos.count
        func put(_ text: String, _ url: URL) {
            if let u = Exporter.write(text, url) { report.files.append(u) } else { report.warnings.append("Could not write \(url.lastPathComponent)") }
        }
        /// Machine-oriented files (BORIS, frame labels) without the Excel byte-order mark.
        func putPlain(_ text: String, _ url: URL) {
            if (try? Data(text.utf8).write(to: url, options: .atomic)) != nil { report.files.append(url) } else { report.warnings.append("Could not write \(url.lastPathComponent)") }
        }

        let byAssay = Dictionary(grouping: plan.items, by: { $0.row.session.assay })
        let assays = Assay.allCases.filter { byAssay[$0] != nil }
        let poseJobs = (o.poseCSV || o.poseDLC) ? plan.videos.filter { $0.recording.hasPose } : []
        let totalSteps = Double(max(1, assays.count * 2 + poseJobs.count + 2))
        var done = 0.0
        func tick(_ step: String) { done += 1; progress(min(0.99, done / totalSteps), step) }

        // QC of every video.
        if o.qc && !plan.videos.isEmpty {
            put(qcTable(plan.videos), root.appendingPathComponent("qc_videos.csv"))
        }
        if o.methods {
            for (name, text) in plan.studies {
                put(text, root.appendingPathComponent("study_\(Exporter.safeName(name))_design.txt"))
            }
        }
        tick(L("Quality control", "质量控制"))

        // Pose tracks are read once per video and only when needed.
        var poseCache: [UUID: PoseTrack] = [:]
        func pose(_ item: Item) -> PoseTrack? {
            guard let rid = item.recordingID, let folder = item.recordingFolder else { return nil }
            if let t = poseCache[rid] { return t }
            let t = PoseStorage.load(folder: folder)
            if poseCache.count > 8 { poseCache.removeAll() }
            if let t { poseCache[rid] = t }
            return t
        }

        for a in assays {
            let items = byAssay[a] ?? []
            let rows = items.map(\.row)
            let dir = root.appendingPathComponent("\(a.code)_\(Exporter.safeName(a.name.en))", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let base = a.code

            if o.summary, let u = Exporter.groupCSV(rows, name: nil) {
                let dest = dir.appendingPathComponent("\(base)_summary.csv")
                try? fm.removeItem(at: dest)
                if (try? fm.moveItem(at: u, to: dest)) != nil { report.files.append(dest) } else { report.warnings.append("Could not write \(base)_summary.csv") }
                try? fm.removeItem(at: u.deletingLastPathComponent())
            }
            let missing = rows.filter { $0.result == nil }.count
            if missing > 0 {
                report.warnings.append("\(a.name.en): \(missing) analysis(es) have no result yet (still tracking, failed, or waiting for calibration) — their measures are empty.")
            }

            if a.isBehavior {
                if o.segments { put(behaviorSegments(rows), dir.appendingPathComponent("\(base)_segments.csv")) }
                if o.ethogram { put(behaviorEthogram(rows), dir.appendingPathComponent("\(base)_ethogram.csv")) }
                if o.timeBins { put(behaviorBins(rows), dir.appendingPathComponent("\(base)_time_bins.csv")) }
                if o.boris { putPlain(boris(rows), dir.appendingPathComponent("\(base)_boris_events.tsv")) }
            } else if a == .tailSuspension {
                if o.segments { put(tstBouts(rows), dir.appendingPathComponent("\(base)_segments.csv")) }
                if o.ethogram { put(tstEthogram(rows), dir.appendingPathComponent("\(base)_ethogram.csv")) }
                if o.details { put(tstPerMinute(rows), dir.appendingPathComponent("\(base)_per_minute.csv")) }
                if o.boris { putPlain(boris(rows), dir.appendingPathComponent("\(base)_boris_events.tsv")) }
            } else if a == .cylinder {
                if o.segments { put(cylinderContacts(rows), dir.appendingPathComponent("\(base)_segments.csv")) }
                if o.boris { putPlain(boris(rows), dir.appendingPathComponent("\(base)_boris_events.tsv")) }
            } else if a == .gait, o.details {
                put(gaitStrides(rows), dir.appendingPathComponent("\(base)_strides.csv"))
                put(gaitFootprints(rows), dir.appendingPathComponent("\(base)_footprints.csv"))
            }
            if o.methods {
                put(methods(rows, models: items.map(\.poseModel)), dir.appendingPathComponent("\(base)_methods.txt"))
            }
            tick(a.name.text)

            if o.frameLabels && (a.isBehavior || a == .tailSuspension || a == .cylinder) {
                let fl = dir.appendingPathComponent("frame_labels", isDirectory: true)
                try? fm.createDirectory(at: fl, withIntermediateDirectories: true)
                for item in items {
                    guard let r = item.row.result, let t = pose(item) else { continue }
                    if let text = frameLabels(item.row.session, result: r, track: t) {
                        putPlain(text, fl.appendingPathComponent(fileStem(item.row) + "_labels.csv"))
                    }
                }
            }
            if o.perVideoFolders {
                let pv = dir.appendingPathComponent("per_video", isDirectory: true)
                for item in items {
                    guard let r = item.row.result else { continue }
                    let sub = pv.appendingPathComponent(fileStem(item.row), isDirectory: true)
                    try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
                    let urls = Exporter.sessionFiles(item.row.session, result: r, track: nil, skeletonURL: nil,
                                                     includePose: false, includeVideo: false, design: item.row)
                    for u in urls {
                        let dest = sub.appendingPathComponent(u.lastPathComponent)
                        try? fm.removeItem(at: dest)
                        if (try? fm.moveItem(at: u, to: dest)) != nil {
                            report.files.append(dest)
                            if item.poseModel != .visible, dest.lastPathComponent.hasSuffix("_summary.csv") {
                                namePoseModel(item.poseModel, in: dest)
                            }
                        }
                    }
                    if let tmp = urls.first?.deletingLastPathComponent() { try? fm.removeItem(at: tmp) }
                }
            }
            tick(a.name.text)
        }

        // Frame-by-frame keypoints, one file per video.
        if !poseJobs.isEmpty {
            let pdir = root.appendingPathComponent("pose", isDirectory: true)
            let ddir = root.appendingPathComponent("pose_dlc", isDirectory: true)
            if o.poseCSV { try? fm.createDirectory(at: pdir, withIntermediateDirectories: true) }
            if o.poseDLC { try? fm.createDirectory(at: ddir, withIntermediateDirectories: true) }
            for v in poseJobs {
                autoreleasepoolIfAvailable {
                    let folder = recordingFolder(of: v, plan: plan)
                    guard let folder, let t = PoseStorage.load(folder: folder) else {
                        report.warnings.append("No pose for \(v.recording.originalName)")
                        return
                    }
                    let who = v.blinded ? (v.blindCode.isEmpty ? "animal" : v.blindCode) : (v.animal.isEmpty ? v.recording.originalName : v.animal)
                    var stemParts = [who]
                    if !v.recording.timepoint.isEmpty { stemParts.append(v.recording.timepoint) }
                    stemParts.append(String(v.recording.id.uuidString.prefix(6)).lowercased())
                    let stem = Exporter.safeName(stemParts.joined(separator: "_"))
                    if o.poseCSV {
                        let u = pdir.appendingPathComponent(stem + "_pose.csv")
                        if Exporter.writePoseCSV(t, to: u) { report.files.append(u) }
                    }
                    if o.poseDLC {
                        let u = ddir.appendingPathComponent(stem + "_DLC.csv")
                        if writeDLC(t, to: u) { report.files.append(u) }
                    }
                }
                tick(L("Pose", "姿态"))
            }
        }

        put(readme(plan, options: o, assays: assays), root.appendingPathComponent("README.txt"))
        if let data = manifest(plan, options: o) {
            let u = root.appendingPathComponent("export_manifest.json")
            if (try? data.write(to: u, options: .atomic)) != nil { report.files.append(u) }
        }
        tick(L("Finishing", "完成中"))
        return report
    }

    private static func recordingFolder(of v: VideoItem, plan: Plan) -> URL? {
        if let item = plan.items.first(where: { $0.recordingID == v.recording.id }) { return item.recordingFolder }
        return nil
    }

    /// Releases temporary objects per video on Apple platforms (large pose tracks).
    private static func autoreleasepoolIfAvailable(_ body: () -> Void) {
        #if canImport(ObjectiveC)
        autoreleasepool { body() }
        #else
        body()
        #endif
    }

    // MARK: Tables

    private static func qcTable(_ videos: [VideoItem]) -> String {
        var h = ["recording_id", "study", "animal_id", "blind_code", "sex", "group", "timepoint", "trial", "video",
                 "pose_model", "status", "failure", "fps", "duration_s", "frames", "mouse_detected_pct", "mouse_tracked_pct",
                 "recoverable_by_gap_filling_pct"]
        for k in Kp.allCases { h.append("\(k.exportName)_tracked_pct") }
        h += ["longest_lost_s", "long_gaps", "jump_frames_pct", "body_length_px", "body_length_cv", "frame_timing_cv",
              "qc_verdict", "decision", "exclusion_reason", "tasks", "qc_issues"]
        var out = Exporter.row(h)
        for v in videos {
            let r = v.recording
            let q = r.qc
            var fields = [String(r.id.uuidString.prefix(8)).lowercased(), v.study, v.animal, v.blindCode, v.sex, v.group,
                          r.timepoint, "\(r.trial)", v.blinded ? "" : r.originalName, v.poseModel.rawValue,
                          r.status.rawValue, r.failure ?? "",
                          f(q?.fps ?? r.fps, 2), f(q?.duration ?? r.duration, 2), q.map { "\($0.frames)" } ?? "",
                          f(q.map { $0.detection * 100 }, 1), f(q.map { $0.coreCoverage * 100 }, 1), f(q.map { $0.recoverable * 100 }, 1)]
            for k in Kp.allCases {
                let v: Double? = q.flatMap { k.rawValue < $0.filledCoverage.count ? $0.filledCoverage[k.rawValue] * 100 : nil }
                fields.append(f(v, 1))
            }
            fields += [f(q?.longestLost, 2), q.map { "\($0.longGaps)" } ?? "", f(q.map { $0.jumpRate * 100 }, 2),
                       f(q?.bodyLength, 1), f(q?.bodyLengthCV, 3), f(q?.timingCV, 3),
                       q?.verdict.rawValue ?? "", r.decision.rawValue, r.exclusionReason, v.tasks.joined(separator: ";"),
                       (q?.issues ?? []).map { $0.text.en }.joined(separator: " | ")]
            out += Exporter.row(fields)
        }
        return out
    }

    private static func behaviorSegments(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["event", "onset_s", "offset_s", "duration_s", "onset_after_injection_s",
                                           "auto_label", "final_label", "final_label_name", "edited", "counted", "info"])
        for r in rows {
            guard let d = r.result?.behavior else { continue }
            let idc = ids(r)
            for (i, e) in d.events.enumerated() {
                out += Exporter.row(idc + ["\(i + 1)", f(e.onset, 3), f(e.offset, 3), f(e.duration, 3), f(e.onset - d.origin, 3),
                                           e.auto, e.label, d.eventClass(e.label).label.en, e.edited ? "1" : "0",
                                           e.counted ? "1" : "0", e.info ?? ""])
            }
        }
        return out
    }

    private static func behaviorEthogram(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["behavior", "behavior_name", "start_s", "end_s", "duration_s", "start_after_injection_s"])
        for r in rows {
            guard let d = r.result?.behavior else { continue }
            let idc = ids(r)
            for tr in d.tracks {
                for iv in tr.intervals {
                    out += Exporter.row(idc + [tr.key, tr.label.en, f(iv.start, 3), f(iv.end, 3), f(iv.duration, 3), f(iv.start - d.origin, 3)])
                }
            }
        }
        return out
    }

    private static func behaviorBins(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["bin", "start_after_injection_s", "end_after_injection_s", "measure", "measure_name", "unit", "value"])
        for r in rows {
            guard let d = r.result?.behavior, d.binSize > 0 else { continue }
            let idc = ids(r)
            for series in d.bins {
                for (i, v) in series.values.enumerated() {
                    let a = Double(i) * d.binSize
                    out += Exporter.row(idc + ["\(i + 1)", f(a, 1), f(a + d.binSize, 1), series.key, series.label.en, series.unit, f(v, 4)])
                }
            }
        }
        return out
    }

    private static func tstBouts(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["event", "onset_s", "offset_s", "duration_s", "label", "in_scoring_window"])
        for r in rows {
            guard let d = r.result?.tst else { continue }
            let idc = ids(r)
            var events: [(Interval, String)] = d.bouts.map { ($0, "immobile") } + d.climbing.map { ($0, "tail_climbing") }
            events.sort { $0.0.start < $1.0.start }
            for (i, e) in events.enumerated() {
                let inWindow = e.0.end > d.window.start && e.0.start < d.window.end
                out += Exporter.row(idc + ["\(i + 1)", f(e.0.start, 3), f(e.0.end, 3), f(e.0.duration, 3), e.1, inWindow ? "1" : "0"])
            }
        }
        return out
    }

    private static func tstEthogram(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["behavior", "behavior_name", "start_s", "end_s", "duration_s", "start_after_injection_s"])
        for r in rows {
            guard let d = r.result?.tst else { continue }
            let idc = ids(r)
            for iv in d.bouts { out += Exporter.row(idc + ["immobile", "Immobility", f(iv.start, 3), f(iv.end, 3), f(iv.duration, 3), ""]) }
            for iv in d.climbing { out += Exporter.row(idc + ["tail_climbing", "Tail climbing", f(iv.start, 3), f(iv.end, 3), f(iv.duration, 3), ""]) }
        }
        return out
    }

    private static func tstPerMinute(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["minute", "immobility_s"])
        for r in rows {
            guard let d = r.result?.tst else { continue }
            let idc = ids(r)
            for (i, v) in d.perMinute.enumerated() { out += Exporter.row(idc + ["\(i + 1)", f(v, 2)]) }
        }
        return out
    }

    private static func cylinderContacts(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["event", "onset_s", "offset_s", "duration_s", "rear", "auto_label", "final_label", "edited", "counted"])
        for r in rows {
            guard let d = r.result?.cylinder else { continue }
            let idc = ids(r)
            for (i, e) in d.events.enumerated() {
                out += Exporter.row(idc + ["\(i + 1)", f(e.onset, 3), f(e.offset, 3), f(e.offset - e.onset, 3), "\(e.rear)",
                                           e.auto.rawValue, e.label.rawValue, e.edited ? "1" : "0", e.counted ? "1" : "0"])
            }
        }
        return out
    }

    private static func gaitStrides(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["paw", "start_s", "end_s", "stride_s", "stance_s", "swing_s", "duty", "stride_length", "speed", "unit"])
        for r in rows {
            guard let d = r.result?.gait else { continue }
            let idc = ids(r)
            for x in d.strides {
                out += Exporter.row(idc + [x.paw.code, f(x.start, 4), f(x.end, 4), f(x.end - x.start, 4), f(x.stance, 4), f(x.swing, 4),
                                           f(x.duty, 4), f(x.length, 4), f(x.speed, 3), d.unit])
            }
        }
        return out
    }

    private static func gaitFootprints(_ rows: [ExportRow]) -> String {
        var out = Exporter.row(idHeader + ["paw", "strike_s", "x_px", "y_px"])
        for r in rows {
            guard let d = r.result?.gait else { continue }
            let idc = ids(r)
            for x in d.footprints { out += Exporter.row(idc + [x.paw.code, f(x.t, 4), f(x.x, 2), f(x.y, 2)]) }
        }
        return out
    }

    /// The shared per-video summary writes `model,CylinderMousePoseV2`: name the model that was used.
    private static func namePoseModel(_ model: PoseModelID, in url: URL) {
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let old = "\nmodel," + kPoseModelName + ","
        guard text.contains(old) else { return }
        text = text.replacingOccurrences(of: old, with: "\nmodel," + model.rawValue + ",")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Methods text of a task: the first analysis' paragraph, plus a note when parameters differ.
    private static func methods(_ rows: [ExportRow], models: [PoseModelID]) -> String {
        guard let first = rows.first(where: { $0.result != nil }) ?? rows.first else { return "" }
        var t = Exporter.methods(first.session, result: first.result)
        // The shared paragraph names CylinderMousePoseV2; say which model(s) really tracked these videos.
        let used = PoseModelID.allCases.filter { models.contains($0) }
        if !used.isEmpty, used != [.visible] {
            let threshold = first.session.params.common.keypointThreshold
            let original = PoseModelID.visible.methodsSentence(threshold: threshold)
            let replacement = used.count == 1 ? used[0].methodsSentence(threshold: threshold) : used.map { m -> String in
                let n = models.filter { $0 == m }.count
                return m.methodsSentence(threshold: threshold)
                    .replacingOccurrences(of: "Pose estimation: ", with: "Pose estimation (\(n) of \(models.count) analyses): ")
            }.joined()
            t = t.replacingOccurrences(of: original, with: replacement)
        }
        let distinct = Set(rows.map { r -> String in
            var p = r.session.params
            p.keepPerAnimal(from: AssayParams.defaults(for: r.session.assay))
            return (try? String(decoding: JSONEncoder().encode(p), as: UTF8.self)) ?? ""
        })
        if distinct.count > 1 {
            t += "\nNote: \(distinct.count) different parameter sets were used across the \(rows.count) analyses of this export (see export_manifest.json for each analysis' parameters).\n"
        }
        return t
    }

    // MARK: Interoperability

    /// BORIS "aggregated events" table (TSV). Every event becomes a STATE event with start, stop and
    /// duration (a zero-length one a POINT event); Observation id = the analysis.
    private static func boris(_ rows: [ExportRow]) -> String {
        let header = ["Observation id", "Observation date", "Description", "Media file", "Total length", "FPS", "Subject",
                      "Behavior", "Behavioral category", "Modifiers", "Behavior type", "Start (s)", "Stop (s)", "Duration (s)",
                      "Comment start", "Comment stop"]
        func tsv(_ fields: [String]) -> String {
            fields.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t") + "\n"
        }
        let iso = ISO8601DateFormatter()
        var out = tsv(header)
        for r in rows {
            guard let res = r.result else { continue }
            let obs = fileStem(r)
            let subject = r.blinded ? r.blindCode : (r.animal.isEmpty ? r.session.subject : r.animal)
            let media = r.blinded ? "" : r.session.originalName
            let common = [obs, iso.string(from: r.recorded), r.session.assay.name.en, media,
                          f(r.session.duration, 3), f(r.session.fps, 3), subject]
            var events: [(String, String, Double, Double, String)] = []   // behavior, category, start, stop, comment
            if let d = res.behavior {
                for e in d.events where e.counted {
                    events.append((d.eventClass(e.label).label.en, r.session.assay.name.en, e.onset, e.offset, e.edited ? "edited by reviewer" : (e.info ?? "")))
                }
            } else if let d = res.tst {
                events += d.bouts.map { ("Immobility", "Tail suspension", $0.start, $0.end, "") }
                events += d.climbing.map { ("Tail climbing", "Tail suspension", $0.start, $0.end, "") }
            } else if let d = res.cylinder {
                for e in d.events where e.counted && e.label != .ignore {
                    events.append(("Forepaw contact (\(e.label.rawValue))", "Cylinder", e.onset, e.offset, "rear \(e.rear)"))
                }
            }
            events.sort { $0.2 < $1.2 }
            for e in events {
                let type = e.3 > e.2 ? "STATE" : "POINT"
                out += tsv(common + [e.0, e.1, "", type, f(e.2, 3), f(e.3, 3), f(max(0, e.3 - e.2), 3), e.4, ""])
            }
        }
        return out
    }

    /// One row per frame, 0/1 per behavior and a "background" column that is 1 when no behavior is
    /// scored (daart / DeepEthogram label layout). Only counted events / bouts are used.
    static func frameLabels(_ s: Session, result: AnalysisResult, track: PoseTrack) -> String? {
        var classes: [(String, [Interval])] = []
        if let d = result.behavior {
            var map: [String: [Interval]] = [:]
            var order: [String] = []
            for c in d.classes { order.append(c.key); map[c.key] = [] }
            for e in d.events where e.counted && e.label != EventClass.ignore.key {
                if map[e.label] == nil { order.append(e.label); map[e.label] = [] }
                map[e.label, default: []].append(Interval(start: e.onset, end: e.offset))
            }
            classes = order.map { ($0, map[$0] ?? []) }
        } else if let d = result.tst {
            classes = [("immobile", d.bouts), ("tail_climbing", d.climbing)]
        } else if let d = result.cylinder {
            classes = [("left_contact", d.leftContacts), ("right_contact", d.rightContacts)]
        } else {
            return nil
        }
        guard !classes.isEmpty else { return nil }
        var out = Exporter.row([""] + ["background"] + classes.map(\.0))
        let n = min(track.frameCount, track.times.count)
        // Walk every class's sorted intervals alongside the frames (linear time).
        let sorted = classes.map { $0.1.sorted { $0.start < $1.start } }
        var cursor = Array(repeating: 0, count: sorted.count)
        var chunk = ""
        chunk.reserveCapacity(64 * 1024)
        for i in 0..<n {
            let t = track.times[i]
            var flags = [String](repeating: "0", count: sorted.count)
            var any = false
            for c in 0..<sorted.count {
                let list = sorted[c]
                while cursor[c] < list.count && list[cursor[c]].end <= t { cursor[c] += 1 }
                var j = cursor[c]
                while j < list.count && list[j].start <= t {
                    if t < list[j].end { flags[c] = "1"; any = true; break }
                    j += 1
                }
            }
            chunk += "\(i),\(any ? "0" : "1")," + flags.joined(separator: ",") + "\n"
            if chunk.utf8.count > 60_000 { out += chunk; chunk = "" }
        }
        out += chunk
        return out
    }

    /// Keypoints in DeepLabCut's CSV layout: three header rows (scorer, bodyparts, coords) and one row
    /// per frame with x, y, likelihood per body part. Missing keypoints have empty x / y.
    static func writeDLC(_ t: PoseTrack, to url: URL) -> Bool {
        let scorer = "RodentLimb_\(t.modelName.isEmpty ? kPoseModelName : t.modelName)"
        var head1 = ["scorer"], head2 = ["bodyparts"], head3 = ["coords"]
        for k in Kp.allCases {
            head1 += [scorer, scorer, scorer]
            head2 += [k.exportName, k.exportName, k.exportName]
            head3 += ["x", "y", "likelihood"]
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            var chunk = [head1, head2, head3].map { $0.joined(separator: ",") }.joined(separator: "\n") + "\n"
            let n = t.frameCount
            for i in 0..<n {
                var r = ["\(i)"]
                for k in Kp.allCases {
                    let x = t.x[k.rawValue][i], y = t.y[k.rawValue][i]
                    if x >= 0 && y >= 0 {
                        r += [String(format: "%.3f", x), String(format: "%.3f", y)]
                    } else {
                        r += ["", ""]
                    }
                    r.append(String(format: "%.4f", t.c[k.rawValue][i]))
                }
                chunk += r.joined(separator: ",") + "\n"
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

    // MARK: README and manifest

    /// "CylinderMousePoseV2 (visible light)" or both models with their counts.
    private static func modelsText(_ plan: Plan) -> String {
        let models = plan.videos.map(\.poseModel)
        let used = PoseModelID.allCases.filter { models.contains($0) }
        if used.count <= 1 {
            let m = used.first ?? .visible
            return "\(m.rawValue) (\(m.shortTitle.en.lowercased()))"
        }
        return used.map { m in "\(m.rawValue) (\(m.shortTitle.en.lowercased()), \(models.filter { $0 == m }.count) videos)" }.joined(separator: ", ")
    }

    private static func readme(_ plan: Plan, options o: ExportOptions, assays: [Assay]) -> String {
        let df = ISO8601DateFormatter()
        var t = """
        RodentLimb export — \(plan.scopeText)
        Created \(df.string(from: Date())) by RodentLimb for Mac \(AppInfo.version), pose model \(modelsText(plan)).
        \(plan.items.count) analyses, \(plan.videos.count) videos.\(o.includeNotIncluded ? " Videos that were excluded or not yet reviewed are included and flagged in the `included` column (1 = included, 0 = excluded, pending = not reviewed)." : " Only videos included after QC are exported.")

        All tables are comma-separated, UTF-8, one header row (except the DeepLabCut pose files). Times are in seconds of the video
        (time 0 = first decoded frame); "after_injection" times are relative to the injection time set in the analysis parameters.
        Distances are in body lengths (BL, median nose–tail-base distance) unless a cm scale was calibrated.

        IDENTIFICATION COLUMNS (first columns of every combined table; join tables on analysis_id)
          analysis_id   first 8 characters of the analysis' identifier (also in export_manifest.json)
          study         study name (empty for videos outside a study)
          animal_id     animal ID (empty while the study is blinded)
          blind_code    random code shown while the study is blinded
          sex           male / female / empty
          group         combination of between-subject factor levels (empty while blinded)
          timepoint     within-subject level (e.g. Baseline, Day 7)
          trial         trial number of the animal at that timepoint
          video         original file name (empty while blinded)
          included      1 included, 0 excluded, pending = QC decision not made

        FILES

        """
        if o.qc { t += "qc_videos.csv — one row per video: pose model (CylinderMousePoseV2 = visible light; CylinderPose7_FP16_640 = the same network with half-precision weights; PalmReaderPose8_640_W8A16 = near-infrared dark box, which has no mouth keypoint, so mouth_tracked_pct is 0), tracking status, frame rate, share of frames with the mouse tracked (nose and tail base, after short-gap filling), per-keypoint tracked %, longest untracked stretch, implausible jumps, QC verdict, inclusion decision and exclusion reason, assigned tasks.\n\n" }
        if o.methods { t += "study_<name>_design.txt — design, animals and group sizes, randomisation, blinding, a-priori inclusion criteria and exclusions (ARRIVE 2.0).\n\n" }
        for a in assays {
            let code = a.code
            t += "\(code)_\(Exporter.safeName(a.name.en))/ — \(a.name.en)\n"
            if o.summary { t += "  \(code)_summary.csv — one row per analysis: design columns, QC, then every measure (column name = measure key [unit]). Ready for two-way / mixed ANOVA or linear mixed models with animal as random effect.\n" }
            if a.isBehavior {
                if o.segments { t += "  \(code)_segments.csv — behavior segments: every automatically detected event or bout (event number, onset_s, offset_s, duration_s, onset_after_injection_s, auto_label, final_label = after review, edited = 1 when changed by the reviewer, counted = inside the analysis window and not ignored, info).\n" }
                if o.ethogram { t += "  \(code)_ethogram.csv — behavior intervals per ethogram row (behavior key and name, start, end, duration).\n" }
                if o.timeBins { t += "  \(code)_time_bins.csv — time course: one row per analysis × bin × measure (bin edges relative to the injection).\n" }
            } else if a == .tailSuspension {
                if o.segments { t += "  \(code)_segments.csv — immobility bouts and tail-climbing episodes (in_scoring_window = overlaps the scored window, default 2–6 min).\n" }
                if o.ethogram { t += "  \(code)_ethogram.csv — the same as intervals per behavior.\n" }
                if o.details { t += "  \(code)_per_minute.csv — immobility seconds per minute.\n" }
            } else if a == .cylinder {
                if o.segments { t += "  \(code)_segments.csv — forepaw wall contacts (rear number, automatic and final label left/right/both/ignore, edited, counted).\n" }
            } else if a == .gait, o.details {
                t += "  \(code)_strides.csv — every stride of every paw (stance, swing, duty factor, stride length, speed).\n  \(code)_footprints.csv — foot-strike positions (video pixels).\n"
            }
            if o.boris && (a.isBehavior || a == .tailSuspension || a == .cylinder) {
                t += "  \(code)_boris_events.tsv — the same events as a BORIS aggregated-events table (one observation per analysis; STATE events with start/stop).\n"
            }
            if o.frameLabels && (a.isBehavior || a == .tailSuspension || a == .cylinder) {
                t += "  frame_labels/<animal>_..._labels.csv — one row per video frame: first column frame index, `background` = 1 when no behavior is scored, then 0/1 per behavior (DeepEthogram / daart label layout; counted events only).\n"
            }
            if o.methods { t += "  \(code)_methods.txt — methods paragraph with the parameter values and references.\n" }
            if o.perVideoFolders { t += "  per_video/<animal>_<id>/ — the single-analysis files of the iPhone app (summary, events / bouts, time bins, ethogram, methods).\n" }
            t += "\n"
        }
        if o.poseCSV { t += "pose/<animal>_..._pose.csv — frame-by-frame keypoints: frame, time_s, box_confidence, then x, y, confidence of L_fore_paw, L_hind_paw, R_fore_paw, R_hind_paw, tail_base, nose, mouth (video pixels, displayed orientation; empty x/y = not found).\n\n" }
        if o.poseDLC { t += "pose_dlc/<animal>_..._DLC.csv — the same keypoints in DeepLabCut's CSV layout (rows: scorer, bodyparts, coords; columns x, y, likelihood per body part), readable by DeepLabCut, SimBA, Keypoint-MoSeq (format 'deeplabcut') and pandas.read_csv(header=[0,1,2], index_col=0).\n\n" }
        t += "export_manifest.json — app and model versions, export options, and for every analysis: identifiers, video, parameters, calibration, reviewer edits count and analysis date.\n"
        return t
    }

    private struct ManifestAnalysis: Encodable {
        var analysis_id: String
        var recording_id: String
        var task: String
        var video: String
        var animal: String
        var timepoint: String
        var included: String
        var analyzed_at: Date?
        var result_version: Int?
        var parameters: AssayParams
        var calibration: Calibration
        var reviewer_edits: Int
        var pose_model: String
    }

    private struct Manifest: Encodable {
        var app = "RodentLimb for Mac"
        var app_version = AppInfo.version
        var model: String
        var created = Date()
        var scope: String
        var options: ExportOptions
        var analyses: [ManifestAnalysis]
    }

    private static func manifest(_ plan: Plan, options: ExportOptions) -> Data? {
        let models = PoseModelID.allCases.filter { m in plan.items.contains { $0.poseModel == m } }
        let m = Manifest(model: (models.isEmpty ? [PoseModelID.visible] : models).map(\.rawValue).joined(separator: "; "),
                         scope: plan.scopeText, options: options, analyses: plan.items.map { i in
            let r = i.row, s = r.session
            return ManifestAnalysis(analysis_id: s.id.uuidString.lowercased(), recording_id: s.recordingID?.uuidString.lowercased() ?? "",
                                    task: s.assay.code, video: r.blinded ? "" : s.originalName,
                                    animal: r.blinded ? r.blindCode : r.animal, timepoint: r.timepoint, included: r.included,
                                    analyzed_at: r.result?.analyzedAt, result_version: r.result?.version,
                                    parameters: s.params, calibration: s.calibration,
                                    reviewer_edits: s.overrides.count + (s.eventOverrides?.count ?? 0),
                                    pose_model: i.poseModel.rawValue)
        })
        let e = Coders.encoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(m)
    }
}
