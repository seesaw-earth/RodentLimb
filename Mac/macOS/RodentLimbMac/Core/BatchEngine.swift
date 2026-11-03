// BatchEngine.swift — runs the pose model over every queued video, unattended and without losing
// work.
//
//  • One video per worker thread (1–3 at a time, Settings › Processing). AVAssetReader and Vision
//    block, so they run on their own threads, never on the main thread or Swift's cooperative pool.
//  • Each video saves its keypoints while it runs (PoseCheckpoint): pausing, quitting, sleep, a
//    crash or a power cut lose at most a few seconds; the video then continues from where it was.
//  • One video's problem never stops the batch: retryable errors (a decoder hiccup, a Core ML
//    error) are retried from the checkpoint up to 3 times, anything else marks that video as failed
//    with the reason and the batch goes on.
//  • Videos whose file is not reachable (drive unplugged) wait in the queue and are skipped until
//    the file is back; the batch continues with the others.
//  • A crash journal (BatchJournal) notes which videos were running. If the app stops
//    unexpectedly twice while the same video runs, that video is set aside so an unattended batch
//    cannot crash in a loop.
//  • Low disk space pauses the batch instead of failing videos.
//
// Foundation + Observation only: the Mac runner (Engine/PoseRunner.swift) is injected, and tests
// use a simulated one (tools/tests).

import Foundation
import Observation

@MainActor
@Observable
final class BatchEngine {
    enum State: Equatable {
        case idle
        case running
        /// Paused by the user (running videos went back to the queue with their checkpoint).
        case paused
        /// The model could not be loaded (message).
        case waitingForModel(String)
        /// Less free space than `minimumFreeBytes` on the library's disk.
        case lowDisk
    }

    struct Job: Identifiable {
        var id: UUID
        var name: String
        var phase: RunProgress.Phase = .opening
        var framesDone = 0
        var framesTotal = 0
        var resumedFrames = 0
        var mediaTime: Double = 0
        var duration: Double = 0
        var fps: Double = 0
        var secondsLeft: Double?
        var startedAt = Date()

        var fraction: Double {
            if duration > 0 { return min(1, max(0, mediaTime / duration)) }
            return framesTotal > 0 ? min(1, Double(framesDone) / Double(framesTotal)) : 0
        }
    }

    struct Hooks {
        /// The engine started (true) or stopped (false) working: keep the Mac awake, show the Dock badge.
        var activeChanged: ((Bool) -> Void)?
        /// Overall progress of the batch 0…1 (nil when idle), at most a few times per second.
        var progressChanged: ((Double?) -> Void)?
        /// The queue ran empty after a batch.
        var finished: ((BatchSummary) -> Void)?
    }

    private(set) var state: State = .idle
    private(set) var jobs: [UUID: Job] = [:]
    /// Live preview of each running video (about once per second).
    private(set) var previews: [UUID: PreviewSnapshot] = [:]
    private(set) var summary = BatchSummary()
    /// Short status for the queue header (e.g. videos waiting for an offline drive).
    private(set) var notice: String?

    /// Videos processed at the same time.
    var maxSimultaneous = 1
    var boxThreshold = 0.25
    /// Start automatically when videos are queued.
    var autoStart = true
    /// Pause when the library's disk has less than this free.
    var minimumFreeBytes: Int64 = 300 * 1_048_576

    @ObservationIgnored var hooks = Hooks()
    @ObservationIgnored let store: SessionStore
    /// Makes a runner (the Mac: Core ML + AVFoundation). Runners are reused for later videos.
    @ObservationIgnored private let makeRunner: () -> VideoPoseRunning

    @ObservationIgnored private var idleRunners: [VideoPoseRunning] = []
    @ObservationIgnored private var controls: [UUID: ProcessingControl] = [:]
    @ObservationIgnored private var accesses: [UUID: VideoAccess] = [:]
    @ObservationIgnored private var meters: [UUID: ThroughputMeter] = [:]
    @ObservationIgnored private var journal = BatchJournal()
    @ObservationIgnored private var batchStarted: Date?
    @ObservationIgnored private var lastProgressHook = 0.0
    @ObservationIgnored private var wasActive = false
    /// Recordings stopped by the user's cancel (not retried).
    @ObservationIgnored private var cancelled = Set<UUID>()

    init(store: SessionStore, makeRunner: @escaping () -> VideoPoseRunning) {
        self.store = store
        self.makeRunner = makeRunner
    }

