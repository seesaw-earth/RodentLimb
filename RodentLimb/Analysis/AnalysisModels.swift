// AnalysisModels.swift — assays, parameters, calibration and result types.

import Foundation

// MARK: - Assays

enum Assay: String, Codable, CaseIterable, Identifiable {
    case tailSuspension, cylinder, gait, itch, pain, grooming, seizure
    var id: String { rawValue }

    var name: LText {
        switch self {
        case .tailSuspension: return LText("Tail suspension", "悬尾实验")
        case .cylinder: return LText("Cylinder test", "圆筒实验")
        case .gait: return LText("Gait analysis", "步态分析")
        case .itch: return LText("Itch (scratching)", "瘙痒（抓挠）")
        case .pain: return LText("Spontaneous pain", "自发痛行为")
        case .grooming: return LText("Self-grooming", "自我理毛")
        case .seizure: return LText("Seizure scoring", "癫痫发作评分")
        }
    }

    var code: String {
        switch self {
        case .tailSuspension: return "TST"
        case .cylinder: return "CYL"
        case .gait: return "GAIT"
        case .itch: return "ITCH"
        case .pain: return "PAIN"
        case .grooming: return "GROOM"
        case .seizure: return "SZ"
        }
    }

    var symbol: String {
        switch self {
        case .tailSuspension: return "arrow.down.to.line"
        case .cylinder: return "cylinder"
        case .gait: return "pawprint.fill"
        case .itch: return "allergens"
        case .pain: return "flame.fill"
        case .grooming: return "sparkles"
        case .seizure: return "bolt.fill"
        }
    }

    /// Behavior assays share the event / ethogram result (`AnalysisResult.behavior`).
    var isBehavior: Bool {
        switch self {
        case .itch, .pain, .grooming, .seizure: return true
        default: return false
        }
    }

    var summary: LText {
        switch self {
        case .tailSuspension:
            return LText("Immobility, latency, per-minute profile, hindlimb clasping and tail climbing",
                         "不动时间、潜伏期、逐分钟曲线、后肢抱握与爬尾检测")
        case .cylinder:
            return LText("Forelimb wall contacts during rearing: left, right, both and use asymmetry",
                         "竖立时前爪触壁：左、右、双爪及使用不对称性")
        case .gait:
            return LText("Stance/swing, stride, duty factor, base of support, interlimb phase, regularity",
                         "支撑相/摆动相、步幅、占空比、支撑面宽度、肢间相位、规律性")
        case .itch:
            return LText("Scratching bouts, time and latency after a pruritogen; time course; which hind paw",
                         "致痒剂后的抓挠次数、时长与潜伏期；时间进程；哪只后爪")
        case .pain:
            return LText("Licking/biting and flinching of the injected paw; formalin phase I / II; time course",
                         "舔咬与甩动注射爪；福尔马林 I / II 相；时间进程")
        case .grooming:
            return LText("Grooming time, bouts, latency; face, body, hind-leg and tail/genital grooming; sequence",
                         "理毛时间、次数、潜伏期；面部、躯体、后腿、尾/生殖区理毛；序列")
        case .seizure:
            return LText("Myoclonic jerks, clonic and tonic-clonic seizures, tonic extension; latencies; Racine stage",
                         "肌阵挛、阵挛与强直-阵挛发作、强直伸展；潜伏期；Racine 分级")
        }
    }

