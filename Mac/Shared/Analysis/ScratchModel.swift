// ScratchModel.swift — optional trained scratching detector.
//
// The Colab notebook (RodentLimb_PublicDatasets_Behavior.ipynb, section 9) trains a small
// gradient-boosted tree model on Scratch-AID (Yu et al. 2022) and exports it as JSON: the
// feature names (defined in KinematicFeatures), every tree, the post-processing tuned on the
// validation videos, and test vectors. Copy that file into RodentLimb/Models/ as
// `ScratchModel.json` (or keep its original name `compact_scratch_model.json`) and rebuild;
// the Itch assay then uses it instead of the keypoint rules. Nothing else changes.
//
// Prediction for one frame: start at node 0 of every tree; at a split go left when the feature
// is ≤ threshold (missing values follow `missing_left`); add the leaf values to `baseline`;
// p = 1 / (1 + e^−z). On load the test vectors are re-scored; a file that does not reproduce
// them is rejected.

import Foundation

struct TreeModelFile: Decodable {
    struct Feature: Decodable { var index: Int; var name: String }
    struct Tree: Decodable {
        var feature: [Int]
        var threshold: [Double]
        var missing_left: [Int]
        var left: [Int]
        var right: [Int]
        var value: [Double]
    }
    struct Post: Decodable { var smooth_s: Double; var thr: Double; var gap_s: Double; var min_s: Double }
    struct TestVector: Decodable { var x: [Double?]; var p: Double }
    struct TestMetrics: Decodable { var frame_F1: Double?; var frame_P: Double?; var frame_R: Double?; var AP: Double? }

    var name: String?
    var model_tag: String?
    var constants: FeatureConstants?
    var features: [Feature]
    var baseline: Double
    var trees: [Tree]
    var postprocess: Post
    var test_vectors: [TestVector]?
    var metrics_official_test: [TestMetrics]?
}

final class ScratchModel: @unchecked Sendable {
    let file: TreeModelFile
    let featureNames: [String]
    let constants: FeatureConstants
    /// Largest |p − expected| over the file's test vectors (0 if it has none).
    let selfTestError: Double
    let sourceName: String

    /// The model bundled with the app, if any (loaded once).
    static let bundled: ScratchModel? = {
        for name in ["ScratchModel", "compact_scratch_model"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json"), let m = ScratchModel(url: url) { return m }
        }
        return nil
    }()

    convenience init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data, sourceName: url.lastPathComponent)
    }

    init?(data: Data, sourceName: String = "ScratchModel.json") {
        guard let f = try? JSONDecoder().decode(TreeModelFile.self, from: data), !f.trees.isEmpty else { return nil }
        let names = f.features.sorted { $0.index < $1.index }.map(\.name)
        for t in f.trees {
            let c = t.feature.count
            guard c > 0, t.threshold.count == c, t.missing_left.count == c, t.left.count == c, t.right.count == c,
                  t.value.count == c, t.feature.allSatisfy({ $0 < names.count }) else { return nil }
            // Every split node must point at nodes of this tree, or `score` would index out of range.
            for j in 0..<c where t.feature[j] >= 0 {
                guard t.left[j] >= 0, t.left[j] < c, t.right[j] >= 0, t.right[j] < c else { return nil }
            }
        }
        file = f
        featureNames = names
        constants = f.constants ?? FeatureConstants()
        self.sourceName = sourceName
        var err = 0.0
        for v in f.test_vectors ?? [] {
            let x = v.x.map { $0 ?? .nan }
            guard x.count == names.count else { return nil }
            err = max(err, abs(ScratchModel.score(f, x) - v.p))
        }
        selfTestError = err
        guard err < 1e-6 else { return nil }
    }

    private static func score(_ f: TreeModelFile, _ x: [Double]) -> Double {
        var z = f.baseline
        for t in f.trees {
            var i = 0
            var guardSteps = 0
            while t.feature[i] >= 0 && guardSteps < 4096 {
                let v = x[t.feature[i]]
                if v.isNaN {
                    i = t.missing_left[i] == 1 ? t.left[i] : t.right[i]
                } else {
                    i = v <= t.threshold[i] ? t.left[i] : t.right[i]
                }
                guardSteps += 1
            }
            z += t.value[i]
        }
        return 1 / (1 + exp(-z))
    }

    func probability(_ x: [Double]) -> Double { ScratchModel.score(file, x) }

    /// Feature columns the app cannot compute (should be empty for models exported by the notebook).
    func missingFeatures(_ fx: KinematicFeatures) -> [String] {
        featureNames.filter { fx.column($0) == nil }
    }

    /// Scratching probability for every original video frame, or nil when a feature is missing.
    func probabilities(_ fx: KinematicFeatures) -> [Double]? {
        var cols: [[Double]] = []
        for name in featureNames {
            guard let c = fx.column(name) else { return nil }
            cols.append(c)
        }
        let m = fx.featureFrames
        var pf = [Double](repeating: .nan, count: m)
        var x = [Double](repeating: .nan, count: cols.count)
        for j in 0..<m {
            for k in 0..<cols.count { x[k] = cols[k][j] }
            pf[j] = probability(x)
        }
        return fx.back.map { pf[$0] }
    }

    var testF1: Double? { file.metrics_official_test?.first?.frame_F1 }
}

/// The notebook's post-processing: centered moving average → threshold → fill gaps → drop short
/// runs. All durations are converted with `nwin` at the video's fps.
enum PostProcess {
    static func smooth(_ p: [Double], fps: Double, seconds: Double) -> [Double] {
        seconds > 0 ? Rolling.mean(p, nwin(seconds, fps), 1) : p
    }

    static func binarize(_ ps: [Double], fps: Double, threshold: Double, gap: Double, minDuration: Double) -> [Bool] {
        var b = ps.map { $0.isFinite && $0 >= threshold }
        if gap > 0 { b = Bouts.fillGaps(b, maxFrames: nwin(gap, fps)) }
        if minDuration > 0 { b = Bouts.dropShort(b, minFrames: nwin(minDuration, fps)) }
        return b
    }
}