    /// Whether videos are running. Stored (changes only when a video starts or stops), so menus and
    /// toolbars that read it are not rebuilt by the per-frame progress in `jobs`.
    private(set) var isActive = false
    var runningIDs: [UUID] { Array(jobs.keys) }

    /// Queued videos that can start now (file reachable), in queue order.
    var eligibleQueue: [Recording] {
        store.queuedRecordings.filter { jobs[$0.id] == nil && !store.missingVideos.contains($0.id) }
    }

    /// `eligibleQueue.count` without building and sorting the queue (progress and the time left are
    /// read several times a second while tracking).
    var eligibleCount: Int {
        var n = 0
        for r in store.recordings where r.status == .queued && jobs[r.id] == nil && !store.missingVideos.contains(r.id) { n += 1 }
        return n
    }

    var waitingOffline: Int {
        var n = 0
        for r in store.recordings where r.status == .queued && store.missingVideos.contains(r.id) { n += 1 }
        return n
    }

    // MARK: Launch recovery

    /// Reads the crash journal left by the previous run of the app (call once, after the library loaded).
    func recoverAfterLaunch() {
        let previous = BatchJournal.load(store.base)
        BatchJournal.clear(store.base)
        guard !previous.running.isEmpty else { return }
        for id in previous.running where store.recording(id) != nil {
            store.noteCrash(id)
            let crashes = store.source(id)?.crashes ?? 0
            let name = store.recording(id).map { store.displayName($0) } ?? id.uuidString
            if crashes >= BatchJournal.crashLimit {
                store.markFailed(id, L("The app stopped unexpectedly twice while processing this video, so it was set aside. Check that the file plays in QuickTime (or convert it to H.264 MP4), then choose Retry.",
                                       "处理该视频时 App 两次意外退出，已将其搁置。请确认文件能在 QuickTime 中播放（或转为 H.264 MP4），然后选择“重试”。"))
                summary.failed += 1
                store.log.write("Recovered after an unexpected stop: \(name) set aside (stopped \(crashes)×)")
            } else {
                store.log.write("Recovered after an unexpected stop: \(name) will continue from its checkpoint")
            }
        }
    }

    // MARK: Control

    /// Starts (or resumes) the batch.
    func start() {
        switch state {
        case .running: break
        default:
            state = .running
            notice = nil
        }
        if batchStarted == nil {
            batchStarted = Date()
            summary = BatchSummary()
        }
        fill()
    }

    /// Starts when videos are waiting and automatic start is on.
    func kick() {
        guard autoStart else { return }
        if case .idle = state, !eligibleQueue.isEmpty { start() }
    }

    /// Pauses the batch: running videos stop after their current frame, save their checkpoint and go
    /// back to the front of the queue.
    func pause() {
        state = .paused
        for (_, c) in controls { c.stop(.pause) }
        updateActivity()
    }

    /// Stops one video. It is marked as cancelled (its checkpoint is kept; Retry continues it).
    func cancel(_ id: UUID) {
        cancelled.insert(id)
        controls[id]?.stop(.cancel)
    }

    /// Stops everything and waits until the running videos saved their checkpoints (quit, closing
    /// the library). Returns after at most `timeout` seconds.
    func shutdown(timeout: Double = 12) async {
        state = .paused
        for (_, c) in controls { c.stop(.shutdown) }
        // The runs stop after their current frame and report back on the main actor.
        let deadline = Date().addingTimeInterval(timeout)
        while !jobs.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        if jobs.isEmpty {
            BatchJournal.clear(store.base)
        }
        updateActivity()
    }

    // MARK: Scheduling

    private func fill() {
        guard state == .running else { updateActivity(); return }
        if let free = store.freeSpace(), free < minimumFreeBytes {
            state = .lowDisk
            notice = L("Paused: less than 300 MB free on the library's disk. Free some space, then press Start.",
                       "已暂停：资料库所在磁盘剩余空间不足 300 MB。请释放空间后点击“开始”。")
            store.log.write("Paused: low disk space")
            updateActivity()
            return
        }
        while jobs.count < max(1, maxSimultaneous) {
            guard let next = nextEligible() else { break }
            launch(next)
        }
        if jobs.isEmpty { finishBatchIfDone() }
        updateActivity()
    }

