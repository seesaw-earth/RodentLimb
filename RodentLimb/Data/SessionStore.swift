// SessionStore.swift — tasks (studies), recordings (videos) and analyses on disk, and the analysis queue.
//
// Folders (Documents/RodentLimb/, visible in the Files app; the same layout as the Mac app):
//   Experiments/<id>.json            task / study design, animals, allocation, QC criteria
//   Recordings/<id>/                 recording.json, the video, pose.bin, source.json (pose model,
//                                    fingerprint), optionally skeleton.mp4
//   Sessions/<id>/                   one analysis (session of a task): session.json, result.json
//   Recently Deleted/<entry>/        deleted items, same layout, kept 30 days (LibrarySafety.swift)
//   Backups/metadata-*.json          daily and before-change metadata backups
//
// Flow (1.4, task first): a task is created → videos are added to it; each video becomes a Recording
// and, at once, the Session of the task's paradigm → the pose model runs once per video (the model
// chosen when it was added) → a QC report is computed → a video that passes is included, otherwise it
// waits for a review → results and group comparisons use included sessions only.
// Up to 1.2 every Session owned its own video; those are migrated on first launch (files are moved,
// never copied or deleted). Videos planned for a task in 1.3 get their session on launch.
//
// Smoothness / stability rules:
//  • Nothing heavy runs on the main thread (copying videos, pose and result coding, QC, storage).
//  • Disk writes go through one serial queue, coalesced (~0.4 s); decisions, deletes, imports and
//    task edits are written at once; everything is written when the app goes to the background.
//  • Lookups by id are O(1) (verified index), so list rows never scan the library.
//  • Deleting moves folders into Recently Deleted (restorable for 30 days); nothing is erased at once.
//  • Analyses run one at a time; the session on screen goes first.

