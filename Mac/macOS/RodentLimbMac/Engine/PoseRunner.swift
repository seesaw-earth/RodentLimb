// PoseRunner.swift — runs the video's pose model (CylinderMousePoseV2, or PalmReaderPose8 for
// near-infrared dark-box videos — see Core/PoseModels.swift) over one video on the Mac.
//
// The frame path is the iPhone app's (Pose/PoseEngine.swift of RodentLimb 1.3), so a video gives the
// same keypoints on both: AVAssetReader decodes BGRA frames → Vision (VNCoreMLRequest, .scaleFit
// letterbox, orientation .up on the decoded buffer) → PoseDecoder → keypoints mapped into the
// displayed (orientation-corrected) frame.
//
// Mac additions:
//  • Checkpoint: every frame is appended to Recordings/<id>/checkpoint/ (PoseCheckpoint) and flushed
//    every ~2 s; a stopped, failed or crashed run continues after the last saved frame (the reader is
//    reopened at that time and the frames up to it are skipped).
//  • Stop requests (pause / cancel / quit) are honoured between frames; the checkpoint is flushed.
//  • A small live preview (about once per second) for the queue.
//  • One runner per worker thread; the model is loaded once per runner (on that thread, never on
//    the main thread) and reused for the following videos.
//  • Memory stays flat on long videos: each frame's Vision / Core ML / CoreVideo objects are released
//    in a per-frame autorelease pool, and only the keypoints are kept.

import Foundation
import AVFoundation
import CoreImage
import CoreML
import CoreVideo
import Vision

struct ModelInfo: Equatable {
    var version: String
    var inputSize: Int
    var author: String
}

/// Loads a pose model (compiled into the app as <name>.mlmodelc).
enum PoseModelLoader {
    /// The default model for new imports (CylinderPose7 FP16 unless changed in Settings).
    static var modelURL: URL? { modelURL(PoseModelID.defaultChoice) }
    static var isInstalled: Bool { modelURL != nil }

    static func modelURL(_ model: PoseModelID) -> URL? {
        Bundle.main.url(forResource: model.resourceName, withExtension: "mlmodelc")
    }
    static func isInstalled(_ model: PoseModelID) -> Bool { modelURL(model) != nil }

    static func computeUnits(_ c: ComputeChoice) -> MLComputeUnits {
        switch c {
        case .all: return .all
        case .cpuAndGPU: return .cpuAndGPU
        case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
        case .cpuOnly: return .cpuOnly
        }
    }

    /// Blocking; call off the main thread.
    static func load(_ model: PoseModelID = .visible, _ choice: ComputeChoice) throws -> (VNCoreMLModel, ModelInfo) {
        guard let url = modelURL(model) else {
            if model == PoseModelID.defaultChoice { throw PoseRunError.modelMissing }
            throw PoseRunError.modelFailed(String(format: L("%@ is not installed in this build.", "此版本未安装 %@。"), model.displayName))
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = computeUnits(choice)
            let ml = try MLModel(contentsOf: url, configuration: config)
            guard let image = ml.modelDescription.inputDescriptionsByName.values.compactMap({ $0.imageConstraint }).first else {
                throw PoseRunError.modelFailed(L("input is not an image", "输入不是图像"))
            }
            guard image.pixelsWide == image.pixelsHigh, image.pixelsWide > 0 else {
                throw PoseRunError.modelFailed("input \(image.pixelsWide)×\(image.pixelsHigh)")
            }
            let meta = ml.modelDescription.metadata
            let info = ModelInfo(version: (meta[.versionString] as? String) ?? "—",
                                 inputSize: image.pixelsWide,
                                 author: (meta[.author] as? String) ?? "")
            return (try VNCoreMLModel(for: ml), info)
        } catch let e as PoseRunError {
            throw e
        } catch {
            throw PoseRunError.modelFailed(error.localizedDescription)
        }
    }
}

/// Waits for an async AVFoundation call on a worker thread (never call from the main thread).
private final class Waiter<T>: @unchecked Sendable {
    var result: Result<T, Error>?
    let done = DispatchSemaphore(value: 0)
}

private func blocking<T>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
    let w = Waiter<T>()
    Task.detached(priority: .userInitiated) {
        do { w.result = .success(try await op()) } catch { w.result = .failure(error) }
        w.done.signal()
    }
    w.done.wait()
    guard let r = w.result else { throw PoseRunError.badVideo("no result") }
    return try r.get()
}