    var cameraTip: LText {
        switch self {
        case .tailSuspension:
            return LText("Film the hanging mouse from the front or back (ventral/dorsal view) so both hind paws are visible; one mouse per video. Start recording at suspension; a standard test lasts 6 min.",
                         "从正面或背面拍摄悬挂的小鼠（腹侧/背侧视角），保证两只后爪可见；每段视频一只小鼠。从悬挂开始录制，标准时长 6 分钟。")
        case .cylinder:
            return LText("Bottom view through a transparent floor works best (paws touching the wall appear at the rim). Side view also works with a floor line. 5–10 min per mouse.",
                         "最佳为透明底面的仰视拍摄（触壁的爪出现在圆周边缘）；侧视也可用，需标定地面线。每只小鼠 5–10 分钟。")
        case .gait:
            return LText("Bottom (ventral) view of a straight walkway, camera fixed, high frame rate (≥ 60 fps recommended). Place a ruler in view once to calibrate cm.",
                         "直线步道的仰视（腹侧）拍摄，相机固定，帧率越高越好（建议 ≥ 60 fps）。画面中放一次标尺用于厘米标定。")
        case .itch:
            return LText("Bottom view through a transparent floor, one mouse per chamber, ≥ 30 fps (60 fps is better: scratching strokes are fast). Record 30–60 min from the injection; set the injection time in Parameters if the video starts earlier.",
                         "透明底面仰视拍摄，每个小室一只小鼠，≥ 30 fps（60 fps 更好，抓挠动作很快）。从注射起录制 30–60 分钟；若视频早于注射开始，请在“参数”中设置注射时刻。")
        case .pain:
            return LText("Bottom view through a transparent floor so the injected paw is visible, ≥ 30 fps, in normal light. Formalin: record 45–60 min from the injection; capsaicin: 5–10 min. Set the injected paw in Parameters.",
                         "透明底面仰视拍摄，确保注射爪可见，≥ 30 fps，正常光照。福尔马林：从注射起录制 45–60 分钟；辣椒素：5–10 分钟。在“参数”中设置注射爪。")
        case .grooming:
            return LText("Bottom view through a transparent floor, one mouse, ≥ 30 fps. A 10-min session after a short habituation is common; for splash tests start right after the spray.",
                         "透明底面仰视拍摄，每段一只小鼠，≥ 30 fps。常用做法是短暂适应后记录 10 分钟；溅水实验则在喷雾后立即开始。")
        case .seizure:
            return LText("Bottom view through a transparent floor or cylinder, one mouse, ≥ 30 fps, in normal light. Start before the convulsant injection and record ≥ 30 min after it; set the injection time in Parameters. Automated stages are estimates — confirm every event on the video.",
                         "透明底面或透明圆筒仰视拍摄，每段一只小鼠，≥ 30 fps，正常光照。在注射致惊厥药前开始录制，注射后至少录 30 分钟；在“参数”中设置注射时刻。自动分级仅为估计，请在视频上逐个确认事件。")
        }
    }
}

// MARK: - Parameters

struct CommonParams: Codable, Equatable {
    /// Keypoints below this confidence are treated as missing.
    var keypointThreshold: Double = 0.30
    /// Gaps up to this length (s) are filled; longer gaps stay missing and are excluded.
    var maxGap: Double = 0.25
    /// Centered moving-average window for positions (s).
    var smoothing: Double = 0.10
    /// How short gaps are filled (see GapRepair). Linear is the validated default.
    var gapFill: GapFill = .linear
    /// Remove implausible jumps (keypoint far from where the neighbouring frames put it) before
    /// filling. Off by default so validated results do not change.
    var rejectJumps: Bool = false
    /// Jump threshold: distance from the ±0.1 s median position, in body lengths.
    var jumpThreshold: Double = 0.5

    init() {}

    // Tolerant decoding: sessions saved before 1.3 lack the gap-repair keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CommonParams()
        keypointThreshold = (try? c.decodeIfPresent(Double.self, forKey: .keypointThreshold)) ?? d.keypointThreshold
        maxGap = (try? c.decodeIfPresent(Double.self, forKey: .maxGap)) ?? d.maxGap
        smoothing = (try? c.decodeIfPresent(Double.self, forKey: .smoothing)) ?? d.smoothing
        gapFill = (try? c.decodeIfPresent(GapFill.self, forKey: .gapFill)) ?? d.gapFill
        rejectJumps = (try? c.decodeIfPresent(Bool.self, forKey: .rejectJumps)) ?? d.rejectJumps
        jumpThreshold = (try? c.decodeIfPresent(Double.self, forKey: .jumpThreshold)) ?? d.jumpThreshold
    }
}

