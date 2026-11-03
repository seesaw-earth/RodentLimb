// PoseModels.swift — the pose models of RodentLimb (iPhone and Mac: this file is shared), chosen per
// video when it is added to a task or re-tracked. The choices (first = default):
//
//  1. CylinderPose7_FP16_640 (default) — CylinderMousePose v2 (YOLO26s-pose, 7 keypoints, run
//     20261014_1156_dlc_distill) exported with half-precision weights, for ordinary visible-light video
//     (room light, bottom view). All 104 weight tensors equal those of the full-precision
//     CylinderMousePoseV2 within FP16 rounding (≤ 0.05 % relative); 19 MB; outputs Float16.
//  2. PalmReaderPose8_640_W8A16 — an Ultralytics YOLO-pose model with 8 keypoints (tail base, body
//     centre, neck, snout, four paws) for the bottom-up near-infrared recordings of dark-box rigs
//     (Blackbox Bio "Palmreader" style: the mouse moves in apparent darkness in an opaque chamber and is
//     filmed from below under near-infrared light). Source: Zenodo record 16321240; 8-bit palettized
//     weights, FP16 compute.
//
// CylinderMousePoseV2 (full precision, 38 MB) is no longer included. It remains a known model: videos
// tracked with it (iPhone 1.0–1.3 and Mac up to 1.3.5 — every video without a recorded model) keep that
// label in the app and in exports; if such a video is tracked again, the FP16 model (the same network)
// is used and recorded.
//
// Every video keeps the same stored format whatever the model (Shared/: 7 keypoints, pose.bin, the
// analyses), so all analyses, QC and exports work unchanged. The near-infrared model's keypoints are
// mapped onto that format: snout → nose, tail base, the four paws; it has no mouth point, so the
// mouth stays missing and the analyses use the nose instead (as they already do whenever the mouth is
// not tracked); body centre and neck are not stored.
//
// Which model tracked a video is kept in its sidecar (Recordings/<id>/source.json, written by the Mac
// and, since 1.4, by the iPhone) and in pose.bin itself (PoseTrack.modelName).

import Foundation

enum PoseModelID: String, Codable, CaseIterable, Identifiable, Sendable {
    // Declaration order = order of the choices in the app (first = default for new imports).
    case visibleFP16 = "CylinderPose7_FP16_640"
    case nearInfrared = "PalmReaderPose8_640_W8A16"
    case visible = "CylinderMousePoseV2"

    /// Preselected for new imports when Settings has no other choice.
    static let standard: PoseModelID = .visibleFP16

    /// The models shipped in the app, in the order they are offered.
    static let choices: [PoseModelID] = [.visibleFP16, .nearInfrared]

    /// Shipped and offered (CylinderMousePoseV2 is only a label for videos tracked with it).
    var isAvailable: Bool { Self.choices.contains(self) }

    /// The model that runs when a video of this model is tracked (again).
    var runnable: PoseModelID { isAvailable ? self : Self.standard }

    /// UserDefaults key of the model preselected for new videos.
    static let settingsKey = "rl.defaultPoseModel"

    var id: String { rawValue }

    /// Compiled model in the app bundle (<name>.mlmodelc).
    var resourceName: String { rawValue }

    /// Short name for tables and exports.
    var displayName: String {
        switch self {
        case .visible: return "CylinderMousePoseV2"
        case .nearInfrared: return "PalmReaderPose8"
        case .visibleFP16: return "CylinderPose7 FP16"
        }
    }

    var lighting: LText {
        switch self {
        case .visible, .visibleFP16: return LText("Visible light", "可见光")
        case .nearInfrared: return LText("Near-infrared (dark)", "近红外（暗箱）")
        }
    }

    /// Short distinct label for menus, cards and the inspector (two models share visible light).
    var shortTitle: LText {
        switch self {
        case .visibleFP16: return LText("Visible light (FP16, default)", "可见光（FP16，默认）")
        case .nearInfrared: return LText("Near-infrared (dark box)", "近红外（暗箱）")
        case .visible: return LText("Visible light (older FP32 model)", "可见光（旧版 FP32 模型）")
        }
    }

    /// Picker title: lighting first (that is what decides), model name second.
    var title: LText {
        switch self {
        case .visibleFP16: return LText("Visible light — default (CylinderPose7 FP16)", "可见光——默认（CylinderPose7 FP16）")
        case .nearInfrared: return LText("Near-infrared, dark box (PalmReaderPose8)", "近红外暗箱（PalmReaderPose8）")
        case .visible: return LText("Older visible-light model (CylinderMousePoseV2, no longer included)", "旧版可见光模型（CylinderMousePoseV2，已不再包含）")
        }
    }

