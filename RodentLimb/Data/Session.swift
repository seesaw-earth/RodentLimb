// Session.swift — one video of one animal in one assay.

import Foundation
import CoreGraphics

enum SessionStatus: String, Codable {
    case queued, processing, needsSetup, done, failed

    var title: String {
        switch self {
        case .queued: return L("Queued", "排队中")
        case .processing: return L("Detecting pose", "姿态识别中")
        case .needsSetup: return L("Needs calibration", "需要标定")
        case .done: return L("Done", "已完成")
        case .failed: return L("Failed", "失败")
        }
    }

    var symbol: String {
        switch self {
        case .queued: return "clock"
        case .processing: return "waveform.path.ecg"
        case .needsSetup: return "scope"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

struct Session: Codable, Identifiable, Equatable {
    var id: UUID
    var assay: Assay
    var subject: String
    var group: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var videoFile: String
    var originalName: String
    var status: SessionStatus
    var failure: String?
    var videoWidth: Int?
    var videoHeight: Int?
    var fps: Double?
    var duration: Double?
    var calibration: Calibration
    var params: AssayParams
    var overrides: [Int: PawLabel]
    var hasPose: Bool
    var hasSkeletonVideo: Bool
    var modelVersion: String?
    /// Up to three highlighted metrics, cached for lists.
    var summary: [Metric]
    var worstNote: NoteLevel?

    init(assay: Assay, subject: String, group: String, notes: String, videoFile: String, originalName: String) {
        id = UUID()
        self.assay = assay
        self.subject = subject
        self.group = group
        self.notes = notes
        createdAt = Date()
        updatedAt = createdAt
        self.videoFile = videoFile
        self.originalName = originalName
        status = .queued
        calibration = Calibration()
        params = AssayParams.defaults(for: assay)
        overrides = [:]
        hasPose = false
        hasSkeletonVideo = false
        summary = []
    }

    var displayName: String { subject.isEmpty ? originalName : subject }

    var videoSize: CGSize? {
        guard let w = videoWidth, let h = videoHeight, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Whether the current calibration is enough to analyze.
    var isCalibrated: Bool {
        switch assay {
        case .tailSuspension, .gait: return true
        case .cylinder:
            return params.cylinder.view == .bottom ? calibration.circle != nil : calibration.floorY != nil
        }
    }
}

enum Analyzer {
    static func run(session: Session, track: PoseTrack) -> AnalysisResult {
        let series = PoseSeries(track: track, params: session.params.common)
        var result: AnalysisResult
        switch session.assay {
        case .tailSuspension:
            result = TSTAnalyzer.run(series, session.params.tst, duration: track.duration)
        case .cylinder:
            result = CylinderAnalyzer.run(series, session.params.cylinder, calibration: session.calibration, overrides: session.overrides)
        case .gait:
            result = GaitAnalyzer.run(series, session.params.gait, calibration: session.calibration)
        }
        if track.detectedFraction < 0.5 {
            result.notes.insert(Note(.warning,
                                     String(format: "The mouse was detected in only %.0f%% of frames. Check the camera view, or lower the detection threshold in Settings.", track.detectedFraction * 100),
                                     String(format: "仅 %.0f%% 的帧检测到小鼠。请检查拍摄视角，或在“设置”中降低检测阈值。", track.detectedFraction * 100)), at: 0)
        }
        if session.assay != .cylinder && track.detectedFraction >= 0.5 && result.poseCoverage < 0.6 {
            result.notes.append(Note(.info,
                                     "CylinderMousePoseV2 was trained on cylinder videos. For this assay, keypoints may be less reliable; check the overlay in the review player.",
                                     "CylinderMousePoseV2 基于圆筒视频训练，用于本范式时关键点可能不够可靠，请在回放中检查叠加的关键点。"))
        }
        return result
    }
}
