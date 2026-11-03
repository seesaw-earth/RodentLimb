// TaskView.swift — one task, the hub (TASK_FIRST_SPEC §2.6): header (name, paradigm, counts), the
// primary action Add Videos, and Sessions | Results | Design. Export is in the toolbar.
//
//   Sessions — needs review first, then group → animal → session (timepoint · trial · date).
//              Excluded sessions stay visible, marked, and are left out of the results.
//   Results  — group comparison (each animal a dot, group mean ± SEM) and time courses.
//   Design   — name, groups, animals, timepoints, QC criteria, parameters, calibration, blinding.

import SwiftUI

enum TaskTab: String, CaseIterable, Identifiable {
    case sessions, results, design
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: return L("Sessions", "实验")
        case .results: return L("Results", "结果")
        case .design: return L("Design", "设计")
        }
    }
}

@MainActor
struct TaskView: View {
    let task: TaskRef

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @State private var tab: TaskTab = .sessions
    @State private var share: SharePayload?
    @State private var exporting = false
    @State private var excluding: Recording?
    @State private var reason = ""
    @State private var deletingSession: Session?
    @State private var sheet: TaskSheet?
    @State private var moving: MoveTarget?

    private var experiment: Experiment? { store.experiment(task.experimentID) }

    var body: some View {
        // Computed once per update and shared by the header, the list and the toolbar.
        let all = store.sessions(in: task)
        Group {
            if let e = experiment, store.taskExists(task) {
                List {
                    header(e, all)
                    Section {
                        Picker(L("View", "视图"), selection: $tab) {
                            ForEach(TaskTab.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    switch tab {
                    case .sessions: sessionsContent(e, all)
                    case .results: TaskResultsSections(task: task)
                    case .design: TaskDesignSections(task: task, sheet: $sheet)
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
            } else {
                ContentUnavailableView {
                    Text(L("Task deleted", "该任务已删除"))
                } description: {
                    Text(L("It can be restored from Settings › Recently Deleted.", "可在“设置 › 最近删除”中恢复。"))
                }
            }
        }
        .navigationTitle(store.taskName(task))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if exporting {
                    ProgressView()
                } else {
                    Button(L("Export", "导出")) { export() }
                        .disabled(experiment == nil || all.isEmpty)
                }
            }
        }
        .sheet(item: $share) { ShareSheet(items: $0.items) }
        .sheet(item: $sheet) { which in sheetContent(which).environmentObject(store).environmentObject(app) }
        .sheet(item: $moving) { m in
            MoveToTaskSheet(recordingIDs: m.ids, source: m.source).environmentObject(store).environmentObject(app)
        }
        .alert(L("Exclude this video?", "排除该视频？"), isPresented: Binding(get: { excluding != nil }, set: { if !$0 { excluding = nil } })) {
            TextField(L("Reason", "原因"), text: $reason)
            Button(L("Exclude", "排除"), role: .destructive) {
                if let r = excluding { store.setDecision(r.id, .excluded, reason: reason.trimmingCharacters(in: .whitespaces)) }
                excluding = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { excluding = nil }
        } message: {
            Text(L("Excluded sessions stay in the task, marked, and are left out of the group results. The reason goes into the exports (ARRIVE 2.0).",
                   "已排除的实验仍保留在任务中并有标记，但不计入组结果。原因会写入导出文件（ARRIVE 2.0）。"))
        }
        .confirmationDialog(L("Delete this session?", "删除该实验？"),
                            isPresented: Binding(get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } }),
                            titleVisibility: .visible, presenting: deletingSession) { s in
            Button(L("Remove from task, keep the video", "从任务中移除，保留视频")) {
                if let rid = s.recordingID {
                    app.moved(store.removeFromTask([rid], task: task), L("Removed from the task", "已从任务中移除"))
                } else {
                    app.deleted(store.delete([s.id]), L("Session deleted", "实验已删除"))
                }
            }
            Button(L("Delete session and video", "删除实验和视频"), role: .destructive) {
                if let rid = s.recordingID {
                    if queue.currentID == rid { queue.cancelCurrent() }
                    app.deleted(store.deleteRecordings([rid]), L("Session and video deleted", "实验和视频已删除"))
                }
            }
        } message: { _ in
            Text(L("The session goes to Recently Deleted for 30 days. A kept video without other sessions moves to \u{201C}Not in a task\u{201D}.",
                   "实验会移到“最近删除”，保留 30 天。保留的视频若没有其他实验，会移到“未归入任务”。"))
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: TaskSheet) -> some View {
        let eid = task.experimentID
        switch which {
        case .design: StudyEditorSheet(experimentID: eid)
        case .newAnimal: AnimalEditorSheet(experimentID: eid, animalID: nil)
        case .animal(let a): AnimalEditorSheet(experimentID: eid, animalID: a)
        case .randomize: RandomizeSheet(experimentID: eid)
        case .params(let s): ParamsSheet(sessionID: s)
        case .calibration(let s): CalibrationLoader(sessionID: s)
        case .group(let g): GroupNameSheet(experimentID: eid, old: g)
        }
    }

    // MARK: Header

    private func header(_ e: Experiment, _ all: [Session]) -> some View {
        let c = store.counts(of: all)
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    AssayChip(assay: task.assay)
                    if e.blinded { Tag(text: L("Blinded", "盲法")) }
                    Spacer(minLength: 0)
                }
                countsLine(c)
                Button { app.addVideos(to: task) } label: {
                    Text(L("Add Videos", "添加视频")).frame(maxWidth: .infinity)
                }
                .primaryAction()
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
    }

    private func countsLine(_ c: TaskCounts) -> some View {
        FlowLayout(spacing: 14, lineSpacing: 4) {
            stat("\(c.sessions)", L("sessions", "个实验"), .primary)
            if c.needsReview > 0 { stat("\(c.needsReview)", L("need review", "待审核"), Palette.warning) }
            if c.processing > 0 { stat("\(c.processing)", L("processing", "处理中"), .secondary) }
            if c.excluded > 0 { stat("\(c.excluded)", L("excluded", "已排除"), .secondary) }
            if c.failed > 0 { stat("\(c.failed)", L("failed", "失败"), Palette.danger) }
        }
        .font(.subheadline)
    }

    private func stat(_ n: String, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(n).font(.headline).monospacedDigit().foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: Sessions

    @ViewBuilder
    private func sessionsContent(_ e: Experiment, _ all: [Session]) -> some View {
        let review = all.compactMap { s -> ReviewItem? in
            guard let r = store.recording(for: s), store.needsReview(r) else { return nil }
            return ReviewItem(session: s, recording: r)
        }
        if all.isEmpty {
            Section {
                Text(L("No videos yet. Add the videos of this task: each one becomes a session, is tracked once by the pose model and checked for quality.",
                       "还没有视频。添加本任务的视频后，每段视频成为一个实验，由姿态模型识别一次并检查质量。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        if !review.isEmpty {
            Section {
                ForEach(review) { item in
                    ReviewRow(session: item.session, recording: item.recording,
                              include: { store.setDecision(item.recording.id, .included) },
                              exclude: { reason = defaultReason(item.recording); excluding = item.recording })
                }
            } header: {
                Text(String(format: L("Needs review (%d)", "待审核（%d）"), review.count))
            } footer: {
                Text(L("Tracking quality did not meet every criterion. Open a video to check it, then include or exclude it.",
                       "追踪质量未满足全部标准。打开视频检查后，选择纳入或排除。"))
            }
        }
        ForEach(store.taskTree(task, sessions: all)) { group in
            Section {
                ForEach(group.animals) { animal in
                    ForEach(animal.sessions) { s in
                        NavigationLink(value: Route.session(s.id)) {
                            TaskSessionRow(session: s, title: animal.label)
                        }
                        .swipeActions(edge: .trailing) {
                            // Opens a confirmation, so no destructive role (that would remove the row at once).
                            Button(L("Delete", "删除")) { deletingSession = s }.tint(.red)
                        }
                        .contextMenu { sessionMenu(s) }
                    }
                }
            } header: {
                HStack {
                    Text(group.name)
                    Spacer()
                    Text(String(format: L("%d animals · %d sessions", "%d 只动物 · %d 个实验"), group.animals.count, group.sessionCount))
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func sessionMenu(_ s: Session) -> some View {
        if let r = store.recording(for: s) {
            Button(L("Video and quality check", "视频与质量检查")) { app.openRecording(r.id) }
            if r.isProcessed {
                if r.decision != .included {
                    Button(L("Include", "纳入")) { store.setDecision(r.id, .included) }
                }
                if r.decision != .excluded {
                    Button(L("Exclude…", "排除…")) { reason = defaultReason(r); excluding = r }
                }
            }
        }
        if let rid = s.recordingID, experiment?.blinded != true, store.tasks.count > 1 {
            Button(L("Move to Another Task…", "移到其他任务…")) { moving = MoveTarget(ids: [rid], source: task) }
        }
        Button(L("Delete…", "删除…"), role: .destructive) { deletingSession = s }
    }

    private func defaultReason(_ r: Recording) -> String {
        r.qc?.verdict == .fail ? L("Poor tracking (failed QC)", "追踪质量差（QC 未通过）") : ""
    }

    // MARK: Export

    private func export() {
        guard !exporting else { return }
        exporting = true
        Task { @MainActor in
            let urls = await TaskExport.files(store: store, task: task)
            exporting = false
            if urls.isEmpty { app.notice = L("Nothing to export yet", "还没有可导出的内容") } else { share = SharePayload(items: urls) }
        }
    }
}

// MARK: - Rows

struct ReviewItem: Identifiable {
    let session: Session
    let recording: Recording
    var id: UUID { session.id }
}

/// Short coloured state text with a small dot (no icons).
struct StateLabel: View {
    let state: SessionState

    static func color(_ s: SessionState) -> Color {
        switch s {
        case .needsReview, .needsCalibration: return Palette.warning
        case .failed, .excluded: return Palette.danger
        case .ready: return Palette.success
        case .queued, .processing, .checking: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Self.color(state)).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(state.title).foregroundStyle(Self.color(state))
        }
        .font(.footnote.weight(.medium))
        .lineLimit(1)
    }
}

@MainActor
struct TaskSessionRow: View {
    let session: Session
    let title: String
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue

    var body: some View {
        let r = store.recording(for: session)
        let state = store.state(of: session)
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(state == .excluded ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let r {
                    Text(store.sessionLine(r)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                if state == .excluded, let r {
                    Text(r.exclusionReason.isEmpty ? L("Excluded, no reason given", "已排除，未填写原因") : L("Excluded: ", "已排除：") + r.exclusionReason)
                        .font(.caption).foregroundStyle(Palette.danger).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing(state)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailing(_ state: SessionState) -> some View {
        switch state {
        case .processing:
            LiveProgress(progress: queue.progress) { p in
                let f = queue.currentID == session.recordingID ? p.fraction : 0
                Text(String(format: "%.0f%%", f * 100)).font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
            }
        case .ready:
            if let m = session.summary.first {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(m.formatted + (m.unit.isEmpty ? "" : " " + m.unit))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(m.label.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                StateLabel(state: state)
            }
        case .excluded:
            EmptyView()
        default:
            StateLabel(state: state)
        }
    }
}

/// A session whose QC needs a decision, with Include / Exclude at hand.
@MainActor
struct ReviewRow: View {
    let session: Session
    let recording: Recording
    let include: () -> Void
    let exclude: () -> Void
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { app.openRecording(recording.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.displayName(recording)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            if let qc = recording.qc { QCBadge(verdict: qc.verdict, compact: true) }
                            if let qc = recording.qc {
                                Text(String(format: L("mouse tracked %.0f%%", "可用帧 %.0f%%"), qc.coreCoverage * 100))
                                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    Spacer()
                    Text(L("Check", "检查")).font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                Button(L("Include", "纳入"), action: include).buttonStyle(SecondaryButtonStyle())
                Button(L("Exclude…", "排除…"), action: exclude).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
}
