// SessionStore.swift — the Mac library: studies, recordings (videos) and analyses on disk.
//
// Same folders and files as the iPhone app (Documents/RodentLimb/), so a library can be copied
// between the two:
//   Experiments/<id>.json            study design, animals, allocation, QC criteria
//   Recordings/<id>/                 recording.json, pose.bin, source.json (Mac: where the video is),
//                                    checkpoint/ (Mac: pose saved while the model runs),
//                                    and the video itself when it was copied into the library
//   Sessions/<id>/                   one analysis (task) of a recording: session.json, result.json
//   Logs/                            activity log of the batch (Mac)
//
// Flow (as on the iPhone): a video is imported as a Recording → the pose model runs once
// (BatchEngine) → a QC report is computed → the video is included or excluded → it is assigned to
// one or more tasks; each task is a Session that shares the recording's pose.
//
// Mac differences: videos are referenced in place by default (VideoSource, security-scoped
// bookmark) instead of being copied; the library can live anywhere; loading happens off the main
// thread; several analyses run at once.
//
// Smoothness / stability rules (kept from the iPhone app):
//  • Nothing heavy runs on the main thread (decoding the library, pose and result files, QC,
//    analyses, copying videos, exports).
//  • Disk writes go through one serial queue in the order they were issued; bursts are coalesced.
//  • A damaged file never stops loading: it is skipped (or repaired) and the rest loads.

