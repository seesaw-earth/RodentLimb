// TaskDesignView.swift — Design of a task: name and note, groups, animals, timepoints, QC criteria,
// parameters (with protocol presets), calibration, blinding, and deleting the task. Text fields save
// on Return, when they lose focus and when the screen closes.

import SwiftUI

/// Sheets of the task screen (presented by TaskView, one presenter for all of them).
enum TaskSheet: Identifiable {
    case design, newAnimal, animal(UUID), randomize, params(UUID), calibration(UUID), group(String?)
    var id: String {
        switch self {
        case .design: return "design"
        case .newAnimal: return "newAnimal"
        case .animal(let a): return "animal-" + a.uuidString
        case .randomize: return "randomize"
        case .params(let s): return "params-" + s.uuidString
        case .calibration(let s): return "calibration-" + s.uuidString
        case .group(let g): return "group-" + (g ?? "")
        }
    }
}

@MainActor
struct TaskDesignSections: View {
    let task: TaskRef
    @Binding var sheet: TaskSheet?
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @Environment(\.dismiss) private var dismiss
    @State private var showAllAnimals = false
    @State private var confirmUnblind = false
    @State private var confirmDelete = false
    @State private var removingGroup: String?

    var body: some View {
        if let e = store.experiment(task.experimentID) {
            taskSection(e)
            groupsSection(e)
            animalsSection(e)
            timepointsSection(e)
            qcSection(e)
            analysisSection(e)
            blindingSection(e)
            deleteSection
        }
    }

    // MARK: Task

