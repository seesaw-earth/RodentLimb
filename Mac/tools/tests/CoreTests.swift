// CoreTests.swift — command-line tests of the Mac app's Foundation layer (no Xcode needed):
//   • PoseCheckpoint: rows round-trip bit-exactly; a run cut in the middle of a line continues
//     after the last complete row and gives the same track as an uninterrupted run.
//   • BatchEngine with a simulated pose runner: a batch of videos with a permanently broken file,
//     a file that fails once (retried from its checkpoint), a pause in the middle, an offline video,
//     and recovery from the crash journal (a video that "crashed" twice is set aside).
//   • ImportNaming: animal / timepoint / trial from file and folder names.
//   • Tasks: create, add videos with groups (sessions at once), move in / out, legacy studies,
//     relaunch, delete.
// Run: sh tools/run_core_tests.sh

import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if ok { print("  ok    \(what)") } else { failures += 1; print("  FAIL  \(what)  (\(file.split(separator: "/").last ?? ""):\(line))") }
}

func tempDir(_ name: String) -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("rl-tests-\(name)-\(UUID().uuidString.prefix(6))", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

// MARK: - Simulated runner

/// Mimics Engine/PoseRunner: writes every frame to the checkpoint, honours stop requests, and can
/// fail at a given frame (once, or every time).
final class SimRunner: VideoPoseRunning {
    var modelName: String { kPoseModelName }
    var modelVersion: String { "sim-1" }
    /// file name → (frame, permanent)
    static var failures: [String: (Int, Bool)] = [:]
    static var failedOnce = Set<String>()
    static let lock = NSLock()
    static var delayPerFrame: UInt32 = 200   // µs
    /// Model each job asked for (file name → model).
    static var modelsUsed: [String: PoseModelID] = [:]

    func run(_ job: PoseJob, control: ProcessingControl, progress: @escaping (RunProgress) -> Void) throws -> PoseTrack {
        let fm = FileManager.default
        guard fm.fileExists(atPath: job.videoURL.path) else { throw PoseRunError.videoMissing }
        let frames = 240
        let fp = try VideoFingerprint.make(job.videoURL)
        SimRunner.lock.lock(); SimRunner.modelsUsed[job.videoURL.lastPathComponent] = job.model; SimRunner.lock.unlock()
        let fresh = PoseCheckpointManifest(videoSize: fp.size, videoModified: fp.modified, videoFingerprint: fp.fingerprint,
                                           modelName: job.model.rawValue, modelVersion: modelVersion, boxThreshold: job.boxThreshold,
                                           width: 640, height: 480, fps: 30, duration: Double(frames) / 30)
        let resume = try PoseCheckpoint.prepare(folder: job.checkpointFolder, fresh: fresh)
        let writer = try PoseCheckpointWriter(folder: job.checkpointFolder, resume: resume)
        var rows = resume.rows
        let start = rows.count
        if rows.isEmpty { try writer.setFirstPTS(0) }
        let name = job.videoURL.lastPathComponent
        for i in start..<frames {
            if let r = control.stopReason { writer.suspend(); throw PoseRunError.stopped(r) }
            SimRunner.lock.lock()
            let f = SimRunner.failures[name]
            var fail = false
            if let f, i == f.0 {
                if f.1 { fail = true } else if !SimRunner.failedOnce.contains(name) { SimRunner.failedOnce.insert(name); fail = true }
            }
            SimRunner.lock.unlock()
            if fail { writer.suspend(); throw f!.1 ? PoseRunError.noFrames : PoseRunError.readerFailed("simulated decoder hiccup") }
            let t = Double(i) / 30
            var row = PoseRow.missing(frame: i, pts: t)
            row.box = 0.9
            for k in 0..<PoseRow.keypoints {
                row.x[k] = Float(100 + Double(k) * 10 + 20 * sin(t + Double(k)))
                row.y[k] = Float(200 + 30 * cos(t * 1.3 + Double(k)))
                row.c[k] = 0.8
            }
            try writer.append(row)
            rows.append(row)
            if i % 20 == 0 {
                progress(RunProgress(phase: .tracking, framesDone: i + 1, framesTotal: frames, resumedFrames: start,
                                     mediaTime: t, duration: Double(frames) / 30, preview: nil))
            }
            usleep(SimRunner.delayPerFrame)
        }
        try writer.closeSegment()
        var track = PoseCheckpoint.track(rows: rows, manifest: writer.manifest)
        if job.model == .nearInfrared {
            // Like the real decoder: this model has no mouth keypoint.
            for i in 0..<track.c[Kp.mouth.rawValue].count { track.x[Kp.mouth.rawValue][i] = -1; track.y[Kp.mouth.rawValue][i] = -1; track.c[Kp.mouth.rawValue][i] = 0 }
        }
        return track
    }
}

// MARK: - Tests

func testCheckpoint() throws {
    print("PoseCheckpoint")
    let dir = tempDir("cp")
    let m = PoseCheckpointManifest(videoSize: 1000, videoModified: 1, videoFingerprint: "abc", modelName: kPoseModelName,
                                   modelVersion: "1", boxThreshold: 0.25, width: 640, height: 480, fps: 30, duration: 200)
    var all: [PoseRow] = []
    for i in 0..<5000 {
        var r = PoseRow.missing(frame: i, pts: 1.0 / 3.0 + Double(i) / 29.97)
        if i % 7 != 0 {
            r.box = Float(i % 100) / 100 + 0.001
            for k in 0..<PoseRow.keypoints { r.x[k] = Float(i) * 0.137 + Float(k) / 3; r.y[k] = Float(k) * 1.0001 + 1 / 3; r.c[k] = 0.3333333 }
        }
        all.append(r)
    }
    // First run: 3100 rows, then "crash" with a half-written line.
    var resume = try PoseCheckpoint.prepare(folder: dir, fresh: m)
    check(resume.isFresh, "new checkpoint starts empty")
    var w: PoseCheckpointWriter? = try PoseCheckpointWriter(folder: dir, resume: resume)
    try w?.setFirstPTS(all[0].pts)
    for r in all.prefix(3100) { try w?.append(r) }
    try w?.flush(sync: true)
    w = nil
    let partial = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".partial") }
    check(partial.count == 1, "one partial segment while running")
    if let p = partial.first {
        let h = try FileHandle(forWritingTo: dir.appendingPathComponent(p))
        try h.seekToEnd()
        try h.write(contentsOf: Data("3100,103.4,0.5,1.0,2".utf8))   // torn line
        try h.close()
    }
    check(PoseCheckpoint.savedFrames(folder: dir) == 3100, "saved-frame count ignores the torn line")
    // Second run continues.
    var m2 = m
    m2.startedAt = Date()
    resume = try PoseCheckpoint.prepare(folder: dir, fresh: m2)
    check(resume.rows.count == 3100, "resume finds 3100 complete rows (got \(resume.rows.count))")
    check(resume.lastPTS == all[3099].pts, "resume continues after the last complete frame")
    let w2 = try PoseCheckpointWriter(folder: dir, resume: resume)
    var rows = resume.rows
    for r in all.dropFirst(3100) { try w2.append(r); rows.append(r) }
    try w2.closeSegment()
    let reread = try PoseCheckpoint.load(folder: dir, manifest: PoseCheckpointManifest.load(dir))
    check(reread.rows == all, "rows read back bit-identical after interruption (\(reread.rows.count) rows)")
    let t = PoseCheckpoint.track(rows: rows, manifest: w2.manifest)
    check(t.frameCount == 5000 && t.times.first == 0 && abs((t.timeOffset ?? 0) - all[0].pts) < 1e-12, "pose track rebuilt with time zero at the first frame")
    check(t.x[3][4999] == all[4999].x[3] && t.c[0][7] == 0 && t.x[0][7] == -1, "keypoints and missing values preserved")
    // pose.bin round trip of the rebuilt track
    let bin = try PoseStorage.encode(t)
    let back = try PoseStorage.decode(bin)
    check(back.x == t.x && back.times == t.times, "pose.bin round trip (iPhone format)")
    // A different video discards the checkpoint.
    var other = m
    other.videoFingerprint = "zzz"
    let r3 = try PoseCheckpoint.prepare(folder: dir, fresh: other)
    check(r3.isFresh, "a different video file starts a new checkpoint")
}