import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var recordings: [Recording] = []
    private(set) var experiments: [Experiment] = []
    private(set) var results: [UUID: AnalysisResult] = [:]
    /// Where each recording's video is (Mac sidecar), keyed by recording id.
    private(set) var sources: [UUID: VideoSource] = [:]
    /// Recordings whose video cannot be found right now (drive unplugged, file moved or deleted).
    private(set) var missingVideos: Set<UUID> = []
    /// Analyses waiting for or running an analysis (for spinners in lists).
    private(set) var analysing: Set<UUID> = []
    private(set) var isLoaded = false
    /// Problems found while loading (damaged files that were skipped).
    private(set) var loadWarnings: [String] = []
    /// Changes whenever Recently Deleted changes (lists showing it reload).
    private(set) var recentlyDeletedVersion = 0

    let base: URL
    let root: URL
    let recordingsRoot: URL
    let experimentsRoot: URL
    let logsRoot: URL
    @ObservationIgnored let log: ActivityLog

    // MARK: Caches (not observed)

    @ObservationIgnored private var poseCache: [UUID: PoseTrack] = [:]
    @ObservationIgnored private var poseOrder: [UUID] = []
    @ObservationIgnored private var poseLoads: [UUID: Task<PoseTrack?, Never>] = [:]
    @ObservationIgnored private static let maxCachedPoses = 4

    @ObservationIgnored private var resultOrder: [UUID] = []
    @ObservationIgnored private var unsavedResults: [UUID: (serial: Int, result: AnalysisResult)] = [:]
    @ObservationIgnored private var resultWriteSerial = 0
    @ObservationIgnored private static let maxCachedResults = 48

    @ObservationIgnored private var analysisQueue: [UUID] = []
    @ObservationIgnored private var backgroundAnalyses = Set<UUID>()
    @ObservationIgnored private var analysisWorkers = 0
    @ObservationIgnored private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    /// Analyses that may run at the same time (CPU only, a few seconds each).
    @ObservationIgnored var maxConcurrentAnalyses = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2))

    @ObservationIgnored private var qcQueue: [UUID] = []
    @ObservationIgnored private var qcWorker: Task<Void, Never>?

    @ObservationIgnored private var ioTail: Task<Void, Never>?
    @ObservationIgnored private var resolvedVideos: [UUID: URL] = [:]

    @ObservationIgnored private var dirty = Set<UUID>()
    @ObservationIgnored private var dirtyRecordings = Set<UUID>()
    @ObservationIgnored private var dirtyExperiments = Set<UUID>()
    @ObservationIgnored private var dirtySources = Set<UUID>()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var firstUnsavedChange: Date?
    @ObservationIgnored private var lastChangeBackup: Date?

    // Lookup indexes (id → position). Rebuilt lazily after an insert, sort or removal; an in-place
    // replacement keeps positions. Every hit is verified, so a stale index can never return the
    // wrong item. Tables call these lookups for every row: O(1) instead of a scan.
    @ObservationIgnored private var sessionIndex: [UUID: Int] = [:]
    @ObservationIgnored private var sessionsByRecording: [UUID: [Int]] = [:]
    @ObservationIgnored private var recordingIndex: [UUID: Int] = [:]
    @ObservationIgnored private var experimentIndex: [UUID: Int] = [:]
    @ObservationIgnored private var sessionIndexValid = false
    @ObservationIgnored private var recordingIndexValid = false
    @ObservationIgnored private var experimentIndexValid = false

    /// Called after a recording's pose is ready and its QC is computed (BatchEngine listens).
    @ObservationIgnored var onRecordingChanged: ((UUID) -> Void)?

    init(base: URL) {
        self.base = base
        root = base.appendingPathComponent("Sessions", isDirectory: true)
        recordingsRoot = base.appendingPathComponent("Recordings", isDirectory: true)
        experimentsRoot = base.appendingPathComponent("Experiments", isDirectory: true)
        logsRoot = base.appendingPathComponent("Logs", isDirectory: true)
        log = ActivityLog(folder: logsRoot)
        for d in [root, recordingsRoot, experimentsRoot, logsRoot] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    // MARK: Paths

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func recordingFolder(_ id: UUID) -> URL { recordingsRoot.appendingPathComponent(id.uuidString, isDirectory: true) }
    func checkpointFolder(_ id: UUID) -> URL { recordingFolder(id).appendingPathComponent("checkpoint", isDirectory: true) }
    func resultURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("result.json") }
    func skeletonURL(_ recordingID: UUID) -> URL { recordingFolder(recordingID).appendingPathComponent("skeleton.mp4") }
    private func experimentURL(_ id: UUID) -> URL { experimentsRoot.appendingPathComponent(id.uuidString + ".json") }

    // MARK: Lookups

    func session(_ id: UUID) -> Session? {
        let list = sessions
        if !sessionIndexValid { rebuildSessionIndex() }
        if let i = sessionIndex[id], i < list.count, list[i].id == id { return list[i] }
        guard sessionIndexValid, sessionIndex[id] != nil else { return nil }
        rebuildSessionIndex()
        return sessionIndex[id].flatMap { $0 < list.count && list[$0].id == id ? list[$0] : nil }
    }
    func recording(_ id: UUID?) -> Recording? {
        guard let id else { return nil }
        let list = recordings
        if !recordingIndexValid { rebuildRecordingIndex() }
        if let i = recordingIndex[id], i < list.count, list[i].id == id { return list[i] }
        guard recordingIndex[id] != nil else { return nil }
        rebuildRecordingIndex()
        return recordingIndex[id].flatMap { $0 < list.count && list[$0].id == id ? list[$0] : nil }
    }
    func recording(for s: Session) -> Recording? { recording(s.recordingID) }
    func experiment(_ id: UUID?) -> Experiment? {
        guard let id else { return nil }
        let list = experiments
        if !experimentIndexValid { rebuildExperimentIndex() }
        if let i = experimentIndex[id], i < list.count, list[i].id == id { return list[i] }
        guard experimentIndex[id] != nil else { return nil }
        rebuildExperimentIndex()
        return experimentIndex[id].flatMap { $0 < list.count && list[$0].id == id ? list[$0] : nil }
    }
    func experiment(for r: Recording) -> Experiment? { experiment(r.experimentID) }
    func sessions(of recordingID: UUID) -> [Session] {
        let list = sessions
        if !sessionIndexValid { rebuildSessionIndex() }
        let hits = (sessionsByRecording[recordingID] ?? []).compactMap { $0 < list.count ? list[$0] : nil }
        if hits.allSatisfy({ $0.recordingID == recordingID }) { return hits }
        rebuildSessionIndex()
        return list.filter { $0.recordingID == recordingID }
    }

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
    }
    private func rebuildRecordingIndex() {
        var byID = [UUID: Int](minimumCapacity: recordings.count)
        for (i, r) in recordings.enumerated() where byID[r.id] == nil { byID[r.id] = i }
        recordingIndex = byID
        recordingIndexValid = true
    }
    private func rebuildExperimentIndex() {
        var byID = [UUID: Int](minimumCapacity: experiments.count)
        for (i, e) in experiments.enumerated() where byID[e.id] == nil { byID[e.id] = i }
        experimentIndex = byID
        experimentIndexValid = true
    }
    func recordings(in experimentID: UUID) -> [Recording] { recordings.filter { $0.experimentID == experimentID } }
    func source(_ id: UUID) -> VideoSource? { sources[id] }

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
        if experiment(for: r)?.blinded == true { return L("(hidden while blinded)", "（盲态下隐藏）") }
        return r.originalName
    }

    // MARK: Loading

    private struct Snapshot: Sendable {
        var experiments: [Experiment] = []
        var recordings: [Recording] = []
        var sessions: [Session] = []
        var sources: [UUID: VideoSource] = [:]
        var dirtyRecordings: Set<UUID> = []
        var dirtySessions: Set<UUID> = []
        var warnings: [String] = []
    }

    /// Reads the whole library off the main thread and shows it. Call once after init.
    func load() async {
        let base = self.base
        let snap = await Task.detached(priority: .userInitiated) { SessionStore.read(base: base) }.value
        experiments = snap.experiments
        recordings = snap.recordings
        experimentIndexValid = false
        recordingIndexValid = false
        sources = snap.sources
        loadWarnings = snap.warnings
        dirtyRecordings.formUnion(snap.dirtyRecordings)
        // Mirror recording state into each analysis (status, subject, group, video facts).
        var list = snap.sessions
        var dirtyList = snap.dirtySessions
        let byID = Dictionary(recordings.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in list.indices {
            if let r = list[i].recordingID.flatMap({ byID[$0] }) {
                let before = list[i]
                sync(&list[i], with: r)
                if list[i] != before { dirtyList.insert(list[i].id) }
            } else if list[i].hasPose || list[i].status != .failed {
                list[i].hasPose = false
                list[i].status = .failed
                list[i].failure = L("The video of this analysis is missing.", "该分析对应的视频已丢失。")
                dirtyList.insert(list[i].id)
            }
        }
        sessions = list.sorted { $0.createdAt > $1.createdAt }
        sessionIndexValid = false
        dirty.formUnion(dirtyList)
        isLoaded = true
        if !dirty.isEmpty || !dirtyRecordings.isEmpty { flush() }
        log.write("Library opened: \(base.path) — \(recordings.count) videos, \(sessions.count) analyses, \(experiments.count) studies")
        // Recordings without a QC report (libraries from 1.2): computed quietly in the background.
        for r in recordings where r.hasPose && r.qc == nil { enqueueQC(r.id) }
        // Housekeeping off the main thread: Recently Deleted older than 30 days, today's backup.
        enqueueIO {
            let n = RecentlyDeleted.purge(base)
            if n > 0 { Task { @MainActor [weak self] in self?.log.write("Erased \(n) Recently Deleted item(s) older than \(RecentlyDeleted.keepDays) days") } }
        }
        await dailyBackupIfNeeded()
        await refreshAvailability()
    }

    nonisolated private static func read(base: URL) -> Snapshot {
        var snap = Snapshot()
        let decoder = Coders.decoder()
        let fm = FileManager.default
        let experimentsRoot = base.appendingPathComponent("Experiments", isDirectory: true)
        let recordingsRoot = base.appendingPathComponent("Recordings", isDirectory: true)
        let sessionsRoot = base.appendingPathComponent("Sessions", isDirectory: true)

        for u in (try? fm.contentsOfDirectory(at: experimentsRoot, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "json" {
            guard let d = try? Data(contentsOf: u) else { continue }
            if let e = try? decoder.decode(Experiment.self, from: d) {
                if !snap.experiments.contains(where: { $0.id == e.id }) { snap.experiments.append(e) }
            } else {
                snap.warnings.append("Skipped a damaged study file: \(u.lastPathComponent)")
            }
        }
        snap.experiments.sort { $0.createdAt > $1.createdAt }

        for d in (try? fm.contentsOfDirectory(at: recordingsRoot, includingPropertiesForKeys: nil)) ?? [] {
            let file = d.appendingPathComponent("recording.json")
            guard let data = try? Data(contentsOf: file) else { continue }
            guard var r = try? decoder.decode(Recording.self, from: data) else {
                snap.warnings.append("Skipped a damaged video record: \(d.lastPathComponent)")
                continue
            }
            // A folder duplicated by hand carries the same id: keep the first.
            if snap.recordings.contains(where: { $0.id == r.id }) { continue }
            // Interrupted while processing (quit or crash): back to the queue; the checkpoint is kept.
            if r.status == .processing { r.status = .queued; snap.dirtyRecordings.insert(r.id) }
            if r.hasPose && !PoseStorage.exists(folder: d) {
                r.hasPose = false
                r.status = .queued
                snap.dirtyRecordings.insert(r.id)
            }
            if let s = VideoSource.load(folder: d) {
                snap.sources[r.id] = s
            } else {
                // Libraries from the iPhone: the video is inside the recording folder.
                let fp = (try? VideoFingerprint.make(d.appendingPathComponent(r.videoFile)))
                snap.sources[r.id] = VideoSource(mode: .copied, bookmark: nil, path: d.appendingPathComponent(r.videoFile).path,
                                                 fileName: r.originalName, size: fp?.size ?? 0, modified: fp?.modified ?? 0,
                                                 fingerprint: fp?.fingerprint ?? "")
            }
            snap.recordings.append(r)
        }

        for d in (try? fm.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: d.appendingPathComponent("session.json")) else { continue }
            guard var s = try? decoder.decode(Session.self, from: data) else {
                snap.warnings.append("Skipped a damaged analysis: \(d.lastPathComponent)")
                continue
            }
            if snap.sessions.contains(where: { $0.id == s.id }) { continue }
            if s.recordingID == nil {
                // iPhone 1.0–1.2 analysis that owns its video: turned into a recording (files moved).
                let r = migrate(&s, folder: d, recordingsRoot: recordingsRoot, existing: snap.recordings.first { $0.id == s.id })
                snap.recordings.removeAll { $0.id == r.id }
                snap.recordings.append(r)
                if snap.sources[r.id] == nil {
                    let path = recordingsRoot.appendingPathComponent(r.id.uuidString).appendingPathComponent(r.videoFile)
                    snap.sources[r.id] = VideoSource(mode: .copied, bookmark: nil, path: path.path, fileName: r.originalName,
                                                     size: 0, modified: 0, fingerprint: "")
                }
            }
            snap.sessions.append(s)
        }
        snap.recordings.sort { $0.createdAt > $1.createdAt }
        return snap
    }

    /// Turns a 1.0–1.2 session (video and pose in its own folder) into a recording plus this analysis.
    nonisolated private static func migrate(_ s: inout Session, folder d: URL, recordingsRoot: URL, existing: Recording?) -> Recording {
        let fm = FileManager.default
        let recDir = recordingsRoot.appendingPathComponent(s.id.uuidString, isDirectory: true)
        try? fm.createDirectory(at: recDir, withIntermediateDirectories: true)
        for name in [s.videoFile, PoseStorage.fileName, PoseStorage.legacyFileName, "skeleton.mp4"] where !name.isEmpty {
            let src = d.appendingPathComponent(name), dst = recDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
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
            if s.status == .failed && !r.hasPose {
                r.status = .failed
                r.failure = s.failure
            } else {
                r.status = r.hasPose ? .ready : .queued
            }
            r.decision = r.hasPose ? .included : .pending
        }
        r.updatedAt = Date()
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

    // MARK: Video files

    /// The video file of a recording (resolved bookmark, or the copy in the library). Does not start
    /// security-scoped access; use `videoAccess` to read the file.
    func videoURL(_ r: Recording) -> URL? {
        if let u = resolvedVideos[r.id] { return u }
        let src = sources[r.id]
        if src?.mode == .referenced, let b = src?.bookmark {
            guard let resolved = VideoBookmarks.resolve(b) else { return nil }
            resolvedVideos[r.id] = resolved.url
            if let fresh = resolved.refreshed { updateSource(r.id) { $0.bookmark = fresh } }
            return resolved.url
        }
        return recordingFolder(r.id).appendingPathComponent(r.videoFile)
    }

    func videoURL(_ s: Session) -> URL? { recording(for: s).flatMap { videoURL($0) } }

    /// Opens the video for reading; nil when it cannot be found. Keep the returned object alive while
    /// the file is used.
    func videoAccess(_ r: Recording) -> VideoAccess? {
        guard let url = videoURL(r) else { markMissing(r.id, true); return nil }
        let referenced = sources[r.id]?.mode == .referenced
        let access = VideoBookmarks.access(url, scoped: referenced)
        let exists = FileManager.default.fileExists(atPath: url.path)
        markMissing(r.id, !exists)
        return exists ? access : nil
    }

    private func markMissing(_ id: UUID, _ missing: Bool) {
        if missing {
            if !missingVideos.contains(id) { missingVideos.insert(id) }
        } else if missingVideos.contains(id) {
            missingVideos.remove(id)
        }
    }

    /// Checks which videos are reachable. Bookmarks are resolved and files checked off the main thread
    /// (a disconnected network drive can take seconds to answer). Called on open, when the app becomes
    /// active and before a batch starts.
    func refreshAvailability() async {
        var items: [(id: UUID, cached: URL?, bookmark: Data?, fallback: URL, referenced: Bool)] = []
        for r in recordings {
            let src = sources[r.id]
            let referenced = src?.mode == .referenced
            items.append((r.id, resolvedVideos[r.id], referenced ? src?.bookmark : nil,
                          recordingFolder(r.id).appendingPathComponent(r.videoFile), referenced))
        }
        let check = items
        let out = await Task.detached(priority: .utility) { () -> (resolved: [UUID: URL], missing: Set<UUID>, refreshed: [UUID: Data]) in
            var resolved: [UUID: URL] = [:]
            var missing = Set<UUID>()
            var refreshed: [UUID: Data] = [:]
            for item in check {
                var url = item.cached
                if url == nil {
                    if item.referenced {
                        if let b = item.bookmark, let r = VideoBookmarks.resolve(b) {
                            url = r.url
                            if let fresh = r.refreshed { refreshed[item.id] = fresh }
                        }
                    } else {
                        url = item.fallback
                    }
                }
                guard let u = url else { missing.insert(item.id); continue }
                resolved[item.id] = u
                let access = VideoBookmarks.access(u, scoped: item.referenced)
                if !FileManager.default.fileExists(atPath: u.path) { missing.insert(item.id) }
                _ = access
            }
            return (resolved, missing, refreshed)
        }.value
        // Only what changed: this runs every time the app becomes active, and every write notifies
        // the views that read it.
        for (id, u) in out.resolved where resolvedVideos[id] != u && recording(id) != nil { resolvedVideos[id] = u }
        for (id, d) in out.refreshed { updateSource(id) { $0.bookmark = d } }
        let missing = out.missing.filter { recording($0) != nil }
        if missing != missingVideos { missingVideos = missing }
    }

    /// Points a recording at a video the user located (moved or renamed file, another drive).
    /// Returns a message when the file differs from the original (size or fingerprint).
    @discardableResult
    func relinkVideo(_ id: UUID, to url: URL) async -> String? {
        guard recording(id) != nil else { return nil }
        let info = await Task.detached(priority: .userInitiated) { () -> (VideoFingerprint.Info?, Data?) in
            let access = VideoBookmarks.access(url, scoped: true)
            defer { _ = access }
            return (try? VideoFingerprint.make(url), VideoBookmarks.make(url))
        }.value
        let old = sources[id]
        var warning: String?
        if let fp = info.0, let old, old.size > 0, (old.size != fp.size || (!old.fingerprint.isEmpty && old.fingerprint != fp.fingerprint)) {
            warning = L("This file is not identical to the original video (size or content differs). Tracking will run again on it.",
                        "该文件与原视频不完全相同（大小或内容不同），将对其重新识别。")
        }
        var src = old ?? VideoSource(mode: .referenced, bookmark: nil, path: url.path, fileName: url.lastPathComponent,
                                     size: 0, modified: 0, fingerprint: "")
        src.mode = .referenced
        src.bookmark = info.1
        src.path = url.path
        src.fileName = url.lastPathComponent
        if let fp = info.0 { src.size = fp.size; src.modified = fp.modified; src.fingerprint = fp.fingerprint }
        resolvedVideos[id] = url
        setSource(id, src)
        markMissing(id, false)
        if warning != nil, recording(id)?.hasPose == true { rerunDetection(id) }
        log.write("Relinked video of \(id.uuidString) to \(url.path)")
        return warning
    }

    private func setSource(_ id: UUID, _ s: VideoSource) {
        sources[id] = s
        dirtySources.insert(id)
        scheduleFlush()
    }

    func updateSource(_ id: UUID, _ change: (inout VideoSource) -> Void) {
        guard var s = sources[id] else { return }
        change(&s)
        guard s != sources[id] else { return }
        setSource(id, s)
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

    /// Debounced write: 0.4 s after the last change, but never more than 2 s after the first unsaved
    /// one (a steady stream of changes must not postpone saving indefinitely).
    private func scheduleFlush() {
        let now = Date()
        if firstUnsavedChange == nil { firstUnsavedChange = now }
        if let first = firstUnsavedChange, now.timeIntervalSince(first) >= 2 {
            flush()
            return
        }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Updates memory immediately (the UI reacts at once) and writes shortly after, off the main thread.
    func save(_ s: Session) {
        var s = s
        if let i = indexOfSession(s.id) {
            var old = sessions[i]
            old.updatedAt = s.updatedAt
            if old == s { return }
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
            experimentIndexValid = false
        }
        dirtyExperiments.insert(e.id)
        scheduleFlush()
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

    /// Writes pending changes now (off the main thread).
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        firstUnsavedChange = nil
        let items = dirty.compactMap { id in session(id).map { ($0, folder(id)) } }
        let recs = dirtyRecordings.compactMap { id in recording(id).map { ($0, recordingFolder(id)) } }
        let exps = dirtyExperiments.compactMap { id in experiment(id).map { ($0, experimentURL(id)) } }
        let srcs = dirtySources.compactMap { id in sources[id].map { ($0, recordingFolder(id)) } }
        dirty.removeAll()
        dirtyRecordings.removeAll()
        dirtyExperiments.removeAll()
        dirtySources.removeAll()
        guard !items.isEmpty || !recs.isEmpty || !exps.isEmpty || !srcs.isEmpty else { return }
        enqueueIO {
            let encoder = Coders.encoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let fm = FileManager.default
            // Never recreate the folder of something deleted in the meantime.
            for (r, dir) in recs {
                guard fm.fileExists(atPath: dir.path), let data = try? encoder.encode(r) else { continue }
                try? data.write(to: dir.appendingPathComponent("recording.json"), options: .atomic)
            }
            for (s, dir) in srcs {
                guard fm.fileExists(atPath: dir.path) else { continue }
                try? s.save(folder: dir)
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

    /// Writes everything and waits until it is on disk (quit, switching library).
    func flushAndWait() async {
        flush()
        await ioTail?.value
        log.drain()
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
        // Another task's QC criteria apply: check again. A video leaving every task keeps the report
        // of the criteria it was judged by (re-checking with the defaults could include it behind
        // the task's back, e.g. between a removal and its Undo).
        if r.experimentID != studyBefore, r.experimentID != nil, r.hasPose { enqueueQC(id) }
    }

    /// The same change for many recordings (batch editing in tables).
    func updateRecordings(_ ids: Set<UUID>, _ change: (inout Recording) -> Void) {
        for id in ids { updateRecording(id, change) }
    }

    // MARK: Studies

    @discardableResult
    func createExperiment(_ name: String) -> Experiment {
        var e = Experiment(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? L("New study", "新研究") : name)
        e.ensureBlindCodes()
        saveExperiment(e)
        return e
    }

    func updateExperiment(_ id: UUID, _ change: (inout Experiment) -> Void) {
        guard var e = experiment(id) else { return }
        let before = e
        change(&e)
        e.ensureBlindCodes()
        saveExperiment(e)
        if e.factors != before.factors || e.animals != before.animals || e.blinded != before.blinded {
            for r in recordings where r.experimentID == id { resync(recording: r.id) }
        }
        if e.qc != before.qc { for r in recordings where r.experimentID == id && r.hasPose { enqueueQC(r.id) } }
    }

    /// Removes a study. Its videos stay (outside any study) with the animal code and group kept as
    /// text, unless `deleteVideos` is set. Everything goes to Recently Deleted (restorable for 30 days,
    /// the videos rejoin the study when it is restored). Returns the Recently Deleted entry.
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
                entry.detached.append(DeletedEntry.Link(recordingID: r.id, animalID: r.animalID, subject: r.subject, group: r.group))
                updateRecording(r.id) { r in
                    if let a = e.animal(r.animalID) {
                        r.subject = a.code
                        r.group = e.groupLabel(a)
                    }
                    r.experimentID = nil
                    r.animalID = nil
                }
            }
        }
        experiments.removeAll { $0.id == id }
        experimentIndexValid = false
        dirtyExperiments.remove(id)
        entry.items.append("Experiments/\(id.uuidString).json")
        trash(entry)
        log.write("Moved study \(e.name) to Recently Deleted\(deleteVideos ? " with \(recs.count) video(s)" : "")")
        return entry.id
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

    /// Moves recordings into a study (or out of any study with nil), keeping the animal code (and,
    /// when leaving a study that is not blinded, the animal's group as text).
    func move(_ ids: Set<UUID>, toStudy experimentID: UUID?) {
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

    /// Sets the animal of a recording by code (creating the animal in the study when it is new).
    func setAnimal(_ id: UUID, code: String) {
        guard let r = recording(id) else { return }
        let c = code.trimmingCharacters(in: .whitespaces)
        if let eid = r.experimentID {
            let aid = animalID(code: c, in: eid)
            updateRecording(id) { $0.animalID = aid; $0.subject = aid == nil ? c : "" }
        } else {
            updateRecording(id) { $0.subject = c }
        }
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
        log.write("Moved \(entry.sessionIDs.count) analysis(es) to Recently Deleted")
        return entry.id
    }

    /// Deletes videos with their pose, QC and every analysis made from them. A referenced video file
    /// is never touched — only the library's record of it; a copy inside the library moves with the
    /// record. Everything goes to Recently Deleted; returns its entry.
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
        log.write("Moved \(present.count) video record(s) to Recently Deleted")
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
            dirtySources.remove(id)
            qcQueue.removeAll { $0 == id }
            poseCache[id] = nil
            poseOrder.removeAll { $0 == id }
            sources[id] = nil
            resolvedVideos[id] = nil
            missingVideos.remove(id)
        }
        recordings.removeAll { ids.contains($0.id) }
        recordingIndexValid = false
    }

    /// Moves an entry's folders into Recently Deleted, after every write issued before it.
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
        log.write("Erased a Recently Deleted item for good")
    }

    /// Erases everything in Recently Deleted.
    func emptyRecentlyDeleted() async {
        let base = self.base
        await performIO { RecentlyDeleted.eraseAll(base) }
        recentlyDeletedVersion += 1
        log.write("Emptied Recently Deleted")
    }

    private struct RestoredItems: Sendable {
        var experiments: [Experiment] = []
        var recordings: [Recording] = []
        var repaired: Set<UUID> = []
        var sources: [UUID: VideoSource] = [:]
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
            experiments.insert(e, at: 0)
            experiments.sort { $0.createdAt > $1.createdAt }
            experimentIndexValid = false
        }
        for r in items.recordings where recording(r.id) == nil {
            recordings.append(r)
            if let src = items.sources[r.id] { sources[r.id] = src }
            if items.repaired.contains(r.id) { dirtyRecordings.insert(r.id) }
        }
        recordings.sort { $0.createdAt > $1.createdAt }
        recordingIndexValid = false
        for var s in items.sessions where session(s.id) == nil {
            let before = s
            if let r = s.recordingID.flatMap({ recording($0) }) { sync(&s, with: r) }
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
                }
            }
        }
        for r in items.recordings where r.hasPose && r.qc == nil { enqueueQC(r.id) }
        if !dirty.isEmpty || !dirtyRecordings.isEmpty { flush() }
        recentlyDeletedVersion += 1
        await refreshAvailability()
        log.write("Restored from Recently Deleted: \(out.restored.count) item(s), \(out.conflicts.count) left (name conflicts)")
        for r in items.recordings { onRecordingChanged?(r.id) }
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
                guard let d = try? Data(contentsOf: url.appendingPathComponent("recording.json")),
                      var r = try? decoder.decode(Recording.self, from: d) else { continue }
                if r.status == .processing { r.status = .queued; out.repaired.insert(r.id) }
                if r.hasPose && !PoseStorage.exists(folder: url) {
                    r.hasPose = false
                    r.status = .queued
                    out.repaired.insert(r.id)
                }
                if let src = VideoSource.load(folder: url) {
                    out.sources[r.id] = src
                } else {
                    let fp = try? VideoFingerprint.make(url.appendingPathComponent(r.videoFile))
                    out.sources[r.id] = VideoSource(mode: .copied, bookmark: nil, path: url.appendingPathComponent(r.videoFile).path,
                                                    fileName: r.originalName, size: fp?.size ?? 0, modified: fp?.modified ?? 0,
                                                    fingerprint: fp?.fingerprint ?? "")
                }
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

    /// Writes a backup of the studies, video records and analysis settings (off the main thread).
    func backup(_ reason: String) {
        guard isLoaded, !(recordings.isEmpty && experiments.isEmpty && sessions.isEmpty) else { return }
        let snap = metadataSnapshot(reason: reason)
        let base = self.base
        enqueueIO {
            do { try MetadataBackup.write(snap, base: base) } catch {
                Task { @MainActor [weak self] in self?.log.write("Backup failed: \(error.localizedDescription)") }
            }
        }
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
        guard isLoaded, !(recordings.isEmpty && experiments.isEmpty && sessions.isEmpty) else { return }
        let base = self.base
        let last = await performIO { MetadataBackup.latest(base, reason: MetadataBackup.Reason.daily)?.createdAt }
        if let last, Date().timeIntervalSince(last) < 20 * 3600 { return }
        backup(MetadataBackup.Reason.daily)
    }

    func backups() async -> [BackupInfo] {
        let base = self.base
        return await performIO { MetadataBackup.list(base) }
    }

    /// Restores the studies, the design information and decisions of the videos, and the settings
    /// and labels of the analyses from a backup. Tracking and QC are never touched, nothing is
    /// deleted, and the current state is backed up first (so a restore can itself be undone).
    func restoreBackup(_ url: URL) async -> String {
        let loaded: MetadataSnapshot? = await performIO { try? MetadataBackup.load(url) }
        guard let snap = loaded else {
            return L("This backup could not be read.", "无法读取该备份。")
        }
        backup(MetadataBackup.Reason.beforeRestore)
        var studies = 0, videos = 0, analyses = 0
        for e in snap.experiments {
            if experiment(e.id) != nil {
                if experiment(e.id) != e { updateExperiment(e.id) { $0 = e }; studies += 1 }
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
        log.write("Restored backup \(url.lastPathComponent): \(studies) studies, \(videos) videos, \(analyses) analyses changed")
        return String(format: L("Backup restored: %d studies, %d videos and %d analyses changed. The state before the restore was backed up.",
                                "备份已恢复：更改了 %d 个研究、%d 段视频和 %d 个分析。恢复前的状态已另行备份。"), studies, videos, analyses)
    }


    // MARK: Import

    /// One video to import, with the design information chosen in the import sheet.
    struct ImportItem: Sendable {
        var url: URL
        var animal: String
        var timepoint: String
        var trial: Int
        var group: String
        var notes: String
        var experimentID: UUID?
        var planned: [Assay]
        /// Probed by the import sheet (shown in lists before the model runs).
        var duration: Double?
        var fps: Double?
        var width: Int?
        var height: Int?
        var recordedOn: Date?
        /// Pose model chosen in the import sheet.
        var model: PoseModelID = .standard
        /// Create the sessions of `planned` right away (videos added to a task), instead of when
        /// the video is included after QC.
        var createSessions = false
    }

    struct ImportOutcome {
        var created: [Recording] = []
        var duplicates: [String] = []
        var failures: [(String, String)] = []
    }

    /// Imports videos: referenced in place (bookmark) or copied into the library. Fingerprints, bookmarks
    /// and copies are made off the main thread. A file already in the library (same fingerprint) is
    /// skipped unless `allowDuplicates`.
    func importVideos(_ items: [ImportItem], copy: Bool, allowDuplicates: Bool = false,
                      progress: ((Int, Int) -> Void)? = nil) async -> ImportOutcome {
        var outcome = ImportOutcome()
        var known = Set(sources.values.filter { !$0.fingerprint.isEmpty }.map { "\($0.size)|\($0.fingerprint)" })
        /// Videos added to a study: linked to their animal (and given their sessions) after the loop.
        var joined: [(id: UUID, item: ImportItem)] = []
        for (index, item) in items.enumerated() {
            progress?(index, items.count)
            let ext = item.url.pathExtension.isEmpty ? "mov" : item.url.pathExtension.lowercased()
            var r = Recording(videoFile: "video." + ext, originalName: item.url.lastPathComponent)
            let dir = recordingFolder(r.id)
            let dest = dir.appendingPathComponent(r.videoFile)
            let url = item.url
            let prepared = await Task.detached(priority: .userInitiated) { () -> Result<(VideoFingerprint.Info, Data?), Error> in
                let access = VideoBookmarks.access(url, scoped: true)
                defer { _ = access }
                do {
                    let fp = try VideoFingerprint.make(url)
                    let bookmark = copy ? nil : VideoBookmarks.make(url)
                    return .success((fp, bookmark))
                } catch {
                    return .failure(error)
                }
            }.value
            guard case .success(let (fp, bookmark)) = prepared else {
                if case .failure(let e) = prepared { outcome.failures.append((item.url.lastPathComponent, e.localizedDescription)) }
                continue
            }
            let key = "\(fp.size)|\(fp.fingerprint)"
            if !allowDuplicates && known.contains(key) {
                outcome.duplicates.append(item.url.lastPathComponent)
                continue
            }
            #if os(macOS)
            if !copy && bookmark == nil {
                outcome.failures.append((item.url.lastPathComponent,
                                         L("The app could not keep access to this file. Choose “Copy videos into the library”.",
                                           "App 无法保留对该文件的访问权限，请选择“将视频复制到资料库”。")))
                continue
            }
            #endif
            let copied: Error? = await Task.detached(priority: .userInitiated) { () -> Error? in
                let fm = FileManager.default
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    if copy {
                        let access = VideoBookmarks.access(url, scoped: true)
                        defer { _ = access }
                        try fm.copyItem(at: url, to: dest)
                    }
                    return nil
                } catch {
                    try? fm.removeItem(at: dir)
                    return error
                }
            }.value
            if let copied {
                outcome.failures.append((item.url.lastPathComponent, copied.localizedDescription))
                continue
            }
            known.insert(key)
            r.notes = item.notes
            r.timepoint = item.timepoint
            r.trial = max(1, item.trial)
            r.plannedAssays = item.createSessions ? [] : item.planned
            r.duration = item.duration
            r.fps = item.fps
            r.videoWidth = item.width
            r.videoHeight = item.height
            r.recordedOn = item.recordedOn
            let code = item.animal.trimmingCharacters(in: .whitespaces)
            if let eid = item.experimentID, experiment(eid) != nil {
                r.experimentID = eid
                r.subject = code
                joined.append((r.id, item))
            } else {
                r.subject = code
                r.group = item.group
            }
            var src = VideoSource(mode: copy ? .copied : .referenced, bookmark: bookmark, path: copy ? dest.path : url.path,
                                  fileName: url.lastPathComponent, size: fp.size, modified: fp.modified, fingerprint: fp.fingerprint)
            src.poseModel = item.model.runnable
            sources[r.id] = src
            if !copy { resolvedVideos[r.id] = url }
            dirtySources.insert(r.id)
            saveRecording(r)
            if r.experimentID == nil, item.createSessions && !item.planned.isEmpty { assign(item.planned, to: r.id) }
            outcome.created.append(r)
            // On disk at once: a crash in the middle of a long (copying) import loses nothing.
            flush()
        }
        // New animals and their groups: one change per study for the whole import (each change of a
        // study re-syncs all its videos), then each video is linked to its animal and gets its sessions.
        prepareAnimals(for: joined.map(\.item))
        for (id, item) in joined {
            guard let eid = item.experimentID else { continue }
            let code = item.animal.trimmingCharacters(in: .whitespaces)
            if let aid = experiment(eid)?.animal(code: code)?.id {
                updateRecording(id) { $0.animalID = aid; $0.subject = "" }
            }
            if item.createSessions && !item.planned.isEmpty { assign(item.planned, to: id) }
        }
        for i in outcome.created.indices { if let r = recording(outcome.created[i].id) { outcome.created[i] = r } }
        progress?(items.count, items.count)
        flush()
        log.write("Imported \(outcome.created.count) video(s) (\(copy ? "copied" : "referenced")); \(outcome.duplicates.count) duplicate(s) skipped; \(outcome.failures.count) failed")
        return outcome
    }

    /// Creates the new animals of an import (and their groups) with one change per study, instead of
    /// one per video: every change of a study re-syncs all its videos. The first group given for an
    /// animal wins; an animal that already has a group keeps it.
    private func prepareAnimals(for items: [ImportItem]) {
        var byStudy: [UUID: [(code: String, group: String)]] = [:]
        for item in items {
            guard let eid = item.experimentID else { continue }
            let code = item.animal.trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty else { continue }
            byStudy[eid, default: []].append((code, item.group.trimmingCharacters(in: .whitespaces)))
        }
        for (eid, list) in byStudy {
            guard let e = experiment(eid) else { continue }
            let single = e.factors.count <= 1 && !e.blinded
            var newAnimals: [Animal] = []
            var groupOf: [String: String] = [:]   // lower-cased code → group
            var seen = Set(e.animals.map { $0.code.lowercased() })
            for (code, group) in list {
                let key = code.lowercased()
                if !group.isEmpty && groupOf[key] == nil { groupOf[key] = group }
                if !seen.contains(key) {
                    seen.insert(key)
                    newAnimals.append(Animal(code: code))
                }
            }
            let needsGroups = single && !groupOf.isEmpty
            guard !newAnimals.isEmpty || needsGroups else { continue }
            updateExperiment(eid) { x in
                x.animals.append(contentsOf: newAnimals)
                guard needsGroups else { return }
                if x.factors.isEmpty { x.factors = [DesignFactor(name: kTaskGroupFactor, levels: [])] }
                let fid = x.factors[0].id.uuidString
                for i in x.animals.indices {
                    guard x.animals[i].levels[fid].map({ x.factors[0].levels.contains($0) }) != true,
                          let g = groupOf[x.animals[i].code.lowercased()] else { continue }
                    let level = x.factors[0].levels.first { $0.compare(g, options: .caseInsensitive) == .orderedSame } ?? g
                    if !x.factors[0].levels.contains(level) { x.factors[0].levels.append(level) }
                    x.animals[i].levels[fid] = level
                }
            }
        }
    }

    var knownGroups: [String] {
        var seen = Set<String>(), out: [String] = []
        for r in recordings where r.experimentID == nil && !r.group.isEmpty && !seen.contains(r.group) {
            seen.insert(r.group); out.append(r.group)
        }
        return out
    }

    // MARK: Processing queue (driven by BatchEngine)

    /// Number of queued recordings (no sorting: read by toolbars and progress several times a second).
    var queuedCount: Int {
        var n = 0
        for r in recordings where r.status == .queued { n += 1 }
        return n
    }

    /// Position (0-based) of a recording in the queue, without sorting the whole queue.
    func queuePosition(of id: UUID) -> Int? {
        guard let me = recordings.first(where: { $0.id == id }), me.status == .queued else { return nil }
        let key = { (r: Recording) in self.sources[r.id]?.queueRank ?? r.createdAt.timeIntervalSince1970 }
        let mine = key(me)
        var ahead = 0
        for r in recordings where r.status == .queued && r.id != id {
            let k = key(r)
            if k < mine || (k == mine && r.createdAt < me.createdAt) { ahead += 1 }
        }
        return ahead
    }

    /// Recordings waiting for the pose model, in queue order (rank, then import order).
    var queuedRecordings: [Recording] {
        recordings.filter { $0.status == .queued }.sorted { a, b in
            let ra = sources[a.id]?.queueRank ?? a.createdAt.timeIntervalSince1970
            let rb = sources[b.id]?.queueRank ?? b.createdAt.timeIntervalSince1970
            return ra != rb ? ra < rb : a.createdAt < b.createdAt
        }
    }

    /// Moves recordings to the front (or the end) of the queue, keeping their relative order.
    func reorderQueue(_ ids: [UUID], toFront: Bool) {
        let queue = queuedRecordings
        let ranks = queue.map { sources[$0.id]?.queueRank ?? $0.createdAt.timeIntervalSince1970 }
        let lo = ranks.min() ?? Date().timeIntervalSince1970
        let hi = ranks.max() ?? lo
        for (i, id) in ids.enumerated() {
            updateSource(id) { $0.queueRank = toFront ? lo - Double(ids.count - i) : hi + Double(i + 1) }
        }
    }

    func markProcessing(_ id: UUID) {
        updateRecording(id) { $0.status = .processing; $0.failure = nil }
        updateSource(id) { $0.attempts += 1 }
    }

    func markFailed(_ id: UUID, _ message: String) {
        updateRecording(id) { $0.status = .failed; $0.failure = message }
        log.write("FAILED \(recording(id).map { displayName($0) } ?? id.uuidString): \(message)")
    }

    /// Back to the queue (paused, interrupted). The checkpoint is kept.
    func markQueued(_ id: UUID) {
        updateRecording(id) { $0.status = .queued }
    }

    func noteCrash(_ id: UUID) {
        updateSource(id) { $0.crashes += 1 }
    }

    /// Re-queues failed recordings (or re-runs the model for finished ones).
    func requeue(_ ids: Set<UUID>) {
        for id in ids {
            guard let r = recording(id), r.status != .processing else { continue }
            updateSource(id) { $0.crashes = 0; $0.attempts = 0 }
            if r.status == .failed { updateRecording(id) { $0.status = .queued; $0.failure = nil } }
        }
    }

    /// Re-runs detection for a video (all its analyses wait for the new pose). The checkpoint is
    /// discarded so the model really runs again.
    /// Tracks the video again, optionally with another pose model (nil = the same model).
    func rerunDetection(_ id: UUID, model: PoseModelID? = nil) {
        let cp = checkpointFolder(id)
        enqueueIO { try? FileManager.default.removeItem(at: cp) }
        poseCache[id] = nil
        if let model, model != poseModel(id) {
            updateSource(id) { $0.poseModel = model.runnable }
            log.write("Pose model for \(recording(id).map { displayName($0) } ?? id.uuidString): \(model.displayName)")
        }
        updateRecording(id) { $0.hasPose = false; $0.status = .queued; $0.failure = nil }
    }

    /// The pose model that tracks / tracked a video.
    func poseModel(_ id: UUID) -> PoseModelID {
        sources[id]?.poseModel ?? .visible
    }

    /// Detection finished: save the pose, compute QC, then include / assign planned tasks and
    /// (re-)analyse every task of this video.
    func finishProcessing(_ id: UUID, track: PoseTrack, modelVersion: String) async throws {
        try await storePose(track, recording: id)
        updateRecording(id) {
            $0.hasPose = true
            $0.videoWidth = track.width
            $0.videoHeight = track.height
            $0.fps = track.fps
            $0.duration = track.duration
            $0.modelVersion = modelVersion
            $0.status = .ready
            $0.failure = nil
        }
        updateSource(id) { $0.crashes = 0 }
        let cp = checkpointFolder(id)
        enqueueIO { try? FileManager.default.removeItem(at: cp) }
        await computeQC(id, track: track)
        for s in sessions(of: id) { analyze(s.id, background: true) }
        if let r = recording(id) {
            log.write("Done \(displayName(r)): \(track.frameCount) frames, mouse detected in \(Int((track.detectedFraction * 100).rounded()))% — QC \(r.qc?.verdict.rawValue ?? "?")")
        }
        onRecordingChanged?(id)
    }

    // MARK: Quality control

    func computeQC(_ id: UUID, track: PoseTrack? = nil) async {
        guard let r = recording(id), r.hasPose else { return }
        let criteria = experiment(for: r)?.qc ?? QCCriteria()
        var loaded = track
        if loaded == nil { loaded = await recordingPose(id) }
        guard let t = loaded else { return }
        let report = await Task.detached(priority: .utility) { QualityControl.report(track: t, criteria: criteria) }.value
        updateRecording(id) { r in
            r.qc = report
            if r.decision == .pending && report.verdict == .pass { r.decision = .included }
        }
        assignPlannedIfIncluded(id)
    }

    private func assignPlannedIfIncluded(_ id: UUID) {
        guard let r = recording(id), r.decision == .included, r.hasPose, !r.plannedAssays.isEmpty else { return }
        let planned = r.plannedAssays
        assign(planned, to: id)
        updateRecording(id) { $0.plannedAssays = [] }
    }

    func setDecision(_ id: UUID, _ decision: InclusionDecision, reason: String = "") {
        updateRecording(id) {
            $0.decision = decision
            $0.exclusionReason = decision == .excluded ? reason : ""
        }
        assignPlannedIfIncluded(id)
    }

    func setDecision(_ ids: Set<UUID>, _ decision: InclusionDecision, reason: String = "") {
        if ids.count > 5 { backupBeforeChange(MetadataBackup.Reason.beforeBulk) }
        for id in ids { setDecision(id, decision, reason: reason) }
        // Decisions are what a review session produces: on disk at once, not after the debounce.
        flush()
        log.write("\(decision.rawValue.capitalized): \(ids.count) video(s)\(reason.isEmpty ? "" : " — " + reason)")
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

    // MARK: Tasks

    /// Creates an analysis of the recording for each task it does not have yet. Parameters and
    /// calibration start from the latest analysis of the same task (same study first).
    @discardableResult
    func assign(_ assays: [Assay], to recordingID: UUID) -> [Session] {
        guard let r = recording(recordingID) else { return [] }
        var created: [Session] = []
        for a in assays where !sessions.contains(where: { $0.recordingID == recordingID && $0.assay == a }) {
            var s = Session(recording: r, assay: a)
            // Parameters and calibration come from the same task only (another task may use another
            // camera or protocol); a video in no task takes them from the latest one in no task.
            let prev = r.experimentID == nil
                ? sessions.first { $0.assay == a && recording(for: $0)?.experimentID == nil }
                : sessions.first { $0.assay == a && recording(for: $0)?.experimentID == r.experimentID }
            if let prev {
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

    /// Assigns tasks to many recordings. Videos that are not included yet keep the tasks as planned
    /// (they are created when the video is included).
    func assign(_ assays: [Assay], to ids: Set<UUID>) {
        for id in ids {
            guard let r = recording(id) else { continue }
            if r.decision == .included && r.hasPose {
                assign(assays, to: id)
            } else {
                updateRecording(id) { rec in
                    for a in assays where !rec.plannedAssays.contains(a) { rec.plannedAssays.append(a) }
                }
            }
        }
    }

    /// Copies parameters (and optionally calibration) of one analysis to others of the same task.
    /// Each video keeps its own injection time and injected paw.
    func applySettings(from sourceID: UUID, to ids: [UUID], calibration: Bool) {
        guard let src = session(sourceID) else { return }
        if ids.count > 1 { backupBeforeChange(MetadataBackup.Reason.beforeBulk) }
        for id in ids where id != sourceID {
            guard var s = session(id), s.assay == src.assay else { continue }
            let own = s.params
            s.params = src.params
            s.params.keepPerAnimal(from: own)
            // The lesioned hemisphere belongs to the animal, as in the iPhone's "apply to all".
            s.params.cylinder.lesion = own.cylinder.lesion
            if calibration {
                s.calibration = src.calibration
                s.calibration.copiedFrom = src.displayName
            }
            save(s)
            analyze(id, background: true)
        }
    }

    // MARK: Pose

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

    /// Pose track of a recording, from the cache or loaded off the main thread.
    func recordingPose(_ id: UUID) async -> PoseTrack? {
        if let t = poseCache[id] {
            poseOrder.removeAll { $0 == id }
            poseOrder.append(id)
            return t
        }
        if let running = poseLoads[id] { return await running.value }
        let dir = recordingFolder(id)
        let task = Task.detached(priority: .userInitiated) { () -> PoseTrack? in
            guard var t = PoseStorage.load(folder: dir) else { return nil }
            if t.timeOffset == nil { t.timeOffset = 0 }
            return t
        }
        poseLoads[id] = task
        let loaded = await task.value
        poseLoads[id] = nil
        if let loaded, recording(id) != nil { cachePose(loaded, id) }
        return loaded
    }

    /// Pose of a recording without keeping it in the cache (exports of many videos).
    nonisolated func readPose(folder: URL) -> PoseTrack? { PoseStorage.load(folder: folder) }

    // MARK: Results

    func result(_ id: UUID) async -> AnalysisResult? {
        if let r = results[id] { touchResult(id); return r }
        if let pending = unsavedResults[id]?.result { insertResult(pending, id); return pending }
        let url = resultURL(id)
        let fromDisk = await Task.detached(priority: .userInitiated) { SessionStore.readResult(url) }.value
        if let r = results[id] { touchResult(id); return r }
        guard let loaded = fromDisk, session(id) != nil else { return nil }
        // Results computed by an older analyzer version are recomputed on open.
        if (loaded.version ?? 0) < AnalysisResult.currentVersion { analyze(id) }
        insertResult(loaded, id)
        return loaded
    }

    nonisolated static func readResult(_ url: URL) -> AnalysisResult? {
        let decoder = Coders.decoder()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AnalysisResult.self, from: data)
    }

    /// Results for many sessions (exports, comparisons), read off the main thread and not cached.
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
        trimResults(keepRecent: 6, limit: Self.maxCachedResults)
    }

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

    /// Re-runs the analysis of a session (its pose must exist). Requests are queued; up to
    /// `maxConcurrentAnalyses` run at once. Requests for the session on screen go first.
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

    /// Re-analyses many sessions (after "apply to all", a changed QC or study).
    func analyze(_ ids: [UUID]) {
        for id in ids { analyze(id, background: true) }
    }

    private func enqueueAnalysis(_ id: UUID, background: Bool) {
        if let i = analysisQueue.firstIndex(of: id) {
            if background { return }
            analysisQueue.remove(at: i)
        }
        if background {
            backgroundAnalyses.insert(id)
            analysisQueue.append(id)
        } else {
            backgroundAnalyses.remove(id)
            analysisQueue.insert(id, at: 0)
        }
        if !analysing.contains(id) { analysing.insert(id) }
        while analysisWorkers < maxConcurrentAnalyses && !analysisQueue.isEmpty {
            analysisWorkers += 1
            Task { [weak self] in
                while let self, !self.analysisQueue.isEmpty {
                    let next = self.analysisQueue.removeFirst()
                    await self.runAnalysis(next)
                    if !self.analysisQueue.contains(next) { self.analysing.remove(next) }
                }
                self?.analysisWorkers -= 1
            }
        }
    }

    private func runAnalysis(_ id: UUID) async {
        let inBackground = backgroundAnalyses.remove(id) != nil
        guard let s = session(id), s.hasPose, let track = await pose(id) else { return }
        let input = session(id) ?? s
        let result = await Task.detached(priority: inBackground ? .utility : .userInitiated) {
            Analyzer.run(session: input, track: track)
        }.value
        guard var current = session(id), current.hasPose else { return }
        // Parameters changed while this ran: a newer analysis is queued and will replace it.
        if current.params != input.params || current.calibration != input.calibration
            || current.overrides != input.overrides || current.eventOverrides != input.eventOverrides {
            if !analysisQueue.contains(id) { enqueueAnalysis(id, background: inBackground) }
            return
        }
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
            Task { @MainActor [weak self] in self?.resultSaved(id, serial) }
        }
    }

    private func resultSaved(_ id: UUID, _ serial: Int) {
        if unsavedResults[id]?.serial == serial { unsavedResults[id] = nil }
        // No clean-up of a deleted analysis' folder here: a result is only written for an analysis
        // that exists, before any later delete on the same serial queue, so the file moves to
        // Recently Deleted with its folder. Removing the folder now could erase an analysis that
        // was deleted and restored (Undo) in the meantime.
    }

    // MARK: Memory

    func trimMemory() {
        poseCache.removeAll()
        poseOrder.removeAll()
        trimResults(keepRecent: 4, limit: 4)
    }

    // MARK: Storage

    func storageBytes() async -> Int64 {
        let base = self.base
        return await Task.detached(priority: .utility) { () -> Int64 in
            guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total: Int64 = 0
            while let url = e.nextObject() as? URL {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }.value
    }

    /// Free space on the library's volume (bytes), nil when unknown.
    nonisolated func freeSpace() -> Int64? {
        #if os(macOS)
        let values = try? base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
        #else
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: base.path)
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value
        #endif
    }
}

/// JSON coders for session.json, recording.json, result.json and studies (same as the iPhone app).
/// Non-finite numbers are written as strings so one NaN measure cannot prevent a file from saving.
enum Coders {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}
