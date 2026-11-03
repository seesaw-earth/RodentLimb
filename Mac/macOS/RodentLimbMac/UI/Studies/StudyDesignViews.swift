// StudyDesignViews.swift — the study's design: a summary card on the study page (factors × levels,
// number of groups, timepoints in order, planned tasks, blinding, randomisation record) and the
// editor sheet (name and aim, factors with levels and presets, ordered timepoints, blinding,
// planned tasks). As on the iPhone, groups are locked while the study is blinded; renaming a
// level unassigns animals that had the old name. Renaming a timepoint also renames it on the
// study's videos (Mac).

import SwiftUI

// MARK: - Summary card

struct StudyDesignSummaryCard: View {
    let experiment: Experiment
    let onEdit: () -> Void

    init(experiment: Experiment, onEdit: @escaping () -> Void) {
        self.experiment = experiment
        self.onEdit = onEdit
    }

    var body: some View {
        let e = experiment
        Card {
            CardHeader(title: L("Design", "实验设计"), symbol: "square.grid.3x3",
                       subtitle: L("The groups and the timepoints (repeated measurements of the same animals) of this task.",
                                   "本任务的组别与时间点（对同一批动物的重复测量）。")) {
                Button(L("Edit Design…", "编辑设计…"), action: onEdit)
                    .controlSize(.small)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    key(L("Design", "设计"))
                    Text(e.design.label)
                }
                if e.activeFactors.isEmpty {
                    GridRow {
                        key(L("Groups", "组别"))
                        Text(L("Single group — no between-subject factor", "单组——无组间因素")).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(e.activeFactors) { f in
                        GridRow {
                            key(f.name)
                            levels(f, blinded: e.blinded)
                        }
                    }
                    GridRow {
                        key(L("Groups", "组数"))
                        Text(StudyText.groupCount(e)).monospacedDigit()
                    }
                }
                GridRow {
                    key(L("Timepoints", "时间点"))
                    timepoints(e)
                }
                GridRow {
                    key(L("Blinding", "盲法"))
                    Text(e.blinded ? L("Blinded: groups hidden, animals shown by code", "盲法：隐藏组别，动物以编码显示")
                                    : L("Not blinded", "未设盲"))
                        .foregroundStyle(e.blinded ? Color.accentColor : Color.secondary)
                }
                if !e.randomization.isEmpty {
                    GridRow {
                        key(L("Randomisation", "随机分组"))
                        Text(e.randomization)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.callout)
        }
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    private func levels(_ f: DesignFactor, blinded: Bool) -> some View {
        if blinded {
            Text(L("Levels hidden while blinded", "盲法期间隐藏水平")).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(f.levels.enumerated()), id: \.offset) { item in
                    Tag(text: item.offset == 0 ? item.element + " " + L("(reference)", "（对照）") : item.element,
                        color: item.offset == 0 ? Color.secondary : Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func timepoints(_ e: Experiment) -> some View {
        if e.timepoints.isEmpty {
            Text(L("None — one recording session per animal", "无——每只动物一次记录")).foregroundStyle(.secondary)
        } else {
            Text(e.timepoints.joined(separator: " → "))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func tasks(_ e: Experiment) -> some View {
        if e.plannedAssays.isEmpty {
            Text(L("None planned (tasks can still be assigned to any video)", "未计划（仍可给任意视频分配任务）"))
                .foregroundStyle(.secondary)
        } else {
            Text(e.plannedAssays.map { $0.name.text }.joined(separator: ", "))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Editor sheet

struct StudyDesignEditorSheet: View {
    let experimentID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private struct FactorDraft: Identifiable {
        var id: UUID
        var name: String
        var levels: String
    }

    private struct TimepointDraft: Identifiable {
        var id = UUID()
        /// The stored name when the editor opened (nil for a new row): a changed name is a rename.
        var original: String?
        var name: String
    }

    @State private var name = ""
    @State private var notes = ""
    @State private var factors: [FactorDraft] = []
    @State private var timepoints: [TimepointDraft] = []
    @State private var blinded = false
    @State private var planned = Set<Assay>()
    @State private var loaded = false
    /// Blinded when the editor opened: the groups cannot be changed (that would silently drop
    /// allocations nobody can see) and unblinding goes through the page's confirmation.
    @State private var wasBlinded = false

    init(experimentID: UUID) { self.experimentID = experimentID }

    var body: some View {
        VStack(spacing: 0) {
            if app.store.experiment(experimentID) == nil {
                EmptyState(title: L("Task deleted", "该任务已删除"), message: L("This task no longer exists.", "该任务已不存在。"),
                           symbol: "trash")
            } else {
                Form {
                    studySection
                    factorsSection
                    timepointsSection
                    blindingSection
                }
                .formStyle(.grouped)
            }
            Divider()
            footer
        }
        .sheetFrame(minWidth: 480, idealWidth: 640, maxWidth: 820, minHeight: 360, idealHeight: 720, maxHeight: 960)
        .onAppear { load() }
    }

    // MARK: Sections

    private var studySection: some View {
        Section {
            TextField(L("Name", "名称"), text: $name, prompt: Text(L("Task name", "任务名称")))
            TextField(L("Aim", "目的"), text: $notes, prompt: Text(L("Aim, hypothesis, primary outcome…", "目的、假设、主要结局指标…")),
                      axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text(L("Task", "任务"))
        }
    }

    private var factorsSection: some View {
        Section {
            if wasBlinded {
                ForEach(factors) { f in
                    LabeledContent(f.name.isEmpty ? L("Factor", "因素") : f.name,
                                   value: L("Levels hidden while blinded", "盲法期间隐藏水平"))
                }
            } else {
                ForEach(factors) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField(L("Factor", "因素"), text: factorBinding(f.id, \.name), prompt: Text(L("e.g. Genotype", "如 Genotype")))
                            .labelsHidden()
                            .frame(width: 170)
                        TextField(L("Levels", "水平"), text: factorBinding(f.id, \.levels),
                                  prompt: Text(L("Levels, comma-separated (control first)", "水平，用逗号分隔（对照放第一个）")))
                            .labelsHidden()
                        Button(L("Remove", "移除")) {
                            factors.removeAll { $0.id == f.id }
                        }
                        .buttonStyle(.borderless)
                        .help(L("Remove this factor", "移除该因素"))
                    }
                }
                Menu {
                    ForEach(StudyPresets.factors) { p in
                        Button(p.title) { factors.append(FactorDraft(id: UUID(), name: p.name, levels: p.levels.joined(separator: ", "))) }
                            .disabled(factors.contains { StudyText.trimmed($0.name).caseInsensitiveCompare(p.name) == .orderedSame })
                    }
                    Divider()
                    Button(L("Empty Factor", "空白因素")) { factors.append(FactorDraft(id: UUID(), name: "", levels: "")) }
                } label: {
                    Text(L("Add Factor", "添加因素"))
                }
                .fixedSize()
            }
        } header: {
            Text(L("Groups (between-subject factors)", "组别（组间因素）"))
        } footer: {
            Text(wasBlinded
                 ? L("Groups are hidden and locked while the task is blinded.", "盲法期间组别被隐藏并锁定。")
                 : L("Every combination of levels is a group (e.g. 2 × 2 = 4 groups). Renaming a level unassigns animals that had the old name. Sex is recorded per animal and can be used to split comparisons.",
                     "各水平的每种组合即一个组（如 2 × 2 = 4 组）。重命名水平会使原水平下的动物变为未分组。性别按动物记录，可用于拆分比较。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timepointsSection: some View {
        Section {
            ForEach(Array(timepoints.enumerated()), id: \.element.id) { item in
                timepointRow(item.element, index: item.offset)
            }
            HStack(spacing: 10) {
                Button {
                    timepoints.append(TimepointDraft(original: nil, name: ""))
                } label: {
                    Text(L("Add Timepoint", "添加时间点"))
                }
                Menu {
                    ForEach(StudyPresets.timepoints) { p in
                        Button(p.title) { applyPreset(p) }
                    }
                } label: {
                    Text(L("Presets", "预设"))
                }
                .fixedSize()
                Spacer()
            }
        } header: {
            Text(L("Repeated measurements (within-subject), in order", "重复测量（组内），按顺序"))
        } footer: {
            Text(L("Each animal is recorded at every timepoint or condition. For crossover designs, counterbalance the order of conditions between animals. Renaming a timepoint also renames it on this task's videos; videos of a removed timepoint keep it as text.",
                   "每只动物在每个时间点或条件下各录一次。交叉设计中，请在动物间平衡条件顺序。重命名时间点会同时更新本任务视频上的时间点；被删除时间点的视频以文字形式保留原时间点。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timepointRow(_ t: TimepointDraft, index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            TextField(L("Timepoint", "时间点"), text: timepointBinding(t.id), prompt: Text(L("e.g. Day 7", "如 Day 7")))
                .labelsHidden()
            if let o = t.original, !o.isEmpty, StudyText.trimmed(t.name) != o {
                Text(String(format: L("was “%@”", "原为“%@”"), o))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button { move(t.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help(L("Move earlier", "上移"))
            Button { move(t.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(index >= timepoints.count - 1)
                .help(L("Move later", "下移"))
            Button(L("Remove", "移除")) {
                timepoints.removeAll { $0.id == t.id }
            }
            .buttonStyle(.borderless)
            .help(L("Remove this timepoint", "移除该时间点"))
        }
    }

    private var blindingSection: some View {
        Section {
            Toggle(L("Blind the scoring", "评分时设盲"), isOn: $blinded)
                .disabled(wasBlinded)
        } footer: {
            Text(wasBlinded
                 ? L("To unblind, use Unblind on the task page (it asks for confirmation).", "如需揭盲，请在任务页面点按“揭盲”（需确认）。")
                 : L("While blinded, group labels and group comparisons are hidden and animals are shown by random codes, so videos are reviewed, relabelled and included / excluded without knowing the group.",
                     "设盲期间隐藏组别和组间比较，动物以随机编码显示，从而在不知道分组的情况下复核视频、修改标签、决定纳入/排除。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tasksSection: some View {
        Section {
            ForEach(Assay.allCases) { a in
                Toggle(isOn: assayBinding(a)) {
                    HStack(spacing: 8) {
                        AssayBadge(assay: a, size: 20)
                        Text(a.name.text)
                    }
                }
            }
        } header: {
            Text(L("Tasks of this task", "本任务的任务"))
        } footer: {
            Text(L("Preselected when videos are imported into this task; assigned automatically once a video is included.",
                   "向本任务导入视频时默认选中；视频被纳入后自动分配。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if wasBlinded {
                Text(L("Groups are locked while the task is blinded.", "盲法期间组别已锁定。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Cancel", "取消")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(L("Save", "保存")) {
                save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(app.store.experiment(experimentID) == nil)
        }
        .padding(14)
    }

    // MARK: Bindings (looked up by id, so removing a row never leaves a dangling index)

    private func factorBinding(_ id: UUID, _ key: WritableKeyPath<FactorDraft, String>) -> Binding<String> {
        Binding(get: { factors.first { $0.id == id }?[keyPath: key] ?? "" },
                set: { v in
                    if let i = factors.firstIndex(where: { $0.id == id }) { factors[i][keyPath: key] = v }
                })
    }

    private func timepointBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { timepoints.first { $0.id == id }?.name ?? "" },
                set: { v in
                    if let i = timepoints.firstIndex(where: { $0.id == id }) { timepoints[i].name = v }
                })
    }

    private func assayBinding(_ a: Assay) -> Binding<Bool> {
        Binding(get: { planned.contains(a) },
                set: { on in
                    if on { planned.insert(a) } else { planned.remove(a) }
                })
    }

    // MARK: Editing

    private func move(_ id: UUID, by delta: Int) {
        guard let i = timepoints.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard timepoints.indices.contains(j) else { return }
        timepoints.swapAt(i, j)
    }

    /// Replaces the list. Names that already existed keep their videos; nothing is renamed.
    private func applyPreset(_ p: StudyTimepointPreset) {
        let existing = Set(timepoints.compactMap(\.original))
        timepoints = p.timepoints.map { TimepointDraft(original: existing.contains($0) ? $0 : nil, name: $0) }
    }

    private func load() {
        guard !loaded, let e = app.store.experiment(experimentID) else { return }
        loaded = true
        wasBlinded = e.blinded
        name = e.name
        notes = e.notes
        factors = e.factors.map { FactorDraft(id: $0.id, name: $0.name, levels: $0.levels.joined(separator: ", ")) }
        timepoints = e.timepoints.map { TimepointDraft(original: $0, name: $0) }
        blinded = e.blinded
        planned = Set(e.plannedAssays)
    }

    private func save() {
        let store = app.store
        guard let current = store.experiment(experimentID) else { return }
        let newFactors: [DesignFactor] = factors.compactMap { row in
            let n = StudyText.trimmed(row.name)
            let levels = StudyText.list(row.levels)
            guard !n.isEmpty || !levels.isEmpty else { return nil }
            return DesignFactor(id: row.id, name: n.isEmpty ? L("Factor", "因素") : n, levels: levels)
        }
        var seen = Set<String>()
        var tps: [String] = []
        var renames: [String: String] = [:]
        for t in timepoints {
            let n = StudyText.trimmed(t.name)
            guard !n.isEmpty, !seen.contains(n) else { continue }
            seen.insert(n)
            tps.append(n)
            if let o = t.original, !o.isEmpty, o != n { renames[o] = n }
        }
        let n = StudyText.trimmed(name)
        let note = notes
        let blind = blinded
        let tasks = Assay.allCases.filter { planned.contains($0) }
        let locked = wasBlinded || current.blinded
        store.updateExperiment(experimentID) { e in
            if !n.isEmpty { e.name = n }
            e.notes = note
            e.timepoints = tps
            e.plannedAssays = tasks
            // While blinded the groups and the blinding itself are left as they are.
            guard !locked else { return }
            e.factors = newFactors
            e.blinded = blind
            // Allocations to levels that no longer exist are dropped.
            let valid = Dictionary(newFactors.map { ($0.id.uuidString, Set($0.levels)) }, uniquingKeysWith: { first, _ in first })
            for i in e.animals.indices {
                e.animals[i].levels = e.animals[i].levels.filter { valid[$0.key]?.contains($0.value) == true }
            }
        }
        // Renamed timepoints: the study's videos follow (each video is updated once, from its old name).
        if !renames.isEmpty {
            for r in store.recordings(in: experimentID) {
                if let to = renames[r.timepoint] { store.updateRecording(r.id) { $0.timepoint = to } }
            }
        }
        app.toast = L("Design saved", "设计已保存")
    }
}
