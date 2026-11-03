// TaskSessions.swift — the Sessions tab of a task: one row per video of the task (its session of the
// task's paradigm), ordered by group, animal, timepoint and trial. The state column follows the
// video through tracking, QC, the inclusion decision and the analysis; the task's key measures
// follow. Double-click opens the session (or the video while it is not tracked yet). Every cell gets
// plain values: on macOS a table cell is not guaranteed to see the window's environment.

import SwiftUI

/// Where a session stands, for the state column (rank = sort order: problems first).
struct TaskSessionState: Equatable {
    var text: String
    var color: Color
    var rank: Int
    var detail: String = ""
    /// Being tracked now: the cell shows the live percentage.
    var tracking = false

    @MainActor
    static func of(_ s: Session, recording r: Recording?, store: SessionStore) -> TaskSessionState {
        guard let r else { return TaskSessionState(text: L("Video missing", "视频缺失"), color: Palette.danger, rank: 0) }
        switch r.status {
        case .failed:
            return TaskSessionState(text: L("Tracking failed", "识别失败"), color: Palette.danger, rank: 0, detail: r.failure ?? "")
        case .processing:
            return TaskSessionState(text: L("Tracking", "识别中"), color: .accentColor, rank: 3, tracking: true)
        case .queued:
            return TaskSessionState(text: L("Queued", "排队中"), color: .secondary, rank: 4)
        case .ready:
            switch r.decision {
            case .pending:
                if r.qc == nil { return TaskSessionState(text: L("Checking", "质控中"), color: .secondary, rank: 5) }
                return TaskSessionState(text: L("Needs review", "待复核"), color: Palette.warning, rank: 1,
                                        detail: L("QC flagged this video: check it and include or exclude it.", "质控标记了该视频：请检查后纳入或排除。"))
            case .excluded:
                return TaskSessionState(text: L("Excluded", "已排除"), color: .secondary, rank: 8, detail: r.exclusionReason)
            case .included:
                if store.analysing.contains(s.id) { return TaskSessionState(text: L("Analysing", "分析中"), color: .accentColor, rank: 3) }
                switch s.status {
                case .done: return TaskSessionState(text: L("Done", "已完成"), color: Palette.success, rank: 7)
                case .needsSetup:
                    return TaskSessionState(text: L("Needs calibration", "需要标定"), color: Palette.warning, rank: 2,
                                            detail: L("Open the session and calibrate it (once for the whole task if the camera did not move).",
                                                      "打开会话进行标定（相机位置不变时可一次用于整个任务）。"))
                case .failed: return TaskSessionState(text: L("Analysis failed", "分析失败"), color: Palette.danger, rank: 0, detail: s.failure ?? "")
                case .queued, .processing: return TaskSessionState(text: L("Analysing", "分析中"), color: .accentColor, rank: 3)
                }
            }
        }
    }
}

/// One row of the sessions table.
struct TaskSessionRow: Identifiable {
    let id: UUID
    let session: Session
    let recordingID: UUID?
    let hasPose: Bool
    let animal: String
    let group: String
    let groupRank: Int
    let timepoint: String
    let timepointRank: Int
    let trial: Int
    let state: TaskSessionState
    let stateRank: Int
    let m0: Double
    let m1: Double
    let m2: Double
    let values: [String]
    let updated: Date
    /// Sort key of the default order: group, animal, timepoint, trial.
    let order: Int
}

struct TaskSessionsView: View {
    let task: TaskRef
    let group: String?
    let experiment: Experiment
    let empty: Bool