@MainActor
func waitIdle(_ e: BatchEngine, timeout: Double = 60) async {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        try? await Task.sleep(nanoseconds: 50_000_000)
        if e.jobs.isEmpty && (e.state != .running) { return }
    }
    print("  (timeout waiting for the batch)")
}

@MainActor
func testBatch() async throws {
    print("BatchEngine")
    let lib = tempDir("lib")
    let videos = tempDir("videos")
    var items: [SessionStore.ImportItem] = []
    for i in 1...6 {
        let u = videos.appendingPathComponent("M\(i)_Day7.mp4")
        try Data((0..<(4096 + i)).map { UInt8(truncatingIfNeeded: $0 &* (i + 1)) }).write(to: u)
        items.append(.init(url: u, animal: "M\(i)", timepoint: "Day7", trial: 1, group: "", notes: "", experimentID: nil,
                           planned: [.grooming], duration: 8, fps: 30, width: 640, height: 480))
    }
    SimRunner.failures = ["M2_Day7.mp4": (50, true), "M3_Day7.mp4": (120, false)]
    let store = SessionStore(base: lib)
    await store.load()
    let outcome = await store.importVideos(items, copy: false)
    check(outcome.created.count == 6, "6 videos imported by reference")
    let dup = await store.importVideos([items[0]], copy: false)
    check(dup.created.isEmpty && dup.duplicates.count == 1, "the same file imported twice is detected as a duplicate")
    // Video 6 is offline.
    let offline = items[5].url
    try FileManager.default.moveItem(at: offline, to: videos.appendingPathComponent("moved.mp4"))
    await store.refreshAvailability()
    check(store.missingVideos.count == 1, "offline video detected")

    let engine = BatchEngine(store: store, makeRunner: { SimRunner() })
    engine.maxSimultaneous = 2
    var finishedSummary: BatchSummary?
    engine.hooks.finished = { finishedSummary = $0 }
    var activeChanges: [Bool] = []
    engine.hooks.activeChanged = { activeChanges.append($0) }
    engine.start()
    // Pause shortly after the start, then resume.
    try await Task.sleep(nanoseconds: 30_000_000)
    engine.pause()
    await waitIdle(engine)
    check(engine.state == .paused, "pause stops the running videos")
    let saved = store.recordings.filter { PoseCheckpoint.savedFrames(folder: store.checkpointFolder($0.id)) > 0 }.count
    check(saved >= 1, "paused videos kept their checkpoints (\(saved))")
    check(store.recordings.allSatisfy { $0.status != .processing }, "no video left in 'processing' after pause")
    engine.start()
    await waitIdle(engine)
    let ready = store.recordings.filter { $0.status == .ready }
    let failed = store.recordings.filter { $0.status == .failed }
    check(ready.count == 4, "4 videos finished (got \(ready.count))")
    check(failed.count == 1 && failed.first?.originalName == "M2_Day7.mp4", "the broken video failed with a reason: \(failed.first?.failure ?? "-")")
    check(store.recordings.first { $0.originalName == "M3_Day7.mp4" }?.status == .ready, "a video that failed once was retried from its checkpoint")
    check(store.recordings.first { $0.originalName == "M6_Day7.mp4" }?.status == .queued, "the offline video waits in the queue")
    check(engine.notice?.contains("1") == true, "notice mentions the waiting offline video")
    check(finishedSummary?.finished == 4, "batch summary reported (\(finishedSummary.map { "\($0.finished) done, \($0.failed) failed" } ?? "none"))")
    check(activeChanges.first == true && activeChanges.last == false, "keep-awake hook switched on and off")
    // Results: planned task created and analysed after QC.
    try await Task.sleep(nanoseconds: 1_500_000_000)
    let analyses = store.sessions.filter { $0.assay == .grooming }
    check(!analyses.isEmpty, "planned tasks assigned to included videos (\(analyses.count))")
    for r in ready { check(PoseStorage.exists(folder: store.recordingFolder(r.id)), "pose.bin written for \(r.originalName)"); break }
    check(ready.allSatisfy { !FileManager.default.fileExists(atPath: store.checkpointFolder($0.id).path) }, "checkpoints removed after success")
    // The offline video comes back.
    try FileManager.default.moveItem(at: videos.appendingPathComponent("moved.mp4"), to: offline)
    await store.refreshAvailability()
    engine.start()
    await waitIdle(engine)
    check(store.recordings.first { $0.originalName == "M6_Day7.mp4" }?.status == .ready, "the reconnected video is processed")

    // Export everything with every option on.
    var opts = ExportOptions()
    opts.frameLabels = true; opts.boris = true; opts.poseCSV = true; opts.poseDLC = true; opts.perVideoFolders = true
    let exportParent = ProcessInfo.processInfo.environment["RL_EXPORT_DIR"].map { URL(fileURLWithPath: $0) } ?? tempDir("export")
    try? FileManager.default.createDirectory(at: exportParent, withIntermediateDirectories: true)
    let preview = ExportService.preview(.library, options: opts, store: store)
    check(preview.analyses == store.sessions.count && preview.recordings == 6, "export preview counts (\(preview.analyses) analyses, \(preview.recordings) videos)")
    var steps = 0
    let report = try await ExportService.run(.library, options: opts, into: exportParent, store: store) { _ in steps += 1 }
    let names = Set(report.files.map { $0.lastPathComponent })
    check(names.contains("README.txt") && names.contains("export_manifest.json") && names.contains("qc_videos.csv"), "export: README, manifest and QC table")
    check(names.contains("GROOM_summary.csv") && names.contains("GROOM_segments.csv") && names.contains("GROOM_time_bins.csv"), "export: summary, segments and time bins of the task")
    check(report.files.contains { $0.path.contains("/pose_dlc/") } && report.files.contains { $0.path.contains("/frame_labels/") }, "export: DeepLabCut pose and frame labels")
    check(report.warnings.isEmpty, "export without warnings \(report.warnings)")
    print("  export folder: \(report.folder.path) (\(report.files.count) files)")

    // Crash journal: pretend the app died twice while M2 (now retried) was running.
    let m2 = store.recordings.first { $0.originalName == "M2_Day7.mp4" }!
    store.requeue([m2.id])
    SimRunner.failures = [:]
    await store.flushAndWait()
    BatchJournal(running: [m2.id]).save(lib)
    let store2 = SessionStore(base: lib)
    await store2.load()
    let e2 = BatchEngine(store: store2, makeRunner: { SimRunner() })
    e2.recoverAfterLaunch()
    check(store2.source(m2.id)?.crashes == 1 && store2.recording(m2.id)?.status == .queued, "first unexpected stop: video stays queued")
    await store2.flushAndWait()
    BatchJournal(running: [m2.id]).save(lib)
    let store3 = SessionStore(base: lib)
    await store3.load()
    let e3 = BatchEngine(store: store3, makeRunner: { SimRunner() })
    e3.recoverAfterLaunch()
    check(store3.recording(m2.id)?.status == .failed, "second unexpected stop: video set aside (\(store3.recording(m2.id)?.failure?.prefix(40) ?? ""))")
    check(!FileManager.default.fileExists(atPath: BatchJournal.url(lib).path), "journal cleared after recovery")

    // Shutdown while running keeps the checkpoint and leaves no journal.
    store3.requeue([m2.id])
    SimRunner.delayPerFrame = 3000
    e3.start()
    try await Task.sleep(nanoseconds: 100_000_000)
    await e3.shutdown()
    check(e3.jobs.isEmpty && !FileManager.default.fileExists(atPath: BatchJournal.url(lib).path), "shutdown waits for the run and clears the journal")
    check(store3.recording(m2.id)?.status == .queued && PoseCheckpoint.savedFrames(folder: store3.checkpointFolder(m2.id)) > 0,
          "after shutdown the video is queued with its checkpoint")
    SimRunner.delayPerFrame = 200
}