struct TSTParams: Codable, Equatable {
    var windowStart: Double = 120
    var windowEnd: Double = 360
    /// Motion below this (body lengths / s) counts as immobile.
    var motionThreshold: Double = 0.25
    var minBout: Double = 1.0
    var motionSmoothing: Double = 0.25
    /// Hind paw lateral distance from the body axis (body lengths).
    var claspPartial: Double = 0.25
    var claspFull: Double = 0.10
    var claspWindow: Double = 10
    /// Nose–tail-base distance below this fraction of body length = tail climbing.
    var climbRatio: Double = 0.5
}

enum CylinderViewMode: String, Codable, CaseIterable, Identifiable {
    case bottom, side
    var id: String { rawValue }
    var label: String { self == .bottom ? L("Bottom view", "仰视") : L("Side view", "侧视") }
}

enum CylinderScoring: String, Codable, CaseIterable, Identifiable {
    case firstPerRear, allContacts
    var id: String { rawValue }
    var label: String { self == .firstPerRear ? L("First contact per rear", "每次竖立首次触壁") : L("Every contact", "所有触壁") }
}

enum LesionSide: String, Codable, CaseIterable, Identifiable {
    case none, left, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return L("Not set", "不设置")
        case .left: return L("Left hemisphere", "左半球")
        case .right: return L("Right hemisphere", "右半球")
        }
    }
}

struct CylinderParams: Codable, Equatable {
    var view: CylinderViewMode = .bottom
    /// Bottom view: a paw within this fraction of the radius from the rim is at the wall.
    var wallMargin: Double = 0.15
    /// Side view: paw height above the floor line (body lengths) to count as raised.
    var elevation: Double = 0.30
    /// A placed paw moves slower than this (body lengths / s).
    var stillSpeed: Double = 0.8
    var minContact: Double = 0.10
    /// Left and right placements within this interval are scored "both".
    var simultaneity: Double = 0.20
    /// Contacts separated by less than this belong to the same rear.
    var rearGap: Double = 0.5
    var scoring: CylinderScoring = .firstPerRear
    var lesion: LesionSide = .none
    var swapLR: Bool = false
    /// Score only the first N seconds / first N contacts (0 = no limit).
    var timeLimit: Double = 0
    var contactLimit: Int = 0
}

struct GaitParams: Codable, Equatable {
    /// Stance if paw speed < max(stanceFloor·BL/s, stanceRatio·body speed). 0.8 was the least
    /// biased value on simulated trot/walk at 30–100 fps with 1–2 px keypoint noise.
    var stanceRatio: Double = 0.8
    var stanceFloor: Double = 0.8
    var minPhase: Double = 0.03
    /// Strides are used only while the body moves at least this fast (BL / s).
    var minBodySpeed: Double = 1.0
    var maxStride: Double = 1.0
    var swapLR: Bool = false
    /// Strides are kept only while walking straight: mean |angular velocity| ≤ this (deg/s).
    /// Sheppard et al. 2022 analyzed straight strides at −20…+20 °/s.
    var maxTurnRate: Double = 30
    /// Drop the first and last stride of every continuous walking run (acceleration /
    /// deceleration), as in Sheppard et al. 2022.
    var trimRunEnds: Bool = true
    /// Speed at which speed-matched values are reported (body lengths / s).
    var referenceSpeed: Double = 2.0

    init() {}

