// TasksView.swift — the Tasks tab: every task (name, paradigm, "12 sessions · 3 need review"), the
// lists of videos (needs review, not in a task, all videos), and New Task (choose the paradigm
// first, then name, groups and timepoints).

import SwiftUI

@MainActor
struct TasksView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @State private var pendingDelete: TaskRef?

    var body: some View {
        NavigationStack(path: $app.tasksPath) {
            let tasks = store.tasks
            let counts = store.taskCounts()
            let names = store.taskNames(tasks)
            let legacy = store.studiesWithoutTask
            List {
                if tasks.isEmpty && legacy.isEmpty {
                    Section { welcome }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                } else {
                    Section {
                        ForEach(tasks) { t in
                            NavigationLink(value: Route.task(t)) {
                                TaskRow(name: names[t] ?? t.assay.name.text, assay: t.assay, counts: counts[t] ?? TaskCounts(),
                                        blinded: store.experiment(t.experimentID)?.blinded == true)
                            }
                            .swipeActions {
                                // Opens a confirmation, so no destructive role (that would remove the row at once).
                                Button(L("Delete", "删除")) { pendingDelete = t }.tint(.red)
                            }
                        }
                        ForEach(legacy) { e in
                            LegacyStudyRow(experiment: e)
                        }
                    } header: {
                        Text(L("Tasks", "任务"))
                    }
                }
                listsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Tasks", "任务"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.showNewTask = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L("New Task", "新建任务"))
                }
            }
            .confirmationDialog(L("Delete this task?", "删除该任务？"),
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { t in
                if store.deletionPlan(t).wholeStudy {
                    Button(L("Delete task, keep its videos", "删除任务，保留视频")) { app.deleteTask(t, keepVideos: true); pendingDelete = nil }
                    Button(L("Delete task and its videos", "删除任务及其视频"), role: .destructive) { app.deleteTask(t, keepVideos: false); pendingDelete = nil }
                } else {
                    Button(L("Remove this paradigm's sessions", "移除该范式的实验"), role: .destructive) { app.deleteTask(t, keepVideos: true); pendingDelete = nil }
                }
            } message: { t in
                Text(TaskDeleteText.message(store.deletionPlan(t)))
            }
            .routeDestinations()
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Start with a task", "从任务开始"))
                .font(.title2.weight(.bold))
            Text(L("A task is one paradigm run as one experiment, for example \u{201C}Gait — SNI cohort 2\u{201D}. Choose the paradigm and the groups, then add the videos: each video becomes a session, is tracked once, checked for quality, and the groups are compared.",
                   "一个任务就是用一种范式完成的一次实验，例如“步态——SNI 第 2 批”。先选择范式和分组，再添加视频：每段视频成为一个实验记录，只识别一次并检查质量，最后按组比较。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { app.showNewTask = true } label: { Text(L("New Task", "新建任务")).frame(maxWidth: .infinity) }
                .primaryAction()
            Text(L("Everything stays on this device.", "所有数据都保存在本机。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var listsSection: some View {
        let review = store.recordings.reduce(0) { $0 + (store.needsReview($1) ? 1 : 0) }
        let unassigned = store.unassignedRecordings.count
        if !store.recordings.isEmpty {
            Section {
                if review > 0 {
                    NavigationLink(value: Route.needsReview) {
                        CountRow(title: L("Needs review", "待审核"), count: review, color: Palette.warning)
                    }
                }
                if unassigned > 0 {
                    NavigationLink(value: Route.unassigned) {
                        CountRow(title: L("Not in a task", "未归入任务"), count: unassigned)
                    }
                }
                NavigationLink(value: Route.allVideos) {
                    CountRow(title: L("All videos", "全部视频"), count: store.recordings.count)
                }
            } header: {
                Text(L("Videos", "视频"))
            }
        }
    }

}

/// Text of the task-delete confirmation: a task alone in its study deletes the study (keep or delete
/// its videos); a paradigm of an older multi-paradigm study only loses its sessions. Both can be
/// undone right after, also when the task had no session.
enum TaskDeleteText {
    static func message(_ plan: TaskDeletionPlan) -> String {
        if plan.wholeStudy {
            return String(format: L("The task and its %d videos go to Recently Deleted for 30 days (or the videos move to \u{201C}Not in a task\u{201D} if you keep them).",
                                    "任务及其 %d 段视频会移到“最近删除”，保留 30 天（若保留视频，视频会移到“未归入任务”）。"), plan.videos)
        }
        return String(format: L("This study from an earlier version has other paradigms. Only this paradigm's %d sessions go to Recently Deleted; the videos stay in the study's other tasks, or move to \u{201C}Not in a task\u{201D}.",
                                "该研究来自早期版本，还有其他范式。只有该范式的 %d 个实验会移到“最近删除”；视频保留在该研究的其他任务中，或移到“未归入任务”。"), plan.sessions)
    }
}

/// One task in the list: name, paradigm and state counts.
@MainActor
struct TaskRow: View {
    let name: String
    let assay: Assay
    let counts: TaskCounts
    var blinded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.body.weight(.semibold)).lineLimit(2)
            HStack(spacing: 8) {
                AssayChip(assay: assay)
                if blinded { Tag(text: L("Blinded", "盲法")) }
            }
            Text(counts.summary)
                .font(.footnote)
                .foregroundStyle(counts.needsReview > 0 || counts.failed > 0 ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(.secondary))
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A list entry with a count on the right.
struct CountRow: View {
    let title: String
    let count: Int
    var color: Color = .secondary

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(color)
        }
    }
}

/// A study from 1.0–1.3 without any paradigm: choose one to make it a task.
@MainActor
struct LegacyStudyRow: View {
    let experiment: Experiment
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(experiment.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(L("Study without a paradigm", "尚未选择范式的研究")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Menu(L("Choose paradigm", "选择范式")) {
                ForEach(TaskCatalog.sections) { section in
                    Section(section.title.text) {
                        ForEach(section.assays) { a in
                            Button(a.name.text) { store.setParadigm(a, for: experiment.id) }
                        }
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - New Task

@MainActor
struct NewTaskSheet: View {
    let created: (TaskRef) -> Void
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var assay: Assay?
    @State private var name = ""
    @State private var nameEdited = false
    @State private var groups: [GroupField] = [GroupField(), GroupField()]
    @State private var timepoints = ""
    @State private var notes = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, group(UUID), timepoints, notes }

    private struct GroupField: Identifiable {
        let id = UUID()
        var name = ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if let assay { details(assay) } else { paradigmList }
            }
            .navigationTitle(assay == nil ? L("Choose the paradigm", "选择范式") : L("New Task", "新建任务"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if assay == nil {
                        Button(L("Cancel", "取消")) { dismiss() }
                    } else {
                        Button(L("Back", "返回")) { withAnimation(Motion.snappy) { assay = nil } }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let assay {
                        Button(L("Create", "创建")) { create(assay) }.fontWeight(.semibold)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done", "完成")) { focus = nil }.fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(assay != nil)
    }

    // Step 1
    private var paradigmList: some View {
        List {
            ForEach(TaskCatalog.sections) { section in
                Section(section.title.text) {
                    ForEach(section.assays) { a in
                        Button {
                            withAnimation(Motion.snappy) { choose(a) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.name.text).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(TaskCatalog.blurb(a).text).font(.footnote).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // Step 2
    private func details(_ a: Assay) -> some View {
        Form {
            Section {
                HStack {
                    Text(L("Paradigm", "范式"))
                    Spacer()
                    Text(a.name.text).foregroundStyle(.secondary)
                }
                TextField(L("Task name", "任务名称"), text: $name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = groups.first.map { Field.group($0.id) } ?? Field.timepoints }
                    .onChange(of: name) { _, _ in if focus == .name { nameEdited = true } }
            } footer: {
                Text(L("For example the paradigm and the cohort: \u{201C}Gait — SNI cohort 2\u{201D}.", "例如范式加批次：“步态——SNI 第 2 批”。"))
            }
            Section {
                ForEach($groups) { $g in
                    let i = groups.firstIndex { $0.id == g.id } ?? 0
                    TextField(i == 0 ? L("Control", "对照组") : i == 1 ? L("Treatment", "处理组") : String(format: L("Group %d", "第 %d 组"), i + 1),
                              text: $g.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .group(g.id))
                        .submitLabel(.next)
                        .onSubmit { focus = i + 1 < groups.count ? .group(groups[i + 1].id) : .timepoints }
                }
                .onDelete { offsets in groups.remove(atOffsets: offsets) }
                Button(L("Add group", "添加分组")) {
                    let g = GroupField()
                    groups.append(g)
                    focus = .group(g.id)
                }
            } header: {
                Text(L("Groups", "分组"))
            } footer: {
                Text(L("Optional. Each animal belongs to one group; leave empty for a single group. Groups can be changed later.",
                       "可选。每只动物属于一个组；留空即为单组。之后可以修改。"))
            }
            Section {
                TextField(L("e.g. Baseline, Day 7, Day 28", "如 Baseline, Day 7, Day 28"), text: $timepoints)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .timepoints)
                    .submitLabel(.next)
                    .onSubmit { focus = .notes }
            } header: {
                Text(L("Timepoints", "时间点"))
            } footer: {
                Text(L("Optional, comma-separated, for animals recorded more than once.", "可选，用逗号分隔，用于同一动物多次录制。"))
            }
            Section {
                TextField(L("Aim, treatment, protocol…", "目的、处理、实验方案…"), text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focus, equals: .notes)
            } header: {
                Text(L("Note", "备注"))
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func choose(_ a: Assay) {
        assay = a
        if !nameEdited {
            let date = Date().formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(Locale(identifier: Lang.isChinese ? "zh-Hans" : "en")))
            name = a.name.text + " " + date
        }
    }

    private func create(_ a: Assay) {
        let tps = timepoints.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" }).map(String.init)
        let t = store.createTask(name: name, assay: a, groups: groups.map(\.name), timepoints: tps, notes: notes)
        UserDefaults.standard.set(a.rawValue, forKey: SettingsKey.lastAssay)
        dismiss()
        created(t)
    }
}
