// RecordingsTable.swift — the native table of videos used by every video page (All Videos, Needs
// Review, Failed, a study): sortable columns, multi-selection mirrored to the app (menus, toolbar,
// inspector), double-click to open, and a context menu with every batch action (include, exclude
// with a reason, tasks, study, tracking, Finder, export, delete).
//
// Columns: Animal (with a lazy thumbnail), Study, Group · Timepoint, Trial, Video, Duration · FPS,
// Status, QC, Decision, Tasks — ten, the most a SwiftUI table builder takes on macOS 14.

import SwiftUI
import AppKit

@MainActor
struct RecordingsTable: View {
    let filter: RecordingFilter
    @Binding var selection: Set<UUID>
    private let externalSort: Binding<[KeyPathComparator<RecordingsRow>]>?

    @Environment(AppModel.self) private var app
    @State private var localSort: [KeyPathComparator<RecordingsRow>]
    @State private var excludeRequest: RecordingsExcludeRequest?
    @State private var pendingDelete: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var pendingRerun: Set<UUID> = []
    @State private var confirmRerun = false

    init(filter: RecordingFilter, selection: Binding<Set<UUID>>) {
        self.filter = filter
        self._selection = selection
        self.externalSort = nil
        self._localSort = State(initialValue: RecordingsQuery.defaultSort(filter))
    }

    /// Same table with the sort order owned by the caller (RecordingsPage uses it to find the next
    /// video in review mode).
    init(filter: RecordingFilter, selection: Binding<Set<UUID>>, sortOrder: Binding<[KeyPathComparator<RecordingsRow>]>) {
        self.filter = filter
        self._selection = selection
        self.externalSort = sortOrder
        self._localSort = State(initialValue: RecordingsQuery.defaultSort(filter))
    }

    private var isReview: Bool {
        if case .needsReview = filter { return true }
        return false
    }

    /// The study page embeds this table without a search field: a query typed on another page must
    /// not filter it invisibly.
    private var searchText: String {
        if case .study = filter { return "" }
        return app.search
    }

