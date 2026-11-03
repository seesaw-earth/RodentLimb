// BehaviorModels.swift — parameters and result types of the behavior assays (itch, spontaneous
// pain, self-grooming, seizure scoring).
//
// All four share one result shape (`BehaviorDetail`): reviewable events (each can be relabeled
// on the video; edits are keyed by onset frame and survive re-analysis, like cylinder
// contacts), an ethogram (behavior intervals per row), a binned time course and one continuous
// signal. Times inside the detail are in *video* time; `origin` is the injection time, so
// latencies and bins are reported relative to it.

import Foundation

// MARK: - Parameters

enum ScratchMethod: String, Codable, CaseIterable, Identifiable {
    case auto, rules
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return L("Trained model if installed", "已安装训练模型时使用模型")
        case .rules: return L("Keypoint rules", "关键点规则")
        }
    }
}

enum ItchSite: String, Codable, CaseIterable, Identifiable {
    case nape, cheek
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nape: return L("Nape / back", "颈背部")
        case .cheek: return L("Cheek (itch vs pain)", "面颊（区分痒与痛）")
        }
    }
}

enum SeizureScale: String, Codable, CaseIterable, Identifiable {
    /// Revised Racine scale for PTZ in mice (Van Erum et al. 2019), stages 1–7.
    case ptzMouse
    /// Modified Racine scale for kainate / pilocarpine (after Racine 1972; Sharma et al. 2018), stages 1–5.
    case racineKainate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ptzMouse: return L("PTZ, mouse (Van Erum 2019, 1–7)", "PTZ 小鼠（Van Erum 2019，1–7 级）")
        case .racineKainate: return L("Kainate / pilocarpine (modified Racine, 1–5)", "海人酸 / 毛果芸香碱（改良 Racine，1–5 级）")
        }
    }
}

enum InjectedPaw: String, Codable, CaseIterable, Identifiable {
    case leftHind, rightHind, leftFore, rightFore
    var id: String { rawValue }
    var kp: Kp {
        switch self {
        case .leftHind: return .lh
        case .rightHind: return .rh
        case .leftFore: return .lf
        case .rightFore: return .rf
        }
    }
    var contralateral: InjectedPaw {
        switch self {
        case .leftHind: return .rightHind
        case .rightHind: return .leftHind
        case .leftFore: return .rightFore
        case .rightFore: return .leftFore
        }
    }
    var label: String {
        switch self {
        case .leftHind: return L("Left hind paw", "左后爪")
        case .rightHind: return L("Right hind paw", "右后爪")
        case .leftFore: return L("Left forepaw", "左前爪")
        case .rightFore: return L("Right forepaw", "右前爪")
        }
    }
    var en: String {
        switch self {
        case .leftHind: return "left hind paw"
        case .rightHind: return "right hind paw"
        case .leftFore: return "left forepaw"
        case .rightFore: return "right forepaw"
        }
    }
}

