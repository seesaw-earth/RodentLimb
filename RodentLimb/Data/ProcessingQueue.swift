// ProcessingQueue.swift — runs pose inference for queued sessions one at a time.
//
// Videos are processed sequentially (one model in memory). The screen is kept awake while
// running. If the app goes to the background, the current video is stopped and put back at the
// front of the queue; it restarts automatically when the app is active again.

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

    var renderSkeleton: () -> InferenceSettings = { InferenceSettings() }

    init(store: SessionStore, engine: PoseEngine) {
        self.store = store
        self.engine = engine
    }

    var queuedCount: Int { store.sessions.filter { $0.status == .queued }.count }

    func kick() {
        guard worker == nil, isActive else { return }
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
            pausedForBackground = false
            kick()
        case .background:
            isActive = false
            if currentID != nil {
                interruptedByBackground = true
                pausedForBackground = true
                control?.cancel()
            }
        default:
            break
        }
    }

    private func nextQueued() -> Session? {
        // Oldest first, so batches finish in import order.
        store.sessions.filter { $0.status == .queued }.min { $0.createdAt < $1.createdAt }
    }

    private func drain() async {
        while isActive, let s = nextQueued() {
            guard let loaded = await engine.load() else {
                // Model missing or failed: leave sessions queued; Home shows the model banner.
                return
            }
            let (model, info) = loaded
            let id = s.id
            currentID = id
            progress.fraction = 0
            progress.framesPerSecond = 0
            progress.secondsLeft = nil
            lastReport = .distantPast
            interruptedByBackground = false
            cancelledByUser = false
            store.update(id) { $0.status = .processing; $0.failure = nil }
            UIApplication.shared.isIdleTimerDisabled = true

            let control = ProcessingControl()
            self.control = control
            let settings = renderSkeleton()
            let videoURL = store.videoURL(s)
            let skeletonURL = settings.renderSkeletonVideo ? store.skeletonURL(id) : nil
            let started = Date()
            do {
                let track = try await Task.detached(priority: .userInitiated) {
                    try await PoseVideoProcessor.run(videoURL: videoURL, model: model, info: info, settings: settings,
                                                     skeletonURL: skeletonURL, control: control) { p in
                        Task { @MainActor [weak self] in self?.report(p, started: started) }
                    }
                }.value
                try store.storePose(track, for: id)
                store.update(id) {
                    $0.hasPose = true
                    $0.hasSkeletonVideo = skeletonURL != nil
                    $0.videoWidth = track.width
                    $0.videoHeight = track.height
                    $0.fps = track.fps
                    $0.duration = track.duration
                    $0.modelVersion = track.modelVersion
                    $0.status = $0.isCalibrated ? .done : .needsSetup
                }
                store.analyze(id)
            } catch {
                if interruptedByBackground {
                    store.update(id) { $0.status = .queued }
                } else if cancelledByUser || error is CancellationError {
                    store.update(id) { $0.status = .failed; $0.failure = L("Cancelled", "已取消") }
                } else {
                    store.update(id) { $0.status = .failed; $0.failure = error.localizedDescription }
                }
            }
            self.control = nil
            currentID = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func report(_ p: PoseVideoProcessor.Progress, started: Date) {
        guard currentID != nil else { return }
        let now = Date()
        // At most 4 updates per second (the last report of a video always goes through).
        guard p.done >= p.total || now.timeIntervalSince(lastReport) >= 0.25 else { return }
        lastReport = now
        progress.fraction = Double(p.done) / Double(max(1, p.total))
        let elapsed = now.timeIntervalSince(started)
        if elapsed > 1, p.done > 0 {
            let fps = Double(p.done) / elapsed
            progress.framesPerSecond = fps
            progress.secondsLeft = Double(max(0, p.total - p.done)) / max(0.1, fps)
        }
    }

    /// Re-queues a failed session.
    func retry(_ id: UUID) {
        store.update(id) { $0.status = .queued; $0.failure = nil }
        kick()
    }
}
