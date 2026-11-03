// ParamsSheet.swift — live parameter editing. Results recompute as sliders move (no model
// re-run), with the key metrics pinned at the top so the effect is visible immediately. A Protocol
// picker sets the values of a published protocol (ParameterPresets.swift); "Apply to all sessions of
// this task" keeps the task consistent (never touches other tasks).

import SwiftUI

@MainActor
struct ParamsSheet: View {
    let sessionID: UUID
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var p = AssayParams()
    @State private var loaded = false
    @State private var confirmApplyAll = false
    @State private var toast: String?
    @State private var commitTask: Task<Void, Never>?

    private var session: Session? { store.session(sessionID) }

    var body: some View {
        NavigationStack {
            Form {
                if let r = store.results[sessionID] {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(r.metrics.filter { $0.highlight }) { MetricTile(metric: $0) }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(L("Live result", "实时结果"))
                    }
                }
                if let s = session { protocolSection(s.assay) }
                if let s = session {
                    switch s.assay {
                    case .tailSuspension: tstSection
                    case .cylinder: cylinderSection
                    case .gait: gaitSection
                    case .itch: itchSection
                    case .pain: painSection
                    case .grooming: groomingSection
                    case .seizure: seizureSection
                    }
                }
                commonSection
                Section {
                    Button(L("Reset to defaults", "恢复默认值")) {
                        var d = AssayParams.defaults(for: session?.assay ?? .tailSuspension)
                        d.cylinder.lesion = p.cylinder.lesion
                        d.cylinder.view = p.cylinder.view
                        d.keepPerAnimal(from: p)
                        p = d
                    }
                    if peers > 0 {
                        Button(String(format: L("Apply to all %d other sessions of this task…", "应用到本任务的其他 %d 个实验…"), peers)) { confirmApplyAll = true }
                    }
                } footer: {
                    Text(L("Use the same parameters for every animal of a task. Each video keeps its own injection time, injected paw and lesioned side. Values are written to the methods export.",
                           "同一任务的所有动物应使用相同参数。每段视频保留各自的注射时间、注射爪和损伤侧。参数值会写入导出的方法描述中。"))
                }
            }
            .navigationTitle(L("Parameters", "参数"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done", "完成")) { dismiss() } }
            }
            .onAppear {
                if !loaded, let s = session { p = s.params; loaded = true }
            }
            .onChange(of: p) { _, new in
                guard loaded else { return }
                // While a slider moves only this form redraws; the session (and every screen
                // observing it) updates once the finger pauses for a moment.
                commitTask?.cancel()
                commitTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard !Task.isCancelled else { return }
                    store.update(sessionID) { $0.params = new }
                    store.analyze(sessionID)
                }
            }
            .onDisappear {
                // Make sure the last change is never lost when the sheet closes quickly.
                if commitTask != nil, loaded {
                    commitTask?.cancel()
                    let final = p
                    store.update(sessionID) { $0.params = final }
                    store.analyze(sessionID)
                }
            }
            .confirmationDialog(L("Apply these parameters to every session of this task?", "将这些参数应用到本任务的所有实验？"),
                                isPresented: $confirmApplyAll, titleVisibility: .visible) {
                Button(L("Apply to all", "全部应用")) { applyAll() }
            }
            .toast($toast)
        }
    }

    /// Other sessions of the same task (same paradigm and study).
    private var peers: Int { store.taskPeers(of: sessionID).count }

    private func applyAll() {
        // The current values first, so nothing typed a moment ago is left out.
        commitTask?.cancel()
        store.update(sessionID) { $0.params = p }
        store.analyze(sessionID)
        let n = store.applyToTask(from: sessionID, params: p)
        toast = String(format: L("Applied to %d sessions", "已应用到 %d 个实验"), n)
    }

    // MARK: Protocol

    @ViewBuilder
    private func protocolSection(_ assay: Assay) -> some View {
        let presets = ParameterPresets.presets(for: assay)
        let current = ParameterPresets.current(p, assay: assay)
        Section {
            Menu {
                ForEach(presets) { preset in
                    Button(preset.title.text) {
                        withAnimation(Motion.snappy) { p = preset.applied(to: p) }
                        toast = preset.title.text
                    }
                }
            } label: {
                HStack {
                    Text(L("Protocol", "实验方案")).foregroundStyle(.primary)
                    Spacer()
                    Text(current?.title.text ?? L("Custom", "自定义")).foregroundStyle(.tint).lineLimit(1)
                }
            }
            if let current {
                Text(current.detail.text + " " + L("Source: ", "来源：") + current.source)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L("Protocol", "实验方案"))
        } footer: {
            Text(L("A protocol sets only the values it defines (window, phases, bins, bout rules, stride filters, keypoint confidence); everything else stays as it is.",
                   "实验方案只设置其规定的数值（窗口、分相、分箱、回合规则、步幅筛选、关键点置信度），其余保持不变。"))
        }
    }

    // MARK: Sections

    private var tstSection: some View {
        Group {
            Section {
                ParamSlider(title: L("Window start", "窗口起点"), value: $p.tst.windowStart, range: 0...600, step: 10, unit: "s", decimals: 0)
                ParamSlider(title: L("Window end", "窗口终点"), value: $p.tst.windowEnd, range: 30...900, step: 10, unit: "s", decimals: 0,
                            help: L("Standard: score minutes 2–6 of a 6-min test (120–360 s).", "标准做法：6 分钟测试中统计第 2–6 分钟（120–360 秒）。"))
            } header: { Text(L("Analysis window", "分析窗口")) }
            Section {
                ParamSlider(title: L("Motion threshold", "运动阈值"), value: $p.tst.motionThreshold, range: 0.05...1.0, step: 0.01, unit: "BL/s",
                            help: L("Below this, the mouse counts as immobile. Raise it if small breathing movements are scored as mobile.",
                                    "低于该值视为不动。若呼吸等微动被判为挣扎，可调高。"))
                ParamSlider(title: L("Minimum bout", "最短不动时长"), value: $p.tst.minBout, range: 0.2...5, step: 0.1, unit: "s", decimals: 1)
                ParamSlider(title: L("Motion smoothing", "运动平滑"), value: $p.tst.motionSmoothing, range: 0...1, step: 0.05, unit: "s")
            } header: { Text(L("Immobility", "不动判定")) }
            Section {
                ParamSlider(title: L("Clasping window", "抱握评估时长"), value: $p.tst.claspWindow, range: 3...60, step: 1, unit: "s", decimals: 0,
                            help: L("Seconds from the start of suspension (Guyenet et al. use ~10 s).", "从悬挂开始计算的秒数（Guyenet 等人约 10 秒）。"))
                ParamSlider(title: L("Partial clasp distance", "部分抱握距离"), value: $p.tst.claspPartial, range: 0.05...0.6, step: 0.01, unit: "BL")
                ParamSlider(title: L("Full clasp distance", "完全抱握距离"), value: $p.tst.claspFull, range: 0.02...0.4, step: 0.01, unit: "BL")
                ParamSlider(title: L("Tail-climbing ratio", "爬尾判定比例"), value: $p.tst.climbRatio, range: 0.2...0.9, step: 0.05, unit: "BL",
                            help: L("Nose closer to the tail base than this = climbing.", "鼻尖到尾根距离小于该值视为爬尾。"))
            } header: { Text(L("Clasping & climbing", "抱握与爬尾")) }
        }
    }

    private var cylinderSection: some View {
        Group {
            Section {
                Picker(L("Camera", "拍摄视角"), selection: $p.cylinder.view) {
                    ForEach(CylinderViewMode.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Lesioned hemisphere", "损伤半球"), selection: $p.cylinder.lesion) {
                    ForEach(LesionSide.allCases) { Text($0.label).tag($0) }
                }
                if p.cylinder.lesion != .none {
                    Text(String(format: L("Contralateral (impaired) paw: %@", "对侧（受损）爪：%@"),
                                p.cylinder.lesion == .left ? L("right", "右爪") : L("left", "左爪")))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Picker(L("Scoring", "计分方式"), selection: $p.cylinder.scoring) {
                    ForEach(CylinderScoring.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("Swap left/right labels", "交换左右标签"), isOn: $p.cylinder.swapLR)
            } header: { Text(L("Setup", "设置")) } footer: {
                Text(L("Swap left/right if the model's L/R labels refer to image sides rather than the animal's body (e.g. mirrored bottom view).",
                       "若模型的左/右指的是画面左右而非动物自身左右（如镜像的仰视画面），请交换。"))
            }
            Section {
                if p.cylinder.view == .bottom {
                    ParamSlider(title: L("Wall zone", "触壁区域"), value: $p.cylinder.wallMargin, range: 0.03...0.4, step: 0.01, unit: "× r",
                                help: L("A paw this close to the rim (fraction of radius) is at the wall.", "爪距边缘在该比例半径内即视为在壁上。"))
                } else {
                    ParamSlider(title: L("Paw height", "爪离地高度"), value: $p.cylinder.elevation, range: 0.1...1.0, step: 0.01, unit: "BL")
                }
                ParamSlider(title: L("Still paw speed", "爪静止速度"), value: $p.cylinder.stillSpeed, range: 0.2...3, step: 0.05, unit: "BL/s")
                ParamSlider(title: L("Minimum contact", "最短触壁"), value: $p.cylinder.minContact, range: 0.03...0.6, step: 0.01, unit: "s")
                ParamSlider(title: L("Simultaneous window", "同时判定窗口"), value: $p.cylinder.simultaneity, range: 0.03...0.6, step: 0.01, unit: "s",
                            help: L("Left and right placed within this time = both.", "左右爪在此时间内先后触壁 = 双爪。"))
                ParamSlider(title: L("Rear gap", "竖立间隔"), value: $p.cylinder.rearGap, range: 0.1...2, step: 0.05, unit: "s")
            } header: { Text(L("Contact detection", "触壁检测")) }
            Section {
                ParamSlider(title: L("Score first", "仅统计前"), value: $p.cylinder.timeLimit, range: 0...900, step: 30, unit: "s", decimals: 0,
                            help: L("0 = whole video.", "0 = 整段视频。"))
                Stepper(value: $p.cylinder.contactLimit, in: 0...100) {
                    HStack {
                        Text(L("Contact limit", "触壁次数上限"))
                        Spacer()
                        Text(p.cylinder.contactLimit == 0 ? L("None", "不限") : "\(p.cylinder.contactLimit)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            } header: { Text(L("Limits", "上限")) } footer: {
                Text(L("Some protocols score the first 20 contacts or the first 3–5 minutes.", "部分方案仅统计前 20 次触壁或前 3–5 分钟。"))
            }
        }
    }

    private var gaitSection: some View {
        Group {
            Section {
                ParamSlider(title: L("Stance speed ratio", "支撑相速度比"), value: $p.gait.stanceRatio, range: 0.1...1.2, step: 0.05, unit: "× body",
                            help: L("Paw slower than this fraction of body speed = stance.", "爪速低于身体速度的该比例 = 支撑相。"))
                ParamSlider(title: L("Stance speed floor", "支撑相速度下限"), value: $p.gait.stanceFloor, range: 0.1...3, step: 0.05, unit: "BL/s")
                ParamSlider(title: L("Minimum phase", "最短相位"), value: $p.gait.minPhase, range: 0...0.15, step: 0.005, unit: "s", decimals: 3)
                Toggle(L("Swap left/right labels", "交换左右标签"), isOn: $p.gait.swapLR)
            } header: { Text(L("Stance / swing", "支撑相 / 摆动相")) }
            Section {
                ParamSlider(title: L("Minimum walking speed", "最低行走速度"), value: $p.gait.minBodySpeed, range: 0.2...5, step: 0.1, unit: "BL/s", decimals: 1,
                            help: L("Strides are analyzed only while the mouse walks at least this fast.", "只分析行走速度不低于该值时的步幅。"))
                ParamSlider(title: L("Maximum turning rate", "最大转向角速度"), value: $p.gait.maxTurnRate, range: 5...120, step: 5, unit: "°/s", decimals: 0,
                            help: L("Strides taken while turning faster than this are excluded (Sheppard et al. 2022 used ±20 °/s).",
                                    "转向快于该值时的步幅会被排除（Sheppard 等 2022 使用 ±20 °/s）。"))
                Toggle(L("Drop first and last stride of each run", "去掉每段行走的首尾步幅"), isOn: $p.gait.trimRunEnds)
                ParamSlider(title: L("Maximum stride", "最长步幅时长"), value: $p.gait.maxStride, range: 0.2...2, step: 0.05, unit: "s")
            } header: { Text(L("Which strides count", "步幅筛选")) } footer: {
                Text(L("Acceleration at the start and end of a run changes stride timing, so those strides are dropped by default.",
                       "每段行走开始和结束时的加减速会改变步态时序，因此默认排除。"))
            }
            Section {
                ParamSlider(title: L("Reference speed", "参考速度"), value: $p.gait.referenceSpeed, range: 0.5...5, step: 0.1, unit: "BL/s", decimals: 1,
                            help: L("Speed-matched values are read off each animal's stride-vs-speed fit at this speed. Use the same value for every animal in a study.",
                                    "速度匹配值取自每只动物“步幅指标—速度”拟合线在该速度处的数值。同一研究中所有动物请使用相同的值。"))
            } header: { Text(L("Speed matching", "速度匹配")) }
        }
    }

    // MARK: Behavior assays

    /// Edits a time stored in seconds as minutes.
    private func minutes(_ kp: WritableKeyPath<AssayParams, Double>) -> Binding<Double> {
        Binding(get: { p[keyPath: kp] / 60 }, set: { p[keyPath: kp] = ($0 * 60).rounded() })
    }

    private var videoMinutes: Double {
        guard let d = session?.duration, d > 0 else { return 120 }
        return max(1, (d / 60).rounded(.up))
    }

    private func injectionSlider(_ kp: WritableKeyPath<AssayParams, Double>) -> some View {
        ParamSlider(title: L("Injection time in the video", "视频中的注射时刻"), value: minutes(kp), range: 0...videoMinutes, step: 0.25,
                    unit: L("min", "分钟"), decimals: 2,
                    help: L("Time zero for latencies, the window and the time bins. Leave at 0 if the video starts at the injection.",
                            "潜伏期、分析窗口和时间段都从这里算起。若视频从注射开始录制，保持 0 即可。"))
    }

    private func binPicker(_ kp: WritableKeyPath<AssayParams, Double>, _ options: [Double]) -> some View {
        Picker(L("Time bins", "时间段"), selection: Binding(get: { p[keyPath: kp] }, set: { p[keyPath: kp] = $0 })) {
            ForEach(options, id: \.self) { v in
                Text(v >= 60 ? String(format: L("%g min", "%g 分钟"), v / 60) : String(format: L("%g s", "%g 秒"), v)).tag(v)
            }
        }
    }

    private var itchSection: some View {
        Group {
            Section {
                injectionSlider(\.itch.injectionTime)
                ParamSlider(title: L("Window start", "窗口起点"), value: minutes(\.itch.windowStart), range: 0...60, step: 0.5, unit: L("min", "分钟"), decimals: 1)
                ParamSlider(title: L("Window end", "窗口终点"), value: minutes(\.itch.windowEnd), range: 1...120, step: 1, unit: L("min", "分钟"), decimals: 0,
                            help: L("Standard: 30 min after an intradermal pruritogen (60 min for some chronic-itch models).",
                                    "标准做法：皮内注射致痒剂后观察 30 分钟（部分慢性痒模型为 60 分钟）。"))
                binPicker(\.itch.binSize, [60, 120, 300, 600])
            } header: { Text(L("Timing (after injection)", "时间（从注射算起）")) }
            Section {
                Picker(L("Injection site", "注射部位"), selection: $p.itch.site) {
                    ForEach(ItchSite.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Detection", "检测方法"), selection: $p.itch.method) {
                    ForEach(ScratchMethod.allCases) { Text($0.label).tag($0) }
                }
                if p.itch.method == .auto {
                    Text(ScratchModel.bundled.map { String(format: L("Installed: %@", "已安装：%@"), $0.sourceName) }
                         ?? L("No trained model installed — keypoint rules are used.", "未安装训练模型，将使用关键点规则。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    if ScratchModel.bundled != nil {
                        ParamSlider(title: L("Model threshold", "模型阈值"), value: $p.itch.modelThreshold, range: 0...0.95, step: 0.05,
                                    help: L("0 = the threshold tuned during training.", "0 = 训练时调好的阈值。"))
                    }
                }
            } header: { Text(L("Setup", "设置")) } footer: {
                Text(L("Cheek model (Shimada & LaMotte 2008): hind-paw scratching of the cheek indicates itch, unilateral forepaw wiping indicates pain; both are scored.",
                       "面颊模型（Shimada & LaMotte 2008）：后爪抓挠面颊代表痒，单侧前爪擦拭代表痛，两者分别计数。"))
            }
            Section {
                ParamSlider(title: L("Hind-paw fast movement", "后爪快速运动阈值"), value: $p.itch.energyThreshold, range: -4 ... -1.5, step: 0.05, unit: "log₁₀",
                            help: L("Minimum high-frequency hind-paw energy. It is raised automatically above this video's own keypoint jitter.",
                                    "后爪高频运动能量的下限；会自动提高到本视频关键点抖动水平之上。"))
                ParamSlider(title: L("Paw–head distance", "爪–头距离"), value: $p.itch.headDistance, range: 0.3...1.0, step: 0.05, unit: "BL")
                ParamSlider(title: L("Maximum body speed", "最大身体速度"), value: $p.itch.maxBodySpeed, range: 0.3...4, step: 0.1, unit: "BL/s", decimals: 1)
            } header: { Text(L("Keypoint rules", "关键点规则")) }
            Section {
                ParamSlider(title: L("Merge pauses shorter than", "合并短于此的停顿"), value: $p.itch.mergeGap, range: 0...2, step: 0.05, unit: "s",
                            help: L("A bout ends when the paw returns to the floor or pauses (Kuraishi et al. 1995).", "后爪放回地面或停顿即一次抓挠结束（Kuraishi 等 1995）。"))
                ParamSlider(title: L("Minimum bout", "最短一次"), value: $p.itch.minBout, range: 0.1...2, step: 0.05, unit: "s")
                ParamSlider(title: L("Train gap", "抓挠串间隔"), value: $p.itch.trainGap, range: 0.5...10, step: 0.5, unit: "s", decimals: 1,
                            help: L("Bouts closer than this form one scratching train (Scratch-AID uses 2 s).", "间隔短于此的多次抓挠合并为一个抓挠串（Scratch-AID 使用 2 秒）。"))
            } header: { Text(L("Bouts", "抓挠次数")) }
        }
    }

    private var painSection: some View {
        Group {
            Section {
                injectionSlider(\.pain.injectionTime)
                Picker(L("Injected paw", "注射爪"), selection: $p.pain.injectedPaw) {
                    ForEach(InjectedPaw.allCases) { Text($0.label).tag($0) }
                }
            } header: { Text(L("Setup", "设置")) } footer: {
                Text(L("Labels refer to the animal's own left and right as the pose model reports them.", "左右以姿态模型标注的动物自身左右为准。"))
            }
            Section {
                ParamSlider(title: L("Phase I ends", "I 相结束"), value: minutes(\.pain.phase1End), range: 1...30, step: 0.5, unit: L("min", "分钟"), decimals: 1)
                ParamSlider(title: L("Phase II starts", "II 相开始"), value: minutes(\.pain.phase2Start), range: 1...40, step: 0.5, unit: L("min", "分钟"), decimals: 1)
                ParamSlider(title: L("Phase II ends", "II 相结束"), value: minutes(\.pain.phase2End), range: 5...120, step: 1, unit: L("min", "分钟"), decimals: 0)
                binPicker(\.pain.binSize, [60, 120, 300, 600])
            } header: { Text(L("Phases (after injection)", "分相（从注射算起）")) } footer: {
                Text(L("Formalin, mouse: phase I 0–10 min, phase II 10–60 min (Mogil et al. 1999); some labs use 0–5 and 15–45 min. Capsaicin: a single 5–15-min period — set phase I to end there and read phase I.",
                       "小鼠福尔马林：I 相 0–10 分钟，II 相 10–60 分钟（Mogil 等 1999）；也有实验室用 0–5 与 15–45 分钟。辣椒素：单一 5–15 分钟时段——把 I 相终点设在该处，读取 I 相即可。"))
            }
            Section {
                ParamSlider(title: L("Mouth–paw distance", "嘴–爪距离"), value: $p.pain.lickDistance, range: 0.1...0.6, step: 0.01, unit: "BL",
                            help: L("Mouth this close to the paw while the body is still = licking / biting.", "身体静止且嘴与爪距离小于该值 = 舔咬。"))
                ParamSlider(title: L("Minimum licking", "最短舔咬"), value: $p.pain.minLick, range: 0.1...3, step: 0.1, unit: "s", decimals: 1)
                ParamSlider(title: L("Merge gaps shorter than", "合并短于此的间隔"), value: $p.pain.lickMergeGap, range: 0...3, step: 0.1, unit: "s", decimals: 1)
                ParamSlider(title: L("Maximum body speed", "最大身体速度"), value: $p.pain.maxBodySpeed, range: 0.3...4, step: 0.1, unit: "BL/s", decimals: 1)
            } header: { Text(L("Licking / biting", "舔咬")) }
            Section {
                ParamSlider(title: L("Paw speed", "爪速度"), value: $p.pain.flinchSpeed, range: 1.5...12, step: 0.25, unit: "BL/s",
                            help: L("Raised automatically when the paw track is noisy.", "爪轨迹抖动大时会自动提高。"))
                ParamSlider(title: L("Maximum duration", "最长时长"), value: $p.pain.flinchMaxDuration, range: 0.05...1, step: 0.05, unit: "s")
                ParamSlider(title: L("Body still below", "身体静止阈值"), value: $p.pain.flinchBodySpeed, range: 0.2...3, step: 0.1, unit: "BL/s", decimals: 1)
            } header: { Text(L("Flinching / shaking", "甩爪 / 抖爪")) } footer: {
                Text(L("Flinches last ~0.1 s; record at ≥ 60 fps to count them reliably.", "甩爪约持续 0.1 秒；建议以 ≥ 60 fps 录制以可靠计数。"))
            }
        }
    }

    private var groomingSection: some View {
        Group {
            Section {
                ParamSlider(title: L("Window start", "窗口起点"), value: minutes(\.grooming.windowStart), range: 0...60, step: 0.5, unit: L("min", "分钟"), decimals: 1)
                ParamSlider(title: L("Window end", "窗口终点"), value: minutes(\.grooming.windowEnd), range: 1...120, step: 1, unit: L("min", "分钟"), decimals: 0,
                            help: L("Common: 10 min (novel cage) or 20 min after a water spray.", "常用：新笼 10 分钟，或喷水后 20 分钟。"))
                binPicker(\.grooming.binSize, [60, 120, 300])
            } header: { Text(L("Analysis window", "分析窗口")) }
            Section {
                ParamSlider(title: L("Face: forepaw–mouth distance", "面部：前爪–嘴距离"), value: $p.grooming.faceDistance, range: 0.1...0.4, step: 0.01, unit: "BL")
                ParamSlider(title: L("Face: forepaw stroking", "面部：前爪擦拭能量"), value: $p.grooming.strokeEnergy, range: -4.5 ... -2, step: 0.05, unit: "log₁₀",
                            help: L("Raised automatically above this video's keypoint jitter.", "会自动提高到本视频关键点抖动水平之上。"))
                ParamSlider(title: L("Body: head turn", "躯体：转头角度"), value: $p.grooming.headTurn, range: 20...120, step: 5, unit: "°", decimals: 0)
                ParamSlider(title: L("Leg: mouth–hind-paw distance", "后腿：嘴–后爪距离"), value: $p.grooming.legDistance, range: 0.1...0.6, step: 0.01, unit: "BL")
                ParamSlider(title: L("Tail: nose–tail-base distance", "尾部：鼻–尾根距离"), value: $p.grooming.tailDistance, range: 0.2...0.7, step: 0.01, unit: "BL")
                ParamSlider(title: L("Maximum body speed", "最大身体速度"), value: $p.grooming.maxBodySpeed, range: 0.3...3, step: 0.1, unit: "BL/s", decimals: 1)
            } header: { Text(L("Body regions", "身体部位")) }
            Section {
                ParamSlider(title: L("Minimum region segment", "最短部位片段"), value: $p.grooming.minPhase, range: 0.2...3, step: 0.1, unit: "s", decimals: 1)
                ParamSlider(title: L("Pause that ends a bout", "结束一次理毛的停顿"), value: $p.grooming.boutGap, range: 1...15, step: 0.5, unit: "s", decimals: 1,
                            help: L("Longer pauses start a new bout; shorter ones (≥ 1 s) make it an interrupted bout (Estanislau 2012: pauses > 5 s separate bouts).",
                                    "更长的停顿开始新的一次；更短的停顿（≥1 秒）使该次成为“中断”（Estanislau 2012：停顿 > 5 秒即分为两次）。"))
                ParamSlider(title: L("Minimum bout", "最短一次"), value: $p.grooming.minBout, range: 0.3...5, step: 0.1, unit: "s", decimals: 1)
            } header: { Text(L("Bouts & microstructure", "次数与微结构")) }
        }
    }

    private var seizureSection: some View {
        Group {
            Section {
                injectionSlider(\.seizure.injectionTime)
                ParamSlider(title: L("Observation period", "观察时长"), value: minutes(\.seizure.windowEnd), range: 1...180, step: 1, unit: L("min", "分钟"), decimals: 0,
                            help: L("Common: 30 min after PTZ; 1–2 h for kainate or pilocarpine.", "常用：PTZ 后 30 分钟；海人酸或毛果芸香碱 1–2 小时。"))
                binPicker(\.seizure.binSize, [60, 120, 300, 600])
                Picker(L("Scale", "评分量表"), selection: $p.seizure.scale) {
                    ForEach(SeizureScale.allCases) { Text($0.label).tag($0) }
                }
            } header: { Text(L("Setup", "设置")) } footer: {
                Text(L("Record a few minutes before the injection: detections in that baseline show the false-positive rate for this video.",
                       "建议注射前先录几分钟：基线期的检出数即该视频的假阳性水平。"))
            }
            Section {
                ParamSlider(title: L("Jerk: body speed", "抽动：身体速度"), value: $p.seizure.jerkSpeed, range: 1.5...12, step: 0.25, unit: "BL/s")
                ParamSlider(title: L("Jerk: maximum duration", "抽动：最长时长"), value: $p.seizure.jerkMaxDuration, range: 0.1...1.5, step: 0.05, unit: "s")
                ParamSlider(title: L("Clonus: limb movement", "阵挛：肢体运动能量"), value: $p.seizure.clonusEnergy, range: -4 ... -1.5, step: 0.05, unit: "log₁₀",
                            help: L("Raised automatically above this video's keypoint jitter.", "会自动提高到本视频关键点抖动水平之上。"))
                ParamSlider(title: L("Clonus: minimum duration", "阵挛：最短时长"), value: $p.seizure.clonusMinDuration, range: 0.5...10, step: 0.5, unit: "s", decimals: 1,
                            help: L("NINDS PTZ endpoint: clonus lasting ~3–5 s.", "NINDS PTZ 终点：阵挛持续约 3–5 秒。"))
                ParamSlider(title: L("Lying on the side: minimum", "侧卧：最短时长"), value: $p.seizure.postureMinDuration, range: 0.3...5, step: 0.1, unit: "s", decimals: 1)
                ParamSlider(title: L("Wild running: body speed", "狂奔：身体速度"), value: $p.seizure.runSpeed, range: 3...20, step: 0.5, unit: "BL/s", decimals: 1)
                ParamSlider(title: L("Tonic extension: minimum", "强直伸展：最短时长"), value: $p.seizure.tonicMinDuration, range: 0.3...5, step: 0.1, unit: "s", decimals: 1)
            } header: { Text(L("Event detection", "事件检测")) }
            Section {
                Toggle(L("Score behavioral arrest (stage 1)", "评分行为停顿（1 级）"), isOn: $p.seizure.scoreArrest)
                if p.seizure.scoreArrest {
                    ParamSlider(title: L("Arrest: minimum duration", "停顿：最短时长"), value: $p.seizure.arrestMinDuration, range: 2...30, step: 1, unit: "s", decimals: 0)
                    ParamSlider(title: L("Arrest: movement below", "停顿：运动低于"), value: $p.seizure.arrestSpeed, range: 0.05...0.5, step: 0.01, unit: "BL/s")
                }
                ParamSlider(title: L("Episode gap", "发作合并间隔"), value: $p.seizure.episodeGap, range: 1...30, step: 1, unit: "s", decimals: 0,
                            help: L("Events closer than this form one seizure episode.", "间隔短于此的事件合并为一次发作。"))
            } header: { Text(L("Stage 1 & episodes", "1 级与发作合并")) } footer: {
                Text(L("From below, a sudden behavioral arrest looks like an ordinary pause; score it only if the baseline is active.",
                       "仰视下突然的行为停顿与普通停歇无法区分；仅在基线期动物很活跃时开启。"))
            }
        }
    }

    private var commonSection: some View {
        Section {
            DisclosureGroup(L("Untracked frames & pose cleaning (advanced)", "未识别帧与姿态预处理（高级）")) {
                ParamSlider(title: L("Keypoint confidence", "关键点置信度"), value: $p.common.keypointThreshold, range: 0.05...0.9, step: 0.01,
                            help: L("Keypoints below this are treated as missing.", "低于该值的关键点视为缺失。"))
                Toggle(L("Remove implausible jumps", "剔除不合理跳点"), isOn: $p.common.rejectJumps)
                if p.common.rejectJumps {
                    ParamSlider(title: L("Jump threshold", "跳点阈值"), value: $p.common.jumpThreshold, range: 0.2...1.5, step: 0.05, unit: L("body lengths", "体长"),
                                help: L("A keypoint farther than this from the median of its neighbouring frames (±0.1 s) is treated as a wrong detection and becomes a gap.",
                                        "关键点与其前后相邻帧（±0.1 秒）中位数的距离超过该值时，视为误识别并当作缺口。"))
                }
                ParamSlider(title: L("Fill gaps up to", "填补缺口上限"), value: $p.common.maxGap, range: 0...1, step: 0.05, unit: "s",
                            help: L("Longer gaps stay missing and are left out of every measure; they are never invented.",
                                    "更长的缺口保持缺失，不计入任何指标，不会凭空补出。"))
                Picker(L("Fill method", "填补方法"), selection: $p.common.gapFill) {
                    ForEach(GapFill.allCases) { Text($0.label.text).tag($0) }
                }
                Text(p.common.gapFill.help.text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ParamSlider(title: L("Position smoothing", "位置平滑"), value: $p.common.smoothing, range: 0...0.5, step: 0.01, unit: "s")
            }
        } footer: {
            Text(L("Defaults (linear fill, no jump removal) reproduce earlier versions. Changing them changes the results; use the same settings for every animal of a study.",
                   "默认设置（线性填补、不剔除跳点）与旧版本结果一致。修改会改变结果；同一研究中所有动物请使用相同设置。"))
        }
    }
}
