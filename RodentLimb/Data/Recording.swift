// Recording.swift — one video of one animal. Every video goes through the pose model once
// (status), gets a tracking QC report and an inclusion decision. Since 1.4 a video is added to a task
// and gets that task's `Session` (analysis) at once; the session shares this recording's video and pose
// and is analysed when the pose is ready (videos of 1.3 libraries got their sessions after inclusion).
//
//   add to task (Session) → queued → processing → ready → QC → include / exclude → results

import Foundation

enum RecordingStatus: String, Codable {
    case queued, processing, ready, failed

    var title: String {
        switch self {
        case .queued: return L("Queued", "排队中")
        case .processing: return L("Detecting pose", "姿态识别中")
        case .ready: return L("Pose ready", "姿态已就绪")
        case .failed: return L("Failed", "失败")
        }
    }
}

/// Inclusion decision for the analysis (ARRIVE 2.0 item 3: report exclusions and reasons).
enum InclusionDecision: String, Codable, CaseIterable, Identifiable {
    case pending, included, excluded
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pending: return L("Needs review", "待审核")
        case .included: return L("Included", "纳入")
        case .excluded: return L("Excluded", "排除")
        }
    }
}

struct Recording: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var videoFile: String
    var originalName: String

    // Design
    var experimentID: UUID?
    var animalID: UUID?
    /// Free-text animal ID (used when the video is not in a study, and kept from 1.2).
    var subject: String
    /// Free-text group (videos outside a study, and sessions from 1.2).
    var group: String
    /// Within-subject level (timepoint / condition) in the study, "" = none.
    var timepoint: String
    var trial: Int
    var recordedOn: Date?
    var notes: String

    // Pose detection
    var status: RecordingStatus
    var failure: String?
    var videoWidth: Int?
    var videoHeight: Int?
    var fps: Double?
    var duration: Double?
    var hasPose: Bool
    var hasSkeletonVideo: Bool
    var modelVersion: String?

    // Quality control
    var qc: QCReport?
    var decision: InclusionDecision
    var exclusionReason: String

    /// Tasks chosen at import; assigned automatically when QC passes.
    var plannedAssays: [Assay]

    init(videoFile: String, originalName: String) {
        id = UUID()
        createdAt = Date()
        updatedAt = createdAt
        self.videoFile = videoFile
        self.originalName = originalName
        subject = ""
        group = ""
        timepoint = ""
        trial = 1
        notes = ""
        status = .queued
        hasPose = false
        hasSkeletonVideo = false
        decision = .pending
        exclusionReason = ""
        plannedAssays = []
    }

    // Tolerant decoding, so recordings saved by this version keep loading after fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
        videoFile = (try? c.decodeIfPresent(String.self, forKey: .videoFile)) ?? "video.mov"
        originalName = (try? c.decodeIfPresent(String.self, forKey: .originalName)) ?? videoFile
        experimentID = try? c.decodeIfPresent(UUID.self, forKey: .experimentID)
        animalID = try? c.decodeIfPresent(UUID.self, forKey: .animalID)
        subject = (try? c.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        group = (try? c.decodeIfPresent(String.self, forKey: .group)) ?? ""
        timepoint = (try? c.decodeIfPresent(String.self, forKey: .timepoint)) ?? ""
        trial = (try? c.decodeIfPresent(Int.self, forKey: .trial)) ?? 1
        recordedOn = try? c.decodeIfPresent(Date.self, forKey: .recordedOn)
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        status = (try? c.decodeIfPresent(RecordingStatus.self, forKey: .status)) ?? .queued
        failure = try? c.decodeIfPresent(String.self, forKey: .failure)
        videoWidth = try? c.decodeIfPresent(Int.self, forKey: .videoWidth)
        videoHeight = try? c.decodeIfPresent(Int.self, forKey: .videoHeight)
        fps = try? c.decodeIfPresent(Double.self, forKey: .fps)
        duration = try? c.decodeIfPresent(Double.self, forKey: .duration)
        hasPose = (try? c.decodeIfPresent(Bool.self, forKey: .hasPose)) ?? false
        hasSkeletonVideo = (try? c.decodeIfPresent(Bool.self, forKey: .hasSkeletonVideo)) ?? false
        modelVersion = try? c.decodeIfPresent(String.self, forKey: .modelVersion)
        qc = try? c.decodeIfPresent(QCReport.self, forKey: .qc)
        decision = (try? c.decodeIfPresent(InclusionDecision.self, forKey: .decision)) ?? .pending
        exclusionReason = (try? c.decodeIfPresent(String.self, forKey: .exclusionReason)) ?? ""
        plannedAssays = (try? c.decodeIfPresent([LossyElement<Assay>].self, forKey: .plannedAssays))?.compactMap { $0.value } ?? []
    }

    var isProcessed: Bool { status == .ready && hasPose }
}

extension Session {
    /// A new analysis of `recording` for `assay`.
    init(recording r: Recording, assay: Assay) {
        self.init(assay: assay, subject: r.subject, group: r.group, notes: r.notes,
                  videoFile: r.videoFile, originalName: r.originalName)
        recordingID = r.id
    }
}
