// ProcessingQueue.swift — runs pose inference for queued recordings (videos) one at a time.
// Every added video goes through its pose model once (the model chosen when it was added, kept in
// its sidecar); QC follows (SessionStore.finishProcessing). `currentID` is the id of the recording
// being processed.
//
// Videos are processed sequentially; each model is loaded once and reused. The screen is kept awake while
// running. As soon as the app stops being active (Control Center, a call, the app switcher) the
// video is paused, so no GPU work is submitted while iOS forbids it; when the app is active again
// it continues from the frame where it stopped. Only with "render skeleton video" on is the video
// restarted, because AVAssetWriter cannot resume after the app was in the background.

import Foundation
import SwiftUI
import UIKit

/// Live progress of the running video. Kept separate from ProcessingQueue so that only the
/// small progress views redraw while a video is processed — not whole screens with charts or
/// text fields (which made typing and scrolling stutter).
@MainActor
final class ProgressInfo: ObservableObject {
    @Published fileprivate(set) var fraction: Double = 0
    @Published fileprivate(set) var framesPerSecond: Double = 0
    @Published fileprivate(set) var secondsLeft: Double?
}

@MainActor
final class ProcessingQueue: ObservableObject {
    @Published private(set) var currentID: UUID?
    @Published private(set) var pausedForBackground = false
    let progress = ProgressInfo()
    private var lastReport = Date.distantPast

    private let store: SessionStore
    private let engine: PoseEngine
    private var control: ProcessingControl?
    private var worker: Task<Void, Never>?
    private var interruptedByBackground = false
    private var cancelledByUser = false
    private var isActive = true
    /// The scene is active (not merely visible behind Control Center, a call, the app switcher).
    private var isForeground = true
    /// The running video writes a skeleton MP4 (cannot be resumed after the background).
    private var runningWithSkeleton = false

    var renderSkeleton: () -> InferenceSettings = { InferenceSettings() }

    init(store: SessionStore, engine: PoseEngine) {
        self.store = store
        self.engine = engine
    }

    var queuedCount: Int { store.recordings.filter { $0.status == .queued }.count }

    func kick() {
        guard worker == nil, isActive, store.isLoaded else { return }
        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    func cancelCurrent() {
        cancelledByUser = true
        control?.cancel()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            isForeground = true
            pausedForBackground = false
            control?.resume()
            kick()
        case .inactive:
            // Stop submitting frames right away; nothing is lost, the loop just waits.
            isForeground = false
            control?.pause()
        case .background:
            isActive = false
            isForeground = false
            guard currentID != nil, let control else { break }
            control.pause()
            pausedForBackground = true
            if runningWithSkeleton {
                interruptedByBackground = true
                control.cancel()
            } else {
                control.noteInterruption()
            }
        default:
            break
        }
    }

    private func nextQueued() -> Recording? { store.nextQueuedRecording() }

    private func drain() async {
        while isActive, let first = nextQueued() {
            // The video's own model (CylinderPose7 FP16 for videos tracked before 1.4).
            let modelID = store.poseModel(first.id).runnable
            guard let loaded = await engine.load(modelID) else {
                // This model cannot be loaded: say why on the video and go on with the others.
                let message = engine.failure(modelID) ?? PoseError.missingModel(modelID).localizedDescription
                store.updateRecording(first.id) { $0.status = .failed; $0.failure = message }
                continue
            }
            // Start a video only while the app is active (no GPU work in the background). If the
            // app went to the background meanwhile, `kick()` restarts the queue when it is back.
            while isActive && !isForeground { try? await Task.sleep(nanoseconds: 200_000_000) }
            guard isActive, let r = nextQueued() else { return }
            // Another video came first meanwhile (re-queued): load its model on the next turn.
            guard store.poseModel(r.id).runnable == modelID else { continue }
            let (model, info) = loaded
            let id = r.id
            currentID = id
            progress.fraction = 0
            progress.framesPerSecond = 0
            progress.secondsLeft = nil
            lastReport = .distantPast
            rateAnchor = nil
            smoothedFPS = 0
            interruptedByBackground = false
            cancelledByUser = false
            store.updateRecording(id) { $0.status = .processing; $0.failure = nil }
            UIApplication.shared.isIdleTimerDisabled = true

            let control = ProcessingControl()
            self.control = control
            let settings = renderSkeleton()
            let videoURL = store.videoURL(r)
            let skeletonURL = settings.renderSkeletonVideo ? store.skeletonURL(id) : nil
            runningWithSkeleton = skeletonURL != nil
            let started = Date()
            do {
                let track = try await Task.detached(priority: .userInitiated) {
                    try await PoseVideoProcessor.run(videoURL: videoURL, model: model, info: info, modelID: modelID, settings: settings,
                                                     skeletonURL: skeletonURL, control: control) { p in
                        Task { @MainActor [weak self] in self?.report(p, started: started) }
                    }
                }.value
                // Saves the pose, computes QC, includes / assigns planned tasks, re-analyses tasks.
                try await store.finishProcessing(id, track: track, skeleton: skeletonURL != nil)
            } catch {
                if store.recording(id) == nil {
                    // Deleted while it was being processed: nothing to report.
                } else if interruptedByBackground || (error as? PoseError)?.isInterruption == true
                            || (!cancelledByUser && control.interruptionCount > 0 && !(error is CancellationError)) {
                    // The app was in the background during this video: whatever failed is most
                    // likely the interruption, so try the video again instead of reporting it.
                    store.updateRecording(id) { $0.status = .queued }
                } else if cancelledByUser || error is CancellationError {
                    store.updateRecording(id) { $0.status = .failed; $0.failure = L("Cancelled", "已取消") }
                } else {
                    store.updateRecording(id) { $0.status = .failed; $0.failure = error.localizedDescription }
                }
            }
            self.control = nil
            currentID = nil
            runningWithSkeleton = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func report(_ p: PoseVideoProcessor.Progress, started: Date) {
        guard currentID != nil else { return }
        let now = Date()
        // At most 4 updates per second (the last report of a video always goes through).
        guard p.done >= p.total || now.timeIntervalSince(lastReport) >= 0.25 else { return }
        lastReport = now
        progress.fraction = min(1, Double(p.done) / Double(max(1, p.total)))
        // Speed from recent progress only (smoothed), so time spent paused in the background
        // does not distort the estimate.
        if let anchor = rateAnchor, p.done >= anchor.done {
            let dt = now.timeIntervalSince(anchor.time)
            if dt > 4 {
                rateAnchor = (now, p.done)            // paused meanwhile: restart the measurement
            } else if dt >= 1 {
                let fps = Double(p.done - anchor.done) / dt
                smoothedFPS = smoothedFPS > 0 ? 0.7 * smoothedFPS + 0.3 * fps : fps
                rateAnchor = (now, p.done)
                progress.framesPerSecond = smoothedFPS
                progress.secondsLeft = smoothedFPS > 0.1 ? Double(max(0, p.total - p.done)) / smoothedFPS : nil
            }
        } else {
            rateAnchor = (now, p.done)
        }
    }

    private var rateAnchor: (time: Date, done: Int)?
    private var smoothedFPS = 0.0

    /// Re-queues a recording (failed, or tracking to be re-run), optionally with another model.
    func retry(recording id: UUID, model: PoseModelID? = nil) {
        if currentID == id { return }
        store.rerunDetection(id, model: model)
        kick()
    }
}
