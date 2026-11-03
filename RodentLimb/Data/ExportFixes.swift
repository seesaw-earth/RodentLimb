// ExportFixes.swift — names the pose model actually used in exports.
//
// The shared exporter (Exporter.swift, identical on the Mac) writes `model,CylinderMousePoseV2` in
// the per-session summary and opens the methods paragraph with that model. Since 1.4 videos are
// tracked with CylinderPose7 FP16 (default) or PalmReaderPose8, so the iPhone corrects these texts after
// they are written, as the Mac's ExportService does. Videos without a recorded model keep
// CylinderMousePoseV2 (they were tracked with it).
//
// Foundation only.

import Foundation

enum ExportFixes {
    /// Rewrites the `model,…` row of a summary CSV written by `Exporter.sessionFiles`.
    static func namePoseModel(_ model: PoseModelID, inSummary url: URL) {
        guard model != .visible, var text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let old = "\nmodel," + kPoseModelName + ","
        guard text.contains(old) else { return }
        text = text.replacingOccurrences(of: old, with: "\nmodel," + model.rawValue + ",")
        // Exporter.write starts files with a UTF-8 BOM (Excel); String keeps it as U+FEFF.
        _ = Exporter.write(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text, url)
    }

    /// The methods paragraph with the pose-estimation sentence of the model(s) that tracked the videos.
    /// `models` holds one entry per analysis.
    static func methods(_ text: String, models: [PoseModelID], threshold: Double) -> String {
        let used = PoseModelID.allCases.filter { models.contains($0) }
        guard !used.isEmpty, used != [.visible] else { return text }
        let original = PoseModelID.visible.methodsSentence(threshold: threshold)
        let replacement: String
        if used.count == 1 {
            replacement = used[0].methodsSentence(threshold: threshold)
        } else {
            replacement = used.map { m -> String in
                let n = models.filter { $0 == m }.count
                return m.methodsSentence(threshold: threshold)
                    .replacingOccurrences(of: "Pose estimation: ", with: "Pose estimation (\(n) of \(models.count) analyses): ")
            }.joined()
        }
        return text.replacingOccurrences(of: original, with: replacement)
    }

    /// Rewrites a methods file written by `Exporter.sessionFiles`.
    static func fixMethodsFile(_ url: URL, model: PoseModelID, threshold: Double) {
        guard model != .visible, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let fixed = methods(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text, models: [model], threshold: threshold)
        _ = Exporter.write(fixed, url)
    }

    /// Applies both fixes to the files of one session export.
    static func apply(to urls: [URL], model: PoseModelID, threshold: Double) {
        guard model != .visible else { return }
        for u in urls {
            if u.lastPathComponent.hasSuffix("_summary.csv") { namePoseModel(model, inSummary: u) }
            if u.lastPathComponent.hasSuffix("_methods.txt") { fixMethodsFile(u, model: model, threshold: threshold) }
        }
    }
}
