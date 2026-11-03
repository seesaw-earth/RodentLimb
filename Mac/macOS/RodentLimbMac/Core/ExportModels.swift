// ExportModels.swift — what an export contains (chosen in the Export sheet, remembered between
// exports) and what it produced.

import Foundation

/// What to export.
enum ExportScope: Hashable {
    /// Selected analyses and/or videos (a video exports all of its analyses).
    case selection(analyses: Set<UUID>, recordings: Set<UUID>)
    case assay(Assay)
    case study(UUID)
    /// One task: the sessions of one paradigm in one study.
    case task(TaskRef)
    case library
}

struct ExportOptions: Codable, Equatable {
    /// One row per analysis with the design columns and every measure (long / tidy format).
    var summary = true
    /// Behavior segments: every event / bout (onset, offset, duration, label, edits), all videos in one file.
    var segments = true
    /// Ethogram intervals (behavior tracks, e.g. grooming regions).
    var ethogram = true
    /// Time course in bins from the injection, long format.
    var timeBins = true
    /// Task-specific tables: tail-suspension bouts and per-minute immobility, cylinder contacts,
    /// gait strides and footprints.
    var details = true
    /// Frame-by-frame behavior labels (0/1 per behavior, plus "background"), for training or
    /// comparing with manual scoring (DeepEthogram / daart layout).
    var frameLabels = false
    /// BORIS-compatible aggregated events (TSV), to open the automatic scoring in BORIS.
    var boris = false
    /// Tracking quality of every video, with the inclusion decision and reason.
    var qc = true
    /// Methods paragraphs with the parameters used, and the study design text.
    var methods = true
    /// Frame-by-frame keypoints (RodentLimb CSV).
    var poseCSV = false
    /// Frame-by-frame keypoints in DeepLabCut's CSV layout (3 header rows) for DLC, SimBA,
    /// Keypoint-MoSeq …
    var poseDLC = false
    /// A folder per video with the same files as the iPhone app's single-analysis export.
    var perVideoFolders = false
    /// Also export videos that were excluded or are still waiting for a QC decision (flagged in the
    /// `included` column). Off: only included videos.
    var includeNotIncluded = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportOptions()
        func v(_ k: CodingKeys, _ def: Bool) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? def }
        summary = v(.summary, d.summary)
        segments = v(.segments, d.segments)
        ethogram = v(.ethogram, d.ethogram)
        timeBins = v(.timeBins, d.timeBins)
        details = v(.details, d.details)
        frameLabels = v(.frameLabels, d.frameLabels)
        boris = v(.boris, d.boris)
        qc = v(.qc, d.qc)
        methods = v(.methods, d.methods)
        poseCSV = v(.poseCSV, d.poseCSV)
        poseDLC = v(.poseDLC, d.poseDLC)
        perVideoFolders = v(.perVideoFolders, d.perVideoFolders)
        includeNotIncluded = v(.includeNotIncluded, d.includeNotIncluded)
    }

    static var saved: ExportOptions {
        guard let d = UserDefaults.standard.data(forKey: SettingsKey.exportOptions),
              let o = try? JSONDecoder().decode(ExportOptions.self, from: d) else { return ExportOptions() }
        return o
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: SettingsKey.exportOptions) }
    }
}

struct ExportReport {
    var folder: URL
    var files: [URL] = []
    var analyses = 0
    var recordings = 0
    var warnings: [String] = []
}

struct ExportProgress: Sendable {
    var fraction: Double
    var step: String
}