func testHalf() {
    print("HalfFloat")
    var bad = 0
    #if arch(x86_64) && os(macOS)
    print("  (skipped: Float16 reference not available on Intel Macs)")
    #else
    for h in 0...Int(UInt16.max) {
        let a = HalfFloat.float(UInt16(h)), b = Float(Float16(bitPattern: UInt16(h)))
        if !(a == b || (a.isNaN && b.isNaN)) || a.sign != b.sign { bad += 1 }
    }
    check(bad == 0, "all 65 536 half-precision values convert exactly (\(bad) differ)")
    #endif
}

func testNaming() {
    print("ImportNaming")
    let auto = NamePattern()
    var s = ImportNaming.suggest(stem: "M12_Day7_T2", pattern: auto, animals: ["M1", "M12"], timepoints: ["Day 7", "Day 28"])
    check(s.animal == "M12" && s.timepoint == "Day 7" && s.trial == 2, "auto: M12 / Day 7 / trial 2 (\(s))")
    s = ImportNaming.suggest(stem: "KO_05", folders: ["Day 28", "Cohort1"], pattern: auto, animals: [], timepoints: ["Day 7", "Day 28"])
    check(s.animal == "KO_05" && s.timepoint == "Day 28", "auto: timepoint from the folder (\(s))")
    var p = NamePattern()
    p.separators = "_"; p.animalPart = 2; p.timepointPart = 3
    s = ImportNaming.suggest(stem: "2026-10-01_WT03_baseline", pattern: p, animals: ["WT03"], timepoints: ["Baseline"])
    check(s.animal == "WT03" && s.timepoint == "Baseline", "pattern: part 2 / part 3, registered spelling (\(s))")
}

