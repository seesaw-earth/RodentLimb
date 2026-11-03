// TaskPage.swift — the page of one task (sidebar › Tasks), the hub of the app: a header (name,
// paradigm, counts by state, notes), the primary action Add Videos, and three tabs:
//   Sessions — every video of the task as a session (group, animal, timepoint, trial, state, key
//              measures); double-click opens it; include / exclude / re-analyse / delete from the menu.
//   Results  — group comparison (each animal a dot, group mean ± SEM, time course), completeness
//              of the design, exclusions with reasons.
//   Design   — groups and animals (randomise, blind), QC criteria, methods text, delete the task.
// Selecting a group in the sidebar shows the same page filtered to that group.

import SwiftUI

enum TaskTab: String, CaseIterable, Identifiable {
    case sessions, results, design
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: return L("Sessions", "会话")
        case .results: return L("Results", "结果")
        case .design: return L("Design", "设计")
        }
    }
}

struct TaskPage: View {
    let task: TaskRef
    /// The group selected in the sidebar (nil = all groups).
    let group: String?

    @Environment(AppModel.self) private var app

    var body: some View {
        if let e = app.store.experiment(task.experimentID), app.store.taskExists(task) {
            TaskPageContent(task: task, group: group, experiment: e)
                .id(task)
        } else {
            EmptyState(title: L("Task not found", "找不到该任务"),
                       message: L("This task was deleted or is not in the open library.", "该任务已被删除，或不在当前打开的资料库中。"),
                       symbol: "")
        }
    }
}

private enum TaskPageSheet: String, Identifiable {
    case design, randomise
    var id: String { rawValue }
}

private struct TaskPageContent: View {
    let task: TaskRef
    let group: String?
    let experiment: Experiment

    @Environment(AppModel.self) private var app
    @State private var tab: TaskTab = .sessions
    @State private var sheet: TaskPageSheet?
    @State private var confirmUnblind = false
    @State private var confirmDelete = false