    var body: some View {
        let sort = externalSort ?? $localSort
        let store = app.store
        let batch = app.batch
        let rows = RecordingsQuery.rows(store, filter: filter, search: searchText).sorted(using: sort.wrappedValue)
        let order = rows.map(\.id)
        Table(rows, selection: $selection, sortOrder: sort) {
            TableColumn(L("Animal", "动物"), value: \RecordingsRow.animal) { row in
                HStack(spacing: 8) {
                    RecordingsThumbnail(recording: row.recording, store: store)
                    Text(row.animal).fontWeight(.medium).lineLimit(1)
                }
                .help(row.animal)
            }
            .width(min: 120, ideal: 180)

            TableColumn(L("Task", "任务"), value: \RecordingsRow.study) { row in
                Text(row.study.isEmpty ? "—" : row.study)
                    .foregroundStyle(row.study.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 120)

            TableColumn(L("Group · Timepoint", "组别 · 时间点"), value: \RecordingsRow.groupTimepoint) { row in
                Text(row.groupTimepoint.isEmpty ? "—" : row.groupTimepoint)
                    .foregroundStyle(row.groupTimepoint.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .help(row.groupTimepoint)
            }
            .width(min: 80, ideal: 140)

            TableColumn(L("Trial", "试次"), value: \RecordingsRow.trial) { row in
                Text("\(row.trial)").monospacedDigit()
            }
            .width(min: 36, ideal: 44, max: 70)

            TableColumn(L("Video", "视频"), value: \RecordingsRow.file) { row in
                Text(row.file)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.file)
            }
            .width(min: 80, ideal: 170)

            TableColumn(L("Duration · FPS", "时长 · 帧率"), value: \RecordingsRow.duration) { row in
                HStack(spacing: 4) {
                    Text(row.duration > 0 ? Fmt.clock(row.duration) : "—").monospacedDigit()
                    Text(Fmt.fps(row.fps)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .lineLimit(1)
            }
            .width(min: 80, ideal: 110)

            TableColumn(L("Status", "状态"), value: \RecordingsRow.statusRank) { row in
                RecordingsStatusCell(recording: row.recording, missing: row.missing, batch: batch)
            }
            .width(min: 90, ideal: 120)

            TableColumn(L("QC", "QC"), value: \RecordingsRow.coverage) { row in
                HStack(spacing: 6) {
                    QCBadge(report: row.recording.qc)
                    if row.coverage >= 0 {
                        Text(Fmt.percent(row.coverage)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .width(min: 90, ideal: 140)

            TableColumn(L("Decision", "决定"), value: \RecordingsRow.decisionRank) { row in
                RecordingsDecisionCell(recording: row.recording)
            }
            .width(min: 80, ideal: 140)

            TableColumn(L("Tasks", "任务"), value: \RecordingsRow.taskCount) { row in
                RecordingsTaskBadges(assays: row.assays, planned: row.planned)
            }
            .width(min: 60, ideal: 100)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(ids, order: order)
        } primaryAction: { ids in
            open(ids, order: order)
        }
        .overlay {
            if rows.isEmpty { emptyState.allowsHitTesting(false) }
        }
        .onChange(of: selection, initial: true) { _, new in
            app.selectedRecordings = new
        }
        .sheet(item: $excludeRequest) { req in
            RecordingsExcludeSheet(count: req.ids.count, initialReason: req.initialReason) { reason in
                RecordingsActions.exclude(req.ids, reason: reason, app: app)
                if isReview, let next = req.next { selection = [next] }
            }
        }
        .confirmationDialog(RecordingsActions.deleteTitle(pendingDelete.count), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button(L("Delete", "删除"), role: .destructive) {
                let ids = pendingDelete
                selection.subtract(ids)
                RecordingsActions.delete(ids, app: app)
                pendingDelete = []
            }
            Button(L("Cancel", "取消"), role: .cancel) { pendingDelete = [] }
        } message: {
            Text(RecordingsActions.deleteMessage(pendingDelete, store: app.store))
        }
        .confirmationDialog(pendingRerun.count == 1 ? L("Re-run tracking for this video?", "重新识别该视频？")
                            : String(format: L("Re-run tracking for %d videos?", "重新识别 %d 段视频？"), pendingRerun.count),
                            isPresented: $confirmRerun, titleVisibility: .visible) {
            ForEach(PoseModelID.choices) { m in
                Button(String(format: L("Re-run with %@", "使用%@重新识别"), m.shortTitle.text)) {
                    app.rerunTracking(pendingRerun, model: m)
                    app.toast = String(format: L("%d video(s) queued for tracking (%@)", "%d 段视频已加入识别队列（%@）"), pendingRerun.count, m.shortTitle.text)
                    pendingRerun = []
                }
            }
            Button(L("Cancel", "取消"), role: .cancel) { pendingRerun = [] }
        } message: {
            Text(L("The pose model runs again on the whole video; the QC report is recomputed and every analysis of the video waits for the new pose. Decisions, tasks and parameters are kept.",
                   "将对整段视频重新运行姿态模型；QC 报告会重新计算，该视频的所有分析会等待新的姿态数据。纳入决定、任务和参数保持不变。"))
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private func menu(_ ids: Set<UUID>, order: [UUID]) -> some View {
        if ids.isEmpty {
            Button(L("Import Videos…", "导入视频…")) { app.chooseFilesToImport() }
        } else {
            let recs = ids.compactMap { app.store.recording($0) }
            let failed = Set(recs.filter { $0.status == .failed }.map(\.id))
            let rerunnable = Set(recs.filter { $0.status == .ready || $0.status == .failed }.map(\.id))
            Group {
                Button(ids.count == 1 ? L("Open", "打开") : String(format: L("Open First of %d", "打开 %d 项中的第一项"), ids.count)) {
                    open(ids, order: order)
                }
                Divider()
                Button(L("Include", "纳入")) { include(ids, order: order) }
                    .disabled(!recs.contains { $0.isProcessed && $0.decision != .included })
                Button(L("Exclude…", "排除…")) { beginExclude(ids, order: order) }
                Button(L("Back to Needs Review", "退回待复核")) { RecordingsActions.backToReview(ids, app: app) }
                    .disabled(!recs.contains { $0.decision != .pending })
                Divider()
                Button(L("Move to Task…", "移到任务…")) { app.assignRequest = AssignRequest(recordings: ids) }
                moveMenu(ids)
            }
            Divider()
            Group {
                Button(L("Re-run Tracking…", "重新识别…")) {
                    pendingRerun = rerunnable
                    confirmRerun = true
                }
                .disabled(rerunnable.isEmpty)
                Button(L("Retry", "重试")) { app.retry(failed) }
                    .disabled(failed.isEmpty)
                Button(L("Locate Video…", "定位视频…")) {
                    if let id = ids.first { app.locateVideo(id) }
                }
                .disabled(ids.count != 1)
                Button(L("Show in Finder", "在访达中显示")) { RecordingsActions.showInFinder(ids, app: app) }
            }
            Divider()
            Group {
                Button(L("Export…", "导出…")) { app.export(.selection(analyses: [], recordings: ids)) }
                Divider()
                Button(L("Delete…", "删除…"), role: .destructive) {
                    pendingDelete = ids
                    confirmDelete = true
                }
            }
        }
    }

    @ViewBuilder
    private func moveMenu(_ ids: Set<UUID>) -> some View {
        let store = app.store
        let inTask = ids.contains { store.recording($0)?.experimentID != nil }
        let blinded = ids.contains { id in store.recording(id).flatMap { store.experiment(for: $0) }?.blinded == true }
        Button(L("Remove from Task", "移出任务")) {
            let m = store.removeFromTask(ids, task: nil)
            app.notify(m.ids.count == 1 ? L("Removed from its task; the video is under “Not in a task”", "已移出任务；视频位于“未归入任务”")
                       : String(format: L("%d videos removed from their task; they are under “Not in a task”", "已将 %d 段视频移出任务；位于“未归入任务”"), m.ids.count),
                       action: ToastAction(title: L("Undo", "撤销")) { [weak app] in
                           guard let app else { return }
                           Task { @MainActor in await app.store.undoMove(m) }
                       })
        }
        .disabled(!inTask || blinded)
        .help(blinded ? L("Unblind the task first: a video outside it would show its animal and group.", "请先揭盲：移出任务的视频会显示其动物和组别。") : "")
    }

    // MARK: Actions

    private func open(_ ids: Set<UUID>, order: [UUID]) {
        guard let id = order.first(where: { ids.contains($0) }) ?? ids.first else { return }
        app.open(.recording(id))
    }

    private func include(_ ids: Set<UUID>, order: [UUID]) {
        let next = RecordingsActions.next(after: ids, in: order)
        if RecordingsActions.include(ids, app: app) > 0, isReview, let next { selection = [next] }
    }

    private func beginExclude(_ ids: Set<UUID>, order: [UUID]) {
        let reasons = Set(ids.compactMap { app.store.recording($0)?.exclusionReason })
        let initial = reasons.count == 1 ? (reasons.first ?? "") : ""
        excludeRequest = RecordingsExcludeRequest(ids: ids, initialReason: initial,
                                                  next: RecordingsActions.next(after: ids, in: order))
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyState: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            EmptyState(title: L("No matching videos", "没有匹配的视频"),
                       message: String(format: L("No video matches “%@”. Search looks at the animal, file name, task, group and timepoint.",
                                                 "没有视频匹配“%@”。搜索范围：动物、文件名、任务、组别和时间点。"), query),
                       symbol: "magnifyingglass")
        } else {
            switch filter {
            case .all:
                EmptyState(title: L("No videos yet", "还没有视频"),
                           message: L("Import videos (⌘O) or drop them on the window. Each video is tracked once by the pose model, checked (QC), included or excluded, and then analysed by any number of tasks.",
                                      "导入视频（⌘O）或直接拖入窗口。每段视频由姿态模型识别一次，经过质控（QC）、纳入或排除后，可由多个任务分析。"))
            case .needsReview:
                EmptyState(title: L("Nothing to review", "没有待复核的视频"),
                           message: L("Videos that pass QC are included automatically. Videos with a QC warning or failure wait here for your decision.",
                                      "通过 QC 的视频会自动纳入；有 QC 警告或未通过的视频会在这里等待你的决定。"),
                           symbol: "checkmark.seal")
            case .failed:
                EmptyState(title: L("No failed videos", "没有失败的视频"),
                           message: L("Videos whose tracking failed are listed here with the reason, to retry or locate them.",
                                      "识别失败的视频会连同原因列在这里，可重试或重新定位文件。"),
                           symbol: "checkmark.circle")
            case .queue:
                EmptyState(title: L("The queue is empty", "队列为空"),
                           message: L("Imported videos wait here until the pose model has tracked them.",
                                      "导入的视频会在这里等待姿态模型识别。"),
                           symbol: "tray")
            case .study:
                EmptyState(title: L("No videos in this task", "该任务还没有视频"),
                           message: L("Add videos to the task from its page.", "请在任务页面中添加视频。"),
                           symbol: "film.stack")
            case .unassigned:
                EmptyState(title: L("Every video is in a task", "所有视频都已归入任务"),
                           message: L("Videos imported without a task, or removed from one, are listed here to be moved into a task.",
                                      "未归入任务或被移出任务的视频会列在这里，可移到某个任务中。"),
                           symbol: "film.stack")
            }
        }
    }
}
