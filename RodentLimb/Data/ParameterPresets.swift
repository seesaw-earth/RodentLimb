// ParameterPresets.swift — published protocols as one-click parameter sets (Parameters › Protocol).
// iPhone copy of the Mac app's file (same presets and sources).
//
// The defaults of every assay stay exactly those of the iPhone app (Shared/, validated), so results
// do not change on their own. A preset only sets the values a protocol defines — scoring window,
// phases, bins, bout rules, stride filters, keypoint confidence — and leaves everything else
// (camera view, lesioned side, injection time, injected paw, calibration) as it is. The preset's
// source is shown with it, and every value still goes to the methods export.
//
// Sources (checked November 2026):
//  TST       Can et al. 2012 JoVE; UCSF IACUC standard procedure (Jan 2025): 6-min test, immobility
//            usually scored in the last 4 min; Steru et al. 1985 scored all 6 min.
//  Formalin  Mogil et al. 1999 (0–10 / 10–60 min); Hunskaar & Hole 1987 and Hunskaar et al. 1985
//            (0–5 / 20–30 min); Nian et al. 2014 Bio-protocol (0–5 / 20–40 min, mouse).
//  Gait      Sheppard et al. 2022 Cell Rep (JAX Kumar4 protocol): strides only while the tail base
//            moves ≥ 5 cm/s, keypoint confidence > 0.3, straight walking; first/last stride of a run
//            dropped.
//  Cylinder  Schallert-type scoring: first 20 weight-bearing contacts (Stanford SBFNL), or a 5-min
//            session (ASAP protocols.io cylinder test, Bentea et al. 2025).
//  Itch      Acute pruritogens: 30-min recording, 5-min bins (Park et al. 2019; Kobayashi et al.
//            2021 / Sakamoto et al. 2022: 20–30 min); trains = bouts < 2 s apart (Scratch-AID).
//  Grooming  Kalueff & Tuohimaa 2004/2005: 5-min sessions, pauses < 6 s do not end a bout;
//            10-min habituation then 10-min scoring (McFarlane et al. 2008; Silverman et al. 2010).
//  Seizure   PTZ 30-min observation (Van Erum et al. 2019); kainate status epilepticus 2 h with
//            the modified Racine scale.
//  Keypoints DeepLabCut's default plotting cut-off p = 0.6 (pcutoff) for a stricter confidence.

import Foundation

struct ParameterPreset: Identifiable {
    let id: String
    let title: LText
    let detail: LText
    let source: String
    /// Sets only the values the protocol defines.
    let apply: (inout AssayParams) -> Void

    func applied(to p: AssayParams) -> AssayParams {
        var q = p
        apply(&q)
        return q
    }
}

enum ParameterPresets {
    /// Presets for a task (its own first, then the keypoint-confidence ones that apply to every task).
    static func presets(for assay: Assay) -> [ParameterPreset] {
        own(assay) + keypoint(assay)
    }

    /// The preset the parameters currently follow (all of its values match), if any.
    static func current(_ p: AssayParams, assay: Assay) -> ParameterPreset? {
        own(assay).first { $0.applied(to: p) == p }
    }

