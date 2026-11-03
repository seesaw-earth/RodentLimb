// PoseEngine.swift — loads the pose models (once each, off the main thread) and runs whole-video
// inference with the model chosen for the video (PoseModels.swift: CylinderPose7 FP16 by default,
// PalmReaderPose8 for near-infrared dark-box videos).
//
// Inference path is identical to the CylinderPose A/B app that validated the visible-light network
// (Vision, .scaleFit letterbox, orientation .up on the decoded buffer). After decoding, keypoints are
// mapped into the displayed (orientation-corrected) frame so overlays, calibration and analysis all
// share one coordinate system. The model's name is written into the track (pose.bin).

import Foundation
import AVFoundation
import CoreML
import Vision
import CoreVideo
import CoreGraphics

enum PoseError: LocalizedError {
    case missingModel(PoseModelID)
    case unsupportedModel(String)
    case noVideoTrack
    case badVideo(String)
    case readerFailed(String)
    case writerFailed(String)
    case inferenceFailed(Int, String)
    case noFrames
    /// The app went to the background and the work could not be resumed (skeleton video).
    case interrupted

    var isInterruption: Bool {
        if case .interrupted = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .missingModel(let m):
            return String(format: L("The pose model %@ is not in this build of the app.", "此版本 App 中没有姿态模型 %@。"), m.rawValue)
        case .unsupportedModel(let d):
            return L("The Core ML model format is not supported (expected a raw pose head without NMS): ", "Core ML 模型格式不受支持（需要未经 NMS 的 pose 输出）：") + d
        case .noVideoTrack:
            return L("This file has no readable video track.", "该文件没有可读取的视频轨道。")
        case .badVideo(let d):
            return L("The video can't be used: ", "视频无法使用：") + d
        case .readerFailed(let d):
            return L("Reading the video failed: ", "读取视频失败：") + d
        case .writerFailed(let d):
            return L("Writing the skeleton video failed: ", "写入骨架视频失败：") + d
        case .inferenceFailed(let f, let d):
            return String(format: L("Pose inference failed at frame %d: ", "第 %d 帧姿态推理失败："), f) + d
        case .noFrames:
            return L("No frames could be decoded. Try converting the video to H.264 MP4.", "没有解码出任何画面，请尝试将视频转为 H.264 MP4。")
        case .interrupted:
            return L("Interrupted because the app went to the background.", "App 切到后台，处理被中断。")
        }
    }
}

/// Name of the full-precision visible-light model of iPhone 1.0–1.3 (no longer shipped). The shared
/// exporter writes it; exports of videos tracked with another model are corrected afterwards
/// (ExportFixes.swift). Videos without a recorded model were tracked with it.
let kPoseModelName = "CylinderMousePoseV2"

/// Thread-safe control of one running video: cancel, pause / resume, and a counter of
/// background interruptions.
///
/// When the app leaves the foreground the processor must stop submitting GPU work at once
/// (iOS refuses background GPU work, and since iOS 26 in-flight GPU work at that moment can take
/// the app down). It is therefore *paused* as soon as the scene becomes inactive, and resumed when
/// it is active again. While the app is in the background AVFoundation also gives up its video
/// decoder, so after a background interruption the reader is reopened at the last processed
/// frame instead of starting the whole video again.
final class ProcessingControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var paused = false
    private var interruptions = 0

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func pause() { lock.lock(); paused = true; lock.unlock() }
    func resume() { lock.lock(); paused = false; lock.unlock() }
    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }

    /// Called when the app enters the background during the run.
    func noteInterruption() { lock.lock(); interruptions += 1; lock.unlock() }
    var interruptionCount: Int { lock.lock(); defer { lock.unlock() }; return interruptions }

    /// Returns once not paused. No frame is decoded or inferred meanwhile.
    func waitWhilePaused() async throws {
        while isPaused {
            if isCancelled { throw CancellationError() }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if isCancelled { throw CancellationError() }
    }
}

struct ModelInfo: Equatable {
    var version: String
    var inputSize: Int
    var author: String
}

@MainActor
final class PoseEngine: ObservableObject {
    enum State: Equatable {
        case notLoaded
        case missing
        case ready(ModelInfo)
        case failed(String)
    }

