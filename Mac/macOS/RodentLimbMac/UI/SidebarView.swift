// SidebarView.swift — Tasks first: every task (name, paradigm, number of sessions) expands into its
// groups; below, the lists that cut across tasks (processing, needs review, failed, all videos, not
// in a task). Counts are computed in one pass per render (SessionStore.taskOverview).

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    @State private var expanded = Set<TaskRef>()

    var body: some View {
        @Bindable var app = app
        let counts = app.counts
        let overview = app.store.taskOverview()
        let outside = overview.notInTask
        List(selection: $app.sidebar) {
            Section(L("Tasks", "任务")) {
                ForEach(overview.tasks, id: \.self) { t in
                    taskRow(t, overview: overview)
                }
                // A full-width row (an easy target), not a small button in the section header.
                Button {
                    app.newTaskRequest = NewTaskRequest()
                } label: {
                    Text(L("New Task…", "新建任务…"))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .selectionDisabled()
                .help(L("New Task (⇧⌘N)", "新建任务（⇧⌘N）"))
            }

            Section(L("Lists", "列表")) {
                // Its own view: the batch progress redraws this row only, not the whole sidebar.
                SidebarProcessingRow(batch: app.batch)
                    .badge(counts.queue)
                    .tag(SidebarItem.queue)
                Text(L("Needs Review", "待复核"))
                    .badge(counts.review)
                    .tag(SidebarItem.review)
                if counts.failed > 0 {
                    Text(L("Failed", "失败"))
                        .badge(counts.failed)
                        .tag(SidebarItem.failed)
                }
                Text(L("All Videos", "全部视频"))
                    .badge(counts.videos)
                    .tag(SidebarItem.videos)
                if outside > 0 || app.sidebar == .unassigned || overview.studiesWithoutTask > 0 {
                    Text(L("Not in a Task", "未归入任务"))
                        .badge(outside)
                        .tag(SidebarItem.unassigned)
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: app.sidebar, initial: true) { _, new in
            app.path = []
            app.selectedRecordings = []
            app.selectedAnalyses = []
            if let t = new?.task { expanded.insert(t) }
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    @ViewBuilder
    private func taskRow(_ t: TaskRef, overview: SessionStore.TaskOverview) -> some View {
        let groups = overview.groups[t] ?? []
        let label = TaskSidebarLabel(title: app.store.taskTitle(t, shared: overview.shared.contains(t.experimentID)),
                                     paradigm: t.assay.name.text,
                                     sessions: overview.sessions[t] ?? 0,
                                     review: overview.review[t] ?? 0,
                                     blinded: app.store.experiment(t.experimentID)?.blinded == true)
        Group {
            if groups.isEmpty {
                label.tag(SidebarItem.task(t))
            } else {
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(t) },
                                                    set: { if $0 { expanded.insert(t) } else { expanded.remove(t) } })) {
                    ForEach(groups, id: \.name) { g in
                        Text(g.name)
                            .lineLimit(1)
                            .badge(g.count)
                            .tag(SidebarItem.taskGroup(t, g.name))
                    }
                } label: {
                    label.tag(SidebarItem.task(t))
                }
            }
        }
        .contextMenu {
            Button(L("Add Videos…", "添加视频…")) { app.chooseFilesToImport(task: t) }
            Button(L("Export…", "导出…")) { app.export(.task(t)) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.libraryURL.lastPathComponent).font(.caption.weight(.semibold)).lineLimit(1)
                Text(app.libraryURL.deletingLastPathComponent().path)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            LanguagePicker(app: app, compact: true)
                .fixedSize()
            Button(L("Show", "显示")) { app.revealLibraryInFinder() }
                .controlSize(.small)
                .fixedSize()
                .help(L("Show the library folder in Finder", "在访达中显示资料库文件夹"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help(app.libraryURL.path)
    }
}

/// "Processing" with the batch progress in whole percent while it runs. Text that changes once per
/// percent (not an animated ring redrawn on every progress report): the sidebar is an AppKit
/// outline view, and its rows should not be re-laid out several times a second.
private struct SidebarProcessingRow: View {
    let batch: BatchEngine

    var body: some View {
        HStack(spacing: 6) {
            Text(L("Processing", "处理队列"))
            Spacer()
            if batch.isActive {
                Text(percent)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percent: String {
        let f = min(1, max(0, (batch.overallFraction ?? 0).finiteOr(0)))
        return "\(Int((f * 100).rounded(.down)))%"
    }
}

/// A task in the sidebar: its name, and below its paradigm with the number of sessions (and of
/// sessions needing review).
private struct TaskSidebarLabel: View {
    let title: String
    let paradigm: String
    let sessions: Int
    let review: Int
    let blinded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).lineLimit(1)
            HStack(spacing: 4) {
                Text(paradigm)
                Text("·")
                Text(String(format: L("%d sessions", "%d 个会话"), sessions)).monospacedDigit()
                if review > 0 {
                    Text("·")
                    Text(String(format: L("%d to review", "%d 待复核"), review)).foregroundStyle(Palette.warning)
                }
                if blinded {
                    Text("·")
                    Text(L("blinded", "盲法"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