// MARK: - Library safety (Recently Deleted, backups, lock, lookup indexes)

func testPresets() {
    print("Parameter presets")
    var bad: [String] = []
    for a in Assay.allCases {
        var base = AssayParams.defaults(for: a)
        base.itch.injectionTime = 42; base.pain.injectionTime = 42; base.seizure.injectionTime = 42
        base.cylinder.lesion = .left; base.cylinder.view = .side
        for preset in ParameterPresets.presets(for: a) {
            let once = preset.applied(to: base)
            if preset.applied(to: once) != once { bad.append("\(preset.id) not idempotent") }
            if once.itch.injectionTime != 42 || once.pain.injectionTime != 42 || once.seizure.injectionTime != 42
                || once.cylinder.lesion != .left || once.cylinder.view != .side { bad.append("\(preset.id) changed per-animal settings") }
            if !preset.id.hasPrefix("kp."), ParameterPresets.current(once, assay: a)?.id == nil { bad.append("\(preset.id) not recognised") }
        }
    }
    check(bad.isEmpty, "presets are idempotent, keep per-animal settings and are recognised \(bad)")
    let tstDefault = ParameterPresets.current(AssayParams.defaults(for: .tailSuspension), assay: .tailSuspension)
    check(tstDefault?.id == "tst.last4", "the TST default is the standard last-4-minutes window")
    check(ParameterPresets.current(AssayParams.defaults(for: .pain), assay: .pain)?.id == "pain.mogil", "the formalin default is Mogil 1999")
}