import Foundation
import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = [] { didSet { revision &+= 1 } }
    @Published private(set) var recordings: [Recording] = [] { didSet { revision &+= 1 } }
    @Published private(set) var experiments: [Experiment] = [] { didSet { revision &+= 1 } }
    /// False until the library has been read (off the main thread) at launch.
    @Published private(set) var isLoaded = false
    @Published private(set) var results: [UUID: AnalysisResult] = [:]
    /// Per-video sidecar (pose model, fingerprint), keyed by recording id.
    @Published private(set) var sidecars: [UUID: RecordingSidecar] = [:]
    /// Changes whenever Recently Deleted changes (screens showing it reload).
    @Published private(set) var recentlyDeletedVersion = 0

    /// Pose tracks, keyed by recording id.
    private var poseCache: [UUID: PoseTrack] = [:]
    private var poseOrder: [UUID] = []
    private var poseLoads: [UUID: Task<PoseTrack?, Never>] = [:]
    private static let maxCachedPoses = 3

    /// Most recently used results last; only results already on disk are ever evicted.
    private var resultOrder: [UUID] = []
    /// Results whose result.json is still being written (serial number of the newest write).
    private var unsavedResults: [UUID: (serial: Int, result: AnalysisResult)] = [:]
    private var resultWriteSerial = 0
    private static let maxCachedResults = 24

    private var analysisQueue: [UUID] = []
    /// Queued for another session than the one on screen: the result is saved but not kept in
    /// memory unless that session's result already is.
    private var backgroundAnalyses = Set<UUID>()
    private var analysisWorker: Task<Void, Never>?
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]

    private var qcQueue: [UUID] = []
    private var qcWorker: Task<Void, Never>?

    /// Tail of the serial disk-write queue.
    private var ioTail: Task<Void, Never>?

    private var dirty = Set<UUID>()
    private var dirtyRecordings = Set<UUID>()
    private var dirtyExperiments = Set<UUID>()
    private var dirtySidecars = Set<UUID>()
    private var flushTask: Task<Void, Never>?
    /// Latest time the pending changes may wait (coalescing never delays a write by more than ~2 s).
    private var flushDeadline: Date?
    private var lastChangeBackup: Date?
    private var loadTask: Task<Void, Never>?

    /// Changes with every change of the sessions, recordings or studies (caches are keyed on it).
    private(set) var revision = 0
    /// Sessions of each task, valid while `revision` is unchanged (Tasks.swift).
    var taskSessionCache: [TaskRef: (revision: Int, list: [Session])] = [:]

    // Lookup indexes (id → position). Rebuilt lazily after an insert, sort or removal; an in-place
    // replacement keeps positions. Every hit is verified, so a stale index never returns the wrong
    // item; a miss while the array has grown rebuilds the index once.
    private var sessionIndex: [UUID: Int] = [:]
    private var sessionsByRecording: [UUID: [Int]] = [:]
    private var recordingIndex: [UUID: Int] = [:]
    private var experimentIndex: [UUID: Int] = [:]
    private var sessionIndexValid = false
    private var recordingIndexValid = false
    private var experimentIndexValid = false
    private var sessionIndexCount = 0
    private var recordingIndexCount = 0
    private var experimentIndexCount = 0

    let base: URL
    /// Analyses (sessions).
    let root: URL
    let recordingsRoot: URL
    let experimentsRoot: URL

    /// `customBase` is for tests only; the app always uses Documents/RodentLimb.
    init(base customBase: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        base = customBase ?? docs.appendingPathComponent("RodentLimb", isDirectory: true)
        root = base.appendingPathComponent("Sessions", isDirectory: true)
        recordingsRoot = base.appendingPathComponent("Recordings", isDirectory: true)
        experimentsRoot = base.appendingPathComponent("Experiments", isDirectory: true)
        // The library is decoded (and 1.2 libraries migrated) off the main thread; the interface
        // shows "Opening library…" meanwhile.
        let clearTemp = customBase == nil
        loadTask = Task { [weak self] in
            await self?.load(clearingTemporaryFiles: clearTemp)
            guard let self else { return }
            // Daily metadata backup and Recently Deleted clean-up, off the main thread.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self?.dailyBackupIfNeeded()
                await self?.purgeRecentlyDeleted()
            }
            // Recordings from 1.2 have no QC report yet, and videos from before 1.4 no fingerprint:
            // compute them quietly in the background.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.backfillQC()
                await self?.backfillFingerprints()
            }
        }
    }

    /// Returns once the library has been read.
    func waitUntilLoaded() async { await loadTask?.value }

    // MARK: Paths

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func recordingFolder(_ id: UUID) -> URL { recordingsRoot.appendingPathComponent(id.uuidString, isDirectory: true) }
    func videoURL(_ r: Recording) -> URL { recordingFolder(r.id).appendingPathComponent(r.videoFile) }
    func videoURL(_ s: Session) -> URL {
        if let r = recording(for: s) { return videoURL(r) }
        return recordingFolder(s.recordingID ?? s.id).appendingPathComponent(s.videoFile)
    }
    func resultURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("result.json") }
    /// Skeleton video of a recording.
    func skeletonURL(_ recordingID: UUID) -> URL { recordingFolder(recordingID).appendingPathComponent("skeleton.mp4") }
    private func experimentURL(_ id: UUID) -> URL { experimentsRoot.appendingPathComponent(id.uuidString + ".json") }

    // MARK: Lookups (O(1))

    func session(_ id: UUID) -> Session? {
        if !sessionIndexValid { rebuildSessionIndex() }
        if let i = sessionIndex[id], i < sessions.count, sessions[i].id == id { return sessions[i] }
        guard sessionIndex[id] != nil || sessions.count != sessionIndexCount else { return nil }
        rebuildSessionIndex()
        return sessionIndex[id].flatMap { $0 < sessions.count && sessions[$0].id == id ? sessions[$0] : nil }
    }

    func recording(_ id: UUID?) -> Recording? {
        guard let id else { return nil }
        if !recordingIndexValid { rebuildRecordingIndex() }
        if let i = recordingIndex[id], i < recordings.count, recordings[i].id == id { return recordings[i] }
        guard recordingIndex[id] != nil || recordings.count != recordingIndexCount else { return nil }
        rebuildRecordingIndex()
        return recordingIndex[id].flatMap { $0 < recordings.count && recordings[$0].id == id ? recordings[$0] : nil }
    }

    func recording(for s: Session) -> Recording? { recording(s.recordingID) }

    func experiment(_ id: UUID?) -> Experiment? {
        guard let id else { return nil }
        if !experimentIndexValid { rebuildExperimentIndex() }
        if let i = experimentIndex[id], i < experiments.count, experiments[i].id == id { return experiments[i] }
        guard experimentIndex[id] != nil || experiments.count != experimentIndexCount else { return nil }
        rebuildExperimentIndex()
        return experimentIndex[id].flatMap { $0 < experiments.count && experiments[$0].id == id ? experiments[$0] : nil }
    }

    func experiment(for r: Recording) -> Experiment? { experiment(r.experimentID) }

    func sessions(of recordingID: UUID) -> [Session] {
        if !sessionIndexValid { rebuildSessionIndex() }
        let hits = (sessionsByRecording[recordingID] ?? []).compactMap { $0 < sessions.count ? sessions[$0] : nil }
        if hits.allSatisfy({ $0.recordingID == recordingID }) && sessions.count == sessionIndexCount { return hits }
        rebuildSessionIndex()
        return (sessionsByRecording[recordingID] ?? []).compactMap { $0 < sessions.count ? sessions[$0] : nil }
    }

    func recordings(in experimentID: UUID) -> [Recording] { recordings.filter { $0.experimentID == experimentID } }

    private func rebuildSessionIndex() {
        var byID = [UUID: Int](minimumCapacity: sessions.count)
        var byRec: [UUID: [Int]] = [:]
        for (i, s) in sessions.enumerated() {
            if byID[s.id] == nil { byID[s.id] = i }
            if let r = s.recordingID { byRec[r, default: []].append(i) }
        }
        sessionIndex = byID
        sessionsByRecording = byRec
        sessionIndexValid = true
        sessionIndexCount = sessions.count
    }

    private func rebuildRecordingIndex() {
        var byID = [UUID: Int](minimumCapacity: recordings.count)
        for (i, r) in recordings.enumerated() where byID[r.id] == nil { byID[r.id] = i }
        recordingIndex = byID
        recordingIndexValid = true
        recordingIndexCount = recordings.count
    }

    private func rebuildExperimentIndex() {
        var byID = [UUID: Int](minimumCapacity: experiments.count)
        for (i, e) in experiments.enumerated() where byID[e.id] == nil { byID[e.id] = i }
        experimentIndex = byID
        experimentIndexValid = true
        experimentIndexCount = experiments.count
    }

    private func indexOfSession(_ id: UUID) -> Int? {
        _ = session(id)
        return sessionIndex[id].flatMap { $0 < sessions.count && sessions[$0].id == id ? $0 : nil }
    }
    private func indexOfRecording(_ id: UUID) -> Int? {
        _ = recording(id)
        return recordingIndex[id].flatMap { $0 < recordings.count && recordings[$0].id == id ? $0 : nil }
    }
    private func indexOfExperiment(_ id: UUID) -> Int? {
        _ = experiment(id)
        return experimentIndex[id].flatMap { $0 < experiments.count && experiments[$0].id == id ? $0 : nil }
    }

    /// Animal shown for a recording (blind code while the study is blinded).
    func subjectLabel(_ r: Recording) -> String {
        if let e = experiment(for: r), let a = e.animal(r.animalID) { return e.displayCode(a) }
        return r.subject
    }

    /// Group (unless blinded) and timepoint of a recording, for lists.
    func groupLabel(_ r: Recording) -> String {
        var parts: [String] = []
        if let e = experiment(for: r) {
            if !e.blinded, let a = e.animal(r.animalID) { parts.append(e.groupLabel(a)) }
        } else {
            parts.append(r.group)
        }
        parts.append(r.timepoint)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func displayName(_ r: Recording) -> String {
        let s = subjectLabel(r)
        return s.isEmpty ? r.originalName : s
    }

    /// The video file name, hidden while the recording's study is blinded (it often names the animal).
    func fileLabel(_ r: Recording) -> String {
        if experiment(for: r)?.blinded == true { return L("(hidden while blinded)", "（盲法期间隐藏）") }
        return r.originalName
    }

    // MARK: Pose models

    /// The pose model that tracks / tracked a video (CylinderMousePoseV2 when none was recorded).
    func poseModel(_ recordingID: UUID) -> PoseModelID { sidecars[recordingID]?.poseModel ?? .visible }

    /// Size-and-fingerprint keys of every video in the library (duplicate detection).
    var knownFingerprints: Set<String> { Set(sidecars.values.compactMap(\.duplicateKey)) }

    private func updateSidecar(_ id: UUID, _ change: (inout RecordingSidecar) -> Void) {
        var s = sidecars[id] ?? RecordingSidecar(fileName: recording(id)?.originalName ?? "", poseModel: nil)
        change(&s)
        guard s != sidecars[id] else { return }
        sidecars[id] = s
        dirtySidecars.insert(id)
        scheduleFlush()
    }

    // MARK: Loading and migration

    /// Everything read from disk at launch (decoded off the main thread).
    private struct LoadedLibrary: Sendable {
        var experiments: [Experiment] = []
        var recordings: [Recording] = []
        var sessions: [Session] = []
        var sidecars: [UUID: RecordingSidecar] = [:]
        var repaired: Set<UUID> = []
        var orphans: [(id: UUID, names: [String])] = []
    }

    private func load(clearingTemporaryFiles: Bool) async {
        let base = self.base, root = self.root, recordingsRoot = self.recordingsRoot, experimentsRoot = self.experimentsRoot
        let lib = await Task.detached(priority: .userInitiated) { () -> LoadedLibrary in
            // Temporary video copies left by an interrupted session; no import can start before the
            // library is open.
            if clearingTemporaryFiles { TempFiles.clearStale() }
            return SessionStore.readLibrary(base: base, root: root, recordingsRoot: recordingsRoot, experimentsRoot: experimentsRoot)
        }.value
        experiments = lib.experiments
        recordings = lib.recordings
        sidecars = lib.sidecars
        dirtyRecordings.formUnion(lib.repaired)
        recordingIndexValid = false
        experimentIndexValid = false

        // Mirror recording state into each analysis (status, subject, group, video facts).
        var list = lib.sessions
        for i in list.indices {
            if let r = recording(list[i].recordingID) {
                let before = list[i]
                sync(&list[i], with: r)
                if list[i] != before { dirty.insert(list[i].id) }
            } else if list[i].hasPose || list[i].status != .failed {
                list[i].hasPose = false
                list[i].status = .failed
                list[i].failure = L("The video of this analysis is missing.", "该分析对应的视频已丢失。")
                dirty.insert(list[i].id)
            }
        }
        sessions = list.sorted { $0.createdAt > $1.createdAt }
        sessionIndexValid = false

        // 1.3 kept tasks chosen at import as "planned" until QC passed; in 1.4 the session exists from
        // the start (so the video shows in its task, waiting for review if needed).
        for r in recordings where !r.plannedAssays.isEmpty && r.status != .failed {
            assign(r.plannedAssays, to: r.id)
            updateRecording(r.id) { $0.plannedAssays = [] }
        }
        isLoaded = true
        if !dirty.isEmpty || !dirtyRecordings.isEmpty { flush() }
        // Folders of an import interrupted by a crash (a video but no recording.json): moved to Recently
        // Deleted, where they can be restored as videos; nothing is erased and nothing piles up.
        for o in lib.orphans {
            var entry = DeletedEntry(kind: .videos)
            entry.recordingIDs = [o.id]
            entry.names = o.names.isEmpty ? [L("Unfinished import", "未完成的导入")] : o.names
            entry.items = ["Recordings/\(o.id.uuidString)"]
            trash(entry)
        }
    }

    /// Reads the library (studies, recordings with their sidecars, analyses). Sessions of 1.0–1.2 own
    /// their video and are turned into a recording here (files are moved, never deleted).
    nonisolated private static func readLibrary(base: URL, root: URL, recordingsRoot: URL, experimentsRoot: URL) -> LoadedLibrary {
        var out = LoadedLibrary()
        let decoder = Coders.decoder()
        let fm = FileManager.default
        for d in [root, recordingsRoot, experimentsRoot] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }

        var exps: [Experiment] = []
        for u in (try? fm.contentsOfDirectory(at: experimentsRoot, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "json" {
            if let d = try? Data(contentsOf: u), let e = try? decoder.decode(Experiment.self, from: d) { exps.append(e) }
        }
        var seenExp = Set<UUID>()
        out.experiments = exps.sorted { $0.createdAt > $1.createdAt }.filter { seenExp.insert($0.id).inserted }

        var recs: [Recording] = []
        var seen = Set<UUID>()
        for d in (try? fm.contentsOfDirectory(at: recordingsRoot, includingPropertiesForKeys: nil)) ?? [] {
            let json = d.appendingPathComponent("recording.json")
            guard fm.fileExists(atPath: json.path) else {
                // No recording.json: an import that never finished (a damaged file is left alone).
                if let id = UUID(uuidString: d.lastPathComponent) {
                    let names = ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { !$0.hasPrefix(".") }
                    out.orphans.append((id, names))
                }
                continue
            }
            guard let data = try? Data(contentsOf: json), var r = try? decoder.decode(Recording.self, from: data) else { continue }
            // A folder duplicated by hand (Files app) carries the same id: keep the first.
            guard seen.insert(r.id).inserted else { continue }
            if r.status == .processing { r.status = .queued; out.repaired.insert(r.id) }
            if r.hasPose && !PoseStorage.exists(folder: d) {
                r.hasPose = false
                r.status = .queued
                out.repaired.insert(r.id)
            }
            if let car = RecordingSidecar.load(folder: d) { out.sidecars[r.id] = car }
            recs.append(r)
        }

        var list: [Session] = []
        var seenSessions = Set<UUID>()
        for d in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: d.appendingPathComponent("session.json")),
                  var s = try? decoder.decode(Session.self, from: data) else { continue }
            guard seenSessions.insert(s.id).inserted else { continue }
            if s.recordingID == nil {
                let r = migrate(&s, folder: d, recordingsRoot: recordingsRoot, existing: recs.first { $0.id == s.id })
                recs.removeAll { $0.id == r.id }
                recs.append(r)
                out.orphans.removeAll { $0.id == r.id }
            }
            list.append(s)
        }
        out.recordings = recs.sorted { $0.createdAt > $1.createdAt }
        out.sessions = list
        return out
    }

    /// Turns a 1.2 session (video and pose in its own folder) into a recording plus this analysis.
    /// Files are moved (an instant rename on the same volume); the recording keeps the session's id.
    nonisolated private static func migrate(_ s: inout Session, folder d: URL, recordingsRoot: URL, existing: Recording?) -> Recording {
        let fm = FileManager.default
        let recDir = recordingsRoot.appendingPathComponent(s.id.uuidString, isDirectory: true)
        try? fm.createDirectory(at: recDir, withIntermediateDirectories: true)
        for name in [s.videoFile, PoseStorage.fileName, PoseStorage.legacyFileName, "skeleton.mp4"] where !name.isEmpty {
            let src = d.appendingPathComponent(name), dst = recDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                // A rename normally; copy if the move fails so the recording still gets its files.
                if (try? fm.moveItem(at: src, to: dst)) == nil { try? fm.copyItem(at: src, to: dst) }
            }
        }
        var r = existing ?? Recording(videoFile: s.videoFile, originalName: s.originalName)
        if existing == nil {
            r.id = s.id
            r.createdAt = s.createdAt
            r.subject = s.subject
            r.group = s.group
            r.notes = s.notes
            r.videoWidth = s.videoWidth
            r.videoHeight = s.videoHeight
            r.fps = s.fps
            r.duration = s.duration
            r.hasSkeletonVideo = s.hasSkeletonVideo
            r.modelVersion = s.modelVersion
            r.hasPose = s.hasPose && PoseStorage.exists(folder: recDir)
            switch s.status {
            case .failed where !r.hasPose:
                r.status = .failed
                r.failure = s.failure
            default:
                r.status = r.hasPose ? .ready : .queued
            }
            // Already analysed in 1.2: keep it in the analysis.
            r.decision = r.hasPose ? .included : .pending
        }
        r.updatedAt = Date()
        // Written synchronously: a crash during migration must not leave a session without its
        // recording (both files are tiny).
        let encoder = Coders.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(r) { try? data.write(to: recDir.appendingPathComponent("recording.json"), options: .atomic) }
        s.recordingID = r.id
        if let data = try? encoder.encode(s) { try? data.write(to: d.appendingPathComponent("session.json"), options: .atomic) }
        return r
    }

    /// Copies the recording's state into an analysis.
    private func sync(_ s: inout Session, with r: Recording) {
        s.subject = subjectLabel(r)
        s.group = groupLabel(r)
        s.notes = r.notes
        s.videoFile = r.videoFile
        s.originalName = r.originalName
        s.videoWidth = r.videoWidth
        s.videoHeight = r.videoHeight
        s.fps = r.fps
        s.duration = r.duration
        s.modelVersion = r.modelVersion
        s.hasSkeletonVideo = r.hasSkeletonVideo
        s.hasPose = r.hasPose
        switch r.status {
        case .queued:
            s.status = .queued
        case .processing:
            s.status = .processing
        case .failed:
            s.status = .failed
            s.failure = r.failure
        case .ready:
            if s.status == .queued || s.status == .processing || s.status == .failed {
                s.status = s.isCalibrated ? .done : .needsSetup
                s.failure = nil
            }
        }
    }

    private func resync(recording id: UUID) {
        guard let r = recording(id) else { return }
        for s in sessions(of: id) {
            var copy = s
            sync(&copy, with: r)
            save(copy)
        }
    }

    // MARK: Saving

    /// Runs disk work one item after another, off the main thread, in the order it was issued.
    private func enqueueIO(_ work: @escaping @Sendable () -> Void) {
        let previous = ioTail
        ioTail = Task.detached(priority: .utility) {
            await previous?.value
            work()
        }
    }

    /// Runs disk work on the same serial queue (after everything issued before it) and returns its result.
    private func performIO<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let previous = ioTail
        let task = Task.detached(priority: .userInitiated) { () -> T in
            await previous?.value
            return work()
        }
        ioTail = Task.detached(priority: .userInitiated) { _ = await task.value }
        return await task.value
    }

    /// Writes ~0.4 s after the last change, but never more than ~2 s after the first unsaved one
    /// (a steady stream of changes cannot keep postponing the write).
    private func scheduleFlush() {
        let now = Date()
        let deadline = flushDeadline ?? now.addingTimeInterval(2)
        flushDeadline = deadline
        if now >= deadline { flush(); return }
        let delay = min(0.4, deadline.timeIntervalSince(now))
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.01, delay) * 1e9))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Updates memory immediately (the UI reacts at once) and writes to disk shortly after, off
    /// the main thread, coalescing bursts such as slider drags or label edits.
    func save(_ s: Session) {
        var s = s
        if let i = indexOfSession(s.id) {
            var old = sessions[i]
            old.updatedAt = s.updatedAt
            if old == s { return }          // nothing changed: no redraw, no write
            s.updatedAt = Date()
            sessions[i] = s
        } else {
            s.updatedAt = Date()
            sessions.insert(s, at: 0)
            sessions.sort { $0.createdAt > $1.createdAt }
            sessionIndexValid = false
        }
        dirty.insert(s.id)
        scheduleFlush()
    }

    private func saveRecording(_ r: Recording) {
        var r = r
        if let i = indexOfRecording(r.id) {
            var old = recordings[i]
            old.updatedAt = r.updatedAt
            if old == r { return }
            r.updatedAt = Date()
            recordings[i] = r
        } else {
            r.updatedAt = Date()
            recordings.insert(r, at: 0)
            recordings.sort { $0.createdAt > $1.createdAt }
            recordingIndexValid = false
        }
        dirtyRecordings.insert(r.id)
        scheduleFlush()
    }

    private func saveExperiment(_ e: Experiment) {
        if let i = indexOfExperiment(e.id) {
            if experiments[i] == e { return }
            experiments[i] = e
        } else {
            experiments.insert(e, at: 0)
            experiments.sort { $0.createdAt > $1.createdAt }
            experimentIndexValid = false
        }
        dirtyExperiments.insert(e.id)
        scheduleFlush()
    }

    /// Writes pending changes now (off the main thread, in order).
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        flushDeadline = nil
        let items = dirty.compactMap { id in session(id).map { ($0, folder(id)) } }
        let recs = dirtyRecordings.compactMap { id in recording(id).map { ($0, recordingFolder(id)) } }
        let exps = dirtyExperiments.compactMap { id in experiment(id).map { ($0, experimentURL(id)) } }
        let cars = dirtySidecars.compactMap { id in sidecars[id].map { ($0, recordingFolder(id)) } }
        dirty.removeAll()
        dirtyRecordings.removeAll()
        dirtyExperiments.removeAll()
        dirtySidecars.removeAll()
        guard !items.isEmpty || !recs.isEmpty || !exps.isEmpty || !cars.isEmpty else { return }
        enqueueIO {
            let encoder = Coders.encoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let fm = FileManager.default
            // Never recreate the folder of something deleted in the meantime.
            for (r, dir) in recs {
                guard fm.fileExists(atPath: dir.path), let data = try? encoder.encode(r) else { continue }
                try? data.write(to: dir.appendingPathComponent("recording.json"), options: .atomic)
            }
            for (car, dir) in cars {
                guard fm.fileExists(atPath: dir.path) else { continue }
                try? car.save(folder: dir)
            }
            for (session, dir) in items {
                if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
                guard let data = try? encoder.encode(session) else { continue }
                try? data.write(to: dir.appendingPathComponent("session.json"), options: .atomic)
            }
            for (e, url) in exps {
                guard let data = try? encoder.encode(e) else { continue }
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// The app is leaving the foreground: write everything now and ask iOS for the few seconds
    /// needed to finish, so no edit is lost if the app is suspended or terminated afterwards.
    func flushForBackground() {
        flush()
        guard ioTail != nil else { return }
        let assertion = BackgroundAssertion(name: "RodentLimb save")
        enqueueIO {
            Task { @MainActor in assertion.end() }
        }
    }

    func update(_ id: UUID, _ change: (inout Session) -> Void) {
        guard var s = session(id) else { return }
        change(&s)
        save(s)
    }

    /// Changes a recording and mirrors the change into its analyses.
    func updateRecording(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard var r = recording(id) else { return }
        let studyBefore = r.experimentID
        change(&r)
        saveRecording(r)
        resync(recording: id)
        // Joined a study: its QC criteria apply now. A video leaving every task keeps the report of
        // the criteria it was judged by (re-checking with the defaults could include it behind the
        // task's back, e.g. between a removal and its Undo).
        if r.experimentID != studyBefore, r.experimentID != nil, r.hasPose { enqueueQC(id) }
    }

    // MARK: Tasks and studies

    @discardableResult
    func createExperiment(_ name: String) -> Experiment {
        var e = Experiment(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? L("New task", "新任务") : name)
        e.ensureBlindCodes()
        saveExperiment(e)
        flush()
        return e
    }

    /// A new task: one paradigm, optional groups (levels of one factor "Group") and timepoints.
    @discardableResult
    func createTask(name: String, assay: Assay, groups: [String], timepoints: [String], notes: String) -> TaskRef {
        let n = name.trimmingCharacters(in: .whitespaces)
        var e = Experiment(name: n.isEmpty ? assay.name.text : n)
        e.notes = notes
        e.plannedAssays = [assay]
        e.timepoints = Self.unique(timepoints)
        let levels = Self.unique(groups)
        if !levels.isEmpty { e.factors = [DesignFactor(name: "Group", levels: levels)] }
        e.ensureBlindCodes()
        saveExperiment(e)
        flush()
        return TaskRef(experimentID: e.id, assay: assay)
    }

    /// Trimmed, non-empty, without repeats, in order.
    nonisolated static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for raw in list {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty && seen.insert(v).inserted { out.append(v) }
        }
        return out
    }

    func updateExperiment(_ id: UUID, _ change: (inout Experiment) -> Void) {
        guard var e = experiment(id) else { return }
        let before = e
        change(&e)
        e.ensureBlindCodes()
        saveExperiment(e)
        // Group labels, blinding or animal codes may have changed: refresh the analyses — all of the
        // study's for a design or blinding change, otherwise only those of the animals that changed
        // (adding animals one by one during an import stays linear).
        if e.factors != before.factors || e.blinded != before.blinded {
            for r in recordings where r.experimentID == id { resync(recording: r.id) }
        } else if e.animals != before.animals {
            var old: [UUID: Animal] = [:]
            for a in before.animals { old[a.id] = a }
            var changed = Set<UUID>()
            for a in e.animals where old[a.id] != a { changed.insert(a.id) }
            let now = Set(e.animals.map(\.id))
            for a in before.animals where !now.contains(a.id) { changed.insert(a.id) }
            if !changed.isEmpty {
                for r in recordings where r.experimentID == id {
                    if let aid = r.animalID, changed.contains(aid) { resync(recording: r.id) }
                }
            }
        }
        if e.qc != before.qc { recomputeQC(experiment: id) }
    }

    /// A task edit made by the user (design, groups, animals, blinding): saved at once.
    func editTask(_ id: UUID, _ change: (inout Experiment) -> Void) {
        updateExperiment(id, change)
        flush()
    }

    /// Gives a study of 1.0–1.3 without any paradigm one, which makes it a task.
    func setParadigm(_ assay: Assay, for eid: UUID) {
        updateExperiment(eid) { e in if !e.plannedAssays.contains(assay) { e.plannedAssays.append(assay) } }
        // Every video of the study gets its session of the paradigm.
        for r in recordings(in: eid) { assign([assay], to: r.id) }
        flush()
    }

    /// Finds the animal with this code in the study, creating it when it is new.
    func animalID(code: String, in experimentID: UUID) -> UUID? {
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, let e = experiment(experimentID) else { return nil }
        if let a = e.animal(code: c) { return a.id }
        let a = Animal(code: c)
        updateExperiment(experimentID) { $0.animals.append(a) }
        return a.id
    }

    /// Allocates an animal to the group with this label (nothing when the label is not a group).
    func allocate(animal id: UUID, in eid: UUID, group label: String) {
        guard let e = experiment(eid), let cell = e.cells.first(where: { $0.joined(separator: " · ") == label }) else { return }
        let active = e.activeFactors
        updateExperiment(eid) { e in
            guard let i = e.animals.firstIndex(where: { $0.id == id }) else { return }
            for (f, level) in zip(active, cell) { e.animals[i].levels[f.id.uuidString] = level }
        }
    }

    /// Adds a group to a task with at most one factor (creates the factor "Group" when there is none).
    func addGroup(_ name: String, to eid: UUID) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let e = experiment(eid), e.factors.count <= 1 else { return }
        editTask(eid) { e in
            if e.factors.isEmpty { e.factors = [DesignFactor(name: "Group", levels: [])] }
            if !e.factors[0].levels.contains(n) { e.factors[0].levels.append(n) }
        }
    }

    /// Renames a group; its animals keep their allocation.
    func renameGroup(_ old: String, to new: String, in eid: UUID) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old, let e = experiment(eid), e.factors.count == 1,
              e.factors[0].levels.contains(old), !e.factors[0].levels.contains(n) else { return }
        let key = e.factors[0].id.uuidString
        editTask(eid) { e in
            if let i = e.factors[0].levels.firstIndex(of: old) { e.factors[0].levels[i] = n }
            for j in e.animals.indices where e.animals[j].levels[key] == old { e.animals[j].levels[key] = n }
        }
    }

    /// Removes a group; its animals become not allocated (their videos stay in the task).
    func removeGroup(_ name: String, from eid: UUID) {
        guard let e = experiment(eid), e.factors.count == 1 else { return }
        backupBeforeChange(MetadataBackup.Reason.beforeBulk)
        let key = e.factors[0].id.uuidString
        editTask(eid) { e in
            e.factors[0].levels.removeAll { $0 == name }
            for j in e.animals.indices where e.animals[j].levels[key] == name { e.animals[j].levels[key] = nil }
            if e.factors[0].levels.isEmpty { e.factors = [] }
        }
    }

    /// Creates the new animals of an import and their groups in one change of the study (the first
    /// group given for an animal wins; animals already in the study keep theirs).
    func prepareAnimals(_ items: [(code: String, group: String)], in eid: UUID) {
        guard let e = experiment(eid) else { return }
        var seen = Set<String>()
        var fresh: [(String, String)] = []
        for item in items {
            let c = item.code.trimmingCharacters(in: .whitespaces)
            let key = c.lowercased()
            guard !c.isEmpty, e.animal(code: c) == nil, seen.insert(key).inserted else { continue }
            fresh.append((c, item.group))
        }
        guard !fresh.isEmpty else { return }
        let active = e.activeFactors
        let cells = e.cells
        updateExperiment(eid) { x in
            for (code, group) in fresh {
                var a = Animal(code: code)
                if !x.blinded, let cell = cells.first(where: { $0.joined(separator: " · ") == group }) {
                    for (f, level) in zip(active, cell) { a.levels[f.id.uuidString] = level }
                }
                x.animals.append(a)
            }
        }
    }

    /// Group of a video in its task ("" = none, or hidden while the task is blinded).
    func taskGroup(_ r: Recording) -> String {
        guard let e = experiment(for: r), !e.blinded, let a = e.animal(r.animalID) else { return "" }
        return e.groupLabel(a)
    }

    /// Puts an animal in a group of a single-factor task (adding the group when it is new). An animal
    /// that already has a group keeps it unless `replace`.
    func setGroup(_ group: String, animal id: UUID, in experimentID: UUID, replace: Bool = false) {
        let g = group.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, let e = experiment(experimentID), e.factors.count <= 1, let a = e.animal(id) else { return }
        if !replace, let f = e.factors.first, a.level(f) != nil { return }
        updateExperiment(experimentID) { x in
            if x.factors.isEmpty { x.factors = [DesignFactor(name: "Group", levels: [])] }
            let level = x.factors[0].levels.first { $0.compare(g, options: .caseInsensitive) == .orderedSame } ?? g
            if !x.factors[0].levels.contains(level) { x.factors[0].levels.append(level) }
            if let i = x.animals.firstIndex(where: { $0.id == id }) { x.animals[i].levels[x.factors[0].id.uuidString] = level }
        }
    }

    /// Moves recordings into a study (or out of any study with nil), keeping the animal code (and,
    /// when leaving a study that is not blinded, the animal's group as text).
    func moveStudy(_ ids: Set<UUID>, toStudy experimentID: UUID?) {
        for id in ids {
            guard let r = recording(id), r.experimentID != experimentID || experimentID == nil else { continue }
            let old = experiment(for: r)
            let animal = old?.animal(r.animalID)
            let code = animal?.code ?? r.subject
            let group = (old?.blinded == false ? animal.map { old!.groupLabel($0) } : nil) ?? r.group
            updateRecording(id) { r in
                r.experimentID = experimentID
                r.animalID = nil
                r.subject = code
                if experimentID == nil { r.group = group }
            }
            if let eid = experimentID, let aid = animalID(code: code, in: eid) {
                updateRecording(id) { $0.animalID = aid }
            }
        }
    }

    /// Puts videos into a task. A video joins the task's study (its animal matched by ID; the group it
    /// carries becomes the animal's group when the animal has none) and gets the task's session. A
    /// video belongs to one study: its sessions of other paradigms belonged to tasks of its old study
    /// and go to Recently Deleted (one entry). Within one study, `source` names the task the videos
    /// leave (its sessions go to Recently Deleted). The result undoes it all (`undoMove`).
    @discardableResult
    func moveToTask(_ ids: Set<UUID>, task t: TaskRef, from source: TaskRef? = nil) -> TaskMove {
        var m = TaskMove(ids: ids)
        guard let target = experiment(t.experimentID) else { return m }
        if ids.count > 5 { backupBeforeChange(MetadataBackup.Reason.beforeBulk) }
        var remove = Set<UUID>()
        var joining = Set<UUID>()
        for id in ids {
            guard let r = recording(id) else { continue }
            m.previousStudy[id] = r.experimentID
            if r.experimentID == t.experimentID {
                if let source, source.experimentID == t.experimentID, source.assay != t.assay {
                    for s in sessions(of: id) where s.assay == source.assay { remove.insert(s.id) }
                }
            } else {
                for s in sessions(of: id) where s.assay != t.assay { remove.insert(s.id) }
                joining.insert(id)
            }
        }
        // The group each joining video carries: its animal's group in its old task (not while that
        // task is blinded), or the group kept as text by a video outside any task.
        var carried: [UUID: String] = [:]
        for id in joining {
            guard let r = recording(id) else { continue }
            let inStudy = r.experimentID.flatMap { experiment($0) } != nil
            let g = inStudy ? taskGroup(r) : r.group
            if !g.trimmingCharacters(in: .whitespaces).isEmpty { carried[id] = g }
        }
        if !remove.isEmpty { m.removedEntry = delete(remove) }
        if !joining.isEmpty {
            moveStudy(joining, toStudy: t.experimentID)
            if !target.blinded && target.factors.count <= 1 {
                for (id, g) in carried {
                    if let aid = recording(id)?.animalID { setGroup(g, animal: aid, in: t.experimentID) }
                }
            }
        }
        for id in ids where recording(id) != nil {
            m.createdSessions.formUnion(assign([t.assay], to: id).map(\.id))
        }
        flush()
        return m
    }

    /// Takes videos out of a task (or, with nil, out of every task of their study): those sessions go
    /// to Recently Deleted (one entry), and a video left with no session in its study leaves the study
    /// (it is then listed under "Not in a task", its animal ID and group kept as text).
    @discardableResult
    func removeFromTask(_ recordingIDs: Set<UUID>, task t: TaskRef?) -> TaskMove {
        var m = TaskMove(ids: [])
        var remove = Set<UUID>()
        var leaving = Set<UUID>()
        for id in recordingIDs {
            guard let r = recording(id), let eid = r.experimentID else { continue }
            if let t, eid != t.experimentID { continue }
            m.ids.insert(id)
            m.previousStudy[id] = eid
            let mine = sessions(of: id)
            let gone = mine.filter { s in t.map { s.assay == $0.assay } ?? true }
            remove.formUnion(gone.map(\.id))
            if gone.count == mine.count { leaving.insert(id) }
        }
        if !remove.isEmpty { m.removedEntry = delete(remove) }
        if !leaving.isEmpty { moveStudy(leaving, toStudy: nil) }
        m.left = leaving
        flush()
        return m
    }

    /// Undoes a move or a removal: new sessions are erased, the videos go back to their studies and
    /// the removed sessions come back from Recently Deleted.
    func undoMove(_ m: TaskMove) async {
        if !m.createdSessions.isEmpty, let e = delete(m.createdSessions) { await eraseDeleted(e) }
        var byStudy: [UUID?: Set<UUID>] = [:]
        for id in m.ids where recording(id) != nil {
            let before = m.previousStudy[id] ?? nil
            if recording(id)?.experimentID != before { byStudy[before, default: []].insert(id) }
        }
        for (study, ids) in byStudy { moveStudy(ids, toStudy: study.flatMap { experiment($0) != nil ? $0 : nil }) }
        if let entry = m.removedEntry { _ = await restoreDeleted(entry) }
        flush()
    }

    /// Removes a study. Its videos stay (outside any task) with the animal code and group kept as
    /// text, unless `deleteVideos` is set. Everything goes to Recently Deleted (restorable for 30
    /// days; the videos rejoin the study when it is restored). Returns the Recently Deleted entry.
    @discardableResult
    func deleteExperiment(_ id: UUID, deleteVideos: Bool) -> UUID? {
        guard let e = experiment(id) else { return nil }
        backupBeforeChange(MetadataBackup.Reason.beforeDelete)
        flush()
        let recs = recordings(in: id)
        var entry = DeletedEntry(kind: .study)
        entry.studyID = id
        entry.studyName = e.name
        if deleteVideos {
            let recIDs = Set(recs.map(\.id))
            entry.names = recs.prefix(50).map { displayName($0) }
            let analyses = forgetAnalyses(Set(sessions.filter { s in s.recordingID.map { recIDs.contains($0) } ?? false }.map(\.id)))
            forgetRecordings(recIDs)
            entry.recordingIDs = recs.map(\.id)
            entry.sessionIDs = analyses
            entry.items = recs.map { "Recordings/\($0.id.uuidString)" } + analyses.map { "Sessions/\($0.uuidString)" }
        } else {
            for r in recs {
                entry.detached.append(DeletedEntry.Link(recordingID: r.id, animalID: r.animalID, subject: r.subject, group: r.group,
                                                        decision: r.decision, exclusionReason: r.exclusionReason))
                updateRecording(r.id) { r in
                    if let a = e.animal(r.animalID) {
                        r.subject = a.code
                        r.group = e.groupLabel(a)
                    }
                    r.experimentID = nil
                    r.animalID = nil
                }
            }
            flush()
        }
        experiments.removeAll { $0.id == id }
        experimentIndexValid = false
        dirtyExperiments.remove(id)
        entry.items.append("Experiments/\(id.uuidString).json")
        trash(entry)
        return entry.id
    }

    /// What deleting a task will do (for its confirmation).
    func deletionPlan(_ t: TaskRef) -> TaskDeletionPlan {
        let all = tasks(of: t.experimentID)
        return TaskDeletionPlan(wholeStudy: all.allSatisfy { $0.assay == t.assay },
                                videos: recordings(in: t.experimentID).count, sessions: sessions(in: t).count)
    }

    /// Deletes a task. A study holding only this task is deleted (its videos too, unless
    /// `keepVideos`); a study with other tasks (1.0–1.3) loses this paradigm: its sessions go to
    /// Recently Deleted and videos left without a session move to "Not in a task". The result undoes it.
    @discardableResult
    func deleteTask(_ t: TaskRef, keepVideos: Bool) -> TaskDeletion {
        guard let e = experiment(t.experimentID) else { return TaskDeletion() }
        let others = tasks(of: t.experimentID).filter { $0.assay != t.assay }
        if others.isEmpty {
            return TaskDeletion(entry: deleteExperiment(t.experimentID, deleteVideos: !keepVideos))
        }
        backupBeforeChange(MetadataBackup.Reason.beforeDelete)
        let ids = Set(sessions(in: t).compactMap(\.recordingID))
        let index = e.plannedAssays.firstIndex(of: t.assay)
        updateExperiment(t.experimentID) { $0.plannedAssays.removeAll { $0 == t.assay } }
        let m = removeFromTask(ids, task: t)
        return TaskDeletion(move: m, unplanned: index == nil ? nil : t, unplannedIndex: index)
    }

    /// Undoes `deleteTask`.
    func undoDeleteTask(_ d: TaskDeletion) async {
        if let entry = d.entry { _ = await restoreDeleted(entry) }
        if let t = d.unplanned {
            updateExperiment(t.experimentID) { x in
                guard !x.plannedAssays.contains(t.assay) else { return }
                x.plannedAssays.insert(t.assay, at: min(d.unplannedIndex ?? x.plannedAssays.count, x.plannedAssays.count))
            }
        }
        if let m = d.move { await undoMove(m) }
        flush()
    }

    // MARK: Deleting

    /// Deletes analyses only (the videos stay). They go to Recently Deleted; returns its entry.
    @discardableResult
    func delete(_ ids: Set<UUID>) -> UUID? {
        let present = sessions.filter { ids.contains($0.id) }
        guard !present.isEmpty else { return nil }
        flush()
        var entry = DeletedEntry(kind: .analyses)
        entry.names = present.prefix(50).map { s in recording(for: s).map { displayName($0) + " · " + s.assay.name.en } ?? s.displayName }
        entry.sessionIDs = forgetAnalyses(Set(present.map(\.id)))
        entry.items = entry.sessionIDs.map { "Sessions/\($0.uuidString)" }
        trash(entry)
        return entry.id
    }

    /// Deletes videos with their pose, QC and every analysis made from them. Everything goes to
    /// Recently Deleted; returns its entry.
    @discardableResult
    func deleteRecordings(_ ids: Set<UUID>) -> UUID? {
        let present = recordings.filter { ids.contains($0.id) }
        guard !present.isEmpty else { return nil }
        backupBeforeChange(MetadataBackup.Reason.beforeDelete)
        flush()
        let recIDs = Set(present.map(\.id))
        var entry = DeletedEntry(kind: .videos)
        entry.names = present.prefix(50).map { displayName($0) }
        entry.sessionIDs = forgetAnalyses(Set(sessions.filter { s in s.recordingID.map { recIDs.contains($0) } ?? false }.map(\.id)))
        forgetRecordings(recIDs)
        entry.recordingIDs = present.map(\.id)
        entry.items = present.map { "Recordings/\($0.id.uuidString)" } + entry.sessionIDs.map { "Sessions/\($0.uuidString)" }
        trash(entry)
        return entry.id
    }

    /// Drops analyses from memory (no disk work). Returns the ids that existed.
    private func forgetAnalyses(_ ids: Set<UUID>) -> [UUID] {
        let present = sessions.filter { ids.contains($0.id) }.map(\.id)
        for id in ids {
            dirty.remove(id)
            debounceTasks[id]?.cancel()
            debounceTasks[id] = nil
            analysisQueue.removeAll { $0 == id }
            backgroundAnalyses.remove(id)
            results[id] = nil
            resultOrder.removeAll { $0 == id }
            unsavedResults[id] = nil
        }
        if !present.isEmpty {
            sessions.removeAll { ids.contains($0.id) }
            sessionIndexValid = false
        }
        return present
    }

    /// Drops video records from memory (no disk work).
    private func forgetRecordings(_ ids: Set<UUID>) {
        for id in ids {
            dirtyRecordings.remove(id)
            dirtySidecars.remove(id)
            qcQueue.removeAll { $0 == id }
            poseCache[id] = nil
            poseOrder.removeAll { $0 == id }
            sidecars[id] = nil
        }
        recordings.removeAll { ids.contains($0.id) }
        recordingIndexValid = false
    }

    /// Moves an entry's folders into Recently Deleted, after every write issued before it (so a
    /// pending write cannot recreate a folder and bring the item back on the next launch).
    private func trash(_ entry: DeletedEntry) {
        let base = self.base
        enqueueIO {
            RecentlyDeleted.move(entry, base: base)
            Task { @MainActor [weak self] in self?.recentlyDeletedVersion += 1 }
        }
    }

    // MARK: Recently Deleted

    /// Entries in Recently Deleted, newest first (after pending moves have finished).
    func recentlyDeleted() async -> [DeletedEntry] {
        let base = self.base
        return await performIO { RecentlyDeleted.list(base) }
    }

    /// Erases one entry for good.
    func eraseDeleted(_ id: UUID) async {
        let base = self.base
        await performIO { RecentlyDeleted.erase(id, base: base) }
        recentlyDeletedVersion += 1
    }

    /// Erases everything in Recently Deleted.
    func emptyRecentlyDeleted() async {
        let base = self.base
        await performIO { RecentlyDeleted.eraseAll(base) }
        recentlyDeletedVersion += 1
    }

    private func purgeRecentlyDeleted() async {
        let base = self.base
        let n = await performIO { RecentlyDeleted.purge(base) }
        if n > 0 { recentlyDeletedVersion += 1 }
    }

    private struct RestoredItems: Sendable {
        var experiments: [Experiment] = []
        var recordings: [Recording] = []
        var repaired: Set<UUID> = []
        var sidecars: [UUID: RecordingSidecar] = [:]
        var sessions: [Session] = []
    }

    /// Puts an entry back into the library. Returns a message for the user.
    func restoreDeleted(_ entryID: UUID) async -> String {
        flush()
        let base = self.base
        guard let out = await performIO({ RecentlyDeleted.restore(entryID, base: base) }) else {
            return L("This item is no longer in Recently Deleted.", "该项目已不在“最近删除”中。")
        }
        let paths = out.restored
        let items = await performIO { SessionStore.readRestored(paths, base: base) }
        // Studies first (videos refer to them), then videos, then analyses.
        for e in items.experiments where experiment(e.id) == nil {
            experiments.append(e)
        }
        experiments.sort { $0.createdAt > $1.createdAt }
        experimentIndexValid = false
        for r in items.recordings where recording(r.id) == nil {
            recordings.append(r)
            if let car = items.sidecars[r.id] { sidecars[r.id] = car }
            if items.repaired.contains(r.id) { dirtyRecordings.insert(r.id) }
        }
        recordings.sort { $0.createdAt > $1.createdAt }
        recordingIndexValid = false
        for var s in items.sessions where session(s.id) == nil {
            let before = s
            if let r = recording(s.recordingID) { sync(&s, with: r) }
            sessions.append(s)
            if s != before { dirty.insert(s.id) }
        }
        sessions.sort { $0.createdAt > $1.createdAt }
        sessionIndexValid = false
        // A restored study takes back the videos that only left it.
        if let sid = out.entry.studyID, experiment(sid) != nil {
            for link in out.entry.detached {
                guard let r = recording(link.recordingID), r.experimentID == nil else { continue }
                updateRecording(r.id) {
                    $0.experimentID = sid
                    $0.animalID = link.animalID
                    $0.subject = link.subject
                    $0.group = link.group
                    // The decision made in the study comes back with it.
                    if let d = link.decision { $0.decision = d }
                    if let why = link.exclusionReason { $0.exclusionReason = why }
                }
            }
        }
        for r in items.recordings where r.hasPose && r.qc == nil { enqueueQC(r.id) }
        flush()
        recentlyDeletedVersion += 1
        if out.conflicts.isEmpty {
            return String(format: L("Restored: %@", "已恢复：%@"), out.entry.title)
        }
        return String(format: L("Restored %d item(s); %d could not be put back because the library already has an item with the same id.",
                                "已恢复 %d 项；%d 项因资料库中已有相同 id 的项目而未能放回。"), out.restored.count, out.conflicts.count)
    }

    /// Reads restored files (same rules as loading the library).
    nonisolated private static func readRestored(_ paths: [String], base: URL) -> RestoredItems {
        var out = RestoredItems()
        let decoder = Coders.decoder()
        for rel in paths {
            let url = base.appendingPathComponent(rel)
            if rel.hasPrefix("Experiments/") {
                if let d = try? Data(contentsOf: url), let e = try? decoder.decode(Experiment.self, from: d) { out.experiments.append(e) }
            } else if rel.hasPrefix("Recordings/") {
                var r: Recording
                if let d = try? Data(contentsOf: url.appendingPathComponent("recording.json")),
                   let decoded = try? decoder.decode(Recording.self, from: d) {
                    r = decoded
                } else if let id = UUID(uuidString: url.lastPathComponent),
                          let video = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
                            .first(where: { $0.hasPrefix("video.") }) {
                    // An import interrupted before recording.json was written: the video comes back as a
                    // new video outside any task, waiting to be tracked.
                    r = Recording(videoFile: video, originalName: video)
                    r.id = id
                    out.repaired.insert(id)
                } else {
                    continue
                }
                if r.status == .processing { r.status = .queued; out.repaired.insert(r.id) }
                if r.hasPose && !PoseStorage.exists(folder: url) {
                    r.hasPose = false
                    r.status = .queued
                    out.repaired.insert(r.id)
                }
                if let car = RecordingSidecar.load(folder: url) { out.sidecars[r.id] = car }
                out.recordings.append(r)
            } else if rel.hasPrefix("Sessions/") {
                if let d = try? Data(contentsOf: url.appendingPathComponent("session.json")),
                   let s = try? decoder.decode(Session.self, from: d) { out.sessions.append(s) }
            }
        }
        return out
    }

    // MARK: Metadata backups

    func metadataSnapshot(reason: String) -> MetadataSnapshot {
        MetadataSnapshot(reason: reason, appVersion: AppInfo.version, experiments: experiments, recordings: recordings, sessions: sessions)
    }

    /// Writes a backup of the tasks, video records and analysis settings (off the main thread).
    func backup(_ reason: String) {
        guard !(recordings.isEmpty && experiments.isEmpty && sessions.isEmpty) else { return }
        let snap = metadataSnapshot(reason: reason)
        let base = self.base
        enqueueIO { _ = try? MetadataBackup.write(snap, base: base) }
    }

    /// A backup before a delete or a bulk change — at most one every 10 minutes (Recently Deleted
    /// keeps the deleted items themselves).
    func backupBeforeChange(_ reason: String) {
        if let last = lastChangeBackup, Date().timeIntervalSince(last) < 600 { return }
        lastChangeBackup = Date()
        backup(reason)
    }

    /// Today's backup, if the newest daily one is older than 20 hours.
    func dailyBackupIfNeeded() async {
        guard !(recordings.isEmpty && experiments.isEmpty && sessions.isEmpty) else { return }
        let base = self.base
        let last = await performIO { MetadataBackup.latest(base, reason: MetadataBackup.Reason.daily)?.createdAt }
        if let last, Date().timeIntervalSince(last) < 20 * 3600 { return }
        backup(MetadataBackup.Reason.daily)
    }

    func backups() async -> [BackupInfo] {
        let base = self.base
        return await performIO { MetadataBackup.list(base) }
    }

    /// Restores the tasks, the design information and decisions of the videos, and the settings and
    /// labels of the analyses from a backup. Tracking and QC are never touched, nothing is deleted,
    /// and the current state is backed up first (so a restore can itself be undone).
    func restoreBackup(_ url: URL) async -> String {
        let loaded: MetadataSnapshot? = await performIO { try? MetadataBackup.load(url) }
        guard let snap = loaded else {
            return L("This backup could not be read.", "无法读取该备份。")
        }
        backup(MetadataBackup.Reason.beforeRestore)
        var studies = 0, videos = 0, analyses = 0
        for e in snap.experiments {
            if let cur = experiment(e.id) {
                if cur != e { updateExperiment(e.id) { $0 = e }; studies += 1 }
            } else {
                saveExperiment(e)
                studies += 1
            }
        }
        for b in snap.recordings {
            guard let cur = recording(b.id), cur.status != .processing else { continue }
            var n = cur
            n.experimentID = b.experimentID.flatMap { experiment($0) != nil ? $0 : nil }
            n.animalID = n.experimentID == nil ? nil : b.animalID
            n.subject = b.subject
            n.group = b.group
            n.timepoint = b.timepoint
            n.trial = b.trial
            n.recordedOn = b.recordedOn
            n.notes = b.notes
            n.decision = b.decision
            n.exclusionReason = b.exclusionReason
            n.plannedAssays = b.plannedAssays
            if n != cur {
                updateRecording(b.id) { $0 = n }
                videos += 1
            }
        }
        for b in snap.sessions {
            if let cur = session(b.id) {
                var n = cur
                n.calibration = b.calibration
                n.params = b.params
                n.overrides = b.overrides
                n.eventOverrides = b.eventOverrides
                if n != cur {
                    save(n)
                    analyze(b.id, background: true)
                    analyses += 1
                }
            } else if let rid = b.recordingID, let r = recording(rid) {
                // Deleted since the backup while its video is still here: made again (results are recomputed).
                var n = b
                sync(&n, with: r)
                save(n)
                if n.hasPose { analyze(n.id, background: true) }
                analyses += 1
            }
        }
        flush()
        return String(format: L("Backup restored: %d tasks, %d videos and %d analyses changed. The state before the restore was backed up.",
                                "备份已恢复：更改了 %d 个任务、%d 段视频和 %d 个分析。恢复前的状态已另行备份。"), studies, videos, analyses)
    }

    // MARK: Import

    /// Moves (or copies) a picked video into a new recording folder, off the main thread. `move`
    /// is used for the app's own temporary copies: a rename is instant and needs no extra space.
    /// With a task, the animal is matched to (or added to) the task, a new animal is allocated to
    /// `group`, and the task's session is created at once.
    func importVideo(from url: URL, move: Bool, task: TaskRef?, animalCode: String, group: String, timepoint: String,
                     trial: Int = 1, notes: String, model: PoseModelID, fingerprint: VideoFingerprint.Info?) async throws -> Recording {
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        var r = Recording(videoFile: "video." + ext, originalName: url.lastPathComponent)
        r.notes = notes
        r.timepoint = timepoint
        r.trial = max(1, trial)
        let code = animalCode.trimmingCharacters(in: .whitespaces)
        let dir = recordingFolder(r.id)
        let dest = videoURL(r)
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                if move, (try? fm.moveItem(at: url, to: dest)) != nil { return }
                try fm.copyItem(at: url, to: dest)
            } catch {
                try? fm.removeItem(at: dir)
                throw error
            }
        }.value
        if let t = task, let e = experiment(t.experimentID) {
            r.experimentID = e.id
            let existed = e.animal(code: code) != nil
            r.animalID = animalID(code: code, in: e.id)
            if r.animalID == nil { r.subject = code }
            // Animals already in the task keep their group.
            if let aid = r.animalID, !existed, !group.isEmpty { allocate(animal: aid, in: e.id, group: group) }
        } else {
            r.subject = code
            r.group = group
        }
        var car = RecordingSidecar(fileName: url.lastPathComponent, poseModel: model.runnable)
        car.path = dest.path
        if let fp = fingerprint {
            car.size = fp.size
            car.modified = fp.modified
            car.fingerprint = fp.fingerprint
        }
        sidecars[r.id] = car
        dirtySidecars.insert(r.id)
        saveRecording(r)
        if let t = task { assign([t.assay], to: r.id) }
        // Each added video is on disk before the next one is copied (a crash mid-batch keeps it).
        flush()
        return r
    }

    /// Group names typed for videos outside any task (1.3).
    var knownGroups: [String] {
        var seen = Set<String>(), out: [String] = []
        for r in recordings where r.experimentID == nil && !r.group.isEmpty && !seen.contains(r.group) {
            seen.insert(r.group); out.append(r.group)
        }
        return out
    }

    /// Fingerprints of videos added before 1.4 (for duplicate detection), read off the main thread.
    private func backfillFingerprints() async {
        let todo = recordings.filter { sidecars[$0.id]?.fingerprint.isEmpty ?? true }.map { ($0.id, videoURL($0)) }
        guard !todo.isEmpty else { return }
        let found = await Task.detached(priority: .background) { () -> [UUID: VideoFingerprint.Info] in
            var out: [UUID: VideoFingerprint.Info] = [:]
            for (id, url) in todo { if let fp = try? VideoFingerprint.make(url) { out[id] = fp } }
            return out
        }.value
        for (id, fp) in found where recording(id) != nil {
            updateSidecar(id) { c in
                c.size = fp.size
                c.modified = fp.modified
                c.fingerprint = fp.fingerprint
                if c.fileName.isEmpty { c.fileName = recording(id)?.originalName ?? "" }
            }
        }
    }

    // MARK: Pose detection (called by ProcessingQueue)

    func nextQueuedRecording() -> Recording? {
        // Oldest first, so batches finish in import order.
        recordings.filter { $0.status == .queued }.min { $0.createdAt < $1.createdAt }
    }

    /// Recordings waiting for the pose model, in the order they will run.
    var queuedRecordings: [Recording] {
        recordings.filter { $0.status == .queued }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Detection finished: save the pose, record the model, compute QC, then (re-)analyse every
    /// session of this video.
    func finishProcessing(_ id: UUID, track: PoseTrack, skeleton: Bool) async throws {
        try await storePose(track, recording: id)
        updateRecording(id) {
            $0.hasPose = true
            $0.hasSkeletonVideo = skeleton
            $0.videoWidth = track.width
            $0.videoHeight = track.height
            $0.fps = track.fps
            $0.duration = track.duration
            $0.modelVersion = track.modelVersion
            $0.status = .ready
            $0.failure = nil
        }
        if let m = PoseModelID(modelName: track.modelName) { updateSidecar(id) { $0.poseModel = m } }
        await computeQC(id, track: track, autoInclude: true)
        for s in sessions(of: id) { analyze(s.id, background: true) }
    }

    /// Re-runs detection for a video (all its analyses wait for the new pose), optionally with
    /// another pose model (nil = the video's model; CylinderMousePoseV2 videos use FP16).
    func rerunDetection(_ id: UUID, model: PoseModelID? = nil) {
        poseCache[id] = nil
        poseOrder.removeAll { $0 == id }
        if let model { updateSidecar(id) { $0.poseModel = model.runnable } }
        updateRecording(id) { $0.hasPose = false; $0.status = .queued; $0.failure = nil }
        flush()
    }

    // MARK: Quality control

    /// Computes (or recomputes) the QC report of a recording and applies the task's criteria. Only
    /// the first report of a tracking (after the model ran, or for a video that never had one)
    /// includes a passing video automatically; a later check (criteria changed, video joined a task)
    /// updates the report and leaves the decision to the reviewer.
    func computeQC(_ id: UUID, track: PoseTrack? = nil, autoInclude: Bool? = nil) async {
        guard let r = recording(id), r.hasPose else { return }
        let include = autoInclude ?? (r.qc == nil)
        let criteria = experiment(for: r)?.qc ?? QCCriteria()
        var loaded = track
        if loaded == nil { loaded = await recordingPose(id) }
        guard let t = loaded else { return }
        let report = await Task.detached(priority: .utility) { QualityControl.report(track: t, criteria: criteria) }.value
        updateRecording(id) { r in
            r.qc = report
            // A video that meets every criterion is included automatically; anything else waits
            // for a reviewer's decision.
            if include && r.decision == .pending && report.verdict == .pass { r.decision = .included }
        }
        assignPlannedIfIncluded(id)
    }

    private func assignPlannedIfIncluded(_ id: UUID) {
        guard let r = recording(id), r.decision == .included, r.hasPose, !r.plannedAssays.isEmpty else { return }
        let planned = r.plannedAssays
        assign(planned, to: id)
        updateRecording(id) { $0.plannedAssays = [] }
    }

    /// Include / exclude a video (a review decision: written at once).
    func setDecision(_ id: UUID, _ decision: InclusionDecision, reason: String = "") {
        updateRecording(id) {
            $0.decision = decision
            $0.exclusionReason = decision == .excluded ? reason : ""
        }
        assignPlannedIfIncluded(id)
        flush()
    }

    func setDecision(_ ids: Set<UUID>, _ decision: InclusionDecision, reason: String = "") {
        if ids.count > 5 { backupBeforeChange(MetadataBackup.Reason.beforeBulk) }
        for id in ids {
            updateRecording(id) {
                $0.decision = decision
                $0.exclusionReason = decision == .excluded ? reason : ""
            }
            assignPlannedIfIncluded(id)
        }
        flush()
    }

    private func recomputeQC(experiment id: UUID) {
        for r in recordings where r.experimentID == id && r.hasPose { enqueueQC(r.id) }
    }

    private func backfillQC() {
        for r in recordings where r.hasPose && r.qc == nil { enqueueQC(r.id) }
    }

    private func enqueueQC(_ id: UUID) {
        if !qcQueue.contains(id) { qcQueue.append(id) }
        guard qcWorker == nil else { return }
        qcWorker = Task { [weak self] in
            while let self, !self.qcQueue.isEmpty {
                let next = self.qcQueue.removeFirst()
                await self.computeQC(next)
            }
            self?.qcWorker = nil
        }
    }

    // MARK: Sessions

    /// Creates the session of each paradigm the recording does not have yet. Parameters and
    /// calibration start from the latest session of the same task (same study and paradigm) —
    /// never from another task. Videos outside any task start from the defaults.
    @discardableResult
    func assign(_ assays: [Assay], to recordingID: UUID) -> [Session] {
        guard let r = recording(recordingID) else { return [] }
        let existing = Set(sessions(of: recordingID).map(\.assay))
        var created: [Session] = []
        for a in assays where !existing.contains(a) {
            var s = Session(recording: r, assay: a)
            let peer = r.experimentID == nil ? nil
                : sessions.first { $0.assay == a && $0.recordingID != recordingID && recording(for: $0)?.experimentID == r.experimentID }
            if let prev = peer {
                // Task-wide settings are copied; the injection time and paw belong to each video.
                let fresh = s.params
                s.params = prev.params
                s.params.keepPerAnimal(from: fresh)
                if prev.calibration.circle != nil || prev.calibration.floorY != nil || prev.calibration.scale != nil {
                    s.calibration = prev.calibration
                    s.calibration.copiedFrom = prev.displayName
                }
            }
            sync(&s, with: r)
            save(s)
            created.append(s)
            if s.hasPose { analyze(s.id, background: true) }
        }
        return created
    }

    /// Copies parameters (and optionally calibration) of one session to the other sessions of its
    /// task. Each video keeps its own injection time, injected paw and lesioned side.
    @discardableResult
    func applyToTask(from sourceID: UUID, params: AssayParams? = nil, calibration: Calibration? = nil) -> Int {
        guard let src = session(sourceID) else { return 0 }
        let peers = taskPeers(of: sourceID)
        if peers.count > 1 { backupBeforeChange(MetadataBackup.Reason.beforeBulk) }
        for other in peers {
            update(other.id) { o in
                if let p = params {
                    let mine = o.params
                    o.params = p
                    o.params.cylinder.lesion = mine.cylinder.lesion
                    o.params.keepPerAnimal(from: mine)
                }
                if var c = calibration {
                    c.copiedFrom = src.displayName
                    o.calibration = c
                }
            }
            if other.hasPose { analyze(other.id, background: true) }
        }
        flush()
        return peers.count
    }

    // MARK: Pose

    /// Saves a new pose track of a recording (encoding and writing happen off the main thread).
    func storePose(_ track: PoseTrack, recording id: UUID) async throws {
        let dir = recordingFolder(id)
        try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: dir.path) else { throw CocoaError(.fileNoSuchFile) }
            try PoseStorage.save(track, folder: dir)
        }.value
        cachePose(track, id)
    }

    private func cachePose(_ t: PoseTrack, _ id: UUID) {
        poseCache[id] = t
        poseOrder.removeAll { $0 == id }
        poseOrder.append(id)
        while poseOrder.count > Self.maxCachedPoses { poseCache[poseOrder.removeFirst()] = nil }
    }

    /// Pose track of an analysis (its recording's track).
    func pose(_ sessionID: UUID) async -> PoseTrack? {
        await recordingPose(session(sessionID)?.recordingID ?? sessionID)
    }

    /// Pose track of a recording, from the cache or loaded off the main thread. Concurrent
    /// requests share one load.
    func recordingPose(_ id: UUID) async -> PoseTrack? {
        if let t = poseCache[id] {
            poseOrder.removeAll { $0 == id }
            poseOrder.append(id)
            return t
        }
        if let running = poseLoads[id] { return await running.value }
        let dir = recordingFolder(id)
        let video = recording(id).map { videoURL($0) }
        let task = Task.detached(priority: .userInitiated) { () async -> PoseTrack? in
            guard var t = PoseStorage.load(folder: dir) else { return nil }
            if t.timeOffset == nil {
                // Tracks made by 1.0–1.1: find the first frame's time once and save it.
                var offset = 0.0
                if let video, let first = await PoseVideoProcessor.firstFrameTime(url: video) { offset = first }
                t.timeOffset = offset
                try? PoseStorage.save(t, folder: dir)
            }
            return t
        }
        poseLoads[id] = task
        let loaded = await task.value
        poseLoads[id] = nil
        if let loaded, recording(id) != nil { cachePose(loaded, id) }
        return loaded
    }

    // MARK: Results

    /// Returns the cached result, loading it from disk into the cache if needed (off the main
    /// thread: a result JSON can be large).
    func result(_ id: UUID) async -> AnalysisResult? {
        if let r = results[id] { touchResult(id); return r }
        // Analyzed in the background and still being written: newer than the file.
        if let pending = unsavedResults[id]?.result { insertResult(pending, id); return pending }
        let url = resultURL(id)
        let fromDisk = await Task.detached(priority: .userInitiated) { SessionStore.readResult(url) }.value
        // An analysis may have finished meanwhile; it is newer than the file.
        if let r = results[id] { touchResult(id); return r }
        guard let loaded = fromDisk, session(id) != nil else { return nil }
        insertResult(loaded, id)
        return loaded
    }

    nonisolated private static func readResult(_ url: URL) -> AnalysisResult? {
        let decoder = Coders.decoder()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AnalysisResult.self, from: data)
    }

    /// Results for many sessions (group export / comparison), read off the main thread. They are
    /// not added to the cache, so a large export does not keep hundreds of results in memory.
    func loadResults(_ ids: [UUID]) async -> [UUID: AnalysisResult] {
        var out: [UUID: AnalysisResult] = [:]
        var missing: [(UUID, URL)] = []
        for id in ids {
            if let r = results[id] ?? unsavedResults[id]?.result { out[id] = r } else { missing.append((id, resultURL(id))) }
        }
        guard !missing.isEmpty else { return out }
        let toRead = missing
        let read = await Task.detached(priority: .userInitiated) { () -> [UUID: AnalysisResult] in
            var d: [UUID: AnalysisResult] = [:]
            for (id, url) in toRead { if let r = SessionStore.readResult(url) { d[id] = r } }
            return d
        }.value
        for (id, r) in read where out[id] == nil { out[id] = results[id] ?? r }
        return out
    }

    private func touchResult(_ id: UUID) {
        resultOrder.removeAll { $0 == id }
        resultOrder.append(id)
    }

    private func insertResult(_ r: AnalysisResult, _ id: UUID) {
        results[id] = r
        touchResult(id)
        trimResults(keepRecent: 4, limit: Self.maxCachedResults)
    }

    /// Drops results that are already on disk, oldest first, keeping the most recently used.
    private func trimResults(keepRecent: Int, limit: Int) {
        guard resultOrder.count > limit else { return }
        var removable = resultOrder.dropLast(keepRecent).filter { unsavedResults[$0] == nil }
        var count = resultOrder.count
        while count > limit, !removable.isEmpty {
            let id = removable.removeFirst()
            results[id] = nil
            resultOrder.removeAll { $0 == id }
            count -= 1
        }
    }

    /// Re-runs the analysis of a session (its pose must exist). Requests are queued and run one
    /// at a time; a request for a session that is already waiting is merged with it. Requests for
    /// the session on screen go first; `background` ones wait at the end of the queue.
    func analyze(_ id: UUID, debounce: Double = 0, background: Bool = false) {
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
        guard debounce > 0 else {
            enqueueAnalysis(id, background: background)
            return
        }
        debounceTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, debounce) * 1e9))
            guard !Task.isCancelled, let self else { return }
            self.debounceTasks[id] = nil
            self.enqueueAnalysis(id, background: background)
        }
    }

    private func enqueueAnalysis(_ id: UUID, background: Bool) {
        if let i = analysisQueue.firstIndex(of: id) {
            if background { return }        // already waiting
            analysisQueue.remove(at: i)
        }
        if background {
            backgroundAnalyses.insert(id)
            analysisQueue.append(id)
        } else {
            backgroundAnalyses.remove(id)
            analysisQueue.insert(id, at: 0)
        }
        guard analysisWorker == nil else { return }
        analysisWorker = Task { [weak self] in
            while let self, !self.analysisQueue.isEmpty {
                let next = self.analysisQueue.removeFirst()
                await self.runAnalysis(next)
            }
            self?.analysisWorker = nil
        }
    }

    private func runAnalysis(_ id: UUID) async {
        let inBackground = backgroundAnalyses.remove(id) != nil
        guard let s = session(id), s.hasPose, let track = await pose(id) else { return }
        // Use the newest parameters (they may have changed while the pose was loading).
        let input = session(id) ?? s
        let result = await Task.detached(priority: .userInitiated) { Analyzer.run(session: input, track: track) }.value
        // Deleted, or tracking is being re-run: this result no longer applies.
        guard var current = session(id), current.hasPose else { return }
        if !inBackground || results[id] != nil { insertResult(result, id) }
        writeResult(result, id)
        current.summary = Array(result.metrics.filter { $0.highlight }.prefix(3))
        current.worstNote = result.notes.map(\.level).max { Self.rank($0) < Self.rank($1) }
        if current.status != .processing && current.status != .queued && current.status != .failed {
            current.status = current.isCalibrated ? .done : .needsSetup
        }
        save(current)
    }

    private static func rank(_ l: NoteLevel) -> Int { l == .error ? 2 : l == .warning ? 1 : 0 }

    private func writeResult(_ r: AnalysisResult, _ id: UUID) {
        let url = resultURL(id), dir = folder(id)
        resultWriteSerial += 1
        let serial = resultWriteSerial
        unsavedResults[id] = (serial, r)
        enqueueIO {
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
            if let data = try? Coders.encoder().encode(r) {
                try? data.write(to: url, options: .atomic)
            }
            Task { @MainActor in self.resultSaved(id, serial) }
        }
    }

    private func resultSaved(_ id: UUID, _ serial: Int) {
        if unsavedResults[id]?.serial == serial { unsavedResults[id] = nil }
        // The analysis was deleted while its result was being written: remove the stray folder
        // (unless it was moved to Recently Deleted, which happens on this same queue first).
        if session(id) == nil {
            let dir = folder(id)
            enqueueIO {
                let fm = FileManager.default
                // Only a folder that holds nothing but the stray result.
                let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                if contents.allSatisfy({ $0 == "result.json" }) { try? fm.removeItem(at: dir) }
            }
        }
    }

    // MARK: Memory

    /// Called on a memory warning: drop everything that can be reloaded from disk. Screens keep
    /// their own copy of the track they show, and the most recently used results stay.
    func trimMemory() {
        poseCache.removeAll()
        poseOrder.removeAll()
        trimResults(keepRecent: 2, limit: 2)
    }

    // MARK: Storage

    /// Total size of all app data, computed off the main thread.
    func storageBytes() async -> Int64 {
        let base = self.base
        return await Task.detached(priority: .utility) { () -> Int64 in
            guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total: Int64 = 0
            for case let url as URL in e {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }.value
    }
}

/// A short UIKit background-task assertion that is always ended exactly once (by the owner or
/// when iOS says time is up — not ending it in time gets the app terminated).
@MainActor
final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        let ending = id
        id = .invalid
        UIApplication.shared.endBackgroundTask(ending)
    }
}
