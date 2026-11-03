// VideoLists.swift — lists of videos reachable from Tasks: Needs review (by task), Not in a task
// (with Move to Task…), and All videos (search, delete with Undo).

import SwiftUI

// MARK: - Needs review

@MainActor
struct NeedsReviewView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @State private var excluding: Recording?
    @State private var reason = ""

    var body: some View {
        let list = store.recordings.filter { store.needsReview($0) }
        let byTask = Dictionary(grouping: list) { r in store.sessions(of: r.id).compactMap { store.task(for: $0) }.first?.id ?? "" }
        let tasks = store.tasks.filter { byTask[$0.id] != nil }
        let names = store.taskNames(store.tasks)
        List {
            if list.isEmpty {
                Text(L("Every tracked video has a decision.", "所有已识别的视频都已有决定。")).foregroundStyle(.secondary)
            }
            ForEach(tasks) { t in
                Section(names[t] ?? t.assay.name.text) {
                    ForEach(byTask[t.id] ?? []) { r in row(r) }
                }
            }
            if let free = byTask[""], !free.isEmpty {
                Section(L("Not in a task", "未归入任务")) {
                    ForEach(free) { r in row(r) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Needs review", "待审核"))
        .alert(L("Exclude this video?", "排除该视频？"), isPresented: Binding(get: { excluding != nil }, set: { if !$0 { excluding = nil } })) {
            TextField(L("Reason", "原因"), text: $reason)
            Button(L("Exclude", "排除"), role: .destructive) {
                if let r = excluding { store.setDecision(r.id, .excluded, reason: reason.trimmingCharacters(in: .whitespaces)) }
                excluding = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { excluding = nil }
        }
    }

    private func row(_ r: Recording) -> some View {
        NavigationLink(value: Route.recording(r.id)) { RecordingRow(recording: r, card: false) }
            .swipeActions(edge: .leading) {
                Button(L("Include", "纳入")) { store.setDecision(r.id, .included) }.tint(Palette.success)
            }
            .swipeActions(edge: .trailing) {
                Button(L("Exclude", "排除")) {
                    reason = r.qc?.verdict == .fail ? L("Poor tracking (failed QC)", "追踪质量差（QC 未通过）") : ""
                    excluding = r
                }
                .tint(Palette.danger)
            }
    }
}

// MARK: - Not in a task

@MainActor
struct UnassignedView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var moving: MoveTarget?

    var body: some View {
        let list = store.unassignedRecordings
        List(selection: $selection) {
            Section {
                ForEach(list) { r in
                    NavigationLink(value: Route.recording(r.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            RecordingRow(recording: r, card: false)
                            let analyses = store.sessions(of: r.id)
                            if !analyses.isEmpty {
                                Text(analyses.map { $0.assay.name.text }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if store.canMoveOut(r.id) {
                            Button(L("Move to Task…", "移到任务…")) { moving = MoveTarget(ids: [r.id]) }.tint(.accentColor)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(L("Delete", "删除"), role: .destructive) { delete([r.id]) }
                    }
                }
            } footer: {
                Text(L("Videos outside any task (for example added in an earlier version without a study). Move them to a task to compare them with its groups; their session for that task is created.",
                       "不属于任何任务的视频（例如在早期版本中添加且未归入研究的视频）。移到任务后会与该任务的分组一起比较，并创建该任务的实验。"))
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if list.isEmpty {
                ContentUnavailableView {
                    Text(L("Every video is in a task", "所有视频都已归入任务"))
                }
            }
        }
        .navigationTitle(L("Not in a task", "未归入任务"))
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? L("Done", "完成") : L("Select", "选择")) {
                    withAnimation(Motion.snappy) { editMode = editMode.isEditing ? .inactive : .active; selection = [] }
                }
                .disabled(list.isEmpty)
            }
            if editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(L("Move to Task…", "移到任务…")) { moving = MoveTarget(ids: Array(selection)) }
                        .disabled(selection.isEmpty || store.tasks.isEmpty || !selection.allSatisfy { store.canMoveOut($0) })
                    Spacer()
                    Button(L("Delete", "删除"), role: .destructive) { delete(selection) }
                        .disabled(selection.isEmpty)
                }
            }
        }
        .sheet(item: $moving) { m in
            MoveToTaskSheet(recordingIDs: m.ids) { selection = []; editMode = .inactive }
                .environmentObject(store)
                .environmentObject(app)
        }
    }

    private func delete(_ ids: Set<UUID>) {
        if let cur = queue.currentID, ids.contains(cur) { queue.cancelCurrent() }
        let n = ids.count
        app.deleted(store.deleteRecordings(ids), n == 1 ? L("Video deleted", "视频已删除") : String(format: L("%d videos deleted", "已删除 %d 段视频"), n))
        selection.subtract(ids)
    }
}

struct MoveTarget: Identifiable {
    let id = UUID()
    let ids: [UUID]
    /// The task the videos leave (left out of the choices), if any.
    var source: TaskRef?
}

/// Choose the task that receives the videos (their current task is not offered).
@MainActor
struct MoveToTaskSheet: View {
    let recordingIDs: [UUID]
    var source: TaskRef?
    var done: () -> Void = {}
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let choices = store.tasks.filter { $0 != source }
        let names = store.taskNames(store.tasks)
        NavigationStack {
            List {
                if choices.isEmpty {
                    Text(L("Create a task first (Tasks › +).", "请先新建任务（任务 › +）。")).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(choices) { t in
                        Button {
                            let m = store.moveToTask(Set(recordingIDs), task: t, from: source)
                            let name = names[t] ?? t.assay.name.text
                            app.moved(m, recordingIDs.count == 1 ? String(format: L("Moved to \u{201C}%@\u{201D}", "已移到“%@”"), name)
                                      : String(format: L("%d videos moved to \u{201C}%@\u{201D}", "已将 %d 段视频移到“%@”"), recordingIDs.count, name))
                            done()
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(names[t] ?? t.assay.name.text).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                AssayChip(assay: t.assay)
                            }
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(L("The animal ID of each video is matched to the task's animals (new IDs are added) and keeps its group when the animal has none yet. A video belongs to one study, so its sessions in other tasks go to Recently Deleted. Undo puts everything back.",
                           "每段视频的动物编号会与任务中的动物对应（新编号自动添加）；动物尚无分组时沿用视频原来的分组。一段视频只属于一个研究，因此它在其他任务中的实验会移到“最近删除”。“撤销”可全部恢复。"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(recordingIDs.count == 1 ? L("Move to Task", "移到任务") : String(format: L("Move %d Videos", "移动 %d 段视频"), recordingIDs.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
            }
        }
    }
}

extension SessionStore {
    /// The task a video is in (its first one), for "Move to another task".
    func currentTask(of recordingID: UUID) -> TaskRef? {
        sessions(of: recordingID).lazy.compactMap { self.task(for: $0) }.first
    }

    /// Videos cannot be moved out of a blinded task (their group would be revealed or lost).
    func canMoveOut(_ recordingID: UUID) -> Bool {
        recording(recordingID).flatMap { experiment(for: $0) }?.blinded != true
    }
}

// MARK: - All videos

@MainActor
struct AllVideosView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @State private var search = ""
    @State private var pendingDelete: Recording?
    @State private var moving: MoveTarget?

    private var videos: [Recording] {
        guard !search.isEmpty else { return store.recordings }
        return store.recordings.filter { r in
            store.displayName(r).localizedCaseInsensitiveContains(search)
            || r.subject.localizedCaseInsensitiveContains(search) || r.originalName.localizedCaseInsensitiveContains(search)
            || r.timepoint.localizedCaseInsensitiveContains(search) || r.notes.localizedCaseInsensitiveContains(search)
            || (store.experiment(for: r)?.name.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        let list = videos
        let names = store.taskNames(store.tasks)
        List {
            Section {
                ForEach(list) { r in
                    NavigationLink(value: Route.recording(r.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            RecordingRow(recording: r, card: false)
                            Text(taskLine(r, names)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        // Opens a confirmation, so no destructive role (that would remove the row at once).
                        Button(L("Delete", "删除")) { pendingDelete = r }.tint(.red)
                    }
                    .contextMenu {
                        if store.canMoveOut(r.id) {
                            Button(L("Move to Task…", "移到任务…")) { moving = MoveTarget(ids: [r.id], source: store.currentTask(of: r.id)) }
                        }
                        Button(L("Delete…", "删除…"), role: .destructive) { pendingDelete = r }
                    }
                }
            } footer: {
                if !list.isEmpty {
                    Text(String(format: L("%d videos, stored on this device. Each is tracked once.", "%d 段视频，保存在本机，每段只识别一次。"), list.count))
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if list.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView {
                        Text(L("No videos yet", "还没有视频"))
                    } description: {
                        Text(L("Add videos inside a task.", "请在任务中添加视频。"))
                    }
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .navigationTitle(L("All videos", "全部视频"))
        .searchable(text: $search, prompt: L("Animal, task or file", "动物编号、任务或文件名"))
        .confirmationDialog(L("Delete this video?", "删除该视频？"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { r in
            Button(L("Delete video and its sessions", "删除视频及其实验"), role: .destructive) {
                if queue.currentID == r.id { queue.cancelCurrent() }
                app.deleted(store.deleteRecordings([r.id]), L("Video deleted", "视频已删除"))
            }
        } message: { _ in
            Text(L("It stays in Recently Deleted for 30 days.", "会在“最近删除”中保留 30 天。"))
        }
        .sheet(item: $moving) { m in
            MoveToTaskSheet(recordingIDs: m.ids, source: m.source).environmentObject(store).environmentObject(app)
        }
    }

    private func taskLine(_ r: Recording, _ names: [TaskRef: String]) -> String {
        let tasks = store.sessions(of: r.id).compactMap { store.task(for: $0) }
        if tasks.isEmpty { return L("Not in a task", "未归入任务") }
        return tasks.map { names[$0] ?? $0.assay.name.text }.joined(separator: ", ")
    }
}
