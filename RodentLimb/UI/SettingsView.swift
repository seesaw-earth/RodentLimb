// SettingsView.swift — language, model, inference options, storage, method guides.

import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var engine: PoseEngine
    @EnvironmentObject private var store: SessionStore
    @AppStorage(AppLanguage.storageKey) private var uiLanguage = "system"
    @AppStorage(SettingsKey.boxThreshold) private var boxThreshold = 0.25
    @AppStorage(SettingsKey.renderSkeleton) private var renderSkeleton = false
    @State private var storage: Int64 = 0
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Language", "语言"), selection: $uiLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.pickerLabel).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(L("Language · 语言", "语言 · Language"))
                } footer: {
                    Text(L("Switches immediately. Exported files are always in English.", "立即切换。导出文件始终为英文。"))
                }

                Section {
                    HStack {
                        Text(L("Pose model", "姿态模型"))
                        Spacer()
                        modelStatus
                    }
                    InfoRow(key: L("Keypoints", "关键点"), value: "7 · " + L("4 paws, tail base, nose, mouth", "四爪、尾根、鼻尖、嘴"))
                    if case .ready(let info) = engine.state {
                        InfoRow(key: L("Version", "版本"), value: info.version)
                        InfoRow(key: L("Input size", "输入尺寸"), value: "\(info.inputSize) × \(info.inputSize)")
                    }
                } header: { Text(L("Model", "模型")) } footer: {
                    Text(L("CylinderMousePoseV2 (DLC-distilled, chosen over V1 in the A/B comparison) runs entirely on this device.",
                           "CylinderMousePoseV2（DLC 蒸馏版，A/B 对比中优于 V1）完全在本机运行。"))
                }

                Section {
                    VStack(alignment: .leading) {
                        ParamSlider(title: L("Detection confidence", "检测置信度"), value: $boxThreshold, range: 0.05...0.8, step: 0.05,
                                    help: L("Lower it if the mouse is often missed; applies to the next pose detection.", "若经常漏检小鼠可调低；对之后的识别生效。"))
                    }
                    Toggle(L("Also render skeleton video", "同时生成骨架视频"), isOn: $renderSkeleton)
                } header: { Text(L("Pose detection", "姿态识别")) } footer: {
                    Text(L("The review player already draws keypoints live. Rendering an MP4 is only needed for sharing and makes detection slower.",
                           "回放时已实时绘制关键点。仅在需要分享视频时才生成 MP4，会使识别变慢。"))
                }

                Section {
                    ForEach(Assay.allCases) { a in
                        NavigationLink {
                            AssayGuideView(assay: a)
                        } label: {
                            HStack(spacing: 12) {
                                AssayBadge(assay: a, size: 30)
                                Text(a.name.text)
                            }
                        }
                    }
                } header: { Text(L("Methods & references", "方法与参考文献")) }

                Section {
                    InfoRow(key: L("Sessions", "记录数"), value: "\(store.sessions.count)")
                    InfoRow(key: L("Storage used", "占用空间"), value: Fmt.bytes(storage))
                } header: { Text(L("Data", "数据")) } footer: {
                    Text(L("Everything stays on this device. Find the files in Files › On My iPhone › RodentLimb.",
                           "所有数据仅保存在本机。可在“文件 › 我的 iPhone › RodentLimb”中找到。"))
                }

                Section {
                    Link(destination: WebLinks.manual) {
                        Label(L("User manual", "使用手册"), systemImage: "book")
                    }
                    Link(destination: WebLinks.support) {
                        Label(L("Support & feedback", "支持与反馈"), systemImage: "questionmark.bubble")
                    }
                    Link(destination: WebLinks.privacy) {
                        Label(L("Privacy policy", "隐私政策"), systemImage: "hand.raised")
                    }
                } header: { Text(L("Help", "帮助")) }

                Section {
                    Button { showWelcome = true } label: { Label(L("Show welcome again", "重新查看欢迎页"), systemImage: "sparkles") }
                    InfoRow(key: L("Version", "版本"), value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0")
                    Text(L("RodentLimb is part of the Rodent series with RodentPose and RodentFlow. Automated scores support, but do not replace, blinded review of the video.",
                           "RodentLimb 与 RodentPose、RodentFlow 同属 Rodent 系列。自动评分用于辅助而非取代对视频的盲法复核。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Settings", "设置"))
            .task { storage = store.storageBytes() }
            .fullScreenCover(isPresented: $showWelcome) { OnboardingView().fontDesign(.rounded) }
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch engine.state {
        case .ready:
            Label(L("Ready", "就绪"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
        case .missing:
            Label(L("Not installed", "未安装"), systemImage: "xmark.octagon.fill").foregroundStyle(Palette.danger)
        case .failed:
            Label(L("Failed to load", "加载失败"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
        case .notLoaded:
            Button(L("Load", "加载")) { Task { _ = await engine.load() } }
        }
    }
}

// MARK: - Method guide

@MainActor
struct AssayGuideView: View {
    let assay: Assay

    private struct Item: Identifiable {
        var id: String { term.en }
        var term: LText
        var detail: LText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    AssayBadge(assay: assay, size: 48)
                    VStack(alignment: .leading) {
                        Text(assay.name.text).font(.title2.weight(.bold))
                        Text(assay.summary.text).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Card {
                    CardHeader(L("Recording", "拍摄要求"), symbol: "video")
                    Text(assay.cameraTip.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Card {
                    CardHeader(L("How RodentLimb scores it", "RodentLimb 如何计分"), symbol: "function")
                    Text(how.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Card {
                    CardHeader(L("Measures", "指标说明"), symbol: "list.bullet.rectangle")
                    ForEach(glossary) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.term.text).font(.subheadline.weight(.semibold))
                            Text(item.detail.text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Card {
                    CardHeader(L("References", "参考文献"), symbol: "books.vertical")
                    ForEach(Exporter.references(assay), id: \.self) { r in
                        Text(r).font(.footnote).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .screenContent()
            .padding(.vertical, 12)
        }
        .background(Palette.canvas)
        .navigationTitle(assay.code)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var how: LText {
        switch assay {
        case .tailSuspension:
            return LText("Motion = mean speed of the four paws and the nose, in body lengths per second. Below the motion threshold for at least the minimum bout = immobile. Immobility is summed over the analysis window (default 2–6 min). Tail climbing (nose near the tail base) and hindlimb clasping (hind paws near the body midline in the first seconds) are flagged separately.",
                         "运动量 = 四只爪和鼻尖的平均速度（体长/秒）。低于运动阈值且持续不短于最短时长 = 不动。在分析窗口内（默认第 2–6 分钟）累计不动时间。爬尾（鼻尖靠近尾根）和后肢抱握（前几秒后爪靠近身体中线）单独标记。")
        case .cylinder:
            return LText("A forepaw is on the wall when it is still and either at the calibrated rim (bottom view) or raised above the floor line (side view). Contacts close in time form one rear. By default the first paw placed in each rear is scored left, right or both (Schallert 2000). Every event can be reviewed on the video and relabeled.",
                         "前爪静止且位于标定的圆筒边缘（仰视）或高于地面线（侧视）时视为触壁。时间上相近的触壁归为一次竖立。默认统计每次竖立中第一个触壁的爪：左、右或双爪（Schallert 2000）。每个事件都可在视频上复核并修改标签。")
        case .gait:
            return LText("Each paw is in stance while its speed is near zero (relative to body speed) and in swing otherwise. A stride runs from one foot strike to the next of the same paw. Only strides taken at walking speed, in a straight line, and away from the start and end of a run are kept (Sheppard et al. 2022). Because gait changes with speed, each animal's measures are also read off its own stride-vs-speed fit at a common reference speed. Nose and tail-base sway capture whole-body coordination, and each hind stride is classified as walk, trot, gallop or bound from interlimb phase.",
                         "爪速接近零（相对身体速度）时为支撑相，否则为摆动相。步幅为同一只爪相邻两次着地之间。仅保留行走速度足够、直线行进且不在每段行走首尾的步幅（Sheppard 等 2022）。由于步态随速度变化，还会按每只动物自身“步幅指标—速度”拟合线，读取共同参考速度下的数值。鼻尖和尾根的侧向摆动反映全身协调；每个后肢步幅按肢间相位分为慢走、小跑、跑步或跳跃。")
        }
    }

    private var glossary: [Item] {
        switch assay {
        case .tailSuspension:
            return [
                Item(term: LText("Immobility time / %", "不动时间 / 比例"), detail: LText("Seconds immobile within the window; % of the window.", "窗口内不动的秒数及其占比。")),
                Item(term: LText("Latency", "潜伏期"), detail: LText("Time from the start of the video to the first immobility bout.", "从视频开始到第一次不动的时间。")),
                Item(term: LText("Bouts", "不动次数"), detail: LText("Number, mean and longest duration of immobility bouts.", "不动的次数、平均时长和最长时长。")),
                Item(term: LText("Clasping score (est.)", "抱握评分（估计）"), detail: LText("0 none · 1 one hind paw near midline > 50% · 2 both partially · 3 both fully. Confirm visually.", "0 无 · 1 一只后爪靠近中线 > 50% · 2 双侧部分 · 3 双侧完全。请目视确认。")),
                Item(term: LText("Tail climbing", "爬尾"), detail: LText("% of the window with the nose near the tail base. > 20% is a common exclusion criterion.", "窗口内鼻尖靠近尾根的时间占比。> 20% 常作为排除标准。")),
            ]
        case .cylinder:
            return [
                Item(term: LText("Contralateral use", "对侧使用率"), detail: LText("contra / (ipsi + contra) × 100; lower values = more impairment of the paw opposite the lesion.", "对侧 / (同侧 + 对侧) × 100；数值越低，损伤对侧爪受损越重。")),
                Item(term: LText("Asymmetry index", "不对称指数"), detail: LText("(ipsi − contra) / (ipsi + contra + both) × 100.", "(同侧 − 对侧) / (同侧 + 对侧 + 双爪) × 100。")),
                Item(term: LText("Both", "双爪"), detail: LText("Left and right placed within the simultaneity window.", "左右爪在同时判定窗口内先后触壁。")),
                Item(term: LText("Rears", "竖立"), detail: LText("Episodes with at least one wall contact.", "至少有一次触壁的竖立。")),
            ]
        case .gait:
            return [
                Item(term: LText("Stride length", "步幅"), detail: LText("Distance between consecutive footprints of one paw (cm with a scale, otherwise body lengths).", "同一只爪相邻两个足印的距离（有标尺为厘米，否则为体长）。")),
                Item(term: LText("Duty factor", "占空比"), detail: LText("Stance duration / stride duration. Rises as mice walk slower or less stably.", "支撑相时长 / 步幅时长。行走越慢或越不稳，数值越高。")),
                Item(term: LText("Base of support", "支撑面宽度"), detail: LText("Distance between left and right footprints perpendicular to the walking direction.", "左右足印在垂直于行走方向上的距离。")),
                Item(term: LText("Interlimb phase", "肢间相位"), detail: LText("When a paw strikes within the reference paw's stride: 0.5 = alternating, 0/1 = synchronous. R = consistency.", "某爪着地时刻在参考爪步幅中的位置：0.5 = 交替，0/1 = 同步。R = 一致性。")),
                Item(term: LText("Regularity index", "规律性指数"), detail: LText("Share of paw placements in normal step-sequence patterns (100% = fully regular).", "符合正常步序模式的着地占比（100% = 完全规律）。")),
                Item(term: LText("Speed-matched values", "速度匹配值"), detail: LText("The animal's own stride-vs-speed regression evaluated at the reference speed; left blank rather than extrapolated when the animal never walked near that speed.", "该动物自身“步幅指标—速度”回归在参考速度处的数值；若动物从未在该速度附近行走，则留空而不外推。")),
                Item(term: LText("Variability (CV)", "变异系数"), detail: LText("Stride-to-stride SD / mean of hind stride length or time; rises with ataxia.", "后肢步幅长度或时长的标准差/均值；共济失调时升高。")),
                Item(term: LText("Lateral sway", "侧向摆动"), detail: LText("Side-to-side range of the nose and tail base within each stride, relative to the body's path (body lengths).", "每个步幅内鼻尖和尾根相对身体路径的左右摆动幅度（体长）。")),
                Item(term: LText("Gait pattern", "步态模式"), detail: LText("Walk/trot: hind limbs alternate (phase ≈ 0.5), trot also couples diagonal limbs; bound: hind limbs together; gallop: in between.", "慢走/小跑：后肢交替（相位≈0.5），小跑同时对角肢同步；跳跃：后肢同步；跑步：介于两者之间。")),
                Item(term: LText("Print position", "足印位置"), detail: LText("Distance between a hind print and the preceding fore print on the same side.", "同侧后爪足印与前一个前爪足印之间的距离。")),
            ]
        }
    }
}

/// Public pages of the manual (GitHub Pages). The Chinese pages live under /zh/.
enum WebLinks {
    static let base = "https://seesaw-earth.github.io/RodentLimb/"
    private static func page(_ path: String) -> URL {
        URL(string: base + (Lang.isChinese ? "zh/" : "") + path)!
    }
    static var manual: URL { page("") }
    static var support: URL { page("support.html") }
    static var privacy: URL { page("privacy.html") }
}