    private func nextEligible() -> Recording? {
        for r in store.queuedRecordings where jobs[r.id] == nil {
            if store.missingVideos.contains(r.id) { continue }
            if store.videoURL(r) == nil { continue }
            return r
        }
        return nil
    }

    private func launch(_ r: Recording) {
        let id = r.id
        guard let access = store.videoAccess(r) else {
            // Offline: stays queued, skipped until the file is back.
            return
        }
        let runner = idleRunners.popLast() ?? makeRunner()
        let control = ProcessingControl()
        controls[id] = control
        accesses[id] = access
        meters[id] = ThroughputMeter()
        let name = store.displayName(r)
        jobs[id] = Job(id: id, name: name, duration: r.duration ?? 0)
        if !isActive { isActive = true }
        store.markProcessing(id)
        journal.running.append(id)
        journal.updatedAt = Date()
        journal.save(store.base)
        store.log.write("Start \(name) (\(r.originalName))")

        // A video of a model no longer shipped (CylinderMousePoseV2) is tracked with its successor,
        // which is recorded so labels and exports name the model that produced the new pose.
        let model = store.poseModel(id).runnable
        if model != store.poseModel(id) { store.updateSource(id) { $0.poseModel = model } }
        let job = PoseJob(recordingID: id, videoURL: access.url, scoped: false,
                          checkpointFolder: store.checkpointFolder(id), boxThreshold: boxThreshold, name: name,
                          model: model)
        let box = RunnerBox(runner)
        let thread = Thread { [weak self] in
            var outcome: Result<PoseTrack, Error>
            do {
                let track = try box.runner.run(job, control: control) { p in
                    Task { @MainActor [weak self] in self?.report(id, p) }
                }
                outcome = .success(track)
            } catch {
                outcome = .failure(error)
            }
            let finalOutcome = outcome
            Task { @MainActor [weak self] in
                await self?.finished(id, runner: box.runner, outcome: finalOutcome)
            }
        }
        thread.name = "RodentLimb pose \(name)"
        thread.qualityOfService = .userInitiated
        thread.stackSize = 16 << 20
        thread.start()
    }

    private func report(_ id: UUID, _ p: RunProgress) {
        guard var j = jobs[id] else { return }
        j.phase = p.phase
        j.framesDone = p.framesDone
        j.framesTotal = max(p.framesTotal, p.framesDone)
        j.resumedFrames = p.resumedFrames
        j.mediaTime = p.mediaTime
        if p.duration > 0 { j.duration = p.duration }
        var m = meters[id] ?? ThroughputMeter()
        m.update(frames: p.framesDone, now: Date().timeIntervalSince1970)
        meters[id] = m
        j.fps = m.fps
        if m.fps > 0.1 {
            j.secondsLeft = Double(max(0, j.framesTotal - j.framesDone)) / m.fps
        }
        jobs[id] = j
        if let preview = p.preview { previews[id] = preview }
        let now = Date().timeIntervalSince1970
        if now - lastProgressHook >= 0.5 {
            lastProgressHook = now
            hooks.progressChanged?(overallFraction)
        }
    }