    // Tolerant decoding: sessions saved by older versions lack the newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GaitParams()
        stanceRatio = try c.decodeIfPresent(Double.self, forKey: .stanceRatio) ?? d.stanceRatio
        stanceFloor = try c.decodeIfPresent(Double.self, forKey: .stanceFloor) ?? d.stanceFloor
        minPhase = try c.decodeIfPresent(Double.self, forKey: .minPhase) ?? d.minPhase
        minBodySpeed = try c.decodeIfPresent(Double.self, forKey: .minBodySpeed) ?? d.minBodySpeed
        maxStride = try c.decodeIfPresent(Double.self, forKey: .maxStride) ?? d.maxStride
        swapLR = try c.decodeIfPresent(Bool.self, forKey: .swapLR) ?? d.swapLR
        maxTurnRate = try c.decodeIfPresent(Double.self, forKey: .maxTurnRate) ?? d.maxTurnRate
        trimRunEnds = try c.decodeIfPresent(Bool.self, forKey: .trimRunEnds) ?? d.trimRunEnds
        referenceSpeed = try c.decodeIfPresent(Double.self, forKey: .referenceSpeed) ?? d.referenceSpeed
    }
}

struct AssayParams: Codable, Equatable {
    var common = CommonParams()
    var tst = TSTParams()
    var cylinder = CylinderParams()
    var gait = GaitParams()
    var itch = ItchParams()
    var pain = PainParams()
    var grooming = GroomingParams()
    var seizure = SeizureParams()

    init() {}

    // Tolerant decoding: sessions saved before the behavior assays existed lack those keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        common = try c.decodeIfPresent(CommonParams.self, forKey: .common) ?? CommonParams()
        tst = try c.decodeIfPresent(TSTParams.self, forKey: .tst) ?? TSTParams()
        cylinder = try c.decodeIfPresent(CylinderParams.self, forKey: .cylinder) ?? CylinderParams()
        gait = try c.decodeIfPresent(GaitParams.self, forKey: .gait) ?? GaitParams()
        itch = (try? c.decodeIfPresent(ItchParams.self, forKey: .itch)) ?? ItchParams()
        pain = (try? c.decodeIfPresent(PainParams.self, forKey: .pain)) ?? PainParams()
        grooming = (try? c.decodeIfPresent(GroomingParams.self, forKey: .grooming)) ?? GroomingParams()
        seizure = (try? c.decodeIfPresent(SeizureParams.self, forKey: .seizure)) ?? SeizureParams()
    }

    /// Gait needs much lighter position smoothing than the other assays: swing phases last only
    /// ~0.1 s, and a 0.1 s window would blur them into stance.
    static func defaults(for assay: Assay) -> AssayParams {
        var p = AssayParams()
        if assay == .gait { p.common.smoothing = 0.03 }
        return p
    }

    /// Settings that belong to one video, not to the study: the injection time (each video
    /// starts at a different moment) and the injected paw.
    mutating func keepPerAnimal(from other: AssayParams) {
        itch.injectionTime = other.itch.injectionTime
        pain.injectionTime = other.pain.injectionTime
        pain.injectedPaw = other.pain.injectedPaw
        seizure.injectionTime = other.seizure.injectionTime
    }
}

// MARK: - Calibration (display-frame pixels)

struct CircleCal: Codable, Equatable {
    var cx: Double
    var cy: Double
    var r: Double
}

struct ScaleCal: Codable, Equatable {
    var x1: Double, y1: Double, x2: Double, y2: Double
    var cm: Double
    var pixels: Double { hypot(x2 - x1, y2 - y1) }
    var pxPerCm: Double? { cm > 0 && pixels > 1 ? pixels / cm : nil }
}

struct Calibration: Codable, Equatable {
    var circle: CircleCal?
    var floorY: Double?
    var scale: ScaleCal?
    /// When calibration was copied from another session (fixed camera), its subject ID.
    var copiedFrom: String?
}

// MARK: - Results

enum NoteLevel: String, Codable { case info, warning, error }

struct Note: Codable, Hashable, Identifiable {
    var level: NoteLevel
    var text: LText
    var id: String { level.rawValue + text.en }
    init(_ level: NoteLevel, _ en: String, _ zh: String) {
        self.level = level
        self.text = LText(en, zh)
    }
}