    /// State of each model that has been checked or loaded.
    @Published private(set) var states: [PoseModelID: State] = [:]

    /// State of the model preselected for new videos (Settings, banners).
    var state: State { state(PoseModelID.defaultChoice) }

    func state(_ m: PoseModelID) -> State { states[m] ?? (Self.modelURL(m) == nil ? .missing : .notLoaded) }

    private var cached: [PoseModelID: (model: VNCoreMLModel, info: ModelInfo)] = [:]
    /// Loads in progress, shared by concurrent callers (app start and the queue), so a model is
    /// never compiled and held in memory twice.
    private var loading: [PoseModelID: Task<(VNCoreMLModel, ModelInfo)?, Never>] = [:]

    /// Compiled model in the app bundle (<name>.mlmodelc).
    nonisolated static func modelURL(_ m: PoseModelID) -> URL? {
        Bundle.main.url(forResource: m.resourceName, withExtension: "mlmodelc")
    }

    func isInstalled(_ m: PoseModelID) -> Bool { Self.modelURL(m) != nil }
    var isInstalled: Bool { isInstalled(PoseModelID.defaultChoice) }

    /// The model, loaded once (off the main thread) and kept for the following videos.
    func load(_ m: PoseModelID) async -> (VNCoreMLModel, ModelInfo)? {
        if let c = cached[m] { return (c.model, c.info) }
        if let running = loading[m] { return await running.value }
        let task = Task { await self.loadNow(m) }
        loading[m] = task
        let value = await task.value
        loading[m] = nil
        return value
    }

    /// Error message of a model that could not be loaded (nil while it loads or when it works).
    func failure(_ m: PoseModelID) -> String? {
        switch state(m) {
        case .missing: return PoseError.missingModel(m).errorDescription
        case .failed(let message): return message
        default: return nil
        }
    }

    private func loadNow(_ m: PoseModelID) async -> (VNCoreMLModel, ModelInfo)? {
        if let c = cached[m] { return (c.model, c.info) }
        guard let url = Self.modelURL(m) else { states[m] = .missing; return nil }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> (VNCoreMLModel, ModelInfo) in
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let ml = try MLModel(contentsOf: url, configuration: config)
                guard let image = ml.modelDescription.inputDescriptionsByName.values.compactMap({ $0.imageConstraint }).first else {
                    throw PoseError.unsupportedModel(L("input is not an image", "输入不是图像"))
                }
                guard image.pixelsWide == image.pixelsHigh, image.pixelsWide > 0 else {
                    throw PoseError.unsupportedModel("input \(image.pixelsWide)×\(image.pixelsHigh)")
                }
                let meta = ml.modelDescription.metadata
                let info = ModelInfo(version: (meta[.versionString] as? String) ?? "—",
                                     inputSize: image.pixelsWide,
                                     author: (meta[.author] as? String) ?? "")
                return (try VNCoreMLModel(for: ml), info)
            }.value
            cached[m] = (loaded.0, loaded.1)
            states[m] = .ready(loaded.1)
            return loaded
        } catch {
            states[m] = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Marks models that are not in the bundle (shown in Settings without loading anything).
    func checkInstalled() {
        for m in PoseModelID.choices where Self.modelURL(m) == nil { states[m] = .missing }
    }

    /// Drops loaded models (memory warning); they are loaded again for the next video.
    func trimMemory(keeping keep: PoseModelID?) {
        for m in cached.keys where m != keep { cached[m] = nil }
    }
}

// MARK: - Whole-video processing

enum PoseVideoProcessor {
    /// Presentation time of the first decodable frame (for tracks saved before `timeOffset`).
    static func firstFrameTime(url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        while let sample = out.copyNextSampleBuffer() {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if t.isFinite, CMSampleBufferGetNumSamples(sample) > 0 { return t }
        }
        return nil
    }

    struct Progress {
        var done: Int
        var total: Int
    }