    var body: some View {
        let e = experiment
        let counts = app.store.taskCounts(task, group: group)
        VStack(spacing: 0) {
            TaskHeader(task: task, group: group, experiment: e, counts: counts)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 10)
            HStack {
                Picker(L("View", "视图"), selection: $tab) {
                    ForEach(TaskTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
            Divider()
            switch tab {
            case .sessions:
                TaskSessionsView(task: task, group: group, experiment: e, empty: counts.sessions == 0)
            case .results:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        StudyCompareCard(experiment: e, assay: task.assay)
                        StudyCompletenessCard(experiment: e)
                        StudyExclusionsCard(experiment: e)
                    }
                    .padding(.vertical, 18)
                    .pageContent()
                }
                .background(Palette.canvas)
            case .design:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        StudyDesignSummaryCard(experiment: e) { sheet = .design }
                        StudyAnimalsCard(experiment: e) { sheet = .randomise }
                        StudyQCCriteriaCard(experiment: e)
                        StudyMethodsCard(experiment: e)
                        deleteRow(e)
                    }
                    .padding(.vertical, 18)
                    .pageContent()
                }
                .background(Palette.canvas)
            }
        }
        .toolbar { toolbar(e) }
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .design: StudyDesignEditorSheet(experimentID: e.id)
                case .randomise: StudyRandomiseSheet(experimentID: e.id)
                }
            }
            .environment(app)
        }
        .confirmationDialog(L("Reveal the group allocation?", "揭盲并显示分组？"), isPresented: $confirmUnblind,
                            titleVisibility: .visible) {
            Button(L("Unblind", "揭盲")) {
                app.store.updateExperiment(e.id) { $0.blinded = false }
                app.toast = L("Task unblinded", "已揭盲")
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(unblindMessage(counts))
        }
        .confirmationDialog(String(format: L("Delete “%@”?", "删除“%@”？"), app.store.taskTitle(task)), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            let plan = app.store.deletionPlan(task)
            if plan.wholeStudy {
                Button(L("Delete Task, Keep Its Videos", "删除任务，保留视频")) { deleteTask(keepVideos: true) }
                Button(String(format: L("Delete Task and Its %d Videos", "删除任务及其 %d 段视频"), plan.videos), role: .destructive) {
                    deleteTask(keepVideos: false)
                }
            } else {
                Button(String(format: L("Delete Task (%d Sessions)", "删除任务（%d 个会话）"), plan.sessions), role: .destructive) {
                    deleteTask(keepVideos: true)
                }
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(app.store.deletionPlan(task).wholeStudy
                 ? L("Everything goes to Recently Deleted (30 days) and can be restored. Kept videos stay in the library under “Not in a task”.",
                     "所有内容都会移到“最近删除”（保留 30 天），可以恢复。保留的视频仍在资料库中，位于“未归入任务”。")
                 : L("The videos also belong to other tasks of the same study and stay there; only this paradigm's sessions go to Recently Deleted.",
                     "这些视频也属于同一研究中的其他任务，会保留在那里；只有本范式的会话会移到“最近删除”。"))
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ e: Experiment) -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                Button(L("Edit Design…", "编辑设计…")) { sheet = .design }
                Button(L("Randomise Groups…", "随机分组…")) { sheet = .randomise }
                    .disabled(e.cells.isEmpty || e.animals.isEmpty)
                Button(e.blinded ? L("Unblind…", "揭盲…") : L("Blind the Scoring", "开始盲法评分")) { toggleBlinding(e) }
                Divider()
                Button(L("Copy Methods Text", "拷贝方法学描述")) {
                    StudyClipboard.copy(app.store.studyMethods(e))
                    app.toast = L("Methods text copied", "已拷贝方法学描述")
                }
                Divider()
                Button(L("Delete Task…", "删除任务…"), role: .destructive) { confirmDelete = true }
            } label: {
                Text(L("Task", "任务"))
            }
            .help(L("Design, randomisation, blinding, methods text, delete", "设计、随机分组、盲法、方法学描述、删除"))
        }
    }

    // MARK: Parts

    private func deleteRow(_ e: Experiment) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Delete this task", "删除该任务")).font(.callout.weight(.semibold))
                Text(L("You can keep its videos (they stay in the library under “Not in a task”) or delete them too. Both can be undone from Recently Deleted.",
                       "可以保留其视频（仍在资料库中，位于“未归入任务”），也可以一并删除；两者都可以在“最近删除”中恢复。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(L("Delete Task…", "删除任务…"), role: .destructive) { confirmDelete = true }
        }
        .padding(.top, 6)
    }

    // MARK: Actions

    private func toggleBlinding(_ e: Experiment) {
        if e.blinded {
            confirmUnblind = true
        } else {
            app.store.updateExperiment(e.id) { $0.blinded = true }
            app.toast = L("Blinded: groups hidden, animals shown by code", "已设盲：隐藏组别，动物以编码显示")
        }
    }

    private func unblindMessage(_ c: TaskCounts) -> String {
        var text = L("Unblind only after every video has been scored and every inclusion decision made.",
                     "请在所有视频评分完成、纳入决定都做出后再揭盲。")
        if c.review > 0 {
            text += "\n" + String(format: L("%d videos still need an inclusion decision.", "仍有 %d 段视频待决定是否纳入。"), c.review)
        }
        if c.tracking > 0 {
            text += "\n" + String(format: L("%d videos are not tracked yet.", "仍有 %d 段视频尚未识别。"), c.tracking)
        }
        return text
    }

    private func deleteTask(keepVideos: Bool) {
        let store = app.store
        let plan = store.deletionPlan(task)
        if plan.wholeStudy && !keepVideos {
            // Every video of the study is deleted: stop their tracking first.
            for r in store.recordings(in: task.experimentID) where app.batch.jobs[r.id] != nil { app.batch.cancel(r.id) }
        }
        app.selectedRecordings = []
        app.selectedAnalyses = []
        let title = store.taskTitle(task)
        let d = store.deleteTask(task, keepVideos: keepVideos)
        app.sidebar = nil
        app.selectDefaultPage()
        app.path = []
        let message = plan.wholeStudy
            ? String(format: keepVideos ? L("“%@” moved to Recently Deleted; videos kept", "“%@”已移到“最近删除”，视频已保留")
                                        : L("“%@” and its videos moved to Recently Deleted", "“%@”及其视频已移到“最近删除”"), title)
            : String(format: L("“%@” deleted; its sessions are in Recently Deleted", "已删除“%@”；其会话在“最近删除”中"), title)
        app.notify(message, action: ToastAction(title: L("Undo", "撤销")) { [weak app] in
            guard let app else { return }
            Task { @MainActor in
                await app.store.undoDeleteTask(d)
                app.batch.kick()
                app.toast = L("Task restored", "已恢复任务")
            }
        })
    }
}