@MainActor
func testPoseModels() async throws {
    print("Pose models")
    // Keypoint mapping and output layouts.
    check(PoseModelID.visible.keypointMap == Kp.allCases.map { Optional($0.rawValue) }, "visible-light model: identity mapping (iPhone-identical decoding)")
    let nir = PoseModelID.nearInfrared
    let names = nir.modelKeypoints
    let mapped = Kp.allCases.map { k in nir.keypointMap[k.rawValue].map { names[$0] } ?? "-" }
    check(mapped == ["flpaw", "hlpaw", "frpaw", "hrpaw", "tailbase", "snout", "-"], "near-infrared model: paws, tail base, snout→nose, no mouth (\(mapped))")
    check(nir.missingKeypoints == [.mouth] && nir.keypointCount == 8, "near-infrared model: 8 keypoints, mouth missing")
    check(PoseOutputLayout.detect(channels: 26, keypointCount: 7) == PoseOutputLayout(keypointCount: 7, endToEnd: false)
          && PoseOutputLayout.detect(channels: 27, keypointCount: 7)?.endToEnd == true
          && PoseOutputLayout.detect(channels: 29, keypointCount: 8) == PoseOutputLayout(keypointCount: 8, endToEnd: false)
          && PoseOutputLayout.detect(channels: 30, keypointCount: 8)?.endToEnd == true
          && PoseOutputLayout.detect(channels: 26, keypointCount: 8) == nil, "output layouts: 26/27 (7 kp), 29/30 (8 kp), mismatches rejected")
    check(PoseModelID(modelName: "PalmReaderPose8_640_W8A16") == .nearInfrared && PoseModelID(modelName: "CylinderMousePoseV2") == .visible
          && PoseModelID(modelName: "CylinderPose7_FP16_640") == .visibleFP16
          && PoseModelID(modelName: "something") == nil, "model recognised from the name stored in pose.bin")
    check(PoseModelID.choices == [.visibleFP16, .nearInfrared] && !PoseModelID.visible.isAvailable && PoseModelID.visible.runnable == .visibleFP16,
          "offered models: CylinderPose7 FP16 (default), PalmReaderPose8; CylinderMousePoseV2 only labels older videos")
    UserDefaults.standard.set(PoseModelID.visible.rawValue, forKey: PoseModelID.settingsKey)
    check(PoseModelID.defaultChoice == .visibleFP16, "a stored default of the removed model falls back to FP16")
    UserDefaults.standard.removeObject(forKey: SettingsKey.defaultPoseModel)
    check(PoseModelID.defaultChoice == .visibleFP16 && PoseModelID.standard == .visibleFP16
          && SessionStore.ImportItem(url: URL(fileURLWithPath: "/x.mp4"), animal: "", timepoint: "", trial: 1, group: "", notes: "",
                                     experimentID: nil, planned: []).model == .visibleFP16,
          "new imports default to CylinderPose7 FP16")
    check(PoseModelID.visibleFP16.keypointMap == PoseModelID.visible.keypointMap && PoseModelID.visibleFP16.missingKeypoints.isEmpty,
          "FP16 model: same 7 keypoints as the standard model")
    check(Set(PoseModelID.allCases.map { $0.shortTitle.en }).count == 3 && Set(PoseModelID.allCases.map { $0.shortTitle.zh }).count == 3,
          "each model has a distinct label in menus (English and Chinese)")
    // The visible-light methods sentence is exactly the shared one (the export replaces it for other models).
    var probe = Session(assay: .grooming, subject: "", group: "", notes: "", videoFile: "v.mov", originalName: "v.mov")
    probe.params = AssayParams.defaults(for: .grooming)
    check(Exporter.methods(probe).contains(PoseModelID.visible.methodsSentence(threshold: probe.params.common.keypointThreshold)),
          "methods sentence matches the shared exporter")

    // Sidecar: old files without the key read as the default model.
    let legacy = #"{"mode":"copied","path":"/x","fileName":"x.mov","size":1,"modified":0,"fingerprint":"f"}"#
    let old = try JSONDecoder().decode(VideoSource.self, from: Data(legacy.utf8))
    check(old.poseModel == nil, "source.json from 1.3.0 / iPhone: no model recorded")
    var src = old; src.poseModel = .nearInfrared
    let back = try JSONDecoder().decode(VideoSource.self, from: JSONEncoder().encode(src))
    check(back.poseModel == .nearInfrared, "pose model saved in source.json")

    // Import two videos with different models, track, re-track one with the other model, export.
    let lib = tempDir("models"), videos = tempDir("models-videos")
    var items: [SessionStore.ImportItem] = []
    for (i, m) in [PoseModelID.visible, .nearInfrared, .visibleFP16].enumerated() {
        let u = videos.appendingPathComponent("P\(i + 1).mp4")
        try Data((0..<(3000 + i)).map { UInt8(truncatingIfNeeded: $0 &* (i + 5)) }).write(to: u)
        items.append(.init(url: u, animal: "P\(i + 1)", timepoint: "", trial: 1, group: "", notes: "", experimentID: nil,
                           planned: [.pain], model: m))
    }
    SimRunner.failures = [:]
    SimRunner.modelsUsed = [:]
    let store = SessionStore(base: lib)
    await store.load()
    let created = await store.importVideos(items, copy: false).created
    let legacyRec = created[0].id
    check(store.poseModel(legacyRec) == .visibleFP16, "a video added with the removed model gets its successor")
    store.updateSource(legacyRec) { $0.poseModel = nil }
    check(store.poseModel(legacyRec) == .visible, "a video without a recorded model was tracked with CylinderMousePoseV2 (older libraries)")
    check(store.poseModel(created[1].id) == .nearInfrared
          && store.poseModel(created[2].id) == .visibleFP16, "each import keeps its model")
    let engine = BatchEngine(store: store, makeRunner: { SimRunner() })
    engine.start()
    await waitIdle(engine)
    check(SimRunner.modelsUsed["P1.mp4"] == .visibleFP16 && SimRunner.modelsUsed["P2.mp4"] == .nearInfrared
          && SimRunner.modelsUsed["P3.mp4"] == .visibleFP16, "the batch runs each video with its model (the removed model's successor for P1)")
    let nirPose = await store.recordingPose(created[1].id)
    check(nirPose?.modelName == PoseModelID.nearInfrared.rawValue, "pose.bin names the near-infrared model")
    try await Task.sleep(nanoseconds: 1_500_000_000)
    check(store.recording(created[1].id)?.qc != nil, "QC computed for the near-infrared video (nose + tail base)")
    store.rerunDetection(created[0].id, model: .nearInfrared)
    check(store.poseModel(created[0].id) == .nearInfrared && store.recording(created[0].id)?.status == .queued, "re-track with the other model")
    engine.start()
    await waitIdle(engine)
    check(SimRunner.modelsUsed["P1.mp4"] == .nearInfrared, "re-tracked with the near-infrared model")
    store.rerunDetection(created[0].id, model: .visible)
    check(store.poseModel(created[0].id) == .visibleFP16, "re-tracking with the removed model uses FP16")
    engine.start()
    await waitIdle(engine)
    try await Task.sleep(nanoseconds: 1_500_000_000)
    // P1 stands for a video of an older library (no recorded model = CylinderMousePoseV2).
    store.updateSource(created[0].id) { $0.poseModel = nil }

    var opts = ExportOptions()
    opts.perVideoFolders = true
    opts.includeNotIncluded = true
    let report = try await ExportService.run(.library, options: opts, into: tempDir("models-export"), store: store) { _ in }
    let qc = (try? String(contentsOf: report.folder.appendingPathComponent("qc_videos.csv"), encoding: .utf8)) ?? ""
    check(qc.contains("pose_model") && qc.contains("PalmReaderPose8_640_W8A16") && qc.contains("CylinderMousePoseV2")
          && qc.contains("CylinderPose7_FP16_640"), "qc_videos.csv names each video's model")
    let methods = report.files.first { $0.lastPathComponent.hasSuffix("_methods.txt") }.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    check(methods.contains("PalmReaderPose8") && methods.contains("CylinderPose7_FP16_640") && methods.contains("(1 of 3 analyses)"),
          "methods text names all three models with counts")
    let summaries = report.files.filter { $0.path.contains("/per_video/") && $0.lastPathComponent.hasSuffix("_summary.csv") }
    let modelRows = summaries.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.compactMap { $0.split(separator: "\n").first { $0.hasPrefix("model,") } }
    check(modelRows.contains { $0.hasPrefix("model,PalmReaderPose8_640_W8A16") } && modelRows.contains { $0.hasPrefix("model,CylinderMousePoseV2") }
          && modelRows.contains { $0.hasPrefix("model,CylinderPose7_FP16_640") },
          "per-video summaries name the model (\(modelRows))")
    let manifest = (try? String(contentsOf: report.folder.appendingPathComponent("export_manifest.json"), encoding: .utf8)) ?? ""
    check(manifest.contains("\"pose_model\" : \"PalmReaderPose8_640_W8A16\""), "manifest: pose model per analysis")
}

