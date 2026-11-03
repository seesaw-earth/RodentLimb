// ImportSheet.swift — the Add Videos sheet of a task. Files and folders (searched recursively) are
// listed in a table, read four at a time (duration, frame rate, size, warnings) and named from their
// file names (animal ID, group, timepoint, trial — editable inline, in bulk, or by a file-name
// pattern). The group, timepoint, notes, pose model and keep-in-place / copy choice above the table
// apply to every video. Adding puts them in the task and the processing queue, reports duplicates
// and failures, and returns to the task. Keyboard: ⌘O add, ⌫ remove, ⌘↩ add, Esc cancel.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct ImportSheet: View {
    let request: ImportRequest

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = ImportSheetModel()
    @State private var selection = Set<UUID>()
    @State private var sortOrder: [KeyPathComparator<ImportPendingVideo>] = []
    @State private var showPattern = false
    @State private var showBulk = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let result = model.result {
                ImportResultPanel(result: result,
                                  busy: model.phase == .importing,
                                  done: model.importDone,
                                  total: model.importTotal,
                                  autoStart: app.batch.autoStart,
                                  importAnyway: { importDuplicates() },
                                  finish: { finish(start: $0) })
            } else {
                ImportOptionsPanel(model: model)
                Divider()
                tableBar
                table
                Divider()
                footer
            }
        }
        .sheetFrame(minWidth: 640, idealWidth: 1000, maxWidth: 1400, minHeight: 440, idealHeight: 680, maxHeight: 1000)
        .onAppear { model.start(request: request, store: app.store) }
        .onDisappear { model.close() }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.phase == .editing, model.result == nil else { return false }
            let files = urls.filter { $0.isFileURL }
            guard !files.isEmpty else { return false }
            model.add(files)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle).font(.title2.weight(.semibold)).lineLimit(1)
                Text(L("Videos are tracked by the pose model, checked (QC) and then analysed with this task's paradigm.",
                       "视频先由姿态模型识别并做质控（QC），再按此任务的范式分析。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Table

    private var tableBar: some View {
        HStack(spacing: 8) {
            Button {
                chooseFiles()
            } label: {
                Text(L("Add Files…", "添加文件…"))
            }
            .keyboardShortcut("o", modifiers: .command)
            .help(L("Add videos or folders (⌘O). You can also drop them on this sheet.", "添加视频或文件夹（⌘O），也可直接拖入此窗口。"))

            Button {
                showPattern.toggle()
            } label: {
                Text(patternTitle)
            }
            .help(L("How animal ID, timepoint and trial are read from file names", "如何从文件名读取动物编号、时间点和试次"))
            .popover(isPresented: $showPattern, arrowEdge: .bottom) {
                ImportPatternEditor(model: model, sample: sampleURL)
                    .environment(app)
            }

            Button {
                showBulk = true
            } label: {
                Text(selection.count > 1 ? String(format: L("Edit %d Videos…", "编辑 %d 个视频…"), selection.count)
                                         : L("Edit Selected…", "编辑所选…"))
            }
            .disabled(selection.isEmpty)
            .help(L("Set animal IDs (or a prefix / numbers), timepoint and trial of the selected videos", "批量设置所选视频的动物编号（或前缀 / 编号）、时间点和试次"))
            .popover(isPresented: $showBulk, arrowEdge: .bottom) {
                ImportBulkEditor(model: model, ids: selection) { showBulk = false }
                    .environment(app)
            }

            Button {
                removeSelected()
            } label: {
                Text(L("Remove", "移除"))
            }
            .disabled(selection.isEmpty)
            .help(L("Remove the selected videos from the list (Delete)", "从列表中移除所选视频（Delete）"))

            Spacer(minLength: 12)
            activity
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .disabled(model.phase != .editing)
    }

    @ViewBuilder
    private var activity: some View {
        let reading = model.summary.reading
        if model.searching > 0 {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L("Searching folders…", "正在查找文件夹…")).foregroundStyle(.secondary)
            }
            .font(.callout)
        } else if reading > 0 {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(String(format: L("Reading %d video(s)…", "正在读取 %d 个视频…"), reading)).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
        } else if let notice = model.notice {
            Text(notice).font(.callout).foregroundStyle(.secondary)
        } else if !model.rows.isEmpty {
            Text(L("Drop more videos or folders here", "可继续拖入视频或文件夹"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private var table: some View {
        let codes = studyCodes
        let timepoints = model.experiment?.timepoints ?? []
        let groups: [String]? = model.groupsEditable ? model.taskGroups : nil
        return Table(model.rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L("Video", "视频"), value: \ImportPendingVideo.name) { nameCell($0) }
                .width(min: 150, ideal: 240)
            TableColumn(L("Duration", "时长"), value: \ImportPendingVideo.duration) { durationCell($0) }
                .width(min: 52, ideal: 64, max: 90)
            TableColumn("fps", value: \ImportPendingVideo.fps) { fpsCell($0) }
                .width(min: 52, ideal: 64, max: 90)
            TableColumn(L("Frame", "画面"), value: \ImportPendingVideo.pixels) { frameCell($0) }
                .width(min: 64, ideal: 84, max: 110)
            TableColumn(L("Size", "大小"), value: \ImportPendingVideo.fileSize) { sizeCell($0) }
                .width(min: 56, ideal: 70, max: 100)
            TableColumn(L("Animal ID", "动物编号"), value: \ImportPendingVideo.animal) { animalCell($0, codes: codes) }
                .width(min: 90, ideal: 130)
            TableColumn(L("Group", "组别"), value: \ImportPendingVideo.group) { groupCell($0, groups: groups) }
                .width(min: 80, ideal: 120)
            TableColumn(L("Timepoint", "时间点"), value: \ImportPendingVideo.timepoint) { timepointCell($0, timepoints: timepoints) }
                .width(min: 80, ideal: 120)
            TableColumn(L("Trial", "试次"), value: \ImportPendingVideo.trial) { trialCell($0) }
                .width(min: 40, ideal: 50, max: 70)
            TableColumn(L("Status", "状态"), value: \ImportPendingVideo.statusRank) { statusCell($0) }
                .width(min: 84, ideal: 104, max: 150)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            openVideos(ids)
        }
        .onDeleteCommand { removeSelected() }
        .onChange(of: sortOrder) { _, order in model.sort(using: order) }
        .overlay { if model.rows.isEmpty { emptyTable } }
        .disabled(model.phase != .editing)
    }

    // MARK: Cells

    private func nameCell(_ row: ImportPendingVideo) -> some View {
        Text(row.name).lineLimit(1).truncationMode(.middle)
        .foregroundStyle(row.status == .unreadable ? Color.secondary : Color.primary)
        .help(row.folder)
    }

    private func durationCell(_ row: ImportPendingVideo) -> some View {
        Text(row.facts.map { Fmt.clock($0.duration) } ?? "—")
            .monospacedDigit()
            .foregroundStyle(row.facts == nil ? Color.secondary : Color.primary)
    }

    private func fpsCell(_ row: ImportPendingVideo) -> some View {
        let low = (row.facts?.fps ?? 60) < 25
        return Text(row.facts.map { Fmt.fps($0.fps) } ?? "—")
            .monospacedDigit()
            .foregroundStyle(low ? Palette.warning : Color.primary)
    }

    private func frameCell(_ row: ImportPendingVideo) -> some View {
        let help = row.facts.map { $0.codec.isEmpty ? $0.sizeLabel : $0.sizeLabel + " · " + $0.codec } ?? ""
        return Text(row.facts?.sizeLabel ?? "—")
            .monospacedDigit()
            .help(help)
    }

    private func sizeCell(_ row: ImportPendingVideo) -> some View {
        Text(row.facts.map { Fmt.bytes($0.fileSize) } ?? "—").monospacedDigit()
    }

    private func animalCell(_ row: ImportPendingVideo, codes: Set<String>?) -> some View {
        HStack(spacing: 4) {
            TextField(L("Animal ID", "动物编号"), text: animalBinding(row), prompt: Text(L("Animal ID", "动物编号")))
                .labelsHidden()
                .textFieldStyle(.plain)
            if let codes, Self.isNew(row.animal, in: codes) {
                Tag(text: L("new", "新"), color: Palette.blue)
                    .help(L("Not in this task yet: it will be added as a new animal.", "该编号尚未在任务中登记，将作为新动物加入。"))
            }
        }
        .disabled(row.status == .unreadable)
    }

    @ViewBuilder
    private func groupCell(_ row: ImportPendingVideo, groups: [String]?) -> some View {
        if let groups {
            if row.animal.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .help(L("Enter the animal ID first: the group belongs to the animal.", "请先填写动物编号：组别属于动物。"))
            } else if row.groupFromAnimal {
                Text(row.group)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(L("This animal is already in this group (change it on the Design tab).", "该动物已在此组（可在“设计”页修改）。"))
            } else {
                Picker(L("Group", "组别"), selection: groupBinding(row)) {
                    Text(L("None", "无")).tag("")
                    ForEach(groups, id: \.self) { Text($0).tag($0) }
                    if !row.group.isEmpty && !groups.contains(row.group) { Text(row.group).tag(row.group) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .disabled(row.status == .unreadable)
            }
        } else {
            Text(model.groupsHidden ? L("Hidden", "已隐藏") : "—").foregroundStyle(.tertiary)
        }
    }

    private func timepointCell(_ row: ImportPendingVideo, timepoints: [String]) -> some View {
        let typed = row.timepoint.trimmingCharacters(in: .whitespaces)
        let unknown = !timepoints.isEmpty && !typed.isEmpty && ImportNaming.registered(typed, in: timepoints) == nil
        return HStack(spacing: 4) {
            TextField(L("Timepoint", "时间点"), text: timepointBinding(row), prompt: Text(L("None", "无")))
                .labelsHidden()
                .textFieldStyle(.plain)
            if unknown {
                Tag(text: L("new", "新"), color: Palette.purple)
                    .help(L("Not one of the task's timepoints.", "不是任务中已有的时间点。"))
            }
        }
        .disabled(row.status == .unreadable)
    }

    private func trialCell(_ row: ImportPendingVideo) -> some View {
        TextField(L("Trial", "试次"), value: trialBinding(row), format: .number)
            .labelsHidden()
            .textFieldStyle(.plain)
            .monospacedDigit()
            .disabled(row.status == .unreadable)
    }

    @ViewBuilder
    private func statusCell(_ row: ImportPendingVideo) -> some View {
        switch row.status {
        case .reading:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(L("Reading…", "读取中…")).foregroundStyle(.secondary)
            }
        case .ready:
            Text(L("Ready", "就绪"))
                .foregroundStyle(Palette.success)
                .help(row.advice)
        case .warning:
            Text(L("Check", "请检查"))
                .foregroundStyle(Palette.warning)
                .help(row.advice)
        case .unreadable:
            Text(L("Unreadable", "无法读取"))
                .foregroundStyle(Palette.danger)
                .help(row.advice + "\n" + L("This file will be skipped.", "该文件将被跳过。"))
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UUID>) -> some View {
        if ids.isEmpty {
            Button(L("Add Files…", "添加文件…")) { chooseFiles() }
        } else {
            Button(ids.count > 1 ? String(format: L("Edit %d Videos…", "编辑 %d 个视频…"), ids.count) : L("Edit…", "编辑…")) {
                selection = ids
                showBulk = true
            }
            if model.groupsEditable, !model.taskGroups.isEmpty {
                Menu(L("Set Group", "设置组别")) {
                    ForEach(model.taskGroups, id: \.self) { g in
                        Button(g) { model.bulkEdit(ids, animal: nil, timepoint: nil, trial: nil, group: g) }
                    }
                }
            }
            if let e = model.experiment, !e.timepoints.isEmpty {
                Menu(L("Set Timepoint", "设置时间点")) {
                    ForEach(e.timepoints, id: \.self) { t in
                        Button(t) { model.bulkEdit(ids, animal: nil, timepoint: t, trial: nil) }
                    }
                }
            }
            if ids.count == 1, let e = model.experiment, !e.animals.isEmpty {
                Menu(L("Set Animal", "设置动物")) {
                    ForEach(Array(e.animals.prefix(300))) { a in
                        Button(a.code.isEmpty ? L("(no ID)", "（无编号）") : a.code) {
                            model.bulkEdit(ids, animal: (mode: ImportAnimalEdit.replace, text: a.code, start: 1, digits: 1),
                                           timepoint: nil, trial: nil)
                        }
                    }
                }
            }
            Button(L("Use File-Name Suggestion", "恢复按文件名建议")) { model.resetToSuggestions(ids) }
            Divider()
            Button(L("Open Video", "打开视频")) { openVideos(ids) }
            Button(L("Show in Finder", "在访达中显示")) { reveal(ids) }
            Divider()
            Button(L("Remove from List", "从列表中移除"), role: .destructive) {
                model.remove(ids)
                selection.subtract(ids)
            }
        }
    }

    private var emptyTable: some View {
        VStack(spacing: 10) {
            if model.searching > 0 {
                ProgressView(L("Searching folders…", "正在查找文件夹…"))
            } else {
                Text(L("Drop videos or folders here", "将视频或文件夹拖到这里"))
                    .font(.title3.weight(.semibold))
                Text(L("MP4, MOV and M4V can be read directly; folders are searched recursively.",
                       "可直接读取 MP4、MOV 和 M4V；文件夹会被递归查找。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L("Add Files…", "添加文件…")) { chooseFiles() }
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(30)
    }

    // MARK: Footer

    private var footer: some View {
        let s = model.summary
        return HStack(spacing: 12) {
            if model.phase == .importing {
                ProgressView(value: Double(min(model.importDone, model.importTotal)), total: Double(max(1, model.importTotal)))
                    .frame(width: 220)
                Text(String(format: L("Importing %d of %d…", "正在导入第 %d / %d 个…"),
                            min(model.importDone + 1, max(1, model.importTotal)), model.importTotal))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summaryLine(s)).font(.callout).monospacedDigit()
                    if let w = summaryWarning(s) {
                        Text(w)
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
            Button(L("Cancel", "取消"), role: .cancel) {
                model.close()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(model.phase == .importing)
            .fixedSize()

            Button {
                importNow()
            } label: {
                Text(importTitle(s.importable)).frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(s.importable == 0 || model.phase != .editing || model.searching > 0
                      || (model.groupsEditable && !s.groupConflicts.isEmpty))
            .help(L("Add to the task and the processing queue (⌘↩)", "加入任务和处理队列（⌘↩）"))
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func summaryLine(_ s: ImportSheetSummary) -> String {
        guard s.total > 0 else { return L("No videos yet", "尚未添加视频") }
        var parts = [s.importable == 1 ? L("1 video", "1 个视频") : String(format: L("%d videos", "%d 个视频"), s.importable)]
        let span = ImportSheetModel.span(s.seconds)
        if !span.isEmpty { parts.append(span) }
        if s.bytes > 0 { parts.append(Fmt.bytes(s.bytes)) }
        if s.unreadable > 0 { parts.append(String(format: L("%d unreadable (skipped)", "%d 个无法读取（跳过）"), s.unreadable)) }
        if s.reading > 0 { parts.append(String(format: L("%d still being read", "%d 个仍在读取"), s.reading)) }
        return parts.joined(separator: " · ")
    }

    private func summaryWarning(_ s: ImportSheetSummary) -> String? {
        if model.groupsEditable, !s.groupConflicts.isEmpty {
            return String(format: L("An animal is in one group only: %@ has two groups. Choose one before adding.",
                                    "一只动物只能属于一个组：%@ 被设为两个组。请先选定一个再添加。"),
                          s.groupConflicts.prefix(3).joined(separator: ", "))
        }
        if let e = model.experiment, !e.timepoints.isEmpty, s.noTimepoint > 0 {
            return String(format: L("%d video(s) have no timepoint.", "%d 个视频没有时间点。"), s.noTimepoint)
        }
        if s.noAnimal > 0 {
            return String(format: L("%d video(s) have no animal ID — without one they cannot be placed in a group.",
                                    "%d 个视频没有动物编号——没有编号就无法归入组别。"), s.noAnimal)
        }
        if model.groupsEditable, !model.taskGroups.isEmpty, s.noGroup > 0 {
            return String(format: L("%d video(s) have no group yet (you can set it later on the Design tab).",
                                    "%d 个视频还没有组别（之后可在“设计”页设置）。"), s.noGroup)
        }
        if s.warnings > 0 {
            return String(format: L("%d video(s) have warnings — point at “Check” for details.", "%d 个视频有警告——将指针移到“请检查”上查看详情。"), s.warnings)
        }
        return nil
    }

    private func importTitle(_ n: Int) -> String {
        if n == 1 { return L("Add 1 Video", "添加 1 个视频") }
        if n > 1 { return String(format: L("Add %d Videos", "添加 %d 个视频"), n) }
        return L("Add", "添加")
    }

    private var headerTitle: String {
        guard let t = model.task ?? (app.store.taskExists(request.task) ? request.task : nil) else {
            return L("Add Videos", "添加视频")
        }
        return String(format: L("Add Videos to “%@”", "添加视频到“%@”"), app.store.taskTitle(t))
    }

    // MARK: Bindings

    private func animalBinding(_ row: ImportPendingVideo) -> Binding<String> {
        Binding(get: { row.animal }, set: { model.setAnimal(row.id, $0) })
    }

    private func timepointBinding(_ row: ImportPendingVideo) -> Binding<String> {
        Binding(get: { row.timepoint }, set: { model.setTimepoint(row.id, $0) })
    }

    private func groupBinding(_ row: ImportPendingVideo) -> Binding<String> {
        Binding(get: { row.group }, set: { model.setGroup(row.id, $0) })
    }

    private func trialBinding(_ row: ImportPendingVideo) -> Binding<Int> {
        Binding(get: { row.trial }, set: { model.setTrial(row.id, $0) })
    }

    private var patternTitle: String {
        model.pattern.isAutomatic ? L("File Names: Automatic", "文件名：自动") : L("File Names: By Position", "文件名：按位置")
    }

    /// The file the pattern editor previews: the first selected video, else the first one.
    private var sampleURL: URL? {
        model.rows.first { selection.contains($0.id) }?.url ?? model.rows.first?.url
    }

    private var studyCodes: Set<String>? {
        guard let e = model.experiment else { return nil }
        return Set(e.animals.map { $0.code.trimmingCharacters(in: .whitespaces).lowercased() })
    }

    private static func isNew(_ code: String, in codes: Set<String>) -> Bool {
        let c = code.trimmingCharacters(in: .whitespaces).lowercased()
        return !c.isEmpty && !codes.contains(c)
    }

    // MARK: Actions

    private func chooseFiles() {
        guard model.phase == .editing, model.result == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder]
        panel.message = L("Choose videos, or folders of videos (searched recursively).", "选择视频或包含视频的文件夹（会递归查找）。")
        panel.prompt = L("Add", "添加")
        guard panel.runModal() == .OK else { return }
        model.add(panel.urls)
    }

    private func removeSelected() {
        guard !selection.isEmpty, model.phase == .editing else { return }
        model.remove(selection)
        selection = []
    }

    private func urls(_ ids: Set<UUID>) -> [URL] {
        model.rows.filter { ids.contains($0.id) }.map(\.url)
    }

    private func openVideos(_ ids: Set<UUID>) {
        for u in urls(ids).prefix(5) { NSWorkspace.shared.open(u) }
    }

    private func reveal(_ ids: Set<UUID>) {
        let list = urls(ids)
        guard !list.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(Array(list.prefix(200)))
    }

    private func importNow() {
        guard model.phase == .editing, model.result == nil, model.summary.importable > 0 else { return }
        Task { @MainActor in
            await model.runImport(app: app)
            guard let r = model.result else { return }
            if r.created > 0, app.batch.autoStart { app.batch.kick() }
            // Everything went in and tracking starts by itself: no result page needed.
            if r.created > 0, r.duplicates.isEmpty, r.failures.isEmpty, app.batch.autoStart {
                finish(start: false)
            }
        }
    }

    private func importDuplicates() {
        Task { @MainActor in
            await model.importDuplicatesAnyway(app: app)
            if (model.result?.created ?? 0) > 0, app.batch.autoStart { app.batch.kick() }
        }
    }

    /// Leaves the sheet; with added videos, returns to the task (its sessions show the tracking) and
    /// starts the batch when asked.
    private func finish(start: Bool) {
        let created = model.result?.created ?? 0
        if created > 0 {
            if start { app.batch.start() } else { app.batch.kick() }
            let added = created == 1 ? L("1 video added and queued for tracking", "已添加 1 段视频，等待识别")
                : String(format: L("%d videos added and queued for tracking", "已添加 %d 段视频，等待识别"), created)
            let text = app.batch.state == .paused ? added + L(" — tracking is paused", "——识别已暂停") : added
            if let t = model.task, app.sidebar?.task != t { app.show(.task(t)) }
            app.notify(text, action: ToastAction(title: L("Show Processing", "查看处理进度")) { [weak app] in app?.show(.queue) })
        }
        model.close()
        dismiss()
    }
}
