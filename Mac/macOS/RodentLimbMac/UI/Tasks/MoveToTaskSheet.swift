// MoveToTaskSheet.swift — puts the selected videos into a task (from All Videos, Not in a task, a
// session's menu or a video's page). The videos join the task's study (the animal is matched by its
// ID), get the task's session at once (analysed when tracked and included), and — when a group is
// chosen — animals that have no group yet are put in it. A video belongs to one study: its sessions
// in tasks of another study go to Recently Deleted (the sheet says how many). Undo is offered after.
// Videos of a blinded task cannot be moved out (their animal and group would show elsewhere).

import SwiftUI

@MainActor
struct MoveToTaskSheet: View {
    let request: AssignRequest

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var target: TaskRef?
    @State private var group = ""
    @State private var loaded = false

    var body: some View {
        let store = app.store
        let recs = request.recordings.compactMap { store.recording($0) }
        let tasks = store.tasks.filter { $0 != request.source }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Move to Task", "移到任务")).font(.title3.weight(.semibold))
                Text(recs.count == 1 ? (recs.first.map { RecordingsQuery.animalLabel($0, store: store) } ?? "")
                     : String(format: L("%d videos selected", "已选择 %d 段视频"), recs.count))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)

            if tasks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("There is no other task yet. Create one first: choose its paradigm, then add or move videos into it.",
                           "还没有其他任务。请先新建任务（选择范式），再添加或移入视频。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L("New Task…", "新建任务…")) {
                        dismiss()
                        // After this sheet has closed (macOS presents one sheet at a time).
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            app.newTaskRequest = NewTaskRequest()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                Form {
                    Section {
                        Picker(L("Task", "任务"), selection: $target) {
                            ForEach(tasks, id: \.self) { t in
                                Text(store.taskTitle(t) + "  ·  " + t.assay.name.text).tag(TaskRef?.some(t))
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    } header: {
                        Text(L("Task", "任务"))
                    }
                    if let t = target, !groupChoices(t).isEmpty {
                        Section {
                            Picker(L("Group", "组别"), selection: $group) {
                                Text(L("Leave as is", "保持不变")).tag("")
                                ForEach(groupChoices(t), id: \.self) { Text($0).tag($0) }
                            }
                        } footer: {
                            Text(L("For animals that have no group in this task yet; an animal that has one keeps it.",
                                   "用于在此任务中尚无组别的动物；已有组别的动物保持不变。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack(alignment: .center) {
                if let note = note(recs) {
                    Text(note.text)
                        .font(.callout)
                        .foregroundStyle(note.blocking ? Palette.danger : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("Cancel", "取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Move", "移动")) { move(recs) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(target == nil || recs.isEmpty || note(recs)?.blocking == true)
            }
            .padding(14)
        }
        .sheetFrame(minWidth: 420, idealWidth: 540, minHeight: 320, idealHeight: 480, maxHeight: 700)
        .onChange(of: target) { _, _ in group = "" }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let ids = Set(recs.compactMap(\.experimentID))
            // Default: the task on screen when moving from elsewhere, else the newest other task.
            target = tasks.first { $0 == app.currentTask && !ids.contains($0.experimentID) }
                ?? tasks.first { !ids.contains($0.experimentID) }
                ?? tasks.first
        }
    }

    /// Groups offered for the target: only for a single-factor task that is not blinded.
    private func groupChoices(_ t: TaskRef) -> [String] {
        guard let e = app.store.experiment(t.experimentID), !e.blinded, e.factors.count <= 1 else { return [] }
        return app.store.taskGroups(t)
    }

    /// What the move will do that the user should know (or why it cannot be done).
    private func note(_ recs: [Recording]) -> (text: String, blocking: Bool)? {
        guard let t = target else { return nil }
        let store = app.store
        let leaving = recs.filter { $0.experimentID != nil && $0.experimentID != t.experimentID }
        if leaving.contains(where: { store.experiment(for: $0)?.blinded == true }) {
            return (L("Some videos belong to a blinded task: unblind it first (their animal and group would show in the other task).",
                      "部分视频属于盲法中的任务：请先揭盲（否则其动物和组别会在另一个任务中显示）。"), true)
        }
        let other = leaving.filter { r in store.sessions(of: r.id).contains { $0.assay != t.assay } }.count
        if other > 0 {
            return (String(format: L("%d video(s) leave their task: those sessions go to Recently Deleted (Undo is offered).",
                                     "%d 段视频将离开原任务：原会话会移到“最近删除”（可撤销）。"), other), false)
        }
        let already = recs.filter { r in r.experimentID == t.experimentID && store.sessions(of: r.id).contains { $0.assay == t.assay } }.count
        if already > 0 {
            return (String(format: L("%d already in this task", "%d 段已在该任务中"), already), false)
        }
        return nil
    }

    private func move(_ recs: [Recording]) {
        guard let t = target, app.store.taskExists(t) else { return }
        let store = app.store
        let ids = Set(recs.map(\.id))
        let m = store.moveToTask(ids, task: t, from: request.source)
        let g = group.trimmingCharacters(in: .whitespaces)
        if !g.isEmpty, groupChoices(t).contains(g) {
            for id in ids {
                if let aid = store.recording(id)?.animalID { store.setGroup(g, animal: aid, in: t.experimentID) }
            }
            store.flush()
        }
        let title = store.taskTitle(t)
        dismiss()
        app.notify(String(format: L("%d video(s) moved to “%@”", "已将 %d 段视频移到“%@”"), ids.count, title),
                   action: ToastAction(title: L("Undo", "撤销")) { [weak app] in
                       guard let app else { return }
                       Task { @MainActor in
                           await app.store.undoMove(m)
                           app.toast = L("Move undone", "已撤销移动")
                       }
                   })
    }
}