    private func finished(_ id: UUID, runner: VideoPoseRunning, outcome: Result<PoseTrack, Error>) async {
        let job = jobs[id]
        let wasCancelled = cancelled.remove(id) != nil
        controls[id] = nil
        meters[id] = nil
        previews[id] = nil
        journal.running.removeAll { $0 == id }
        journal.updatedAt = Date()
        if journal.running.isEmpty { BatchJournal.clear(store.base) } else { journal.save(store.base) }
        let name = job?.name ?? id.uuidString

        switch outcome {
        case .success(let track):
            do {
                // The track names the model and version that produced it (two models can be in use).
                try await store.finishProcessing(id, track: track, modelVersion: track.modelVersion.isEmpty ? runner.modelVersion : track.modelVersion)
                summary.finished += 1
                summary.frames += track.frameCount
                if let r = store.recording(id), r.decision == .pending { summary.needsReview += 1 }
                idleRunners.append(runner)
            } catch {
                store.markQueued(id)
                state = .lowDisk
                notice = PoseRunError.writeFailed(error.localizedDescription).errorDescription
                idleRunners.append(runner)
            }
        case .failure(let error):
            let e = error as? PoseRunError
            switch e {
            case .stopped(let reason)?:
                idleRunners.append(runner)
                if reason == .cancel || wasCancelled {
                    store.markFailed(id, L("Cancelled — choose Retry to continue from where it stopped.", "已取消——选择“重试”可从中断处继续。"))
                } else {
                    store.markQueued(id)
                    if reason == .pause { store.reorderQueue([id], toFront: true) }
                    store.log.write("\(reason == .pause ? "Paused" : "Stopped") \(name) at \(Int(job?.mediaTime ?? 0)) s (checkpoint kept)")
                }
            case .modelMissing?, .modelFailed?:
                // Do not reuse a runner whose model failed to load.
                store.markQueued(id)
                let message = e?.errorDescription ?? error.localizedDescription
                state = .waitingForModel(message)
                notice = message
                for (_, c) in controls { c.stop(.pause) }
                store.log.write("Model problem: \(message)")
            case .videoMissing?:
                idleRunners.append(runner)
                store.markQueued(id)
                await store.refreshAvailability()
            case .writeFailed?:
                idleRunners.append(runner)
                store.markQueued(id)
                state = .lowDisk
                notice = e?.errorDescription
                for (_, c) in controls { c.stop(.pause) }
            default:
                idleRunners.append(runner)
                let attempts = store.source(id)?.attempts ?? 1
                let message = e?.errorDescription ?? error.localizedDescription
                if (e?.isRetryable ?? false) && attempts < 3 && !wasCancelled {
                    store.markQueued(id)
                    store.log.write("Retrying \(name) from its checkpoint (attempt \(attempts + 1)): \(message)")
                } else {
                    store.markFailed(id, message)
                    summary.failed += 1
                }
            }
        }
        jobs[id] = nil
        if jobs.isEmpty && isActive { isActive = false }
        accesses[id] = nil
        hooks.progressChanged?(overallFraction)
        fill()
    }

    private func finishBatchIfDone() {
        guard jobs.isEmpty, state == .running else { return }
        if eligibleQueue.isEmpty {
            state = .idle
            let offline = waitingOffline
            notice = offline > 0
                ? String(format: L("%d video(s) are waiting because their file is not reachable (drive not connected?). Reconnect it, or use Locate Video…",
                                   "%d 个视频的文件无法访问（磁盘未连接？），正在等待。请重新连接，或使用“定位视频…”。"), offline)
                : nil
            if let started = batchStarted, summary.finished + summary.failed > 0 {
                summary.seconds = Date().timeIntervalSince(started)
                store.log.write("Batch finished: \(summary.finished) done, \(summary.failed) failed, \(summary.needsReview) need QC review, \(summary.frames) frames in \(Int(summary.seconds)) s")
                hooks.finished?(summary)
            }
            batchStarted = nil
        }
    }

    private func updateActivity() {
        let active = !jobs.isEmpty
        if active != wasActive {
            wasActive = active
            hooks.activeChanged?(active)
            if !active { hooks.progressChanged?(nil) }
        }
    }

    // MARK: Progress

    /// Overall progress of the current batch (finished + failed + running fractions over all
    /// videos of the batch), nil when nothing runs.
    var overallFraction: Double? {
        guard !jobs.isEmpty else { return nil }
        let done = Double(summary.finished + summary.failed)
        let running = jobs.values.reduce(0.0) { $0 + $1.fraction }
        let total = done + Double(jobs.count + eligibleCount)
        guard total > 0 else { return nil }
        return min(1, (done + running) / total)
    }

    /// Seconds until the whole queue is done (from the measured speed and the queued videos'
    /// durations), nil while unknown.
    var queueSecondsLeft: Double? {
        let speed = jobs.values.reduce(0.0) { $0 + $1.fps }
        guard speed > 0.5 else { return nil }
        var frames = 0.0
        for j in jobs.values { frames += Double(max(0, j.framesTotal - j.framesDone)) }
        // Order does not matter for a sum: no sorting.
        for r in store.recordings where r.status == .queued && jobs[r.id] == nil && !store.missingVideos.contains(r.id) {
            let d = r.duration ?? 0, f = r.fps ?? 30
            frames += d > 0 ? d * (f > 0 ? f : 30) : 0
        }
        return frames / speed
    }
}

/// Hands a runner to its worker thread. A runner is used by one thread at a time: the engine takes it
/// from the idle pool, the thread runs one video, and the engine puts it back after `finished`.
private final class RunnerBox: @unchecked Sendable {
    let runner: VideoPoseRunning
    init(_ runner: VideoPoseRunning) { self.runner = runner }
}
