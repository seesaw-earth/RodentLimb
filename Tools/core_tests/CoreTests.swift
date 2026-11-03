// CoreTests.swift — runtime tests of the iPhone data layer (real SessionStore, Tasks, TaskStats, TaskExport,
// LibrarySafety, RecordingSidecar, ExportFixes) on Linux with stubbed UIKit/Combine symbols.
import Foundation

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if cond() { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg) (line \(line))") }
}

/// The Mac app's VideoSource decoder (fields as in macOS/RodentLimbMac/Core/VideoSource.swift).
struct MacVideoSource: Decodable {
    enum Mode: String, Decodable { case referenced, copied }
    var mode: Mode
    var path: String
    var fileName: String
    var size: Int64
    var fingerprint: String
    var poseModel: PoseModelID?
    init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case mode, path, fileName, size, fingerprint, poseModel }
        let c = try decoder.container(keyedBy: K.self)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .copied
        path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? ""
        size = (try? c.decodeIfPresent(Int64.self, forKey: .size)) ?? 0
        fingerprint = (try? c.decodeIfPresent(String.self, forKey: .fingerprint)) ?? ""
        poseModel = (try? c.decodeIfPresent(PoseModelID.self, forKey: .poseModel)) ?? nil
    }
}

func dummyVideo(_ name: String, bytes: Int = 4096, seed: UInt8 = 1) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let u = dir.appendingPathComponent(name)
    var d = Data(count: bytes)
    for i in 0..<bytes { d[i] = UInt8((i * 31 + Int(seed)) & 0xFF) }
    try? d.write(to: u)
    return u
}

/// A mouse walking left to right at body-length speed, every keypoint tracked.
func syntheticTrack(model: String, seconds: Double = 20, fps: Double = 30, wiggle: Double = 0) -> PoseTrack {
    var t = PoseTrack(width: 640, height: 480, fps: fps, duration: seconds, modelName: model, modelVersion: "test")
    let n = Int(seconds * fps)
    for i in 0..<n {
        let time = Double(i) / fps
        t.times.append(time)
        t.boxConfidence.append(0.9)
        let cx = 100 + 10 * time, cy = 240.0
        let phase = sin(2 * .pi * 3 * time)
        let pts: [(Double, Double)] = [
            (cx + 30 + 6 * phase, cy - 20), (cx + 30 - 6 * phase, cy + 20),   // lf, rf
            (cx - 30 - 6 * phase, cy - 22), (cx - 30 + 6 * phase, cy + 22),   // lh, rh
            (cx - 55, cy + wiggle * phase), (cx + 60, cy), (cx + 52, cy),     // tail, nose, mouth
        ]
        for k in 0..<7 {
            t.x[k].append(Float(pts[k].0)); t.y[k].append(Float(pts[k].1)); t.c[k].append(0.95)
        }
    }
    t.timeOffset = 0
    return t
}

@MainActor
func waitUntil(_ seconds: Double = 10, _ cond: () -> Bool) async {
    let end = Date().addingTimeInterval(seconds)
    while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
}

