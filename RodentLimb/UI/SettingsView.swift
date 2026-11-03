// SettingsView.swift — language, pose models (default for new videos), tracking options, data
// safety (Recently Deleted, backups), storage, method guides.

import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var engine: PoseEngine
    @EnvironmentObject private var store: SessionStore
    @AppStorage(AppLanguage.storageKey) private var uiLanguage = "system"
    @AppStorage(SettingsKey.boxThreshold) private var boxThreshold = 0.25
    @AppStorage(SettingsKey.renderSkeleton) private var renderSkeleton = false
    @AppStorage(PoseModelID.settingsKey) private var defaultModel = PoseModelID.standard.rawValue
    @State private var storage: Int64 = 0
    @State private var showWelcome = false

    private var chosenModel: PoseModelID {
        let m = PoseModelID(rawValue: defaultModel) ?? .standard
        return m.isAvailable ? m : .standard
    }

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
                    Picker(L("For new videos", "新视频默认"), selection: Binding(get: { chosenModel }, set: { defaultModel = $0.rawValue })) {
                        ForEach(PoseModelID.choices) { m in Text(m.shortTitle.text).tag(m) }
                    }
                    ForEach(PoseModelID.choices) { m in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayName)
                                Text(m.lighting.text + " · " + String(format: L("%d keypoints", "%d 个关键点"), m.keypointCount))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            modelStatus(m)
                        }
                    }
                } header: {
                    Text(L("Pose model", "姿态模型"))
                } footer: {
                    Text(chosenModel.detail.text + " " + L("The model is chosen again for each batch when videos are added, and can be changed when a video is tracked again. Everything runs on this device.",
                                                           "每次添加视频时都可以选择模型，重新识别时也可更换。全部在本机运行。"))
                }

                Section {
                    ParamSlider(title: L("Detection confidence", "检测置信度"), value: $boxThreshold, range: 0.05...0.8, step: 0.05,
                                help: L("Lower it if the mouse is often missed; applies to the next tracking.", "若经常漏检小鼠可调低；对之后的识别生效。"))
                    Toggle(L("Also render skeleton video", "同时生成骨架视频"), isOn: $renderSkeleton)
                } header: { Text(L("Tracking", "识别")) } footer: {
                    Text(L("The review player already draws keypoints live. Rendering an MP4 is only needed for sharing and makes tracking slower.",
                           "回放时已实时绘制关键点。仅在需要分享视频时才生成 MP4，会使识别变慢。"))
                }

                Section {
                    NavigationLink(L("Recently Deleted", "最近删除")) { RecentlyDeletedView() }
                    NavigationLink(L("Backups", "备份")) { BackupsView() }
                    InfoRow(key: L("Tasks", "任务"), value: "\(store.tasks.count)")
                    InfoRow(key: L("Videos", "视频"), value: "\(store.recordings.count)")
                    InfoRow(key: L("Storage used", "占用空间"), value: Fmt.bytes(storage))
                } header: { Text(L("Data", "数据")) } footer: {
                    Text(L("Everything stays on this device and is saved as you work. Deleted items are kept for 30 days; the design and decisions are backed up every day. Files: Files › On My iPhone › RodentLimb.",
                           "所有数据只保存在本机，并在操作时随时保存。删除的内容保留 30 天；设计和决定每天自动备份。文件位置：文件 › 我的 iPhone › RodentLimb。"))
                }

                Section {
                    ForEach(Assay.allCases) { a in
                        NavigationLink(a.name.text) { AssayGuideView(assay: a) }
                    }
                } header: { Text(L("Methods and references", "方法与参考文献")) }

                Section {
                    Button(L("Show welcome again", "重新查看欢迎页")) { showWelcome = true }
                    InfoRow(key: L("Version", "版本"), value: AppInfo.version)
                    Text(L("RodentLimb is part of the Rodent series with RodentPose and RodentFlow. Automated scores support, but do not replace, blinded review of the video.",
                           "RodentLimb 与 RodentPose、RodentFlow 同属 Rodent 系列。自动评分用于辅助而非取代对视频的盲法复核。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Settings", "设置"))
            .task { storage = await store.storageBytes() }
            .fullScreenCover(isPresented: $showWelcome) { OnboardingView() }
        }
    }

    @ViewBuilder
    private func modelStatus(_ m: PoseModelID) -> some View {
        switch engine.state(m) {
        case .ready:
            Text(L("Ready", "就绪")).foregroundStyle(Palette.success)
        case .missing:
            Text(L("Not installed", "未安装")).foregroundStyle(Palette.danger)
        case .failed:
            Text(L("Failed to load", "加载失败")).foregroundStyle(Palette.warning)
        case .notLoaded:
            Text(L("Loads when needed", "需要时加载")).foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(assay.name.text).font(.title2.weight(.bold))
                    Text(assay.summary.text).font(.footnote).foregroundStyle(.secondary)
                }
                Card {
                    CardHeader(L("Recording", "拍摄要求"))
                    Text(assay.cameraTip.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Card {
                    CardHeader(L("How RodentLimb scores it", "RodentLimb 如何计分"))
                    Text(how.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Card {
                    CardHeader(L("Measures", "指标说明"))
                    ForEach(glossary) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.term.text).font(.subheadline.weight(.semibold))
                            Text(item.detail.text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Card {
                    CardHeader(L("References", "参考文献"))
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
        case .itch:
            return LText("Scratching is rapid (~20 Hz) hind-paw movement aimed at the head or neck while the body stays in place. If a trained scratch model (ScratchModel.json from the companion notebook) is installed it scores every frame; otherwise keypoint rules are used: high-frequency hind-paw energy well above this video's jitter, the paw near the head, the body still. Following Kuraishi et al. (1995), one bout ends when the paw returns to the floor or pauses; bouts close together form trains. Counts are reported from the injection, in 5-min bins over 30 min by default. In the cheek model (Shimada & LaMotte 2008) unilateral forepaw wiping of the face is scored separately as a pain-like behavior.",
                         "抓挠是后爪朝头颈部的快速（约 20 Hz）运动，同时身体基本不动。若安装了训练好的抓挠模型（配套笔记本导出的 ScratchModel.json），则逐帧打分；否则使用关键点规则：后爪高频运动能量明显高于本视频抖动水平、后爪靠近头部、身体静止。参照 Kuraishi 等（1995），后爪放回地面或停顿即一次抓挠结束；相距很近的多次抓挠组成一个抓挠串。默认从注射开始统计 30 分钟，按 5 分钟分段。面颊模型（Shimada & LaMotte 2008）中，单侧前爪擦拭面部作为痛样行为单独计数。")
        case .pain:
            return LText("Licking or biting the injected paw = the mouth within a set distance of that paw while the body is still (any contact counts, as in Wotton et al. 2020). Licking of the other paw is reported separately as a control for grooming. Flinches are brief, fast movements of the injected paw while the body is still and outside licking. Time is counted from the injection and split into phase I (0–10 min) and phase II (10–60 min) after Mogil et al. (1999), with 5-min bins.",
                         "舔咬注射爪 = 身体静止时嘴与该爪距离小于设定值（任何接触都计入，同 Wotton 等 2020）。舔另一只爪单独报告，作为理毛的对照。甩爪是身体静止、且不在舔咬时注射爪的短暂快速运动。时间从注射开始计算，参照 Mogil 等（1999）分为 I 相（0–10 分钟）和 II 相（10–60 分钟），并按 5 分钟分段。")
        case .grooming:
            return LText("Grooming is scored by body region along the cephalo-caudal chain: face/head (both forepaws stroking at the mouth), body/flank (head turned to the side and moving), hind leg/paw (mouth at a hind paw) and tail/genitals (nose at the tail base). Scratching with a hind paw is excluded. A pause longer than 5 s ends a bout; shorter pauses (≥ 1 s) make it an interrupted bout (Estanislau 2012). Microstructure measures — % interrupted bouts and % incorrect (non head-to-tail) transitions (Kalueff & Tuohimaa 2004, 2005) — are sensitive to stress and are reported with total time, bouts and latency.",
                         "理毛按头—尾顺序分部位评分：面部/头部（双前爪在嘴部擦拭）、躯体/侧腹（头转向一侧并有动作）、后腿/后爪（嘴在后爪处）、尾部/生殖区（鼻尖在尾根处）。后爪抓挠不计入。停顿超过 5 秒即一次理毛结束；更短的停顿（≥1 秒）使该次理毛成为“中断”（Estanislau 2012）。微结构指标——中断比例和非头→尾顺序转换比例（Kalueff & Tuohimaa 2004、2005）——对应激敏感，与总时长、次数和潜伏期一起报告。")
        case .seizure:
            return LText("Convulsive events are detected from the whole-body movement seen from below and mapped to a Racine-type scale: the revised scale for PTZ in mice (Van Erum et al. 2019; myoclonic jerk 3, clonic seizure upright 4, on the belly 5, on the side or wild jumping 6, tonic hindlimb extension 7) or a modified Racine scale for kainate / pilocarpine (1–5). Jerks are brief synchronized twitches of most keypoints; clonus is rhythmic fast movement of fore and hind limbs with the body in place lasting ≥ 3 s; lying on the side shows as all paws on one side of the body axis; tonic extension as both hind paws stretched behind the tail base. Latencies are measured from the injection. Every event should be confirmed on the video.",
                         "从仰视下的全身运动检测惊厥事件，并映射到 Racine 类量表：小鼠 PTZ 修订量表（Van Erum 等 2019；肌阵挛抽动 3 级、直立阵挛 4 级、俯卧 5 级、侧卧或狂跳 6 级、后肢强直伸展 7 级），或海人酸/毛果芸香碱改良 Racine 量表（1–5 级）。抽动是大多数关键点同时出现的短暂抽搐；阵挛是前后肢有节律的快速运动、身体位置不变且持续 ≥3 秒；侧卧表现为所有爪位于身体轴同一侧；强直伸展表现为两后爪伸到尾根之后。潜伏期从注射开始计算。每个事件都应在视频上确认。")
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
        case .itch:
            return [
                Item(term: LText("Scratching bouts", "抓挠次数"), detail: LText("One bout = a series of strokes ending when the hind paw returns to the floor or pauses. The standard itch measure.", "一次 = 一串抓挠动作，后爪放回地面或停顿即结束。痒行为的标准指标。")),
                Item(term: LText("Scratching time", "抓挠时间"), detail: LText("Total seconds scratching in the window; less sensitive to how bouts are split.", "窗口内抓挠的总秒数；受分段方式影响较小。")),
                Item(term: LText("Latency", "潜伏期"), detail: LText("Time from the injection to the first bout.", "从注射到第一次抓挠的时间。")),
                Item(term: LText("Trains", "抓挠串"), detail: LText("Bouts closer than the train gap (2 s) merged, as in Scratch-AID.", "间隔短于抓挠串间隔（2 秒）的多次抓挠合并，同 Scratch-AID。")),
                Item(term: LText("Side index", "侧别指数"), detail: LText("(left − right) / (left + right) × 100 of the scratching hind paw; scratching follows the injection side.", "抓挠后爪（左 − 右）/（左 + 右）× 100；抓挠通常在注射同侧。")),
                Item(term: LText("Wiping (cheek model)", "擦拭（面颊模型）"), detail: LText("Unilateral forepaw strokes of the face with the other forepaw on the floor — pain-like, unlike hind-paw scratching.", "单侧前爪擦脸、另一前爪着地——属于痛样行为，不同于后爪抓挠。")),
            ]
        case .pain:
            return [
                Item(term: LText("Licking / biting time", "舔咬时间"), detail: LText("Seconds with the mouth at the injected paw, per phase. The main formalin / capsaicin measure.", "嘴在注射爪处的秒数，按相统计。福尔马林/辣椒素实验的主要指标。")),
                Item(term: LText("Phase I / II", "I 相 / II 相"), detail: LText("Acute (direct nociceptor activation) and tonic (inflammation, central sensitization) phases of the formalin test.", "福尔马林试验的急性相（直接激活伤害感受器）和持续相（炎症与中枢敏化）。")),
                Item(term: LText("Flinches", "甩爪"), detail: LText("Brief shakes or lifts of the injected paw. More common in rats; needs ≥ 60 fps.", "注射爪的短暂抖动或抬起；大鼠更常见，需 ≥60 fps。")),
                Item(term: LText("Other-paw licking", "舔对侧爪"), detail: LText("Licking of the paw on the other side; high values suggest grooming rather than pain.", "舔另一侧爪；数值高提示是理毛而非疼痛。")),
                Item(term: LText("Ipsilateral share", "同侧占比"), detail: LText("Injected-paw licking / all paw licking × 100.", "注射爪舔咬 / 全部舔爪 × 100。")),
            ]
        case .grooming:
            return [
                Item(term: LText("Grooming time / bouts", "理毛时间 / 次数"), detail: LText("Total seconds and number of bouts in the window (a > 5-s pause starts a new bout).", "窗口内的总秒数和次数（停顿超过 5 秒开始新的一次）。")),
                Item(term: LText("Body regions", "身体部位"), detail: LText("Face/head, body/flank, hind leg/paw, tail/genitals — the four stages of the cephalo-caudal chain visible from below.", "面部/头部、躯体/侧腹、后腿/后爪、尾部/生殖区——仰视下可见的头—尾链四个阶段。")),
                Item(term: LText("Interrupted bouts", "中断比例"), detail: LText("% of bouts containing a pause of 1–5 s; rises with stress.", "包含 1–5 秒停顿的次数占比；应激时升高。")),
                Item(term: LText("Incorrect transitions", "非顺序转换"), detail: LText("% of region changes that skip or reverse the head-to-tail order; rises with stress and in some genetic models.", "跳过或逆转头→尾顺序的部位转换占比；应激时和部分基因模型中升高。")),
                Item(term: LText("Latency", "潜伏期"), detail: LText("Time from the window start to the first bout.", "从窗口开始到第一次理毛的时间。")),
            ]
        case .seizure:
            return [
                Item(term: LText("Maximal stage", "最高分级"), detail: LText("Highest stage reached in the observation period (estimated; confirm on the video).", "观察期内达到的最高分级（估计值，请在视频上确认）。")),
                Item(term: LText("Latency to first jerk", "首次抽动潜伏期"), detail: LText("Injection to the first myoclonic twitch — the most sensitive PTZ endpoint.", "从注射到第一次肌阵挛抽动——PTZ 最敏感的终点。")),
                Item(term: LText("Latency to generalized seizure", "全面性发作潜伏期"), detail: LText("Injection to the first clonic seizure (PTZ stage ≥ 4; modified Racine ≥ 3).", "从注射到第一次阵挛发作（PTZ ≥4 级；改良 Racine ≥3 级）。")),
                Item(term: LText("Tonic extension", "强直伸展"), detail: LText("Hindlimbs stretched straight back — the most severe stage, often followed by death.", "后肢向后伸直——最严重的分级，常随后死亡。")),
                Item(term: LText("Episodes", "发作次数"), detail: LText("Generalized events closer than the episode gap merged into one seizure.", "间隔短于合并间隔的全面性事件合并为一次发作。")),
                Item(term: LText("Baseline events", "基线事件"), detail: LText("Detections before the injection — the false-positive rate of the detector for this video.", "注射前的检出——该视频中检测器的假阳性水平。")),
            ]
        }
    }
}