// MARK: - Header

private struct TaskHeader: View {
    let task: TaskRef
    let group: String?
    let experiment: Experiment
    let counts: TaskCounts

    @Environment(AppModel.self) private var app

    var body: some View {
        let e = experiment
        // Title and notes on the left, the two actions on the right; on a narrow window the actions
        // move below the title (they never leave the window).
        AdaptiveColumns(side: .ideal, threshold: 640, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    StudyCommitField(value: e.name, prompt: L("Task name", "任务名称")) { text in
                        let t = StudyText.trimmed(text)
                        guard !t.isEmpty else { return false }
                        app.store.updateExperiment(e.id) { $0.name = t }
                        return true
                    }
                    .font(.title.weight(.bold))
                    .lineLimit(1)
                    .help(L("Click to rename the task", "点击可重命名任务"))
                    .layoutPriority(1)
                    if let group {
                        Text("›  " + group).font(.title2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    Text(task.assay.name.text)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Palette.assay(task.assay))
                    if e.blinded {
                        Text(L("Blinded", "盲法中"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .help(L("Groups are hidden and animals are shown by random codes.", "组别已隐藏，动物以随机编码显示。"))
                    }
                    Text(designLine(e)).font(.callout).foregroundStyle(.secondary)
                }
                StudyCommitField(value: e.notes,
                                 prompt: L("Aim, hypothesis, primary outcome… (click to add)", "目的、假设、主要结局指标…（点击添加）"),
                                 axis: .vertical) { text in
                    app.store.updateExperiment(e.id) { $0.notes = text }
                    return true
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                // Long notes stay within three lines here (they scroll while being edited), so the
                // sessions below keep their room.
                .lineLimit(1...3)
                countsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(L("Export…", "导出…")) { app.export(.task(task)) }
                    .controlSize(.large)
                    .disabled(counts.sessions == 0)
                    .help(L("Export this task: results, behaviour segments, QC, methods (⌘E)", "导出此任务：结果、行为片段、QC、方法（⌘E）"))
                Button {
                    app.chooseFilesToImport(task: task)
                } label: {
                    Text(L("Add Videos…", "添加视频…")).frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(L("Add videos to this task (⌘O). You can also drop them on the window.", "向此任务添加视频（⌘O），也可以直接拖入窗口。"))
            }
            .fixedSize()
        }
    }

    private var countsRow: some View {
        FlowLayout(spacing: 18, lineSpacing: 4) {
            count(counts.sessions, L("sessions", "个会话"), .primary)
            if counts.tracking > 0 { count(counts.tracking, L("tracking", "识别中"), .accentColor) }
            if counts.review > 0 { count(counts.review, L("need review", "待复核"), Palette.warning) }
            if counts.failed > 0 { count(counts.failed, L("failed", "失败"), Palette.danger) }
            if counts.excluded > 0 { count(counts.excluded, L("excluded", "已排除"), .secondary) }
            count(counts.done, L("analysed", "已分析"), Palette.success)
        }
        .padding(.top, 2)
    }

    private func count(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(n)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func designLine(_ e: Experiment) -> String {
        var parts: [String] = []
        let groups = app.store.taskGroups(task)
        if !e.blinded {
            parts.append(groups.isEmpty ? L("no groups", "未分组")
                         : String(format: L("%d groups", "%d 组"), groups.count))
        }
        parts.append(String(format: L("%d animals", "%d 只动物"), e.animals.count))
        if !e.timepoints.isEmpty { parts.append(e.timepoints.joined(separator: " → ")) }
        return parts.joined(separator: " · ")
    }
}