    @Environment(AppModel.self) private var app
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\TaskSessionRow.order)]
    @State private var groupFilter = ""
    @State private var excludeRequest: RecordingsExcludeRequest?
    @State private var copyRequest: AnalysesCopyRequest?
    @State private var pendingDelete: Set<UUID> = []
    @State private var confirmDelete = false

    private static let missing = -Double.greatestFiniteMagnitude

    var body: some View {
        @Bindable var app = app
        let store = app.store
        let shownGroup = group ?? (groupFilter.isEmpty ? nil : groupFilter)
        let sessions = store.sessions(in: task, group: shownGroup)
        let keys = metricKeys(sessions)
        let rows = makeRows(sessions, keys: keys).sorted(using: sortOrder)
        let order = rows.map(\.id)
        VStack(spacing: 0) {
            if empty {
                emptyTask
            } else {
                filterBar(rows.count)
                Divider()
                table(rows, keys: keys, sessions: sessions, order: order)
            }
        }
        .searchable(text: $app.search, placement: .toolbar, prompt: L("Animal, group, timepoint, file", "动物、组别、时间点、文件"))
        .onChange(of: selection, initial: true) { _, new in app.selectedAnalyses = new }
        .onDisappear { app.selectedAnalyses = [] }
        .sheet(item: $excludeRequest) { req in
            RecordingsExcludeSheet(count: req.ids.count, initialReason: req.initialReason) { reason in
                RecordingsActions.exclude(req.ids, reason: reason, app: app)
            }
        }
        .sheet(item: $copyRequest) { req in AnalysesCopyParametersSheet(request: req).environment(app) }
        .confirmationDialog(pendingDelete.count == 1 ? L("Delete this video from the library?", "从资料库中删除该视频？")
                            : String(format: L("Delete %d videos from the library?", "从资料库中删除 %d 段视频？"), pendingDelete.count),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete", "删除"), role: .destructive) {
                let ids = pendingDelete
                selection = []
                RecordingsActions.delete(ids, app: app)
                pendingDelete = []
            }
            Button(L("Cancel", "取消"), role: .cancel) { pendingDelete = [] }
        } message: {
            Text(L("The records, their tracking, QC and analyses go to Recently Deleted (30 days). A referenced video file on your disk is never deleted.",
                   "记录及其识别结果、QC 和分析会移到“最近删除”（保留 30 天）。磁盘上被引用的视频文件不会被删除。"))
        }
    }

    // MARK: Filter bar

    private func filterBar(_ shown: Int) -> some View {
        let groups = app.store.taskGroups(task)
        let review = app.store.taskCounts(task).review
        return HStack(spacing: 12) {
            if group == nil && !groups.isEmpty {
                Picker(L("Group", "组别"), selection: $groupFilter) {
                    Text(L("All groups", "全部组别")).tag("")
                    ForEach(groups, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
            }
            Text(String(format: L("%d sessions", "%d 个会话"), shown))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if review > 0 {
                Text(String(format: L("%d need review", "%d 个待复核"), review))
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
                Button(L("Review", "复核")) { app.show(.review) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.inset)
    }

    // MARK: Table

    private func table(_ rows: [TaskSessionRow], keys: [String], sessions: [Session], order: [UUID]) -> some View {
        let showGroup = group == nil && !experiment.blinded
        return Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L("Group", "组别"), value: \TaskSessionRow.groupRank) { row in
                if showGroup {
                    Text(row.group.isEmpty ? "—" : row.group)
                        .foregroundStyle(row.group.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                } else {
                    Text(experiment.blinded ? L("Hidden", "已隐藏") : row.group).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .width(min: 60, ideal: 110)

            TableColumn(L("Animal", "动物"), value: \TaskSessionRow.animal) { row in
                Text(row.animal).fontWeight(.medium).lineLimit(1)
            }
            .width(min: 70, ideal: 120)

            TableColumn(L("Timepoint", "时间点"), value: \TaskSessionRow.timepointRank) { row in
                Text(row.timepoint.isEmpty ? "—" : row.timepoint)
                    .foregroundStyle(row.timepoint.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 100)

            TableColumn(L("Trial", "试次"), value: \TaskSessionRow.trial) { row in
                Text("\(row.trial)").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 34, ideal: 44, max: 60)

            TableColumn(L("State", "状态"), value: \TaskSessionRow.stateRank) { row in
                TaskStateCell(state: row.state, recordingID: row.recordingID, batch: app.batch)
            }
            .width(min: 90, ideal: 130)

            TableColumn(columnTitle(keys, 0, sessions), value: \TaskSessionRow.m0) { row in
                TaskValueCell(text: row.values.count > 0 ? row.values[0] : "")
            }
            .width(min: 60, ideal: 110)

            TableColumn(columnTitle(keys, 1, sessions), value: \TaskSessionRow.m1) { row in
                TaskValueCell(text: row.values.count > 1 ? row.values[1] : "")
            }
            .width(min: 60, ideal: 110)

            TableColumn(columnTitle(keys, 2, sessions), value: \TaskSessionRow.m2) { row in
                TaskValueCell(text: row.values.count > 2 ? row.values[2] : "")
            }
            .width(min: 60, ideal: 110)

            TableColumn(L("Updated", "更新于"), value: \TaskSessionRow.updated) { row in
                Text(Fmt.date(row.updated)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .width(min: 90, ideal: 130)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(ids, rows: rows, order: order)
        } primaryAction: { ids in
            open(ids, rows: rows, order: order)
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(title: L("No matching sessions", "没有匹配的会话"),
                           message: app.search.isEmpty ? L("No session in this group yet.", "该组还没有会话。")
                                                       : String(format: L("Nothing matches “%@”.", "没有内容匹配“%@”。"), app.search),
                           symbol: "")
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Empty task

    private var emptyTask: some View {
        VStack(spacing: 14) {
            Spacer()
            Text(L("No videos yet", "还没有视频")).font(.title2.weight(.semibold))
            Text(String(format: L("Add the videos of this %@ experiment. Each one becomes a session: it is tracked by the pose model, checked (QC), and analysed with the task's paradigm. Results appear by group.",
                                  "添加本次“%@”实验的视频。每段视频成为一个会话：由姿态模型识别、质控（QC），再按任务范式分析，结果按组显示。"),
                        task.assay.name.text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button {
                app.chooseFilesToImport(task: task)
            } label: {
                Text(L("Add Videos…", "添加视频…")).frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text(L("or drop videos and folders on the window", "或将视频和文件夹拖入窗口"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: Rows

    private func metricKeys(_ sessions: [Session]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for s in sessions {
            for m in s.summary where !seen.contains(m.key) {
                seen.insert(m.key)
                out.append(m.key)
                if out.count == 3 { return out }
            }
        }
        return out
    }

    private func columnTitle(_ keys: [String], _ i: Int, _ sessions: [Session]) -> String {
        guard i < keys.count else { return " " }
        let key = keys[i]
        for s in sessions {
            if let m = s.summary.first(where: { $0.key == key }) {
                return m.unit.isEmpty ? m.label.text : m.label.text + " (" + m.unit + ")"
            }
        }
        return key
    }

    private func makeRows(_ sessions: [Session], keys: [String]) -> [TaskSessionRow] {
        let store = app.store
        let groups = store.taskGroups(task)
        let timepoints = experiment.timepoints
        let query = app.search.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [TaskSessionRow] = []
        out.reserveCapacity(sessions.count)
        for (i, s) in sessions.enumerated() {
            let r = store.recording(for: s)
            let animal = r.map { RecordingsQuery.animalLabel($0, store: store) } ?? s.displayName
            let group = r.map { store.taskGroup($0) } ?? ""
            let timepoint = r?.timepoint ?? ""
            if !query.isEmpty {
                let file = r.map { store.fileLabel($0) } ?? s.originalName
                if ![animal, group, timepoint, file].contains(where: { $0.localizedCaseInsensitiveContains(query) }) { continue }
            }
            let state = TaskSessionState.of(s, recording: r, store: store)
            var numbers: [Double] = []
            var texts: [String] = []
            for k in 0..<3 {
                if k < keys.count, let m = s.summary.first(where: { $0.key == keys[k] }), let v = m.value, v.isFinite {
                    numbers.append(v)
                    texts.append(m.unit.isEmpty ? m.formatted : m.formatted + " " + m.unit)
                } else {
                    numbers.append(Self.missing)
                    texts.append(k < keys.count ? "—" : "")
                }
            }
            let gRank = group.isEmpty ? groups.count : (groups.firstIndex(of: group) ?? groups.count)
            let tRank = timepoints.firstIndex(of: timepoint) ?? timepoints.count
            out.append(TaskSessionRow(id: s.id, session: s, recordingID: r?.id, hasPose: s.hasPose,
                                      animal: animal, group: group, groupRank: gRank,
                                      timepoint: timepoint, timepointRank: tRank, trial: r?.trial ?? 1,
                                      state: state, stateRank: state.rank,
                                      m0: numbers[0], m1: numbers[1], m2: numbers[2], values: texts,
                                      updated: s.updatedAt, order: gRank * 1_000_000 + i))
        }
        return out
    }

    // MARK: Menu and actions

    private func recordingIDs(_ ids: Set<UUID>, rows: [TaskSessionRow]) -> Set<UUID> {
        Set(rows.filter { ids.contains($0.id) }.compactMap(\.recordingID))
    }

    @ViewBuilder
    private func menu(_ ids: Set<UUID>, rows: [TaskSessionRow], order: [UUID]) -> some View {
        if ids.isEmpty {
            Button(L("Add Videos…", "添加视频…")) { app.chooseFilesToImport(task: task) }
            Button(L("Export Task…", "导出任务…")) { app.export(.task(task)) }
        } else {
            let recs = recordingIDs(ids, rows: rows)
            Group {
                Button(ids.count == 1 ? L("Open", "打开") : String(format: L("Open First of %d", "打开 %d 项中的第一项"), ids.count)) {
                    open(ids, rows: rows, order: order)
                }
                if ids.count == 1, let rid = recs.first {
                    Button(L("Open Video & QC", "打开视频与 QC")) { app.open(.recording(rid)) }
                }
            }
            Divider()
            Group {
                Button(L("Include", "纳入")) { RecordingsActions.include(recs, app: app) }
                Button(L("Exclude…", "排除…")) {
                    let reasons = Set(recs.compactMap { app.store.recording($0)?.exclusionReason })
                    excludeRequest = RecordingsExcludeRequest(ids: recs, initialReason: reasons.count == 1 ? (reasons.first ?? "") : "")
                }
                Button(L("Back to Needs Review", "退回待复核")) { RecordingsActions.backToReview(recs, app: app) }
            }
            Divider()
            Group {
                Button(L("Re-analyse", "重新分析")) { reanalyse(ids) }
                Button(L("Copy Parameters to Selected…", "将参数复制到所选…")) {
                    let ordered = order.filter { ids.contains($0) }
                    copyRequest = AnalysesCopyRequest(ids: ordered, source: ordered.first)
                }
                .disabled(ids.count < 2)
            }
            Divider()
            Group {
                Button(L("Export Selected…", "导出所选…")) { app.export(.selection(analyses: ids, recordings: [])) }
                // While blinded, moving videos out would show their animal and group elsewhere.
                Button(L("Move to Another Task…", "移到其他任务…")) { app.assignRequest = AssignRequest(recordings: recs, source: task) }
                    .disabled(experiment.blinded)
                Button(L("Remove from Task", "移出任务")) { removeFromTask(recs) }
                    .disabled(experiment.blinded)
            }
            Divider()
            Button(L("Delete Videos…", "删除视频…"), role: .destructive) {
                pendingDelete = recs
                confirmDelete = true
            }
        }
    }

    private func open(_ ids: Set<UUID>, rows: [TaskSessionRow], order: [UUID]) {
        guard let id = order.first(where: { ids.contains($0) }) ?? ids.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        if row.hasPose || row.recordingID == nil {
            app.open(.analysis(id))
        } else if let rid = row.recordingID {
            app.open(.recording(rid))
        }
    }

    private func reanalyse(_ ids: Set<UUID>) {
        let ready = ids.filter { app.store.session($0)?.hasPose == true }
        guard !ready.isEmpty else {
            app.toast = L("These sessions wait for their video's tracking", "这些会话正在等待视频识别")
            return
        }
        app.store.analyze(Array(ready))
        app.toast = String(format: L("Re-analysing %d session(s)", "正在重新分析 %d 个会话"), ready.count)
    }

    private func removeFromTask(_ recs: Set<UUID>) {
        guard !recs.isEmpty else { return }
        let store = app.store
        let t = task
        selection = []
        let m = store.removeFromTask(recs, task: t)
        let message: String
        if m.left.count == m.ids.count {
            message = m.ids.count == 1 ? L("Removed from the task; the video is under “Not in a task”", "已移出任务；视频位于“未归入任务”")
                : String(format: L("%d videos removed from the task; they are under “Not in a task”", "已将 %d 段视频移出任务；位于“未归入任务”"), m.ids.count)
        } else {
            message = String(format: L("%d video(s) removed from the task; videos with sessions in other tasks stay there", "已将 %d 段视频移出任务；在其他任务中有会话的视频仍留在那里"), m.ids.count)
        }
        app.notify(message, action: ToastAction(title: L("Undo", "撤销")) { [weak app] in
            guard let app else { return }
            Task { @MainActor in
                await app.store.undoMove(m)
                app.toast = L("Back in the task", "已放回任务")
            }
        })
    }
}

// MARK: - Cells

/// The state of a session; while its video is tracked, the live percentage (only this cell follows
/// the batch progress, not the whole table).
private struct TaskStateCell: View {
    let state: TaskSessionState
    let recordingID: UUID?
    let batch: BatchEngine

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text(text).lineLimit(1).monospacedDigit()
        }
        .help(state.detail.isEmpty ? state.text : state.detail)
    }

    private var text: String {
        guard state.tracking, let id = recordingID, let job = batch.jobs[id] else { return state.text }
        return String(format: L("Tracking %d%%", "识别中 %d%%"), Int((job.fraction * 100).rounded()))
    }
}

private struct TaskValueCell: View {
    let text: String

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(text == "—" ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .textSelection(.enabled)
    }
}
