// ParamsSheet.swift — live parameter editing. Results recompute as sliders move (no model
// re-run), with the key metrics pinned at the top so the effect is visible immediately.

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
                if let s = session {
                    switch s.assay {
                    case .tailSuspension: tstSection
                    case .cylinder: cylinderSection
                    case .gait: gaitSection
                    }
                }
                commonSection
                Section {
                    Button(L("Reset to defaults", "恢复默认值")) {
                        var d = AssayParams.defaults(for: session?.assay ?? .tailSuspension)
                        d.cylinder.lesion = p.cylinder.lesion
                        d.cylinder.view = p.cylinder.view
                        p = d
                    }
                    Button(L("Apply to all sessions of this assay…", "应用到该范式的所有记录…")) { confirmApplyAll = true }
                } footer: {
                    Text(L("Use the same parameters for every animal in a study. Values are written to each session's methods export.",
                           "同一研究中所有动物应使用相同参数。参数值会写入每条记录导出的方法描述中。"))
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
            .confirmationDialog(L("Apply these parameters to every session of this assay?", "将这些参数应用到该范式的所有记录？"),
                                isPresented: $confirmApplyAll, titleVisibility: .visible) {
                Button(L("Apply to all", "全部应用")) { applyAll() }
            }
            .toast($toast)
        }
    }

    private func applyAll() {
        guard let s = session else { return }
        var n = 0
        for other in store.sessions where other.assay == s.assay && other.id != s.id {
            store.update(other.id) { o in
                let lesion = o.params.cylinder.lesion
                o.params = p
                o.params.cylinder.lesion = lesion   // lesion side is per animal
            }
            if other.hasPose { store.analyze(other.id) }
            n += 1
        }
        toast = String(format: L("Applied to %d sessions", "已应用到 %d 条记录"), n)
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

    private var commonSection: some View {
        Section {
            DisclosureGroup(L("Pose cleaning (advanced)", "姿态预处理（高级）")) {
                ParamSlider(title: L("Keypoint confidence", "关键点置信度"), value: $p.common.keypointThreshold, range: 0.05...0.9, step: 0.01,
                            help: L("Keypoints below this are treated as missing.", "低于该值的关键点视为缺失。"))
                ParamSlider(title: L("Fill gaps up to", "填补缺口上限"), value: $p.common.maxGap, range: 0...1, step: 0.05, unit: "s")
                ParamSlider(title: L("Position smoothing", "位置平滑"), value: $p.common.smoothing, range: 0...0.5, step: 0.01, unit: "s")
            }
        }
    }
}