    private func taskSection(_ e: Experiment) -> some View {
        Section {
            CommitTextField(title: L("Task name", "任务名称"), value: e.name) { new in
                let n = new.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.editTask(e.id) { $0.name = n } }
            }
            HStack {
                Text(L("Paradigm", "范式"))
                Spacer()
                Text(task.assay.name.text).foregroundStyle(.secondary)
            }
            CommitTextField(title: L("Note: aim, treatment, protocol…", "备注：目的、处理、实验方案…"), value: e.notes, axis: .vertical) { new in
                store.editTask(e.id) { $0.notes = new }
            }
        } header: {
            Text(L("Task", "任务"))
        }
    }

    // MARK: Groups

    @ViewBuilder
    private func groupsSection(_ e: Experiment) -> some View {
        let sizes = Dictionary(store.groupSizes(e).map { ($0.group, $0.total) }, uniquingKeysWith: { a, _ in a })
        Section {
            if e.factors.count <= 1 {
                let levels = e.factors.first?.levels ?? []
                if levels.isEmpty {
                    Text(L("Single group: every animal is compared together.", "单组：所有动物一起比较。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(levels.enumerated()), id: \.element) { i, g in
                    Button { if !e.blinded { sheet = .group(g) } } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Palette.group(i)).frame(width: 10, height: 10)
                            Text(e.blinded ? String(format: L("Group %d", "第 %d 组"), i + 1) : g).foregroundStyle(.primary)
                            Spacer()
                            if !e.blinded {
                                Text(String(format: L("%d animals", "%d 只"), sizes[g] ?? 0)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if !e.blinded {
                            Button(L("Remove", "移除"), role: .destructive) { removingGroup = g }
                        }
                    }
                }
                if !e.blinded {
                    Button(L("Add group", "添加分组")) { sheet = .group(nil) }
                        // Presented from this one row (a modifier on the Section would repeat per row).
                        .confirmationDialog(L("Remove this group?", "移除该分组？"),
                                            isPresented: Binding(get: { removingGroup != nil }, set: { if !$0 { removingGroup = nil } }),
                                            titleVisibility: .visible, presenting: removingGroup) { g in
                            Button(L("Remove group", "移除分组"), role: .destructive) { store.removeGroup(g, from: e.id) }
                        } message: { _ in
                            Text(L("Its animals and their sessions stay in the task, as not allocated.", "该组的动物及其实验仍保留在任务中，变为未分组。"))
                        }
                }
            } else {
                Text(e.blinded ? L("Groups are hidden while the task is blinded.", "盲法期间隐藏分组。")
                     : e.activeFactors.map { "\($0.name): \($0.levels.joined(separator: ", "))" }.joined(separator: "\n"))
                    .font(.subheadline)
                Button(L("Edit design…", "编辑设计…")) { sheet = .design }
            }
        } header: {
            Text(L("Groups", "分组"))
        } footer: {
            if e.factors.count > 1 {
                Text(L("This study from an earlier version has several factors; every combination is a group.", "该研究来自早期版本，有多个因素；每种组合为一个组。"))
            }
        }
    }

    // MARK: Animals

    @ViewBuilder
    private func animalsSection(_ e: Experiment) -> some View {
        let shown = showAllAnimals ? e.animals : Array(e.animals.prefix(10))
        Section {
            if e.animals.isEmpty {
                Text(L("Animals are added automatically from the animal IDs of the videos, or here.", "动物会根据视频的动物编号自动添加，也可在此添加。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(shown) { a in
                Button { sheet = .animal(a.id) } label: {
                    HStack(spacing: 10) {
                        Text(e.displayCode(a)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .frame(minWidth: 56, alignment: .leading)
                        Text(a.sex.short).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 22)
                        if !e.blinded {
                            Text(e.groupLabel(a).isEmpty && !e.cells.isEmpty ? L("not allocated", "未分组") : e.groupLabel(a))
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if !a.cohort.isEmpty { Tag(text: a.cohort) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if e.animals.count > 10 {
                Button(showAllAnimals ? L("Show fewer", "收起") : String(format: L("Show all %d", "显示全部 %d 只"), e.animals.count)) {
                    withAnimation(Motion.snappy) { showAllAnimals.toggle() }
                }
            }
            Button(L("Add animal", "添加动物")) { sheet = .newAnimal }
            if !e.cells.isEmpty && !e.animals.isEmpty {
                Button(L("Randomise allocation…", "随机分组…")) { sheet = .randomize }
            }
        } header: {
            HStack {
                Text(L("Animals", "动物"))
                Spacer()
                Text("\(e.animals.count)").monospacedDigit()
            }
        } footer: {
            if !e.randomization.isEmpty { Text(e.randomization) }
        }
    }

    // MARK: Timepoints

    private func timepointsSection(_ e: Experiment) -> some View {
        Section {
            CommitTextField(title: L("e.g. Baseline, Day 7, Day 28", "如 Baseline, Day 7, Day 28"),
                            value: e.timepoints.joined(separator: ", ")) { new in
                let list = SessionStore.unique(new.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" }).map(String.init))
                store.editTask(e.id) { $0.timepoints = list }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
            Text(L("Timepoints", "时间点"))
        } footer: {
            Text(L("Optional, comma-separated, in order. Each video is assigned to one when it is added.", "可选，按顺序用逗号分隔。添加视频时为每段视频选择一个。"))
        }
    }

    // MARK: QC

    private func qcSection(_ e: Experiment) -> some View {
        Section {
            InfoRow(key: L("Included automatically when mouse tracked", "自动纳入：小鼠可用帧"), value: String(format: "≥ %.0f%%", e.qc.passCoverage * 100))
            InfoRow(key: L("Fails when mouse tracked", "不通过：小鼠可用帧"), value: String(format: "< %.0f%%", e.qc.failCoverage * 100))
            InfoRow(key: L("Longest loss allowed", "允许的最长丢失"), value: String(format: L("%.0f s", "%.0f 秒"), e.qc.maxLostSeconds))
            InfoRow(key: L("Minimum frame rate", "最低帧率"), value: String(format: "%.0f fps", e.qc.minFPS))
            Button(L("Edit criteria…", "编辑标准…")) { sheet = .design }
        } header: {
            Text(L("Inclusion criteria", "纳入标准"))
        } footer: {
            Text(L("Set before scoring. Sessions meeting every criterion are included automatically; the others wait in Needs review.",
                   "请在评分前设定。满足全部标准的实验自动纳入，其余进入“待审核”。"))
        }
    }

    // MARK: Parameters and calibration

    @ViewBuilder
    private func analysisSection(_ e: Experiment) -> some View {
        let list = store.sessions(in: task)
        let reference = list.first { store.results[$0.id] != nil } ?? list.first { $0.hasPose } ?? list.first
        Section {
            if let s = reference {
                HStack {
                    Text(L("Protocol", "实验方案"))
                    Spacer()
                    Text(ParameterPresets.current(s.params, assay: task.assay)?.title.text ?? L("Custom", "自定义"))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Button(L("Edit parameters…", "编辑参数…")) { sheet = .params(s.id) }
                if TaskCatalog.needsCalibration(task.assay) {
                    let cal = list.first { $0.hasPose } ?? s
                    Button(L("Calibrate…", "标定…")) { sheet = .calibration(cal.id) }
                }
            } else {
                Text(L("Parameters and calibration can be set once the first video is added.", "添加第一段视频后即可设置参数和标定。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Analysis", "分析"))
        } footer: {
            Text(L("Every session of a task should use the same parameters. New sessions start from those of this task; nothing is copied from other tasks.",
                   "同一任务的所有实验应使用相同参数。新实验沿用本任务的参数，不会从其他任务复制。"))
        }
    }

    // MARK: Blinding

    private func blindingSection(_ e: Experiment) -> some View {
        Section {
            Toggle(L("Blind the scoring", "评分时设盲"), isOn: Binding(get: { e.blinded }, set: { on in
                if on { store.editTask(e.id) { $0.blinded = true } } else { confirmUnblind = true }
            }))
            .confirmationDialog(L("Reveal group allocation?", "揭盲，显示分组？"), isPresented: $confirmUnblind, titleVisibility: .visible) {
                Button(L("Unblind", "揭盲")) { store.editTask(e.id) { $0.blinded = false } }
            } message: {
                Text(L("Unblind only after every session has been scored and every inclusion decision made.", "请在所有实验评分完成、纳入决定都做出后再揭盲。"))
            }
        } footer: {
            Text(L("While blinded, groups and group results are hidden and animals are shown by random codes, so sessions are reviewed and included or excluded without knowing the group.",
                   "设盲期间隐藏分组和组结果，动物以随机编码显示，从而在不知道分组的情况下复核、纳入或排除实验。"))
        }
    }

    // MARK: Delete

    private var deleteSection: some View {
        Section {
            Button(L("Delete task…", "删除任务…"), role: .destructive) { confirmDelete = true }
                .confirmationDialog(L("Delete this task?", "删除该任务？"), isPresented: $confirmDelete, titleVisibility: .visible) {
                    if store.deletionPlan(task).wholeStudy {
                        Button(L("Delete task, keep its videos", "删除任务，保留视频")) { app.deleteTask(task, keepVideos: true); dismiss() }
                        Button(L("Delete task and its videos", "删除任务及其视频"), role: .destructive) { app.deleteTask(task, keepVideos: false); dismiss() }
                    } else {
                        Button(L("Remove this paradigm's sessions", "移除该范式的实验"), role: .destructive) { app.deleteTask(task, keepVideos: true); dismiss() }
                    }
                } message: {
                    Text(TaskDeleteText.message(store.deletionPlan(task)))
                }
        } footer: {
            Text(L("Deleted tasks stay in Recently Deleted for 30 days.", "删除的任务会在“最近删除”中保留 30 天。"))
        }
    }
}

// MARK: - Group name

@MainActor
struct GroupNameSheet: View {
    let experimentID: UUID
    let old: String?
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Group name", "分组名称"), text: $name)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { save() }
            }
            .navigationTitle(old == nil ? L("New group", "新分组") : L("Rename group", "重命名分组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "保存")) { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = old ?? ""; focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let old { store.renameGroup(old, to: n, in: experimentID) } else { store.addGroup(n, to: experimentID) }
        dismiss()
    }
}

/// Loads the pose track (for the auto-fit) before showing the calibration of a session.
@MainActor
struct CalibrationLoader: View {
    let sessionID: UUID
    @EnvironmentObject private var store: SessionStore
    @State private var track: PoseTrack?
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                CalibrationView(sessionID: sessionID, track: track)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            track = await store.pose(sessionID)
            ready = true
        }
    }
}