@MainActor
func testSafety() async throws {
    print("Library safety")
    let fm = FileManager.default
    let lib = tempDir("safety")
    let videos = tempDir("safety-videos")
    var items: [SessionStore.ImportItem] = []
    for i in 1...4 {
        let u = videos.appendingPathComponent("S\(i).mp4")
        try Data((0..<(2048 + i)).map { UInt8(truncatingIfNeeded: $0 &* (i + 3)) }).write(to: u)
        items.append(.init(url: u, animal: "S\(i)", timepoint: "", trial: 1, group: "", notes: "", experimentID: nil, planned: []))
    }
    let store = SessionStore(base: lib)
    await store.load()
    let created = await store.importVideos(items, copy: true).created
    check(created.count == 4, "4 videos copied into the library")
    let study = store.createExperiment("Safety study")
    store.move([created[2].id, created[3].id], toStudy: study.id)
    for r in created { store.assign([.grooming], to: r.id) }
    await store.flushAndWait()
    check(store.sessions.count == 4, "one analysis per video")

    // Lookups stay right through inserts, sorts and removals.
    let allOK = created.allSatisfy { store.recording($0.id)?.id == $0.id && store.sessions(of: $0.id).count == 1 }
    check(allOK, "indexed lookups find every video and its analyses")

    // Delete one video: its folder (with the copied video) moves to Recently Deleted.
    let r1 = created[0]
    let entryID = store.deleteRecordings([r1.id])
    await store.flushAndWait()
    check(entryID != nil && store.recording(r1.id) == nil && store.sessions(of: r1.id).isEmpty, "deleted video and its analysis are gone from the library")
    check(!fm.fileExists(atPath: store.recordingFolder(r1.id).path), "its folder left the library")
    let entries = await store.recentlyDeleted()
    check(entries.count == 1 && entries[0].recordingIDs == [r1.id] && entries[0].sessionIDs.count == 1, "Recently Deleted lists it with its analysis")
    let binFolder = RecentlyDeleted.folder(lib, entries[0].id).appendingPathComponent("Recordings/\(r1.id.uuidString)")
    check(fm.fileExists(atPath: binFolder.appendingPathComponent(r1.videoFile).path), "the copied video file is kept in Recently Deleted")
    let reopened = SessionStore(base: lib)
    await reopened.load()
    check(reopened.recording(r1.id) == nil && reopened.recordings.count == 3, "a reopened library does not show the deleted video")

    // Restore.
    let message = await store.restoreDeleted(entryID!)
    await store.flushAndWait()
    check(store.recording(r1.id) != nil && store.sessions(of: r1.id).count == 1, "restored with its analysis (\(message))")
    check(fm.fileExists(atPath: store.recordingFolder(r1.id).appendingPathComponent(r1.videoFile).path), "the video file is back in the library")
    let left = await store.recentlyDeleted()
    check(left.isEmpty, "Recently Deleted is empty after restoring")
    let reopened2 = SessionStore(base: lib)
    await reopened2.load()
    check(reopened2.recordings.count == 4 && reopened2.sessions.count == 4, "a reopened library has everything back")

    // Delete only the study: its videos stay; restoring the study takes them back.
    let animalBefore = store.recording(created[2].id)?.animalID
    let studyEntry = store.deleteExperiment(study.id, deleteVideos: false)
    await store.flushAndWait()
    check(store.experiment(study.id) == nil && store.recording(created[2].id)?.experimentID == nil, "study deleted, its videos kept outside any study")
    check(store.recording(created[2].id)?.subject == "S3", "the video keeps the animal ID as text")
    _ = await store.restoreDeleted(studyEntry!)
    await store.flushAndWait()
    check(store.experiment(study.id) != nil, "study restored")
    check(store.recording(created[2].id)?.experimentID == study.id && store.recording(created[2].id)?.animalID == animalBefore,
          "its videos rejoined it with their animals")

    // Analyses only.
    let a = store.sessions(of: created[1].id)[0].id
    let aEntry = store.delete([a])
    await store.flushAndWait()
    check(store.session(a) == nil && store.recording(created[1].id) != nil, "deleting an analysis keeps the video")
    _ = await store.restoreDeleted(aEntry!)
    check(store.session(a) != nil, "analysis restored")

    // Erase for good, and the 30-day purge.
    let e3 = store.deleteRecordings([created[1].id])
    await store.flushAndWait()
    await store.eraseDeleted(e3!)
    let afterErase = await store.recentlyDeleted()
    check(afterErase.isEmpty && !fm.fileExists(atPath: RecentlyDeleted.folder(lib, e3!).path), "Delete Now erases the entry")
    let old = DeletedEntry(deletedAt: Date().addingTimeInterval(-31 * 86_400), kind: .analyses)
    try fm.createDirectory(at: RecentlyDeleted.folder(lib, old.id), withIntermediateDirectories: true)
    let enc = Coders.encoder()
    try enc.encode(old).write(to: RecentlyDeleted.folder(lib, old.id).appendingPathComponent(RecentlyDeleted.entryFile))
    check(RecentlyDeleted.purge(lib) == 1, "entries older than 30 days are erased")

    // Backups: write, list, restore (design info and settings; nothing deleted).
    store.backup(MetadataBackup.Reason.manual)
    await store.flushAndWait()
    let list = await store.backups()
    let manual = list.first { $0.reason == MetadataBackup.Reason.manual }
    check(manual != nil, "manual backup listed (\(list.map(\.id)))")
    let target = created[3].id
    store.updateRecording(target) { $0.notes = "changed after the backup"; $0.decision = .excluded; $0.exclusionReason = "test" }
    let sid = store.sessions(of: target)[0].id
    store.update(sid) { $0.params.common.keypointThreshold = 0.9 }
    let restoreMessage = await store.restoreBackup(manual!.url)
    await store.flushAndWait()
    check(store.recording(target)?.notes == "" && store.recording(target)?.decision != .excluded, "backup restores the video's notes and decision (\(restoreMessage))")
    check(store.session(sid)?.params.common.keypointThreshold != 0.9, "backup restores the analysis settings")
    let after = await store.backups()
    check(after.contains { $0.reason == MetadataBackup.Reason.beforeRestore }, "the state before the restore was backed up")
    for i in 0..<(MetadataBackup.keepOther + 3) {
        var snap = store.metadataSnapshot(reason: MetadataBackup.Reason.manual)
        snap.createdAt = Date().addingTimeInterval(Double(-100 - i))
        try MetadataBackup.write(snap, base: lib)
    }
    check(MetadataBackup.list(lib).filter { $0.reason != MetadataBackup.Reason.daily }.count == MetadataBackup.keepOther, "old backups are pruned")

    // Library lock.
    LibraryLock.write(lib, token: "A", host: "Mac A", app: "test")
    check(LibraryLock.otherHolder(lib, token: "B")?.host == "Mac A", "another app instance sees the lock")
    check(LibraryLock.otherHolder(lib, token: "A") == nil, "its owner does not")
    check(LibraryLock.otherHolder(lib, token: "B", now: Date().addingTimeInterval(LibraryLock.staleAfter + 5)) == nil, "a stale lock is ignored")
    LibraryLock.release(lib, token: "B")
    check(LibraryLock.read(lib) != nil, "release never removes someone else's lock")
    LibraryLock.release(lib, token: "A")
    check(LibraryLock.read(lib) == nil, "the owner releases it")
}