    /// Runs the model on every frame. Returns the pose track (display coordinates). If
    /// `skeletonURL` is set, also writes an MP4 with the skeleton drawn on each frame.
    ///
    /// Memory: every frame's Vision / Core ML / CoreVideo objects are released inside a per-frame
    /// autorelease pool. Core ML allocates its prediction buffers on each call and frees them when
    /// the surrounding pool drains; a whole video otherwise runs inside one long task with no pool
    /// boundary, memory grows with every frame and iOS terminates the app on long videos.
    static func run(videoURL: URL, model: VNCoreMLModel, info: ModelInfo, modelID: PoseModelID, settings: InferenceSettings,
                    skeletonURL: URL?, control: ProcessingControl,
                    progress: @escaping (Progress) -> Void) async throws -> PoseTrack {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit

        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw PoseError.noVideoTrack }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw PoseError.badVideo(L("zero duration", "时长为 0")) }
        let rawFPS = Double(try await track.load(.nominalFrameRate))
        let nominalFPS = rawFPS.isFinite && rawFPS > 0 ? rawFPS : 0
        let transform = try await track.load(.preferredTransform)
        // No decoder for this codec on this device: fail now with the reason instead of a reader error.
        if (try? await track.load(.isDecodable)) == false {
            let formats = (try? await track.load(.formatDescriptions)) ?? []
            let codec = formats.first.map { VideoCodec.name(CMFormatDescriptionGetMediaSubType($0)) } ?? ""
            throw PoseError.badVideo(VideoCodec.undecodableMessage(codec: codec))
        }
        let estimated = max(1, Int(safe: duration * (nominalFPS > 0 ? nominalFPS : 30), fallback: 1))
        progress(Progress(done: 0, total: estimated))

        /// Opens a reader that decodes BGRA frames, optionally starting at `start` (resume).
        func makeReader(from start: CMTime?) throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
            let r = try AVAssetReader(asset: asset)
            if let start, start.isValid, start.isNumeric {
                r.timeRange = CMTimeRange(start: start, duration: .positiveInfinity)
            }
            let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            o.alwaysCopiesSampleData = false
            r.add(o)
            guard r.startReading() else { throw PoseError.readerFailed(r.error?.localizedDescription ?? "unknown") }
            return (r, o)
        }

        var (reader, output) = try makeReader(from: nil)
        defer { if reader.status == .reading { reader.cancelReading() } }

        guard let first = output.copyNextSampleBuffer(), let firstPixel = CMSampleBufferGetImageBuffer(first) else {
            throw PoseError.noFrames
        }
        let width = CVPixelBufferGetWidth(firstPixel)
        let height = CVPixelBufferGetHeight(firstPixel)
        guard width > 0, height > 0 else { throw PoseError.badVideo(L("invalid frame size", "画面尺寸无效")) }

        // Raw buffer → displayed frame.
        let displayRect = CGRect(x: 0, y: 0, width: width, height: height).applying(transform)
        let dispW = Int(safe: Double(abs(displayRect.width)).rounded(), fallback: width)
        let dispH = Int(safe: Double(abs(displayRect.height)).rounded(), fallback: height)
        func toDisplay(_ x: Double, _ y: Double) -> (Double, Double) {
            let p = CGPoint(x: x, y: y).applying(transform)
            return (Double(p.x - displayRect.minX), Double(p.y - displayRect.minY))
        }

        let decoder = PoseDecoder(threshold: settings.boxThreshold, imageWidth: width, imageHeight: height, inputSize: info.inputSize,
                                  model: modelID)
        var result = PoseTrack(width: dispW, height: dispH, fps: nominalFPS > 0 ? nominalFPS : 30, duration: duration,
                               modelName: modelID.rawValue, modelVersion: info.version)
        // Capped so a corrupt duration in the file header cannot request a huge allocation.
        result.reserve(min(estimated, 500_000) + 16)

        // Optional skeleton video.
        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        if let skeletonURL {
            try? FileManager.default.removeItem(at: skeletonURL)
            let w = try AVAssetWriter(outputURL: skeletonURL, fileType: .mp4)
            let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(12_000_000, max(3_000_000, width * height * 4))]
            ])
            i.expectsMediaDataInRealTime = false
            i.transform = transform
            w.add(i)
            let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
            guard w.startWriting() else { throw PoseError.writerFailed(w.error?.localizedDescription ?? "unknown") }
            w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(first))
            writer = w; input = i; adaptor = a
        }
        defer { if let w = writer, w.status == .writing { w.cancelWriting() } }

        /// Inference (and the optional skeleton frame) for one picture, in its own autorelease pool.
        func processFrame(_ pixel: CVPixelBuffer) throws -> (DecodedPose?, CVPixelBuffer?) {
            try autoreleasepool { () throws -> (DecodedPose?, CVPixelBuffer?) in
                let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
                try handler.perform([request])
                guard let obs = (request.results ?? []).compactMap({ $0 as? VNCoreMLFeatureValueObservation })
                    .first(where: { $0.featureValue.multiArrayValue != nil }),
                      let array = obs.featureValue.multiArrayValue else {
                    throw PoseError.unsupportedModel(L("no MLMultiArray output (was the model exported with nms=True?)", "没有 MLMultiArray 输出（导出时是否设置了 nms=True？）"))
                }
                let decoded = try decoder.decode(array)
                var rendered: CVPixelBuffer?
                if writer != nil {
                    rendered = try SkeletonPainter.render(source: pixel, pose: decoded, keypointThreshold: 0.3,
                                                          pool: adaptor?.pixelBufferPool)
                }
                return (decoded, rendered)
            }
        }

        var frame = 0
        var pending: CMSampleBuffer? = first
        let start0 = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(first))
        /// Presentation time of the last frame stored in `result` (resume point).
        var lastPTS: CMTime?
        /// After reopening the reader, frames up to this time were already processed.
        var skipThrough: CMTime?
        /// Background interruptions already handled by reopening the reader.
        var handledInterruptions = control.interruptionCount
        var reopenCount = 0
        var lastReport = ProcessInfo.processInfo.systemUptime

        while true {
            // Paused while the app is inactive or in the background: no GPU work is submitted.
            try await control.waitWhilePaused()
            try await thermalPause()

            let sample: CMSampleBuffer
            if let p = pending {
                sample = p
                pending = nil
            } else if let next = autoreleasepool(invoking: { output.copyNextSampleBuffer() }) {
                sample = next
            } else {
                if reader.status == .completed { break }
                // The decoder was taken away while the app was in the background: reopen the video
                // just after the last processed frame and carry on (the skeleton video cannot be
                // resumed — AVAssetWriter gives up its encoder in the background).
                if control.interruptionCount != handledInterruptions, writer == nil, reopenCount < 20,
                   lastPTS == nil || lastPTS?.isNumeric == true {
                    try await control.waitWhilePaused()
                    handledInterruptions = control.interruptionCount
                    reopenCount += 1
                    reader.cancelReading()
                    (reader, output) = try makeReader(from: lastPTS)
                    skipThrough = lastPTS
                    continue
                }
                if control.interruptionCount != handledInterruptions { throw PoseError.interrupted }
                throw PoseError.readerFailed(reader.error?.localizedDescription ?? "stopped")
            }
            if control.isCancelled { throw CancellationError() }

            let ptsTime = CMSampleBufferGetPresentationTimeStamp(sample)
            // After reopening, frames up to the resume point come again: skip them.
            if let skip = skipThrough {
                if ptsTime.isNumeric, CMTimeCompare(ptsTime, skip) <= 0 { continue }
                skipThrough = nil
            }
            guard let pixel = CMSampleBufferGetImageBuffer(sample) else { continue }

            var decoded: DecodedPose?
            var rendered: CVPixelBuffer?
            var attempts = 0
            while true {
                do {
                    (decoded, rendered) = try processFrame(pixel)
                    break
                } catch let e as PoseError {
                    throw e
                } catch {
                    // GPU work submitted just as the app leaves the foreground is refused (the
                    // inactive notification may even arrive a moment later). Wait briefly, and
                    // until the app is active again, then run this frame once more.
                    if attempts < 3 {
                        attempts += 1
                        try await Task.sleep(nanoseconds: 300_000_000)
                        try await control.waitWhilePaused()
                        continue
                    }
                    throw PoseError.inferenceFailed(frame, error.localizedDescription)
                }
            }

            let pts = CMTimeGetSeconds(ptsTime)
            result.times.append(pts.isFinite ? max(0, pts - (start0.isFinite ? start0 : 0)) : Double(frame) / result.fps)
            result.boxConfidence.append(Float(decoded?.score ?? 0))
            for k in Kp.allCases {
                if let kp = decoded?.keypoints[k.rawValue], kp.x >= 0, kp.y >= 0 {
                    let (dx, dy) = toDisplay(kp.x, kp.y)
                    result.x[k.rawValue].append(Float(dx))
                    result.y[k.rawValue].append(Float(dy))
                    result.c[k.rawValue].append(Float(kp.confidence))
                } else {
                    result.x[k.rawValue].append(-1)
                    result.y[k.rawValue].append(-1)
                    result.c[k.rawValue].append(0)
                }
            }

            if let w = writer, let i = input, let a = adaptor, let rendered {
                var waitStart = ProcessInfo.processInfo.systemUptime
                while !i.isReadyForMoreMediaData {
                    if control.isCancelled { throw CancellationError() }
                    // Time spent paused does not count towards the encoder timeout.
                    if control.isPaused { waitStart = ProcessInfo.processInfo.systemUptime }
                    if w.status != .writing {
                        if control.interruptionCount != handledInterruptions { throw PoseError.interrupted }
                        throw PoseError.writerFailed(w.error?.localizedDescription ?? "status \(w.status.rawValue)")
                    }
                    if !control.isPaused, ProcessInfo.processInfo.systemUptime - waitStart > 20 {
                        throw PoseError.writerFailed(L("encoder timed out", "编码器超时"))
                    }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                guard a.append(rendered, withPresentationTime: ptsTime) else {
                    if control.interruptionCount != handledInterruptions { throw PoseError.interrupted }
                    throw PoseError.writerFailed(w.error?.localizedDescription ?? "append failed")
                }
            }

            lastPTS = ptsTime
            frame += 1
            // Progress at most 5× per second (each report hops to the main actor).
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastReport >= 0.2 {
                lastReport = now
                progress(Progress(done: frame, total: max(estimated, frame)))
            }
        }
        guard frame > 0 else { throw PoseError.noFrames }

        if let w = writer, let i = input {
            i.markAsFinished()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in w.finishWriting { c.resume() } }
            guard w.status == .completed else { throw PoseError.writerFailed(w.error?.localizedDescription ?? "finish failed") }
        }
        if let last = result.times.last { result.duration = max(duration, last) }
        result.timeOffset = start0.isFinite ? start0 : 0
        progress(Progress(done: frame, total: frame))
        return result
    }

    /// Slows down when the phone is hot instead of letting iOS throttle or terminate the app
    /// (long videos keep the Neural Engine / GPU busy for many minutes).
    private static func thermalPause() async throws {
        switch ProcessInfo.processInfo.thermalState {
        case .critical: try await Task.sleep(nanoseconds: 80_000_000)
        case .serious: try await Task.sleep(nanoseconds: 10_000_000)
        default: break
        }
    }
}

/// Codec names and the message for a video this device cannot decode.
enum VideoCodec {
    static func name(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        let s = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        switch s {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "ap4h", "apch", "apcn", "apcs", "apco": return "ProRes"
        case "mp4v": return "MPEG-4"
        case "av01": return "AV1"
        case "vp08": return "VP8"
        case "vp09": return "VP9"
        case "jpeg", "mjpa", "mjpb": return "Motion JPEG"
        default: return s
        }
    }

    static func undecodableMessage(codec: String) -> String {
        let c = codec.isEmpty ? L("unknown", "未知") : codec
        return String(format: L("This device has no decoder for the video's codec (%@), so it cannot be tracked or played here. Convert it to H.264 MP4 (for example with HandBrake, or ffmpeg -i input -c:v libx264 -crf 18 -pix_fmt yuv420p output.mp4) and add the converted file.",
                                "本设备没有该视频编码（%@）的解码器，无法识别或播放。请先转换为 H.264 MP4（如用 HandBrake，或 ffmpeg -i input -c:v libx264 -crf 18 -pix_fmt yuv420p output.mp4），再添加转换后的文件。"), c)
    }
}