    private static func own(_ assay: Assay) -> [ParameterPreset] {
        switch assay {
        case .tailSuspension:
            return [
                ParameterPreset(id: "tst.last4", title: LText("Last 4 of 6 min (standard)", "6 分钟中的后 4 分钟（标准）"),
                                detail: LText("Immobility scored from 2:00 to 6:00 — almost every mouse struggles in the first 2 min.",
                                              "在 2:00–6:00 计算不动时间——几乎所有小鼠在前 2 分钟都会挣扎。"),
                                source: "Can et al. 2012 JoVE; UCSF IACUC 2025") { p in
                    p.tst.windowStart = 120; p.tst.windowEnd = 360
                },
                ParameterPreset(id: "tst.all6", title: LText("Whole 6 min", "完整 6 分钟"),
                                detail: LText("Immobility over the whole suspension, as in the original test.", "按原始方法计算整个悬挂期间的不动时间。"),
                                source: "Steru et al. 1985 Psychopharmacology") { p in
                    p.tst.windowStart = 0; p.tst.windowEnd = 360
                },
            ]
        case .pain:
            return [
                ParameterPreset(id: "pain.mogil", title: LText("Formalin 0–10 / 10–60 min", "福尔马林 0–10 / 10–60 分钟"),
                                detail: LText("Phase I 0–10 min, phase II 10–60 min, 5-min bins (app default).",
                                              "第 I 相 0–10 分钟，第 II 相 10–60 分钟，5 分钟分箱（App 默认）。"),
                                source: "Mogil et al. 1999 Pain") { p in
                    p.pain.phase1End = 600; p.pain.phase2Start = 600; p.pain.phase2End = 3600; p.pain.binSize = 300
                },
                ParameterPreset(id: "pain.hunskaar", title: LText("Formalin 0–5 / 20–30 min", "福尔马林 0–5 / 20–30 分钟"),
                                detail: LText("The two peaks of licking described for mice: early 0–5 min, late 20–30 min.",
                                              "小鼠舔爪的两个高峰：早相 0–5 分钟，晚相 20–30 分钟。"),
                                source: "Hunskaar et al. 1985 J Neurosci Methods; Hunskaar & Hole 1987 Pain") { p in
                    p.pain.phase1End = 300; p.pain.phase2Start = 1200; p.pain.phase2End = 1800; p.pain.binSize = 300
                },
                ParameterPreset(id: "pain.nian", title: LText("Formalin 0–5 / 20–40 min", "福尔马林 0–5 / 20–40 分钟"),
                                detail: LText("Phase II widened to 20–40 min (mouse protocol).", "第 II 相扩展到 20–40 分钟（小鼠实验方案）。"),
                                source: "Nian et al. 2014 Bio-protocol e1288") { p in
                    p.pain.phase1End = 300; p.pain.phase2Start = 1200; p.pain.phase2End = 2400; p.pain.binSize = 300
                },
            ]
        case .gait:
            return [
                ParameterPreset(id: "gait.default", title: LText("App default", "App 默认"),
                                detail: LText("Strides at ≥ 1 body length/s, turning ≤ 30 °/s, run ends dropped.",
                                              "步幅仅在 ≥ 1 体长/秒、转向 ≤ 30 °/秒时计入，去掉每段行走的首尾步幅。"),
                                source: "RodentLimb validation (simulated trot/walk)") { p in
                    p.gait.minBodySpeed = 1.0; p.gait.maxTurnRate = 30; p.gait.trimRunEnds = true
                },
                ParameterPreset(id: "gait.sheppard", title: LText("Open-field strides (JAX)", "旷场步幅（JAX）"),
                                detail: LText("Strides from ~5 cm/s (≈ 0.5 body length/s), straight walking within ±20 °/s, keypoints > 0.3, first and last stride of a run dropped.",
                                              "从约 5 cm/s（≈ 0.5 体长/秒）起计步幅，直线行走 ±20 °/秒以内，关键点置信度 > 0.3，去掉每段行走的首尾步幅。"),
                                source: "Sheppard et al. 2022 Cell Rep; JAX MPD Kumar4") { p in
                    p.gait.minBodySpeed = 0.5; p.gait.maxTurnRate = 20; p.gait.trimRunEnds = true
                    p.common.keypointThreshold = 0.3
                },
            ]
        case .cylinder:
            return [
                ParameterPreset(id: "cyl.20", title: LText("First 20 contacts", "前 20 次触壁"),
                                detail: LText("Scoring stops after 20 weight-bearing wall contacts.", "记满 20 次承重触壁后停止计分。"),
                                source: "Schallert et al. 2000; Stanford SBFNL cylinder test") { p in
                    p.cylinder.contactLimit = 20; p.cylinder.timeLimit = 0
                },
                ParameterPreset(id: "cyl.5min", title: LText("5-minute session", "5 分钟实验"),
                                detail: LText("Every contact in the first 5 min (check that each animal reaches ~20).",
                                              "计入前 5 分钟内的所有触壁（请确认每只动物约达到 20 次）。"),
                                source: "Bentea et al. 2025, protocols.io (ASAP)") { p in
                    p.cylinder.timeLimit = 300; p.cylinder.contactLimit = 0
                },
                ParameterPreset(id: "cyl.all", title: LText("Whole video", "整段视频"),
                                detail: LText("No time or contact limit (app default).", "不限时间和次数（App 默认）。"),
                                source: "RodentLimb default") { p in
                    p.cylinder.timeLimit = 0; p.cylinder.contactLimit = 0
                },
            ]
        case .itch:
            return [
                ParameterPreset(id: "itch.acute", title: LText("Acute pruritogen: 30 min", "急性致痒剂：30 分钟"),
                                detail: LText("30 min after the injection in 5-min bins; bouts < 2 s apart form a train (app default).",
                                              "注射后 30 分钟，5 分钟分箱；间隔 < 2 秒的抓挠回合合并为一串（App 默认）。"),
                                source: "Park et al. 2019 Exp Neurobiol; Kobayashi et al. 2021 Sci Rep; Scratch-AID (Yu et al. 2022 eLife)") { p in
                    p.itch.windowStart = 0; p.itch.windowEnd = 1800; p.itch.binSize = 300; p.itch.trainGap = 2
                },
                ParameterPreset(id: "itch.spont", title: LText("Spontaneous / chronic itch: 60 min", "自发 / 慢性瘙痒：60 分钟"),
                                detail: LText("60 min in 10-min bins for dermatitis and dry-skin models without an injection at the start.",
                                              "60 分钟，10 分钟分箱，适用于开始时没有注射的皮炎和干皮模型。"),
                                source: "Common practice in chronic itch models (e.g. MC903, AEW)") { p in
                    p.itch.windowStart = 0; p.itch.windowEnd = 3600; p.itch.binSize = 600; p.itch.trainGap = 2
                },
            ]
        case .grooming:
            return [
                ParameterPreset(id: "groom.10", title: LText("10-minute session", "10 分钟实验"),
                                detail: LText("0–10 min in 1-min bins; a pause > 5 s ends a bout (app default).",
                                              "0–10 分钟，1 分钟分箱；停顿 > 5 秒结束一个回合（App 默认）。"),
                                source: "Estanislau et al. 2012") { p in
                    p.grooming.windowStart = 0; p.grooming.windowEnd = 600; p.grooming.binSize = 60; p.grooming.boutGap = 5
                },
                ParameterPreset(id: "groom.kalueff", title: LText("Kalueff: 5 min, 6-s bouts", "Kalueff：5 分钟，6 秒回合"),
                                detail: LText("5-min observation; pauses shorter than 6 s are interruptions within a bout.",
                                              "观察 5 分钟；短于 6 秒的停顿算作回合内的中断。"),
                                source: "Kalueff & Tuohimaa 2004 Brain Res Protoc; Kalueff et al. 2007") { p in
                    p.grooming.windowStart = 0; p.grooming.windowEnd = 300; p.grooming.binSize = 60; p.grooming.boutGap = 6
                },
                ParameterPreset(id: "groom.habit", title: LText("After 10-min habituation (10–20 min)", "适应 10 分钟后（10–20 分钟）"),
                                detail: LText("The first 10 min are habituation; grooming is scored from 10 to 20 min (autism-model protocols).",
                                              "前 10 分钟为适应期，在 10–20 分钟计分（自闭症模型常用方案）。"),
                                source: "McFarlane et al. 2008; Silverman et al. 2010 Nat Rev Neurosci") { p in
                    p.grooming.windowStart = 600; p.grooming.windowEnd = 1200; p.grooming.binSize = 60; p.grooming.boutGap = 5
                },
            ]
        case .seizure:
            return [
                ParameterPreset(id: "sz.ptz", title: LText("PTZ: 30 min", "PTZ：30 分钟"),
                                detail: LText("Revised Racine scale for PTZ in mice, 30 min in 1-min bins (app default).",
                                              "小鼠 PTZ 修订版 Racine 量表，30 分钟，1 分钟分箱（App 默认）。"),
                                source: "Van Erum et al. 2019 Epilepsia") { p in
                    p.seizure.scale = .ptzMouse; p.seizure.windowEnd = 1800; p.seizure.binSize = 60
                },
                ParameterPreset(id: "sz.ka", title: LText("Kainate / pilocarpine: 2 h", "海人酸 / 毛果芸香碱：2 小时"),
                                detail: LText("Modified Racine scale (1–5), 2 h in 10-min bins.", "改良 Racine 量表（1–5 级），2 小时，10 分钟分箱。"),
                                source: "Racine 1972; Sharma et al. 2018") { p in
                    p.seizure.scale = .racineKainate; p.seizure.windowEnd = 7200; p.seizure.binSize = 600
                },
            ]
        }
    }