    var detail: LText {
        switch self {
        case .visible:
            return LText("The full-precision version of the visible-light network, used by earlier versions. Videos tracked with it keep their results; tracking them again uses the FP16 model (the same network).",
                         "可见光网络的全精度版本，旧版本使用。用它识别的视频保留原结果；重新识别时改用 FP16 模型（同一网络）。")
        case .nearInfrared:
            return LText("Videos filmed from below under near-infrared light in the dark (dark-box / Blackbox-style rigs). 8 keypoints; the snout is stored as the nose, and there is no mouth point, so analyses use the nose for licking and face grooming.",
                         "在黑暗中用近红外光从下方拍摄的视频（暗箱 / Blackbox 类装置）。8 个关键点；snout 存为鼻尖；该模型没有嘴部关键点，舔爪和面部理毛改用鼻尖判断。")
        case .visibleFP16:
            return LText("Videos filmed in normal room light (color or grayscale), bottom view. 7 keypoints: four paws, tail base, nose, mouth. Use the same model for every video of a task.",
                         "在普通室内光下拍摄的视频（彩色或灰度），从下方拍摄。7 个关键点：四只爪、尾根、鼻尖、嘴。同一任务的所有视频请用同一个模型。")
        }
    }

    var source: String {
        switch self {
        case .visible: return "RodentLimb CylinderMousePoseV2 v2.0 (YOLO26s-pose, DLC-distilled)"
        case .nearInfrared: return "PalmReaderPose8 v3.0 (Ultralytics YOLO-pose), Zenodo record 16321240"
        case .visibleFP16: return "CylinderMousePose v2.1, FP16 export of CylinderMousePoseV2 (YOLO26s-pose, DLC-distilled)"
        }
    }

    /// Keypoints in the model's output, in order.
    var modelKeypoints: [String] {
        switch self {
        case .visible, .visibleFP16: return Kp.allCases.map(\.exportName)
        case .nearInfrared: return ["tailbase", "centroid", "neck", "snout", "hlpaw", "hrpaw", "flpaw", "frpaw"]
        }
    }

    var keypointCount: Int { modelKeypoints.count }

    /// For each stored keypoint (Kp order), its index in the model output; nil = the model has none.
    var keypointMap: [Int?] {
        switch self {
        case .visible, .visibleFP16:
            return Kp.allCases.map { $0.rawValue }
        case .nearInfrared:
            return Kp.allCases.map { k -> Int? in
                switch k {
                case .lf: return 6      // flpaw
                case .lh: return 4      // hlpaw
                case .rf: return 7      // frpaw
                case .rh: return 5      // hrpaw
                case .tail: return 0    // tailbase
                case .nose: return 3    // snout
                case .mouth: return nil // not in this model
                }
            }
        }
    }

    /// Stored keypoints this model never provides.
    var missingKeypoints: [Kp] { Kp.allCases.filter { keypointMap[$0.rawValue] == nil } }

    /// The model a stored track came from (pose.bin / checkpoint keep the model name).
    init?(modelName: String) {
        if let m = PoseModelID(rawValue: modelName) { self = m; return }
        if modelName.hasPrefix("PalmReader") { self = .nearInfrared; return }
        if modelName.hasPrefix("CylinderPose7") { self = .visibleFP16; return }
        if modelName.hasPrefix("CylinderMousePose") { self = .visible; return }
        return nil
    }

    /// Model chosen in Settings for new imports (the first option, CylinderPose7 FP16, unless changed).
    static var defaultChoice: PoseModelID {
        let stored = PoseModelID(rawValue: UserDefaults.standard.string(forKey: settingsKey) ?? "")
        return stored?.isAvailable == true ? stored! : standard
    }

    /// The opening of the methods paragraph for videos tracked with this model.
    func methodsSentence(threshold: Double) -> String {
        switch self {
        case .visible:
            return String(format: "Pose estimation: %@ (7 keypoints: left/right fore and hind paws, tail base, nose, mouth), run on-device with Core ML on every video frame. Keypoints with confidence < %.2f were treated as missing. ",
                          kPoseModelName, threshold)
        case .visibleFP16:
            return String(format: "Pose estimation: %@ exported with half-precision (FP16) weights (CylinderPose7_FP16_640; 7 keypoints: left/right fore and hind paws, tail base, nose, mouth), run on-device with Core ML on every video frame. Keypoints with confidence < %.2f were treated as missing. ",
                          kPoseModelName, threshold)
        case .nearInfrared:
            return String(format: "Pose estimation: PalmReaderPose8 (Ultralytics YOLO-pose, 8 keypoints, for bottom-up near-infrared recordings in the dark; Zenodo record 16321240), run on-device with Core ML on every video frame. Its snout, tail base and four paw keypoints were used (snout as nose); it has no mouth keypoint, so the nose was used where the mouth is needed. Keypoints with confidence < %.2f were treated as missing. ",
                          threshold)
        }
    }
}

/// Layout of a raw Ultralytics pose output: [cx, cy, w, h, score, K × (x, y, conf)] (one-to-many
/// head, nms=False) or the end-to-end layout [x1, y1, x2, y2, score, class, K × (x, y, conf)].
struct PoseOutputLayout: Equatable, Sendable {
    var keypointCount: Int
    var endToEnd: Bool

    var channels: Int { (endToEnd ? 6 : 5) + 3 * keypointCount }
    var firstKeypointChannel: Int { endToEnd ? 6 : 5 }

    /// The layout of a tensor with this many channels for a model with `keypointCount` keypoints.
    static func detect(channels: Int, keypointCount: Int) -> PoseOutputLayout? {
        let raw = PoseOutputLayout(keypointCount: keypointCount, endToEnd: false)
        if channels == raw.channels { return raw }
        let e2e = PoseOutputLayout(keypointCount: keypointCount, endToEnd: true)
        if channels == e2e.channels { return e2e }
        return nil
    }
}
