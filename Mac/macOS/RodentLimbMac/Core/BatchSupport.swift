// BatchSupport.swift — the pieces the batch engine and the pose runner share: the job, its
// control (stop for pause / cancel / quit), progress, errors, and the crash journal.
//
// Foundation only (tested on Linux with a simulated runner).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One video for the pose model.
struct PoseJob: Sendable {
    var recordingID: UUID
    var videoURL: URL
    /// The URL comes from a security-scoped bookmark (access must be started by the runner).
    var scoped: Bool
    var checkpointFolder: URL
    var boxThreshold: Double
    /// Display name for logs.
    var name: String
    /// Pose model to run (chosen per video; the engine always passes the video's model).
    var model: PoseModelID = .standard
}

/// Why a run was stopped from outside.
enum StopReason: String, Sendable {
    /// Pause: the video goes back to the queue and continues from its checkpoint.
    case pause
    /// The user cancelled this video.
    case cancel
    /// The app is quitting or the library is being closed.
    case shutdown
}

/// Thread-safe stop flag of one running video (checked between frames).
final class ProcessingControl: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: StopReason?

    func stop(_ r: StopReason) {
        lock.lock()
        if reason == nil || r == .cancel { reason = r }
        lock.unlock()
    }

    var stopReason: StopReason? {
        lock.lock(); defer { lock.unlock() }
        return reason
    }

    var isStopped: Bool { stopReason != nil }
}

/// Last known keypoints and (on the Mac) a small picture of the frame being analysed.
final class PreviewSnapshot: @unchecked Sendable {
    let mediaTime: Double
    let frameWidth: Int
    let frameHeight: Int
    /// Kp order, display-frame pixels; nil when the keypoint is missing.
    let keypoints: [CGPoint?]
    #if canImport(CoreGraphics)
    let image: CGImage?
    init(mediaTime: Double, frameWidth: Int, frameHeight: Int, keypoints: [CGPoint?], image: CGImage?) {
        self.mediaTime = mediaTime
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.keypoints = keypoints
        self.image = image
    }
    #else
    init(mediaTime: Double, frameWidth: Int, frameHeight: Int, keypoints: [CGPoint?]) {
        self.mediaTime = mediaTime
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.keypoints = keypoints
    }
    #endif
}

struct RunProgress: Sendable {
    enum Phase: String, Sendable { case opening, tracking, finishing }
    var phase: Phase
    var framesDone: Int
    /// Estimated from duration × frame rate (refined as the video is read).
    var framesTotal: Int
    /// Frames that were already saved in the checkpoint when this run started.
    var resumedFrames: Int
    var mediaTime: Double
    var duration: Double
    var preview: PreviewSnapshot?
}

enum PoseRunError: LocalizedError, Sendable {
    case modelMissing
    case modelFailed(String)
    case videoMissing
    case noVideoTrack
    case badVideo(String)
    case readerFailed(String)
    case inferenceFailed(Int, String)
    case noFrames
    case writeFailed(String)
    case stopped(StopReason)

    /// Worth another attempt (continuing from the checkpoint).
    var isRetryable: Bool {
        switch self {
        case .readerFailed, .inferenceFailed: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            let name = PoseModelID.defaultChoice.rawValue
            return String(format: L("The pose model %@ is not in the app. Run tools/install_model.py and rebuild, or choose another model in Settings › Processing.",
                                    "App 中没有姿态模型 %@。请运行 tools/install_model.py 后重新编译，或在“设置 › 处理”中选择其他模型。"), name)
        case .modelFailed(let d):
            return L("The pose model could not be loaded: ", "姿态模型无法加载：") + d
        case .videoMissing:
            return L("The video file cannot be found (moved, renamed, or on a drive that is not connected).",
                     "找不到视频文件（已移动、重命名，或所在磁盘未连接）。")
        case .noVideoTrack:
            return L("This file has no readable video track.", "该文件没有可读取的视频轨道。")
        case .badVideo(let d):
            return L("The video can't be used: ", "视频无法使用：") + d
        case .readerFailed(let d):
            return L("Reading the video failed: ", "读取视频失败：") + d
        case .inferenceFailed(let f, let d):
            return String(format: L("Pose inference failed at frame %d: ", "第 %d 帧姿态推理失败："), f) + d
        case .noFrames:
            return L("No frames could be decoded. Try converting the video to H.264 MP4.", "没有解码出任何画面，请尝试将视频转为 H.264 MP4。")
        case .writeFailed(let d):
            return L("Saving the pose failed (is the disk full?): ", "保存姿态数据失败（磁盘是否已满？）：") + d
        case .stopped(let r):
            switch r {
            case .pause: return L("Paused", "已暂停")
            case .cancel: return L("Cancelled", "已取消")
            case .shutdown: return L("Stopped when the app quit", "App 退出时已停止")
            }
        }
    }
}

/// Runs the pose model over one video (Engine/PoseRunner.swift on the Mac; a simulator in tests).
/// `run` blocks: the batch engine calls it on its own thread.
protocol VideoPoseRunning: AnyObject {
    var modelName: String { get }
    var modelVersion: String { get }
    func run(_ job: PoseJob, control: ProcessingControl, progress: @escaping (RunProgress) -> Void) throws -> PoseTrack
}

// MARK: - Crash journal

/// Which videos were being processed. Written when a video starts and ends; cleared on a normal
/// quit. Entries found at launch mean the app stopped unexpectedly (crash, force quit, power cut)
/// while those videos were running: each gets a crash count, and a video that was running at two
/// such stops is set aside as failed instead of taking the whole batch down a third time.
struct BatchJournal: Codable, Equatable {
    static let fileName = ".batch_journal.json"
    /// After this many unexpected stops while a video was running, it is not retried automatically.
    static let crashLimit = 2

    var running: [UUID] = []
    var updatedAt = Date()

    static func url(_ base: URL) -> URL { base.appendingPathComponent(fileName) }

    static func load(_ base: URL) -> BatchJournal {
        guard let d = try? Data(contentsOf: url(base)) else { return BatchJournal() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(BatchJournal.self, from: d)) ?? BatchJournal()
    }

    func save(_ base: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(self) { try? d.write(to: Self.url(base), options: .atomic) }
    }

    static func clear(_ base: URL) {
        try? FileManager.default.removeItem(at: url(base))
    }
}

// MARK: - Throughput

/// Smoothed frames per second (exponential moving average over ≥ 1-s windows), so the ETA does not
/// jump and time spent paused does not distort it.
struct ThroughputMeter {
    private var anchor: (time: Double, frames: Int)?
    private(set) var fps: Double = 0

    mutating func update(frames: Int, now: Double) {
        guard let a = anchor, frames >= a.frames else {
            anchor = (now, frames)
            return
        }
        let dt = now - a.time
        if dt > 6 {
            anchor = (now, frames)
        } else if dt >= 1 {
            let f = Double(frames - a.frames) / dt
            fps = fps > 0 ? 0.75 * fps + 0.25 * f : f
            anchor = (now, frames)
        }
    }

    mutating func reset() {
        anchor = nil
        fps = 0
    }
}

/// Summary of one batch, for the notification and the log.
struct BatchSummary: Equatable {
    var finished = 0
    var failed = 0
    var needsReview = 0
    var frames = 0
    var seconds: Double = 0
}
