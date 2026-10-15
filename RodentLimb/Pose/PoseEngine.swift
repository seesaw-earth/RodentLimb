// PoseEngine.swift — loads CylinderMousePoseV2 once and runs whole-video inference.
//
// Inference path is identical to the CylinderPose A/B app that validated V2 (Vision,
// .scaleFit letterbox, orientation .up on the decoded buffer). After decoding, keypoints are
// mapped into the displayed (orientation-corrected) frame so overlays, calibration and
// analysis all share one coordinate system.

import Foundation
import AVFoundation
import CoreML
import Vision
import CoreVideo
import CoreGraphics

enum PoseError: LocalizedError {
    case missingModel
    case unsupportedModel(String)
    case noVideoTrack
    case badVideo(String)
    case readerFailed(String)
    case writerFailed(String)
    case inferenceFailed(Int, String)
    case noFrames

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return L("CylinderMousePoseV2 is not in the app. Run Tools/install_model.py on your Mac and rebuild.",
                     "App 中没有 CylinderMousePoseV2 模型。请在 Mac 上运行 Tools/install_model.py 后重新编译。")
        case .unsupportedModel(let d):
            return L("The Core ML model format is not supported (expected a raw 7-keypoint pose head): ", "Core ML 模型格式不受支持（需要未经 NMS 的 7 关键点 pose 输出）：") + d
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
        }
    }
}

/// Core ML resource name of the V2 model (compiled into the app bundle).
let kPoseModelName = "CylinderMousePoseV2"

final class ProcessingControl: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

struct ModelInfo: Equatable {
    var version: String
    var inputSize: Int
    var author: String
}

@MainActor
final class PoseEngine: ObservableObject {
    static var resourceName: String { kPoseModelName }

    enum State: Equatable {
        case notLoaded
        case missing
        case ready(ModelInfo)
        case failed(String)
    }

    @Published private(set) var state: State = .notLoaded

    private var cached: (model: VNCoreMLModel, info: ModelInfo)?

    nonisolated static var modelURL: URL? {
        Bundle.main.url(forResource: kPoseModelName, withExtension: "mlmodelc")
    }

    var isInstalled: Bool { Self.modelURL != nil }

    func load() async -> (VNCoreMLModel, ModelInfo)? {
        if let c = cached { return (c.model, c.info) }
        guard let url = Self.modelURL else { state = .missing; return nil }
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
            cached = (loaded.0, loaded.1)
            state = .ready(loaded.1)
            return loaded
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    func checkInstalled() {
        if !isInstalled { state = .missing }
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
    static func run(videoURL: URL, model: VNCoreMLModel, info: ModelInfo, settings: InferenceSettings,
                    skeletonURL: URL?, control: ProcessingControl,
                    progress: @escaping (Progress) -> Void) async throws -> PoseTrack {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit

        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw PoseError.noVideoTrack }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw PoseError.badVideo(L("zero duration", "时长为 0")) }
        let nominalFPS = Double(try await track.load(.nominalFrameRate))
        let transform = try await track.load(.preferredTransform)
        let estimated = max(1, Int(duration * (nominalFPS > 0 ? nominalFPS : 30)))
        progress(Progress(done: 0, total: estimated))

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw PoseError.readerFailed(reader.error?.localizedDescription ?? "unknown") }
        defer { if reader.status == .reading { reader.cancelReading() } }

        guard let first = output.copyNextSampleBuffer(), let firstPixel = CMSampleBufferGetImageBuffer(first) else {
            throw PoseError.noFrames
        }
        let width = CVPixelBufferGetWidth(firstPixel)
        let height = CVPixelBufferGetHeight(firstPixel)
        guard width > 0, height > 0 else { throw PoseError.badVideo(L("invalid frame size", "画面尺寸无效")) }

        // Raw buffer → displayed frame.
        let displayRect = CGRect(x: 0, y: 0, width: width, height: height).applying(transform)
        let dispW = Int(abs(displayRect.width).rounded()), dispH = Int(abs(displayRect.height).rounded())
        func toDisplay(_ x: Double, _ y: Double) -> (Double, Double) {
            let p = CGPoint(x: x, y: y).applying(transform)
            return (Double(p.x - displayRect.minX), Double(p.y - displayRect.minY))
        }

        let decoder = PoseDecoder(threshold: settings.boxThreshold, imageWidth: width, imageHeight: height, inputSize: info.inputSize)
        var result = PoseTrack(width: dispW, height: dispH, fps: nominalFPS > 0 ? nominalFPS : 30, duration: duration,
                               modelName: kPoseModelName, modelVersion: info.version)
        result.reserve(estimated + 16)

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

        var frame = 0
        var pending: CMSampleBuffer? = first
        let start0 = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(first))
        while let sample = pending ?? output.copyNextSampleBuffer() {
            pending = nil
            if control.isCancelled { throw CancellationError() }
            guard let pixel = CMSampleBufferGetImageBuffer(sample) else { continue }
            let decoded: DecodedPose?
            do {
                try autoreleasepool {
                    let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
                    try handler.perform([request])
                }
                guard let obs = (request.results ?? []).compactMap({ $0 as? VNCoreMLFeatureValueObservation })
                    .first(where: { $0.featureValue.multiArrayValue != nil }),
                      let array = obs.featureValue.multiArrayValue else {
                    throw PoseError.unsupportedModel(L("no MLMultiArray output (was the model exported with nms=True?)", "没有 MLMultiArray 输出（导出时是否设置了 nms=True？）"))
                }
                decoded = try decoder.decode(array)
            } catch let e as PoseError {
                throw e
            } catch {
                throw PoseError.inferenceFailed(frame, error.localizedDescription)
            }

            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
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

            if let w = writer, let i = input, let a = adaptor {
                let rendered = try SkeletonPainter.render(source: pixel, pose: decoded, keypointThreshold: 0.3)
                let waitStart = ProcessInfo.processInfo.systemUptime
                while !i.isReadyForMoreMediaData {
                    if control.isCancelled { throw CancellationError() }
                    if w.status != .writing { throw PoseError.writerFailed(w.error?.localizedDescription ?? "status \(w.status.rawValue)") }
                    if ProcessInfo.processInfo.systemUptime - waitStart > 20 { throw PoseError.writerFailed(L("encoder timed out", "编码器超时")) }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                guard a.append(rendered, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample)) else {
                    throw PoseError.writerFailed(w.error?.localizedDescription ?? "append failed")
                }
            }

            frame += 1
            if frame % 10 == 0 { progress(Progress(done: frame, total: max(estimated, frame))) }
        }
        guard reader.status == .completed else { throw PoseError.readerFailed(reader.error?.localizedDescription ?? "stopped") }
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
}