@MainActor
func testTasks() async throws {
    print("Tasks (task first)")
    let lib = tempDir("tasks")
    let videos = tempDir("tasks-videos")
    let store = SessionStore(base: lib)
    await store.load()
    let t = store.createTask(assay: .grooming, name: "SNI cohort", groups: ["Sham", " SNI ", "sham", ""],
                             timepoints: ["Baseline", "Day 7"])
    check(store.tasks == [t] && store.taskTitle(t) == "SNI cohort", "a new task is listed under its name")
    check(store.taskGroups(t) == ["Sham", "SNI"], "groups trimmed, duplicates and blanks dropped (\(store.taskGroups(t)))")
    check(store.experiment(t.experimentID)?.plannedAssays == [.grooming] && store.experiment(t.experimentID)?.timepoints == ["Baseline", "Day 7"],
          "stored as a study planned for exactly its paradigm")
    let unnamed = store.createTask(assay: .gait, name: "  ", groups: [])
    check(store.taskTitle(unnamed).hasPrefix(Assay.gait.name.text + " ") && store.taskGroups(unnamed).isEmpty, "an unnamed task is called after its paradigm and date")

    // Group guessed from file and folder names.
    check(SessionStore.guessGroup(URL(fileURLWithPath: "/data/M3_sni_d7.mp4"), groups: ["Sham", "SNI"]) == "SNI"
          && SessionStore.guessGroup(URL(fileURLWithPath: "/data/Sham/M1.mp4"), groups: ["Sham", "SNI"]) == "Sham"
          && SessionStore.guessGroup(URL(fileURLWithPath: "/data/M1.mp4"), groups: ["Sham", "SNI"]) == nil,
          "the group is suggested from the file or folder name")

    // Add videos to the task: sessions exist at once, before tracking.
    func item(_ name: String, animal: String, group: String, task: TaskRef?) throws -> SessionStore.ImportItem {
        let u = videos.appendingPathComponent(name)
        // Unique content per file (the import skips identical files as duplicates).
        try (Data(name.utf8) + Data((0..<3000).map { UInt8(truncatingIfNeeded: $0 &* (name.count + 5)) })).write(to: u)
        return SessionStore.ImportItem(url: u, animal: animal, timepoint: "Baseline", trial: 1, group: group, notes: "",
                                       experimentID: task?.experimentID, planned: task.map { [$0.assay] } ?? [],
                                       createSessions: task != nil)
    }
    let items = [try item("M1_sham.mp4", animal: "M1", group: "Sham", task: t),
                 try item("M2_sham.mp4", animal: "M2", group: "Sham", task: t),
                 try item("M3_sni.mp4", animal: "M3", group: "SNI", task: t),
                 try item("M4_sni.mp4", animal: "M4", group: "SNI", task: t)]
    let created = await store.importVideos(items, copy: true).created
    check(created.count == 4 && store.sessions(in: t).count == 4, "4 videos added: 4 sessions in the task before any tracking")
    check(store.sessions(in: t, group: "Sham").count == 2 && store.sessions(in: t, group: "SNI").count == 2, "2 sessions per group")
    check(store.taskCounts(t).tracking == 4 && store.taskCounts(t).done == 0, "all 4 wait for tracking")
    check(created.allSatisfy { $0.plannedAssays.isEmpty }, "nothing left as planned (the sessions exist)")
    let animals = store.experiment(t.experimentID)?.animals.map(\.code) ?? []
    check(animals == ["M1", "M2", "M3", "M4"], "animals created from the IDs (\(animals))")
    // An animal keeps its group.
    let again = await store.importVideos([try item("M1_day7_sni.mp4", animal: "M1", group: "SNI", task: t)], copy: true).created
    check(again.count == 1 && store.taskGroup(again[0]) == "Sham" && store.sessions(in: t, group: "Sham").count == 3,
          "an animal already in a group keeps it")
    let overview = store.taskOverview()
    check(overview.sessions[t] == 5 && overview.groups[t]?.map(\.count) == [3, 2] && overview.tasks.count == 2,
          "sidebar overview: sessions and sessions per group in one pass")

    // Videos outside any task, moved in and out.
    let loose = await store.importVideos([try item("loose.mp4", animal: "M9", group: "", task: nil)], copy: true).created
    check(store.recordingsNotInTask.map(\.id) == loose.map(\.id), "a video imported without a task is listed as not in a task")
    store.moveToTask(Set(loose.map(\.id)), task: t)
    check(store.recordingsNotInTask.isEmpty && store.sessions(in: t).count == 6, "Move to Task: it joins the task with its session")
    let removal = store.removeFromTask(Set(loose.map(\.id)), task: t)
    check(removal.removedEntry != nil && store.sessions(in: t).count == 5 && store.recordingsNotInTask.map(\.id) == loose.map(\.id),
          "Remove from Task: the session goes to Recently Deleted, the video stays in the library")
    await store.undoMove(removal)
    check(store.sessions(in: t).count == 6 && store.sessions(of: loose[0].id).count == 1 && store.recordingsNotInTask.isEmpty,
          "Undo puts it back without a second session")

    // Moving between tasks of two studies: no copy, no phantom task, and Undo restores it exactly.
    let cyl = store.createTask(assay: .cylinder, name: "Cylinder cohort", groups: [])
    let mover = created[3].id
    let groomingSession = store.sessions(of: mover).first { $0.assay == .grooming }?.id
    let moved = store.moveToTask([mover], task: cyl, from: t)
    check(store.sessions(of: mover).map(\.assay) == [.cylinder] && store.recording(mover)?.experimentID == cyl.experimentID,
          "Move to another task: the video leaves the old task (no copy left behind)")
    check(!store.tasks.contains(TaskRef(experimentID: cyl.experimentID, assay: .grooming)), "no phantom task appears in the target study")
    check(store.taskGroup(store.recording(mover)!) == "SNI" && store.taskGroups(cyl) == ["SNI"], "its group comes along (kept as the animal's group)")
    await store.undoMove(moved)
    check(store.recording(mover)?.experimentID == t.experimentID && store.sessions(of: mover).map(\.id) == [groomingSession].compactMap { $0 },
          "Undo: back in its task with its own session, the new one erased")
    check(store.taskGroup(store.recording(mover)!) == "SNI", "and still in its group")

    // Removing from a task keeps the group as text; moving into another task makes it the animal's group.
    let out = store.removeFromTask([created[0].id], task: t)
    check(store.recording(created[0].id)?.group == "Sham" && store.recording(created[0].id)?.experimentID == nil,
          "a video taken out of a task keeps its group as text")
    let into = store.moveToTask([created[0].id], task: cyl)
    check(store.taskGroup(store.recording(created[0].id)!) == "Sham", "moved into another task, the text becomes the animal's group")
    await store.undoMove(into)
    await store.undoMove(out)
    check(store.recording(created[0].id)?.experimentID == t.experimentID && store.sessions(of: created[0].id).map(\.assay) == [.grooming]
          && !store.tasks.contains(TaskRef(experimentID: t.experimentID, assay: .cylinder)),
          "both undone: back in the first task with only its own session")

    // Legacy studies: several paradigms = several tasks; none = can be given one.
    let legacy = store.createExperiment("Old study")
    let old = await store.importVideos([try item("old1.mp4", animal: "A", group: "", task: nil)], copy: true).created
    store.move(Set(old.map(\.id)), toStudy: legacy.id)
    check(store.studiesWithoutTask.map(\.id) == [legacy.id], "a study without a paradigm is listed")
    _ = store.assign([.gait], to: old[0].id)
    _ = store.assign([.cylinder], to: old[0].id)
    let legacyTasks = store.tasks.filter { $0.experimentID == legacy.id }
    check(legacyTasks.map(\.assay) == [.cylinder, .gait] && store.taskTitle(legacyTasks[0]) == "Old study · " + Assay.cylinder.name.text,
          "a study analysed with two paradigms shows as two tasks (\(legacyTasks.map(\.assay)))")
    let empty = store.createExperiment("Plan only")
    store.setParadigm(.itch, for: empty.id)
    check(store.taskExists(TaskRef(experimentID: empty.id, assay: .itch)), "a study without a paradigm becomes a task")

    // Deleting one paradigm of a study with two: the other task keeps the video.
    let gaitTask = TaskRef(experimentID: legacy.id, assay: .gait)
    check(store.deletionPlan(gaitTask).wholeStudy == false, "a study with two tasks is not deleted with one of them")
    let gone = store.deleteTask(gaitTask, keepVideos: true)
    check(store.sessions(of: old[0].id).map(\.assay) == [.cylinder] && store.recording(old[0].id)?.experimentID == legacy.id
          && !store.taskExists(gaitTask), "deleting the gait task keeps the cylinder session and the video in its study")
    await store.undoDeleteTask(gone)
    check(store.sessions(of: old[0].id).count == 2 && store.taskExists(gaitTask), "Undo brings the gait task back")

    // Two videos of one new animal with two different groups: the first group wins (the sheet blocks this).
    let g1 = try item("Z1_a.mp4", animal: "Z1", group: "Sham", task: t)
    let g2 = try item("Z1_b.mp4", animal: "Z1", group: "SNI", task: t)
    let zz = await store.importVideos([g1, g2], copy: true).created
    check(zz.count == 2 && zz.allSatisfy { store.taskGroup(store.recording($0.id)!) == "Sham" }
          && store.experiment(t.experimentID)?.animals.filter { $0.code == "Z1" }.count == 1,
          "one animal, one group, created once for the whole import")

    await store.flushAndWait()
    let reopened = SessionStore(base: lib)
    await reopened.load()
    check(reopened.tasks.count == store.tasks.count && reopened.sessions(in: t).count == store.sessions(in: t).count
          && reopened.taskGroups(t) == ["Sham", "SNI"],
          "tasks, sessions and groups survive a relaunch")

    // Delete a task, keeping its videos.
    let total = store.recordings.count
    let inTask = Set(store.sessions(in: t).compactMap(\.recordingID)).count
    let del = store.deleteTask(t, keepVideos: true)
    check(del.entry != nil && !store.taskExists(t) && store.recordings.count == total, "Delete Task (keep videos): the task goes, its videos stay")
    check(store.recordingsNotInTask.count == inTask, "its videos are listed as not in a task (\(store.recordingsNotInTask.count) of \(inTask))")
    await store.undoDeleteTask(del)
    check(store.taskExists(t) && store.sessions(in: t).count == inTask, "Undo restores the task with its videos")
}

@main
struct Main {
    static func main() async {
        do {
            try testCheckpoint()
            testNaming()
            testHalf()
            testPresets()
            try await testBatch()
            try await testSafety()
            try await testPoseModels()
            try await testTasks()
        } catch {
            failures += 1
            print("error: \(error)")
        }
        print(failures == 0 ? "\nALL CORE TESTS PASSED" : "\n\(failures) CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