    /// Keypoint confidence: the app's lenient default, or DeepLabCut's stricter plotting cut-off with
    /// jump removal (fewer false positions, more gaps).
    private static func keypoint(_ assay: Assay) -> [ParameterPreset] {
        [
            ParameterPreset(id: "kp.default", title: LText("Keypoints: confidence 0.3 (default)", "关键点：置信度 0.3（默认）"),
                            detail: LText("Keeps more frames; short gaps are filled.", "保留更多帧；短缺口会被填补。"),
                            source: "RodentLimb default; JAX gait pipeline (0.3)") { p in
                p.common.keypointThreshold = 0.3; p.common.rejectJumps = false
            },
            ParameterPreset(id: "kp.strict", title: LText("Keypoints: confidence 0.6 + remove jumps", "关键点：置信度 0.6 + 去除跳点"),
                            detail: LText("Stricter, like DeepLabCut's default cut-off; implausible jumps are removed before gaps are filled. Check the gap counts in QC.",
                                          "更严格，类似 DeepLabCut 的默认阈值；在填补缺口前先去除不合理的跳点。请在 QC 中检查缺口数量。"),
                            source: "DeepLabCut pcutoff 0.6 (Mathis et al. 2018; Nath et al. 2019)") { p in
                p.common.keypointThreshold = 0.6; p.common.rejectJumps = true
            },
        ]
    }
}