final class PoseRunner: VideoPoseRunning {
    /// Models loaded by this runner (each once, on its worker thread), by model.
    private var loaded: [PoseModelID: (model: VNCoreMLModel, info: ModelInfo)] = [:]
    private var lastModel: PoseModelID = .visible
    private let choice: ComputeChoice
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init(choice: ComputeChoice = .current) {
        self.choice = choice
    }

    var modelName: String { lastModel.rawValue }
    var modelVersion: String { loaded[lastModel]?.info.version ?? "—" }

    func run(_ job: PoseJob, control: ProcessingControl, progress: @escaping (RunProgress) -> Void) throws -> PoseTrack {
        let access = VideoBookmarks.access(job.videoURL, scoped: job.scoped)
        defer { _ = access }
        let url = job.videoURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw PoseRunError.videoMissing }
        progress(RunProgress(phase: .opening, framesDone: 0, framesTotal: 0, resumedFrames: 0, mediaTime: 0, duration: 0, preview: nil))

        let modelID = job.model
        if loaded[modelID] == nil { loaded[modelID] = try PoseModelLoader.load(modelID, choice) }
        guard let l = loaded[modelID] else { throw PoseRunError.modelMissing }
        lastModel = modelID
        let model = l.model, info = l.info

        // MARK: Video facts
        let fp: VideoFingerprint.Info
        do { fp = try VideoFingerprint.make(url) } catch { throw PoseRunError.videoMissing }
        let asset = AVURLAsset(url: url)
        let tracks = try blocking { try await asset.loadTracks(withMediaType: .video) }
        guard let track = tracks.first else { throw PoseRunError.noVideoTrack }
        let (cmDuration, rawFPS, transform, natural) = try blocking {
            async let d = asset.load(.duration)
            async let f = track.load(.nominalFrameRate)
            async let t = track.load(.preferredTransform)
            async let n = track.load(.naturalSize)
            return try await (d, f, t, n)
        }
        // No decoder for this codec on this Mac: fail now with the reason (not retryable), instead of
        // three reader failures (VideoToolbox err -12906 in the console).
        let codec: String = (try? blocking { () -> String in
            let formats = try await track.load(.formatDescriptions)
            return formats.first.map { VideoProbe.fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? ""
        }) ?? ""
        if (try? blocking { try await track.load(.isDecodable) }) == false {
            throw PoseRunError.badVideo(VideoProbe.undecodableMessage(codec: codec))
        }
        let duration = CMTimeGetSeconds(cmDuration)
        guard duration.isFinite, duration > 0 else { throw PoseRunError.badVideo(L("zero duration", "时长为 0")) }
        let nominalFPS = rawFPS.isFinite && rawFPS > 0 ? Double(rawFPS) : 0
        let fps = nominalFPS > 0 ? nominalFPS : 30
        let estimated = max(1, Int(safe: duration * fps, fallback: 1))
        let upright = CGRect(origin: .zero, size: natural).applying(transform)
        let dispW0 = Int(safe: Double(abs(upright.width)).rounded(), fallback: 0)
        let dispH0 = Int(safe: Double(abs(upright.height)).rounded(), fallback: 0)
        guard dispW0 > 0, dispH0 > 0 else { throw PoseRunError.badVideo(L("invalid frame size", "画面尺寸无效")) }

        // MARK: Checkpoint
        let fresh = PoseCheckpointManifest(videoSize: fp.size, videoModified: fp.modified, videoFingerprint: fp.fingerprint,
                                           modelName: modelID.rawValue, modelVersion: info.version, boxThreshold: job.boxThreshold,
                                           width: dispW0, height: dispH0, fps: fps, duration: duration)
        let resume: PoseCheckpoint.Resume
        let writer: PoseCheckpointWriter
        do {
            resume = try PoseCheckpoint.prepare(folder: job.checkpointFolder, fresh: fresh)
            writer = try PoseCheckpointWriter(folder: job.checkpointFolder, resume: resume)
        } catch {
            throw PoseRunError.writeFailed(error.localizedDescription)
        }
        let resumed = resume.rows.count
        var acc = PoseCheckpoint.track(rows: resume.rows, manifest: resume.manifest)
        acc.reserve(min(estimated, 1_000_000) + 16)
        var firstPTS: Double? = resume.manifest.firstPTS ?? resume.rows.first?.pts
        let skipThrough = resume.lastPTS

        // MARK: Reader
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        do {
            reader = try AVAssetReader(asset: asset)
            if let s = skipThrough, s.isFinite, s > 0.05 {
                // Reopen just before the last saved frame; frames up to it are skipped below.
                let start = CMTime(seconds: max(0, s - 0.05), preferredTimescale: 600_000)
                reader.timeRange = CMTimeRange(start: start, duration: .positiveInfinity)
            }
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw PoseRunError.readerFailed("cannot add output") }
            reader.add(output)
        } catch let e as PoseRunError {
            throw e
        } catch {
            throw PoseRunError.readerFailed(error.localizedDescription)
        }
        guard reader.startReading() else {
            if resume.rows.isEmpty { throw PoseRunError.badVideo(VideoProbe.undecodableMessage(codec: codec)) }
            throw PoseRunError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit

        var decoder: PoseDecoder?
        var decoderSize = (0, 0)
        var lastReport = 0.0
        var lastPreview = -10.0
        var frame = resumed
        var lastMediaTime = skipThrough ?? 0

        func stopIfRequested() throws {
            if let r = control.stopReason {
                writer.suspend()
                throw PoseRunError.stopped(r)
            }
        }

        while true {
            try stopIfRequested()
            thermalPause()

            var sampleBuffer: CMSampleBuffer?
            autoreleasepool { sampleBuffer = output.copyNextSampleBuffer() }
            guard let sample = sampleBuffer else {
                if reader.status == .completed { break }
                writer.suspend()
                if reader.status == .cancelled { throw PoseRunError.stopped(control.stopReason ?? .pause) }
                // A missing file (drive unplugged) shows up as a reader failure.
                if !FileManager.default.fileExists(atPath: url.path) { throw PoseRunError.videoMissing }
                // Not a single frame of a fresh run decoded: the codec cannot be decoded here.
                if frame == 0 && reader.status == .failed { throw PoseRunError.badVideo(VideoProbe.undecodableMessage(codec: codec)) }
                throw PoseRunError.readerFailed(reader.error?.localizedDescription ?? "stopped at \(String(format: "%.1f", lastMediaTime)) s")
            }
            let ptsTime = CMSampleBufferGetPresentationTimeStamp(sample)
            let pts = CMTimeGetSeconds(ptsTime)
            if let s = skipThrough, pts.isFinite, pts <= s + 1e-6 { continue }
            guard pts.isFinite, let pixel = CMSampleBufferGetImageBuffer(sample) else { continue }

            let width = CVPixelBufferGetWidth(pixel)
            let height = CVPixelBufferGetHeight(pixel)
            guard width > 0, height > 0 else { continue }
            if decoder == nil || decoderSize != (width, height) {
                decoder = PoseDecoder(threshold: job.boxThreshold, imageWidth: width, imageHeight: height, inputSize: info.inputSize,
                                      model: modelID)
                decoderSize = (width, height)
            }
            guard let decoder else { continue }
            // Raw buffer → displayed frame (the same mapping as the iPhone app).
            let displayRect = CGRect(x: 0, y: 0, width: width, height: height).applying(transform)

            // Inference, with two quick retries for a transient Vision / Core ML error.
            var decoded: DecodedPose?
            var attempt = 0
            while true {
                do {
                    decoded = try autoreleasepool { () throws -> DecodedPose? in
                        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
                        try handler.perform([request])
                        guard let obs = (request.results ?? []).compactMap({ $0 as? VNCoreMLFeatureValueObservation })
                            .first(where: { $0.featureValue.multiArrayValue != nil }),
                              let array = obs.featureValue.multiArrayValue else {
                            throw PoseRunError.modelFailed(L("no MLMultiArray output (was the model exported with nms=True?)",
                                                             "没有 MLMultiArray 输出（导出时是否设置了 nms=True？）"))
                        }
                        return try decoder.decode(array)
                    }
                    break
                } catch let e as PoseRunError {
                    writer.suspend()
                    throw e
                } catch {
                    attempt += 1
                    if attempt > 2 {
                        writer.suspend()
                        throw PoseRunError.inferenceFailed(frame, error.localizedDescription)
                    }
                    Thread.sleep(forTimeInterval: 0.2)
                    try stopIfRequested()
                }
            }

            if firstPTS == nil {
                firstPTS = pts
                do { try writer.setFirstPTS(pts) } catch { writer.suspend(); throw PoseRunError.writeFailed(error.localizedDescription) }
            }
            var row = PoseRow.missing(frame: frame, pts: pts)
            row.box = Float(decoded?.score ?? 0)
            var previewPoints: [CGPoint?] = []
            for k in Kp.allCases {
                if let kp = decoded?.keypoints[k.rawValue], kp.x >= 0, kp.y >= 0 {
                    let p = CGPoint(x: kp.x, y: kp.y).applying(transform)
                    let dx = Double(p.x - displayRect.minX), dy = Double(p.y - displayRect.minY)
                    row.x[k.rawValue] = Float(dx)
                    row.y[k.rawValue] = Float(dy)
                    row.c[k.rawValue] = Float(kp.confidence)
                    previewPoints.append(kp.confidence >= 0.3 ? CGPoint(x: dx, y: dy) : nil)
                } else {
                    previewPoints.append(nil)
                }
            }
            do { try writer.append(row) } catch { writer.suspend(); throw PoseRunError.writeFailed(error.localizedDescription) }
            acc.times.append(max(0, pts - (firstPTS ?? pts)))
            acc.boxConfidence.append(row.box)
            for k in 0..<PoseRow.keypoints {
                acc.x[k].append(row.x[k]); acc.y[k].append(row.y[k]); acc.c[k].append(row.c[k])
            }
            frame += 1
            lastMediaTime = pts

            let now = ProcessInfo.processInfo.systemUptime
            var preview: PreviewSnapshot?
            if now - lastPreview >= 1.0 {
                lastPreview = now
                let image = autoreleasepool { previewImage(pixel, transform: transform) }
                preview = PreviewSnapshot(mediaTime: pts, frameWidth: Int(safe: Double(abs(displayRect.width))), frameHeight: Int(safe: Double(abs(displayRect.height))),
                                          keypoints: previewPoints, image: image)
            }
            if preview != nil || now - lastReport >= 0.25 {
                lastReport = now
                progress(RunProgress(phase: .tracking, framesDone: frame, framesTotal: max(estimated, frame), resumedFrames: resumed,
                                     mediaTime: pts - (firstPTS ?? 0), duration: duration, preview: preview))
            }
        }

        try stopIfRequested()
        guard frame > 0 else { writer.suspend(); throw PoseRunError.noFrames }
        progress(RunProgress(phase: .finishing, framesDone: frame, framesTotal: frame, resumedFrames: resumed,
                             mediaTime: duration, duration: duration, preview: nil))
        do { try writer.closeSegment() } catch { throw PoseRunError.writeFailed(error.localizedDescription) }

        acc.fps = fps
        acc.width = dispW0
        acc.height = dispH0
        if let last = acc.times.last { acc.duration = max(duration, last) } else { acc.duration = duration }
        acc.timeOffset = (firstPTS ?? 0).isFinite ? (firstPTS ?? 0) : 0
        acc.modelName = modelID.rawValue
        acc.modelVersion = info.version
        acc.sanitize()
        return acc
    }

    /// Slows down when the Mac is hot instead of letting it throttle hard (long batches keep the
    /// Neural Engine / GPU busy for hours).
    private func thermalPause() {
        switch ProcessInfo.processInfo.thermalState {
        case .critical: Thread.sleep(forTimeInterval: 0.08)
        case .serious: Thread.sleep(forTimeInterval: 0.01)
        default: break
        }
    }

    /// Small upright copy of the frame for the live preview.
    private func previewImage(_ pixel: CVPixelBuffer, transform: CGAffineTransform) -> CGImage? {
        let upright = CIImage(cvPixelBuffer: pixel).oriented(Self.orientation(transform))
        let ext = upright.extent
        guard ext.width > 0, ext.height > 0 else { return nil }
        let scale = min(1, 480 / max(ext.width, ext.height))
        let small = upright.transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(small, from: small.extent)
    }

    /// EXIF orientation of a track's preferred transform (the four rotations phones record).
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        // Rounded: phones write the rotation with small floating-point errors.
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
