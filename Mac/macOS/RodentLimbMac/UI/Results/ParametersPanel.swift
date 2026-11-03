// ParametersPanel.swift — the parameters of one analysis, shown in the window's inspector
// (toolbar button or ⌃⌘I). Results recompute live while values change (no model re-run): edits
// are coalesced for a moment, written with `store.update`, and re-analysed with a 0.4-s debounce.
// "Reset to defaults" keeps the per-animal settings; "Apply to…" copies the parameters to every
// analysis of the same task in the study or the library (each video keeps its own injection time
// and injected paw), after a confirmation that says how many analyses will be re-analysed.

import SwiftUI

@MainActor
struct AnalysisParametersPanel: View {
    let id: UUID
    /// Latest result of the analysis (shown as the live result at the top).
    let result: AnalysisResult?

    @Environment(AppModel.self) private var app

    @State private var p = AssayParams()
    @State private var loadedFor: UUID?
    /// The parameters last written to the store (to tell our own writes from external changes).
    @State private var lastCommitted: AssayParams?
    @State private var commitTask: Task<Void, Never>?
    @State private var applyTarget: ParamsApplyTarget?
    @State private var confirmReset = false

    private var store: SessionStore { app.store }

    var body: some View {
        if let s = store.session(id) {
            form(s)
        } else {
            EmptyState(title: L("No analysis", "没有分析"), message: L("This analysis was deleted.", "该分析已删除。"), symbol: "slider.horizontal.3")
        }
    }