/// Decodes every key that is present and keeps the default for the rest, so sessions saved by an
/// older version (or with a parameter that was added later) still load.
private struct Tolerant {
    let c: KeyedDecodingContainer<AnyKey>
    init(_ decoder: Decoder) throws { c = try decoder.container(keyedBy: AnyKey.self) }
    func callAsFunction<T: Decodable>(_ key: String, _ fallback: T) -> T {
        guard let k = AnyKey(stringValue: key) else { return fallback }
        return (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

struct ItchParams: Codable, Equatable {
    /// Injection time in the video (s). Latency, window and bins are measured from here.
    var injectionTime: Double = 0
    var windowStart: Double = 0
    var windowEnd: Double = 1800
    var binSize: Double = 300
    var method: ScratchMethod = .auto
    /// Cheek model: also score unilateral forepaw wiping of the face (pain-like; Shimada & LaMotte 2008).
    var site: ItchSite = .nape
    /// Rules: hind-paw high-frequency energy threshold (log10 BL², 0.5-s mean).
    var energyThreshold: Double = -2.6
    /// Rules: the scratching hind paw must come within this distance of the head (BL).
    var headDistance: Double = 0.65
    /// Rules: the body hardly moves while scratching (BL/s, 0.5-s mean).
    var maxBodySpeed: Double = 1.5
    /// Scratching separated by less than this is one bout (s): the paw returning to the floor
    /// or a pause ends a bout (Kuraishi et al. 1995; Valtcheva et al. 2015).
    var mergeGap: Double = 0.5
    var minBout: Double = 0.3
    /// Bouts separated by less than this form one scratching train (Scratch-AID: 2 s).
    var trainGap: Double = 2.0
    /// Trained model: probability threshold (0 = use the value tuned in training).
    var modelThreshold: Double = 0

    init() {}
    init(from decoder: Decoder) throws {
        let t = try Tolerant(decoder), d = ItchParams()
        injectionTime = t("injectionTime", d.injectionTime)
        windowStart = t("windowStart", d.windowStart)
        windowEnd = t("windowEnd", d.windowEnd)
        binSize = t("binSize", d.binSize)
        method = t("method", d.method)
        site = t("site", d.site)
        trainGap = t("trainGap", d.trainGap)
        energyThreshold = t("energyThreshold", d.energyThreshold)
        headDistance = t("headDistance", d.headDistance)
        maxBodySpeed = t("maxBodySpeed", d.maxBodySpeed)
        mergeGap = t("mergeGap", d.mergeGap)
        minBout = t("minBout", d.minBout)
        modelThreshold = t("modelThreshold", d.modelThreshold)
    }
}

struct PainParams: Codable, Equatable {
    var injectionTime: Double = 0
    var injectedPaw: InjectedPaw = .rightHind
    /// Phase I = [injection, phase1End); phase II = [phase2Start, phase2End) (s after injection).
    /// Defaults follow the Mogil et al. (1999) protocol: 0–10 and 10–60 min.
    var phase1End: Double = 600
    var phase2Start: Double = 600
    var phase2End: Double = 3600
    var binSize: Double = 300
    /// Mouth (or nose) within this distance of the paw = licking / biting it (BL).
    var lickDistance: Double = 0.30
    var maxBodySpeed: Double = 1.5
    var minLick: Double = 0.5
    var lickMergeGap: Double = 1.0
    /// Flinch: paw speed spike above this (BL/s) lasting ≤ flinchMaxDuration while the body is still.
    var flinchSpeed: Double = 4.0
    var flinchMaxDuration: Double = 0.30
    var flinchBodySpeed: Double = 1.0

    init() {}
    init(from decoder: Decoder) throws {
        let t = try Tolerant(decoder), d = PainParams()
        injectionTime = t("injectionTime", d.injectionTime)
        injectedPaw = t("injectedPaw", d.injectedPaw)
        phase1End = t("phase1End", d.phase1End)
        phase2Start = t("phase2Start", d.phase2Start)
        phase2End = t("phase2End", d.phase2End)
        binSize = t("binSize", d.binSize)
        lickDistance = t("lickDistance", d.lickDistance)
        maxBodySpeed = t("maxBodySpeed", d.maxBodySpeed)
        minLick = t("minLick", d.minLick)
        lickMergeGap = t("lickMergeGap", d.lickMergeGap)
        flinchSpeed = t("flinchSpeed", d.flinchSpeed)
        flinchMaxDuration = t("flinchMaxDuration", d.flinchMaxDuration)
        flinchBodySpeed = t("flinchBodySpeed", d.flinchBodySpeed)
    }
}

struct GroomingParams: Codable, Equatable {
    var windowStart: Double = 0
    var windowEnd: Double = 600
    var binSize: Double = 60
    /// Both forepaws within this distance of the mouth = face / head grooming (BL). Resting
    /// forepaws sit ~0.25–0.35 BL from the mouth in a bottom view.
    var faceDistance: Double = 0.20
    /// Mouth within this distance of a hind paw = hind-leg / paw licking (BL).
    var legDistance: Double = 0.30
    /// Nose within this distance of the tail base = tail / genital grooming (BL).
    var tailDistance: Double = 0.40
    /// Head turned by more than this relative to the trunk = body (flank) grooming (degrees).
    var headTurn: Double = 50
    var maxBodySpeed: Double = 1.0
    /// Forepaw movement needed for face grooming (log10 BL², 0.5-s mean high-frequency energy).
    var strokeEnergy: Double = -3.2
    var minPhase: Double = 0.5
    /// A pause longer than this ends a bout; shorter pauses (≥ 1 s) are interruptions
    /// (Estanislau 2012; reported in the methods export because thresholds vary between labs).
    var boutGap: Double = 5
    var minBout: Double = 1.0

    init() {}
    init(from decoder: Decoder) throws {
        let t = try Tolerant(decoder), d = GroomingParams()
        windowStart = t("windowStart", d.windowStart)
        windowEnd = t("windowEnd", d.windowEnd)
        binSize = t("binSize", d.binSize)
        faceDistance = t("faceDistance", d.faceDistance)
        legDistance = t("legDistance", d.legDistance)
        tailDistance = t("tailDistance", d.tailDistance)
        headTurn = t("headTurn", d.headTurn)
        maxBodySpeed = t("maxBodySpeed", d.maxBodySpeed)
        strokeEnergy = t("strokeEnergy", d.strokeEnergy)
        minPhase = t("minPhase", d.minPhase)
        boutGap = t("boutGap", d.boutGap)
        minBout = t("minBout", d.minBout)
    }
}

struct SeizureParams: Codable, Equatable {
    var injectionTime: Double = 0
    var scale: SeizureScale = .ptzMouse
    /// Observation window after the injection (s).
    var windowEnd: Double = 1800
    var binSize: Double = 60
    /// Myoclonic jerk: whole-body speed spike above this (BL/s) …
    var jerkSpeed: Double = 4.0
    /// … lasting at most this long (s) …
    var jerkMaxDuration: Double = 0.5
    /// … from (and back to) a body moving slower than this (BL/s).
    var jerkQuietSpeed: Double = 1.0
    /// Clonic activity: rhythmic high-frequency movement of ≥ 3 body parts (log10 BL², 0.5-s mean) …
    var clonusEnergy: Double = -2.4
    /// … lasting at least this long (s; NINDS s.c. PTZ endpoint: clonus for ~3–5 s).
    var clonusMinDuration: Double = 3.0
    /// Loss of upright posture (lying on the side) for at least this long (s).
    var postureMinDuration: Double = 1.0
    /// Wild running / jumping: body speed above this (BL/s) …
    var runSpeed: Double = 8.0
    var runMinDuration: Double = 0.3
    /// Tonic hindlimb extension: both hind paws behind the tail base, still, for at least this long (s).
    var tonicMinDuration: Double = 1.0
    /// Score behavioral arrest (stage 1). Off by default: from below, a sudden arrest looks the
    /// same as an ordinary pause, so it is only meaningful when the baseline is active.
    var scoreArrest: Bool = false
    /// Behavioral arrest: sudden immobility of at least this long (s).
    var arrestMinDuration: Double = 5.0
    var arrestSpeed: Double = 0.15
    /// Events closer than this are one seizure episode (s; Van Erum et al. 2019 merged EEG events < 5 s apart).
    var episodeGap: Double = 5

    init() {}
    init(from decoder: Decoder) throws {
        let t = try Tolerant(decoder), d = SeizureParams()
        injectionTime = t("injectionTime", d.injectionTime)
        scale = t("scale", d.scale)
        windowEnd = t("windowEnd", d.windowEnd)
        binSize = t("binSize", d.binSize)
        jerkSpeed = t("jerkSpeed", d.jerkSpeed)
        jerkMaxDuration = t("jerkMaxDuration", d.jerkMaxDuration)
        jerkQuietSpeed = t("jerkQuietSpeed", d.jerkQuietSpeed)
        clonusEnergy = t("clonusEnergy", d.clonusEnergy)
        clonusMinDuration = t("clonusMinDuration", d.clonusMinDuration)
        postureMinDuration = t("postureMinDuration", d.postureMinDuration)
        runSpeed = t("runSpeed", d.runSpeed)
        runMinDuration = t("runMinDuration", d.runMinDuration)
        tonicMinDuration = t("tonicMinDuration", d.tonicMinDuration)
        scoreArrest = t("scoreArrest", d.scoreArrest)
        arrestMinDuration = t("arrestMinDuration", d.arrestMinDuration)
        arrestSpeed = t("arrestSpeed", d.arrestSpeed)
        episodeGap = t("episodeGap", d.episodeGap)
    }
}

// MARK: - Results

/// One kind of event an assay reports (and that a reviewer can assign).
struct EventClass: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    /// RGB, e.g. 0xD55E00.
    var color: UInt32
    var id: String { key }

    static let ignore = EventClass(key: "ignore", label: LText("Not this behavior (ignore)", "不是该行为（忽略）"), color: 0x8E8E93)
}

struct BehaviorEvent: Codable, Hashable, Identifiable {
    /// Onset frame index — stable across re-analysis of the same video, used for edits.
    var id: Int
    var onset: Double
    var offset: Double
    var auto: String
    var label: String
    var edited: Bool
    /// Inside the analysis window and not ignored.
    var counted: Bool
    /// Short description (e.g. "left hind", "peak 6.1 BL/s").
    var info: String?
    var duration: Double { offset - onset }
}

/// One ethogram row.
struct BehaviorTrack: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    var color: UInt32
    var intervals: [Interval]
    var id: String { key }
}

/// One value per time bin (bin i covers origin + i·binSize … origin + (i+1)·binSize).
struct BinSeries: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    var unit: String
    var values: [Double]
    var id: String { key }
}

struct BehaviorDetail: Codable {
    var classes: [EventClass]
    var events: [BehaviorEvent]
    var tracks: [BehaviorTrack]
    var binSize: Double
    var bins: [BinSeries]
    var signal: [SeriesPoint]
    var signalLabel: LText
    var signalUnit: String
    var signalThreshold: Double?
    /// Analysis window in video time.
    var window: Interval
    /// Time zero (injection) in video time.
    var origin: Double
    /// Shaded phases in video time (formalin phase I / II).
    var phases: [LabeledInterval] = []

    func eventClass(_ key: String) -> EventClass {
        classes.first { $0.key == key } ?? (key == EventClass.ignore.key ? .ignore : EventClass(key: key, label: LText(key, key), color: 0x8E8E93))
    }
}

struct LabeledInterval: Codable, Hashable {
    var label: LText
    var interval: Interval
}