struct Metric: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    var value: Double?
    var unit: String
    var decimals: Int
    var highlight: Bool = false
    /// Section this measure is listed under in the Measures tab.
    var group: LText? = nil
    var id: String { key }

    var formatted: String {
        guard let v = value, v.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }

    var exportValue: String {
        guard let v = value, v.isFinite else { return "" }
        return String(format: "%.\(max(decimals, 3))f", v)
    }
}

struct Interval: Codable, Hashable {
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

struct SeriesPoint: Codable, Hashable {
    var t: Double
    var v: Double
}

// TST
struct TSTDetail: Codable {
    var motion: [SeriesPoint]
    var threshold: Double
    var bouts: [Interval]
    var climbing: [Interval]
    var perMinute: [Double]
    var window: Interval
}

// Cylinder
enum PawLabel: String, Codable, CaseIterable, Identifiable {
    case left, right, both, ignore
    var id: String { rawValue }
    var short: String {
        switch self {
        case .left: return L("L", "左")
        case .right: return L("R", "右")
        case .both: return L("Both", "双")
        case .ignore: return L("Ignore", "忽略")
        }
    }
    var name: String {
        switch self {
        case .left: return L("Left", "左爪")
        case .right: return L("Right", "右爪")
        case .both: return L("Both", "双爪")
        case .ignore: return L("Ignored", "已忽略")
        }
    }
}

struct CylinderEvent: Codable, Hashable, Identifiable {
    /// Onset frame index — stable across re-analysis with the same video.
    var id: Int
    var onset: Double
    var offset: Double
    var auto: PawLabel
    var label: PawLabel
    var edited: Bool
    var rear: Int
    var counted: Bool
}

struct CylinderDetail: Codable {
    var events: [CylinderEvent]
    var rears: [Interval]
    var leftContacts: [Interval]
    var rightContacts: [Interval]
}

// Gait
struct GaitStride: Codable, Hashable {
    var paw: Kp
    var start: Double
    var end: Double
    var stance: Double
    var swing: Double
    var duty: Double
    var length: Double      // output units (cm or BL)
    var speed: Double       // output units per s
}

struct Footprint: Codable, Hashable {
    var paw: Kp
    var t: Double
    var x: Double           // display pixels
    var y: Double
}

struct PawSummary: Codable, Hashable {
    var paw: Kp
    var strides: Int
    var strideLength: Double?
    var strideDuration: Double?
    var stance: Double?
    var swing: Double?
    var duty: Double?
}

struct GaitDetail: Codable {
    var unit: String           // "cm" or "BL"
    var stances: [String: [Interval]]   // keyed by Kp.code
    var strides: [GaitStride]
    var footprints: [Footprint]
    var paws: [PawSummary]
    var speed: [SeriesPoint]
    var phases: [PhaseSummary]
    /// Share of hind strides per gait pattern (walk, trot, gallop, bound).
    var patterns: [PatternShare]? = nil
}

struct PatternShare: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    var count: Int
    var id: String { key }
}

extension Array where Element == Metric {
    /// Assigns Measures-tab sections by key.
    func grouped(_ sections: [(LText, [String])]) -> [Metric] {
        map { m in
            var m = m
            m.group = sections.first { $0.1.contains(m.key) }?.0
            return m
        }
    }
}

struct PhaseSummary: Codable, Hashable {
    var key: String
    var label: LText
    var values: [Double]
    var mean: Double?
    var r: Double?
}

struct AnalysisResult: Codable {
    /// Bumped whenever an analyzer changes, so stored results are recomputed on open.
    static let currentVersion = 2
    var version: Int? = AnalysisResult.currentVersion
    var metrics: [Metric]
    var notes: [Note]
    var tst: TSTDetail?
    var cylinder: CylinderDetail?
    var gait: GaitDetail?
    var analyzedAt: Date
    var poseCoverage: Double
    /// Itch, pain, grooming and seizure results (events, ethogram, time course).
    var behavior: BehaviorDetail? = nil

    func metric(_ key: String) -> Metric? { metrics.first { $0.key == key } }
}