    private func form(_ s: Session) -> some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    AssayBadge(assay: s.assay, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Parameters", "参数")).font(.headline)
                        Text(s.assay.name.text).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if store.analysing.contains(id) {
                        ProgressView().controlSize(.small)
                            .help(L("Re-analysing…", "正在重新分析…"))
                    }
                }
                Text(L("Results update while you change a value; the pose model does not run again.",
                       "修改数值时结果会实时更新，无需重新运行姿态模型。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            presetsSection(s)
            liveSection
            AssayParameterSections(p: $p, assay: s.assay, videoDuration: s.duration)
            Section {
                Button(L("Reset to Defaults…", "恢复默认值…")) { confirmReset = true }
                applyMenu(s)
            } footer: {
                Text(L("Use the same parameters for every animal in a task. Values are written to each analysis' methods export.",
                       "同一任务中所有动物应使用相同参数。参数值会写入每个分析导出的方法描述中。"))
            }
        }
        .formStyle(.grouped)
        .onAppear { load(s) }
        .onChange(of: p) { _, new in schedule(new) }
        .onChange(of: s.params) { _, external in adopt(external) }
        .onDisappear {
            commitPending()
            loadedFor = nil
        }
        .confirmationDialog(L("Reset the parameters of this analysis to the defaults?", "将该分析的参数恢复为默认值？"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Reset", "恢复默认")) { reset(s) }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("The camera view, lesioned hemisphere, injection time and injected paw are kept.", "拍摄视角、损伤半球、注射时刻和注射爪会保留。"))
        }
        .confirmationDialog(applyTarget.map { String(format: L("Apply these parameters to %d analyses?", "将这些参数应用到 %d 个分析？"), $0.ids.count) } ?? "",
                            isPresented: Binding(get: { applyTarget != nil }, set: { if !$0 { applyTarget = nil } }),
                            titleVisibility: .visible, presenting: applyTarget) { t in
            Button(String(format: L("Apply and Re-analyse %d", "应用并重新分析 %d 个"), t.ids.count)) { apply(t) }
            Button(L("Cancel", "取消"), role: .cancel) { applyTarget = nil }
        } message: { t in
            Text(String(format: L("%d analyses of %@ %@ will be re-analysed with the parameters of this analysis. Each video keeps its own injection time and injected paw; calibrations are not changed.",
                                  "%3$@中“%2$@”任务的 %1$d 个分析将使用本分析的参数重新分析。各视频保留自己的注射时刻和注射爪；标定不变。"),
                        t.ids.count, s.assay.name.text, t.scope))
        }
    }

    /// Published protocols as one click (Core/ParameterPresets.swift). Only the values a protocol
    /// defines change; the result updates live like any other edit.
    private func presetsSection(_ s: Session) -> some View {
        let presets = ParameterPresets.presets(for: s.assay)
        let current = ParameterPresets.current(p, assay: s.assay)
        return Section {
            Menu {
                ForEach(presets) { preset in
                    // A toggle in a menu shows the system's own check mark for the preset in use.
                    Toggle(preset.title.text, isOn: Binding(get: { preset.applied(to: p) == p },
                                                            set: { _ in p = preset.applied(to: p) }))
                }
            } label: {
                Text(current?.title.text ?? L("Custom values", "自定义参数"))
            }
            .help(L("Parameters used in published protocols", "已发表实验方案中使用的参数"))
            if let c = current {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.detail.text)
                    Text(L("Source: ", "来源：") + c.source).foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
        } header: {
            Text(L("Protocol", "实验方案"))
        } footer: {
            Text(L("A preset sets only what the protocol defines (window, phases, bins, bout and stride rules); camera view, lesion side, injection time and paw stay as they are. Use the same preset for every animal of a task (Apply to…).",
                   "预设只设置实验方案规定的内容（时间窗、分相、分箱、回合与步幅规则）；拍摄视角、损伤侧、注射时刻和注射爪保持不变。同一任务的所有动物应使用相同预设（应用到…）。"))
        }
    }

    @ViewBuilder
    private var liveSection: some View {
        let highlights = result?.metrics.filter { $0.highlight } ?? []
        if !highlights.isEmpty {
            Section {
                ForEach(highlights) { m in
                    LabeledContent(m.label.text) {
                        Text(m.formatted + (m.unit.isEmpty || m.value == nil ? "" : " " + m.unit))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(L("Live result", "实时结果"))
            }
        }
    }

    private func applyMenu(_ s: Session) -> some View {
        let t = targets(s)
        return Menu {
            if let study = t.study {
                Button(String(format: L("All Analyses of This Task in “%@” (%d)…", "任务“%@”中该任务的所有分析（%d 个）…"), study.name, study.ids.count)) {
                    applyTarget = ParamsApplyTarget(ids: study.ids, scope: String(format: L("in “%@”", "任务“%@”"), study.name))
                }
                .disabled(study.ids.isEmpty)
            }
            Button(String(format: L("All Analyses of This Task in the Library (%d)…", "资料库中该任务的所有分析（%d 个）…"), t.library.count)) {
                applyTarget = ParamsApplyTarget(ids: t.library, scope: L("in the library", "资料库"))
            }
            .disabled(t.library.isEmpty)
        } label: {
            Text(L("Apply to…", "应用到…"))
        }
        .disabled(t.library.isEmpty)
        .help(L("Use these parameters for other analyses of the same task", "将这些参数用于同一任务的其他分析"))
    }

    /// Other analyses of the same task: in the same study (when the video is in one) and in the library.
    private func targets(_ s: Session) -> (study: (name: String, ids: [UUID])?, library: [UUID]) {
        let same = store.sessions.filter { $0.assay == s.assay && $0.id != s.id }
        let library = same.map(\.id)
        guard let rid = s.recordingID, let sid = store.recording(rid)?.experimentID else { return (nil, library) }
        let inStudy = Set(store.recordings.filter { $0.experimentID == sid }.map(\.id))
        let ids = same.filter { o in o.recordingID.map { inStudy.contains($0) } ?? false }.map(\.id)
        let name = store.experiment(sid)?.name ?? L("this task", "本任务")
        return (study: (name: name, ids: ids), library: library)
    }

    // MARK: Editing

    private func load(_ s: Session) {
        guard loadedFor != id else { return }
        lastCommitted = s.params
        p = s.params
        loadedFor = id
    }

    /// Coalesces edits (a slider sends many values a second) before writing to the store.
    private func schedule(_ new: AssayParams) {
        guard loadedFor == id, new != lastCommitted else { return }
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            commit(new)
        }
    }

    private func commit(_ new: AssayParams) {
        commitTask = nil
        guard store.session(id) != nil else { return }
        lastCommitted = new
        store.update(id) { $0.params = new }
        store.analyze(id, debounce: 0.4)
    }

    /// Writes an edit that is still waiting (panel closing, or before applying to others).
    private func commitPending() {
        guard commitTask != nil, loadedFor == id else { return }
        commitTask?.cancel()
        commit(p)
    }

    /// Parameters changed elsewhere (applied from another analysis, calibration sheet).
    private func adopt(_ external: AssayParams) {
        guard loadedFor == id, commitTask == nil, external != lastCommitted, external != p else { return }
        lastCommitted = external
        p = external
    }

    private func reset(_ s: Session) {
        var d = AssayParams.defaults(for: s.assay)
        d.cylinder.lesion = p.cylinder.lesion
        d.cylinder.view = p.cylinder.view
        d.keepPerAnimal(from: p)
        p = d
    }

    private func apply(_ t: ParamsApplyTarget) {
        commitPending()
        applyTarget = nil
        guard !t.ids.isEmpty else { return }
        store.applySettings(from: id, to: t.ids, calibration: false)
        app.toast = String(format: L("Applied to %d analyses — re-analysing", "已应用到 %d 个分析，正在重新分析"), t.ids.count)
    }
}

/// Analyses that "Apply to…" will change.
private struct ParamsApplyTarget: Identifiable {
    let id = UUID()
    let ids: [UUID]
    /// "in “Study”" / "in the library", for the confirmation text.
    let scope: String
}
