// AppConstants.swift — names shared by the engine, the exports and the interface.

import Foundation

/// Core ML resource name of the pose model (compiled into the app bundle). Same model and keypoints
/// as the iPhone app, so a video gives the same pose on both.
let kPoseModelName = "CylinderMousePoseV2"

enum AppInfo {
    static let name = "RodentLimb"
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// UserDefaults keys (settings are per Mac, not per library).
enum SettingsKey {
    static let boxThreshold = "rl.boxThreshold"
    static let simultaneous = "rl.simultaneousVideos"
    static let autoStart = "rl.autoStartQueue"
    static let preventSleep = "rl.preventSleep"
    static let computeUnits = "rl.computeUnits"
    static let copyVideos = "rl.copyVideosOnImport"
    static let notifyWhenDone = "rl.notifyWhenDone"
    static let libraryBookmark = "rl.libraryBookmark"
    static let libraryPath = "rl.libraryPath"
    static let namePattern = "rl.namePattern"
    static let showSkeleton = "rl.showSkeleton"
    static let exportOptions = "rl.exportOptions"
    static let lastExportFolder = "rl.lastExportFolderBookmark"
    /// Pose model preselected for new imports (PoseModelID raw value).
    static let defaultPoseModel = PoseModelID.settingsKey
}

/// Which processors Core ML may use (Settings › Processing). "All" is the fastest on Apple silicon;
/// "CPU only" is a fallback when a GPU / Neural Engine problem is suspected.
enum ComputeChoice: String, CaseIterable, Identifiable {
    case all, cpuAndGPU, cpuAndNeuralEngine, cpuOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("Automatic (Neural Engine, GPU, CPU)", "自动（神经网络引擎、GPU、CPU）")
        case .cpuAndGPU: return L("CPU and GPU", "CPU 与 GPU")
        case .cpuAndNeuralEngine: return L("CPU and Neural Engine", "CPU 与神经网络引擎")
        case .cpuOnly: return L("CPU only (slow, most compatible)", "仅 CPU（慢，兼容性最好）")
        }
    }
    static var current: ComputeChoice {
        ComputeChoice(rawValue: UserDefaults.standard.string(forKey: SettingsKey.computeUnits) ?? "") ?? .all
    }
}