@MainActor
func run() async {
    let fm = FileManager.default
    // A throw-away library (never the user's Documents/RodentLimb).
    let base = fm.temporaryDirectory.appendingPathComponent("rl-core-tests-\(UUID().uuidString.prefix(8))/RodentLimb")
    try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base.deletingLastPathComponent()) }
    print("Library:", base.path)

    print("Tasks")
    var store = SessionStore(base: base)
    await store.waitUntilLoaded()
    check(store.isLoaded, "library opened (off the main thread)")
    check(store.tasks.isEmpty, "empty library has no task")
    let t = store.createTask(name: "Gait — SNI cohort 2", assay: .gait, groups: ["Control", "Treatment", " ", "Control"],
                             timepoints: ["Baseline", "Day 7"], notes: "note")
    check(store.tasks == [t], "task listed")
    check(store.taskName(t) == "Gait — SNI cohort 2", "single-paradigm task named after the study")
    let e0 = store.experiment(t.experimentID)!
    check(e0.factors.count == 1 && e0.factors[0].name == "Group" && e0.factors[0].levels == ["Control", "Treatment"], "groups = one factor 'Group', trimmed, unique")
    check(e0.plannedAssays == [.gait], "plannedAssays == [assay]")
    check(store.groupChoices(e0) == ["Control", "Treatment"], "group choices")

    print("Import")
    let v1 = dummyVideo("M1_Baseline.mp4", seed: 1)
    let fp1 = try! VideoFingerprint.make(v1)
    let r1 = try! await store.importVideo(from: v1, move: true, task: t, animalCode: "M1", group: "Control", timepoint: "Baseline",
                                          trial: 1, notes: "", model: .nearInfrared, fingerprint: fp1)
    check(store.sessions(in: t).count == 1, "session created at import")
    await waitUntil(3) { fm.fileExists(atPath: store.recordingFolder(r1.id).appendingPathComponent("recording.json").path) }
    check(fm.fileExists(atPath: store.recordingFolder(r1.id).appendingPathComponent("recording.json").path), "each import is written at once")
    check(store.sessions(of: r1.id).first?.assay == .gait, "session has the task's paradigm")
    check(store.poseModel(r1.id) == .nearInfrared, "model recorded in sidecar")
    check(store.knownFingerprints.contains(fp1.duplicateKey), "fingerprint known (duplicates detected)")
    let e1 = store.experiment(t.experimentID)!
    let a1 = e1.animal(code: "M1")!
    check(e1.groupLabel(a1) == "Control", "new animal allocated to chosen group")
    let r2 = try! await store.importVideo(from: dummyVideo("Treatment/M2.mp4".replacingOccurrences(of: "/", with: "_"), seed: 2), move: true, task: t,
                                          animalCode: "M2", group: "Treatment", timepoint: "Baseline", trial: 1, notes: "", model: .visibleFP16, fingerprint: nil)
    let r3 = try! await store.importVideo(from: dummyVideo("M1_D7.mp4", seed: 3), move: true, task: t, animalCode: "m1", group: "Treatment",
                                          timepoint: "Day 7", trial: 2, notes: "", model: .visibleFP16, fingerprint: nil)
    let e2 = store.experiment(t.experimentID)!
    check(e2.animals.count == 2, "existing animal matched case-insensitively")
    check(e2.groupLabel(e2.animal(code: "M1")!) == "Control", "existing animal keeps its group")
    check(store.recording(r3.id)?.trial == 2, "trial stored")
    let tree = store.taskTree(t)
    check(tree.map(\.name) == ["Control", "Treatment"], "tree groups in design order")
    check(tree.first?.animals.first?.sessions.count == 2, "M1 has two sessions")
    let m1sessions = tree.first!.animals.first!.sessions.compactMap { store.recording(for: $0)?.timepoint }
    check(m1sessions == ["Baseline", "Day 7"], "sessions ordered by timepoint")
    var c = store.counts(t)
    check(c.sessions == 3 && c.processing == 3, "counts: 3 sessions, 3 processing (\(c))")
    check(store.taskCounts()[t] == c, "taskCounts agrees")
    store.flush()
    await waitUntil(3) { fm.fileExists(atPath: store.recordingFolder(r1.id).appendingPathComponent("source.json").path) }
    let mac = try? JSONDecoder().decode(MacVideoSource.self, from: (try? Data(contentsOf: store.recordingFolder(r1.id).appendingPathComponent("source.json"))) ?? Data())
    check(mac?.poseModel == .nearInfrared && mac?.mode == .copied && mac?.fingerprint == fp1.fingerprint, "source.json readable by the Mac's VideoSource")

    print("Processing, QC, analysis")
    for (r, m) in [(r1, "PalmReaderPose8_640_W8A16"), (r2, "CylinderPose7_FP16_640"), (r3, "CylinderPose7_FP16_640")] {
        store.updateRecording(r.id) { $0.status = .processing }
        try! await store.finishProcessing(r.id, track: syntheticTrack(model: m), skeleton: false)
    }
    await waitUntil(20) { store.sessions(in: t).allSatisfy { !$0.summary.isEmpty } }
    let states = store.sessions(in: t).map { store.state(of: $0) }
    print("   states:", states, store.recordings.map { $0.qc?.verdict.rawValue ?? "-" })
    check(store.sessions(in: t).allSatisfy { $0.hasPose }, "sessions have pose")
    check(store.recordings.allSatisfy { $0.qc != nil }, "QC computed")
    check(store.poseModel(r2.id) == .visibleFP16, "model from track")
    // Force a review state and decisions.
    store.updateRecording(r3.id) { $0.decision = .pending }
    check(store.needsReview(store.recording(r3.id)!), "pending video with QC needs review")
    check(store.counts(t).needsReview == 1, "needs review counted")
    store.setDecision(r3.id, .included)
    store.setDecision(r2.id, .excluded, reason: "Protocol deviation")
    check(store.state(of: store.sessions(of: r2.id)[0]) == .excluded, "excluded state")
    let inc = store.inclusionCounts(t)
    check(inc.included == 2 && inc.leftOut == 1, "inclusion counts \(inc)")

    print("Results")
    let results = await store.loadResults(store.sessions(in: t).map(\.id))
    check(results.count == 3, "results on disk / in memory (\(results.count))")
    let measures = store.measureOptions(t, results: results)
    check(!measures.isEmpty && measures.first?.highlight == true, "measures, highlighted first (\(measures.count))")
    let key = measures.first { m in results.values.contains { $0.metric(m.key)?.value?.isFinite == true } }?.key ?? ""
    let gs = store.groupSummaries(t, metric: key, timepoint: "Baseline", results: results)
    print("   metric", key, gs.map { "\($0.name) n=\($0.n) mean=\($0.mean)" })
    check(gs.map(\.name) == ["Control"], "excluded Treatment animal left out; Control at Baseline")
    check(gs.first?.n == 1, "n = animals")
    let course = store.timepointCourse(t, metric: key, results: results)
    check(course.count == 2 && course.allSatisfy { $0.group == "Control" }, "course over 2 timepoints (\(course.count))")
    check(SessionStore.jitter(0) == -0.5 && abs(SessionStore.jitter(1) - 0.118) < 0.01, "deterministic jitter")

    print("Export")
    let urls = await TaskExport.files(store: store, task: t)
    let names = urls.map(\.lastPathComponent)
    print("   files:", names)
    check(names.contains { $0.hasSuffix("_qc.csv") } && names.contains("README.txt") && names.contains("manifest.json"), "task export files")
    if let qcURL = urls.first(where: { $0.lastPathComponent.hasSuffix("_qc.csv") }), let txt = try? String(contentsOf: qcURL, encoding: .utf8) {
        check(txt.contains("PalmReaderPose8_640_W8A16") && txt.contains("CylinderPose7_FP16_640"), "QC table names the models used")
        check(txt.contains("Protocol deviation"), "exclusion reason exported")
    } else { check(false, "qc.csv readable") }
    if let mURL = urls.first(where: { $0.lastPathComponent.hasSuffix("_methods.txt") }), let txt = try? String(contentsOf: mURL, encoding: .utf8) {
        check(txt.contains("PalmReaderPose8") && txt.contains("(2 of 3 analyses)") && !txt.contains("Pose estimation: CylinderMousePoseV2"), "methods name the models")
        check(txt.contains("Study design"), "methods include the design")
    } else { check(false, "methods readable") }
    // Single-session export fix.
    let s1 = store.sessions(of: r1.id)[0]
    let files = Exporter.sessionFiles(s1, result: results[s1.id]!, track: nil, skeletonURL: nil, includePose: false, includeVideo: false)
    ExportFixes.apply(to: files, model: .nearInfrared, threshold: s1.params.common.keypointThreshold)
    let summary = (try? String(contentsOf: files.first { $0.lastPathComponent.hasSuffix("_summary.csv") }!, encoding: .utf8)) ?? ""
    check(summary.contains("\nmodel,PalmReaderPose8_640_W8A16,") && summary.hasPrefix("\u{FEFF}") && !summary.dropFirst().hasPrefix("\u{FEFF}"), "summary names model, one BOM")
    let meth = (try? String(contentsOf: files.first { $0.lastPathComponent.hasSuffix("_methods.txt") }!, encoding: .utf8)) ?? ""
    check(meth.contains("PalmReaderPose8 (Ultralytics YOLO-pose"), "session methods name the model")

    print("Recently Deleted")
    let sid = store.sessions(of: r3.id)[0].id
    let entry = store.delete([sid])
    check(entry != nil && store.session(sid) == nil, "session removed from memory")
    var listed = await store.recentlyDeleted()
    check(listed.count == 1 && listed[0].sessionIDs == [sid], "entry in Recently Deleted")
    check(!fm.fileExists(atPath: store.folder(sid).path), "folder moved out of Sessions/")
    let msg = await store.restoreDeleted(entry!)
    check(store.session(sid) != nil && store.sessions(in: t).count == 3, "restored (\(msg))")
    // Delete task, keep its videos: no QC re-run with the default criteria, decisions come back.
    store.updateRecording(r3.id) { $0.decision = .pending }
    let del = store.deleteTask(t, keepVideos: true)
    check(store.tasks.isEmpty && store.unassignedRecordings.count == 3, "task deleted, videos kept outside")
    await waitUntil(1) { false }
    check(store.recording(r3.id)?.decision == .pending, "leaving every task does not re-run QC (pending stays pending)")
    await store.undoDeleteTask(del)
    await waitUntil(1) { false }
    check(store.tasks == [t] && store.sessions(in: t).count == 3 && store.unassignedRecordings.isEmpty, "task restored with its videos")
    check(store.recording(r2.id)?.decision == .excluded && store.recording(r2.id)?.exclusionReason == "Protocol deviation", "decision and reason restored")
    check(store.recording(r3.id)?.decision == .pending, "re-joining re-checks QC without including behind the reviewer's back")
    store.setDecision(r3.id, .included)
    let vEntry = store.deleteRecordings([r2.id])
    check(store.recording(r2.id) == nil && store.sessions(in: t).count == 2, "video and its session deleted")
    _ = await store.restoreDeleted(vEntry!)
    check(store.recording(r2.id) != nil && store.sessions(in: t).count == 3 && store.poseModel(r2.id) == .visibleFP16, "video restored with sidecar")
    listed = await store.recentlyDeleted()
    check(listed.isEmpty, "Recently Deleted empty after restores")

    print("Move to Task, remove, parameters")
    let free = try! await store.importVideo(from: dummyVideo("Loose.mov", seed: 9), move: true, task: nil, animalCode: "M9", group: "Treatment",
                                            timepoint: "", notes: "", model: .visibleFP16, fingerprint: nil)
    store.assign([.cylinder], to: free.id)
    check(store.unassignedRecordings.map(\.id) == [free.id], "video outside a task listed")
    store.update(store.sessions(in: t)[0].id) { $0.params.gait.minBodySpeed = 0.77 }
    let mv = store.moveToTask([free.id], task: t)
    let moved = store.sessions(of: free.id).first { $0.assay == .gait }
    check(moved != nil && store.task(for: moved!) == t, "session for the task created")
    check(store.experiment(t.experimentID)!.groupLabel(store.experiment(t.experimentID)!.animal(code: "M9")!) == "Treatment", "free-text group becomes the animal's group")
    check(store.tasks(of: t.experimentID) == [t] && store.sessions(of: free.id).map(\.assay) == [.gait], "no phantom task: the other paradigm's session went to Recently Deleted")
    check(mv.removedEntry != nil && mv.createdSessions.count == 1 && mv.previousStudy[free.id] == .some(nil), "move record")
    let peers = store.taskPeers(of: moved!.id)
    check(peers.count == 3 && peers.allSatisfy { $0.assay == .gait }, "peers = same task only")
    let n = store.applyToTask(from: store.sessions(in: t)[0].id, params: store.sessions(in: t)[0].params)
    check(n == 3 && store.sessions(in: t).allSatisfy { $0.params.gait.minBodySpeed == 0.77 }, "apply to task")
    check(ParameterPresets.presets(for: .gait).count >= 2, "presets available")
    await store.undoMove(mv)
    check(store.recording(free.id)?.experimentID == nil && store.sessions(of: free.id).map(\.assay) == [.cylinder], "undo move: back outside with its cylinder session")
    check(store.sessions(in: t).count == 3, "undo move: task as before")
    // Between tasks of two studies: the group travels with the video.
    let t2 = store.createTask(name: "Second cohort", assay: .gait, groups: ["Sham", "Lesion"], timepoints: [], notes: "")
    let mv2 = store.moveToTask([r2.id], task: t2, from: t)
    let e2b = store.experiment(t2.experimentID)!
    check(store.recording(r2.id)?.experimentID == t2.experimentID && e2b.groupLabel(e2b.animal(code: "M2")!) == "Treatment", "group carried into the other task")
    check(store.sessions(in: t).count == 2 && store.sessions(in: t2).count == 1 && store.tasks(of: t.experimentID) == [t], "session moved, no phantom task")
    check(store.recording(r2.id)?.decision == .excluded, "joining re-checks QC but keeps the decision")
    await store.undoMove(mv2)
    check(store.recording(r2.id)?.experimentID == t.experimentID && store.sessions(in: t).count == 3 && store.sessions(in: t2).isEmpty, "undo: back in its task")
    // Remove from task: a video left without sessions leaves the study, with ID and group as text.
    let rm = store.removeFromTask([r3.id], task: t)
    check(store.recording(r3.id)?.experimentID == nil && store.recording(r3.id)?.subject == "M1" && store.recording(r3.id)?.group == "Control", "removed: outside, ID and group kept as text")
    await store.undoMove(rm)
    check(store.recording(r3.id)?.experimentID == t.experimentID && store.sessions(in: t).count == 3, "undo remove")
    // One change of the study for the new animals of an import (first group wins).
    store.prepareAnimals([(code: "A1", group: "Lesion"), (code: "a1", group: "Sham"), (code: "A2", group: "")], in: t2.experimentID)
    let e2c = store.experiment(t2.experimentID)!
    check(e2c.animals.filter { $0.code.lowercased() == "a1" }.count == 1 && e2c.groupLabel(e2c.animal(code: "A1")!) == "Lesion"
          && e2c.groupLabel(e2c.animal(code: "A2")!).isEmpty, "batch animals, first group wins")

    print("Backups")
    store.backup(MetadataBackup.Reason.manual)
    let bks = await store.backups()
    check(bks.contains { $0.reason == "manual" }, "manual backup listed")
    store.editTask(t.experimentID) { $0.name = "Renamed" }
    let rmsg = await store.restoreBackup(bks.first { $0.reason == "manual" }!.url)
    check(store.experiment(t.experimentID)?.name == "Gait — SNI cohort 2", "backup restored name (\(rmsg))")

    print("Reload and legacy studies")
    store.flush()
    await waitUntil(2) { false }
    // A 1.3 study with two planned paradigms and a pending planned video.
    var legacy = Experiment(name: "Old study")
    legacy.plannedAssays = [.tailSuspension, .grooming]
    var oldRec = Recording(videoFile: "video.mov", originalName: "old.mov")
    oldRec.experimentID = legacy.id
    oldRec.plannedAssays = [.tailSuspension]
    let enc = Coders.encoder()
    try! enc.encode(legacy).write(to: store.experimentsRoot.appendingPathComponent(legacy.id.uuidString + ".json"))
    let oldDir = store.recordingFolder(oldRec.id)
    try! fm.createDirectory(at: oldDir, withIntermediateDirectories: true)
    try! enc.encode(oldRec).write(to: oldDir.appendingPathComponent("recording.json"))
    try! Data([1, 2, 3]).write(to: oldDir.appendingPathComponent("video.mov"))
    var noTask = Experiment(name: "Empty study")
    noTask.createdAt = Date(timeIntervalSince1970: 0)
    try! enc.encode(noTask).write(to: store.experimentsRoot.appendingPathComponent(noTask.id.uuidString + ".json"))
    var noTaskRec = Recording(videoFile: "video.mov", originalName: "nt.mov")
    noTaskRec.experimentID = noTask.id
    let ntDir = store.recordingFolder(noTaskRec.id)
    try! fm.createDirectory(at: ntDir, withIntermediateDirectories: true)
    try! enc.encode(noTaskRec).write(to: ntDir.appendingPathComponent("recording.json"))
    // An import interrupted by a crash: the video copied, recording.json never written.
    let orphanID = UUID()
    let orphanDir = store.recordingFolder(orphanID)
    try! fm.createDirectory(at: orphanDir, withIntermediateDirectories: true)
    try! Data([7, 7, 7]).write(to: orphanDir.appendingPathComponent("video.mp4"))
    store = SessionStore(base: base)
    await store.waitUntilLoaded()
    await waitUntil(2) { !fm.fileExists(atPath: orphanDir.path) }
    check(!fm.fileExists(atPath: orphanDir.path), "unfinished import moved out of Recordings/")
    let orphanEntry = await store.recentlyDeleted()
    check(orphanEntry.count == 1 && orphanEntry[0].recordingIDs == [orphanID], "unfinished import in Recently Deleted")
    _ = await store.restoreDeleted(orphanEntry[0].id)
    check(store.recording(orphanID)?.status == .queued && store.unassignedRecordings.contains { $0.id == orphanID }, "unfinished import restored as a video to track")
    check(store.tasks.contains(t), "task survives reload")
    check(store.sessions(in: t).count == 3, "sessions survive reload (\(store.sessions(in: t).count))")
    check(store.poseModel(r1.id) == .nearInfrared, "sidecar survives reload")
    let legacyTasks = store.tasks(of: legacy.id)
    check(legacyTasks.map(\.assay) == [.tailSuspension, .grooming], "legacy study = one task per paradigm")
    check(store.taskName(legacyTasks[0]) == "Old study · " + Assay.tailSuspension.name.text, "legacy task name")
    let onePass = store.taskNames(store.tasks)
    check(store.tasks.allSatisfy { onePass[$0] == store.taskName($0) }, "taskNames (one pass) == taskName")
    check(store.sessions(in: legacyTasks[0]).count == 1, "planned 1.3 video got its session at launch")
    check(store.recording(oldRec.id)?.plannedAssays.isEmpty == true, "planned list cleared")
    check(store.studiesWithoutTask.map(\.id) == [noTask.id], "study without paradigm listed separately")
    store.setParadigm(.seizure, for: noTask.id)
    check(store.tasks(of: noTask.id).map(\.assay) == [.seizure], "choosing a paradigm makes it a task")
    check(store.sessions(in: TaskRef(experimentID: noTask.id, assay: .seizure)).count == 1, "its videos get sessions")
    // Within one study (1.3, several paradigms): the source task's session goes, the target's is made.
    let tst = TaskRef(experimentID: legacy.id, assay: .tailSuspension), groom = TaskRef(experimentID: legacy.id, assay: .grooming)
    let mv3 = store.moveToTask([oldRec.id], task: groom, from: tst)
    check(store.sessions(of: oldRec.id).map(\.assay) == [.grooming] && mv3.removedEntry != nil, "moved between paradigms of one study")
    await store.undoMove(mv3)
    check(store.sessions(of: oldRec.id).map(\.assay) == [.tailSuspension], "undo within one study")
    // Deleting one paradigm of a multi-paradigm study: its sessions go, the paradigm leaves the plan; Undo.
    let plan = store.deletionPlan(tst)
    check(!plan.wholeStudy && plan.sessions == 1, "deletion plan: only this paradigm")
    let d2 = store.deleteTask(tst, keepVideos: true)
    check(store.tasks(of: legacy.id).map(\.assay) == [.grooming] && store.recording(oldRec.id)?.experimentID == nil, "paradigm removed, video left the study")
    await store.undoDeleteTask(d2)
    check(store.tasks(of: legacy.id).map(\.assay) == [.tailSuspension, .grooming] && store.sessions(in: tst).count == 1, "undo restores paradigm and session")

    print("Lookups")
    for s in store.sessions { if store.session(s.id)?.id != s.id { check(false, "session lookup") } }
    for r in store.recordings { if store.recording(r.id)?.id != r.id { check(false, "recording lookup") } }
    check(store.session(UUID()) == nil && store.recording(UUID()) == nil && store.experiment(UUID()) == nil, "misses return nil")

    print("Naming")
    let sug = ImportNaming.suggest(stem: "WT-03_Day 7_T2", folders: ["Control"], pattern: NamePattern(), animals: ["WT-03"], timepoints: ["Day 7", "Day 28"])
    check(sug.animal == "WT-03" && sug.timepoint == "Day 7" && sug.trial == 2, "animal/timepoint/trial from name")
    check(ImportNaming.group(stem: "M4_KO-Drug", groups: ["KO", "KO-Drug"]) == "KO-Drug", "longest group match")
    check(ImportNaming.group(stem: "M4", folders: ["Treatment"], groups: ["Control", "Treatment"]) == "Treatment", "group from folder")

    print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
    try? fm.removeItem(at: base.deletingLastPathComponent())
    exit(failures == 0 ? 0 : 1)
}

@main struct Main {
    static func main() async { await run() }
}
