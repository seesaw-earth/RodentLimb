// ExportSheet.swift — export of a scope (selection, task, study, library): what it covers ("48
// analyses of 3 tasks from 24 videos"), which files to write (remembered between exports), where
// (a folder the user chose once, kept as a security-scoped bookmark), progress while writing, and a
// summary with the files, warnings and "Show in Finder". Exports are always English.

import SwiftUI
import AppKit

@MainActor
struct ExportSheet: View {
    let request: ExportRequest

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions.saved
    @State private var folder: URL?
    @State private var restored = false
    @State private var running = false
    @State private var progress = ExportProgress(fraction: 0, step: "")
    @State private var report: ExportReport?
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            if let report {
                finished(report)
            } else {
                settings
                Divider()
                footer
            }
        }
        .sheetFrame(minWidth: 480, idealWidth: 620, minHeight: 360, idealHeight: report == nil ? 720 : 480, maxHeight: report == nil ? 900 : 600)
        .interactiveDismissDisabled(running)
        .onAppear(perform: restoreFolder)
        .alert(L("Export failed", "导出失败"), isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button(L("OK", "好")) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Options

    private var settings: some View {
        let p = ExportService.preview(request.scope, options: options, store: app.store)
        return Form {
            Section {
                LabeledContent(L("Scope", "范围"), value: scopeTitle)
                LabeledContent(L("Contains", "包含")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: L("%d analyses of %d tasks from %d videos", "来自 %3$d 段视频、%2$d 个任务的 %1$d 个分析"),
                                    p.analyses, p.assays.count, p.recordings))
                            .monospacedDigit()
                        if !p.assays.isEmpty {
                            Text(p.assays.map { $0.name.text }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                }
            } header: {
                Text(L("Export", "导出"))
            }

            Section {
                option($options.summary, L("Summary", "汇总表"),
                       L("One row per analysis: design columns and every measure (tidy format for R, Python, Prism, SPSS).",
                         "每个分析一行：设计信息列与全部指标（整洁长格式，适用于 R、Python、Prism、SPSS）。"))
                option($options.segments, L("Behavior segments", "行为片段"),
                       L("Every event or bout with onset, offset, duration, label and reviewer edits; all videos in one file.",
                         "每个事件或发作的起止时间、时长、标签与人工修改；所有视频合并为一个文件。"))
                option($options.ethogram, L("Ethogram", "行为谱"),
                       L("Behavior intervals per track (e.g. grooming regions, immobility).", "按行为轨道列出的行为区间（如理毛部位、不动）。"))
                option($options.timeBins, L("Time bins", "时间分段"),
                       L("Time course in bins from the injection, long format.", "自注射起按时间段统计的时间进程，长格式。"))
                option($options.details, L("Task details", "任务明细"),
                       L("Task-specific tables: tail-suspension bouts and per-minute immobility, cylinder contacts, gait strides and footprints.",
                         "任务专属表格：悬尾不动发作与逐分钟不动、圆筒触壁、步态步幅与足印。"))
                option($options.qc, L("Tracking quality (QC)", "追踪质量（QC）"),
                       L("Tracking quality of every video with the inclusion decision and its reason (ARRIVE 2.0).",
                         "每段视频的追踪质量及纳入决定与原因（ARRIVE 2.0）。"))
                option($options.methods, L("Methods text", "方法描述"),
                       L("Methods paragraphs with the parameters used, and the task design.", "包含所用参数的方法描述段落及任务设计。"))
            } header: {
                Text(L("Tables", "表格"))
            }

            Section {
                option($options.frameLabels, L("Frame labels (DeepEthogram / daart)", "逐帧标签（DeepEthogram / daart）"),
                       L("One row per frame, 0/1 per behavior plus background — to train models or compare with manual scoring.",
                         "每帧一行、每种行为 0/1（另含 background），用于训练模型或与人工评分比较。"))
                option($options.boris, L("BORIS events", "BORIS 事件"),
                       L("Aggregated events (TSV) to open the automatic scoring in BORIS.", "汇总事件表（TSV），可在 BORIS 中打开自动评分结果。"))
                option($options.poseCSV, L("Pose (CSV)", "姿态（CSV）"),
                       L("Frame-by-frame keypoints of every video (RodentLimb layout). Large files.", "每段视频的逐帧关键点（RodentLimb 格式），文件较大。"))
                option($options.poseDLC, L("Pose in DeepLabCut format", "DeepLabCut 格式姿态"),
                       L("Keypoints in DeepLabCut's CSV layout (3 header rows) for DLC, SimBA, Keypoint-MoSeq …",
                         "DeepLabCut CSV 格式的关键点（3 行表头），可用于 DLC、SimBA、Keypoint-MoSeq 等。"))
                option($options.perVideoFolders, L("A folder per video", "每段视频一个文件夹"),
                       L("The same files as the iPhone app's single-analysis export, one folder per analysis.",
                         "内容与 iPhone 版单个分析导出相同，每个分析一个文件夹。"))
                option($options.includeNotIncluded, L("Also export videos that are not included", "同时导出未纳入的视频"),
                       L("Excluded videos and those waiting for a decision are flagged in the “included” column. Off: included videos only.",
                         "已排除和待决定的视频会在 included 列中标记。关闭则只导出已纳入的视频。"))
            } header: {
                Text(L("Advanced and interoperability", "高级与互通"))
            } footer: {
                Text(L("Files are English, UTF-8 and comma-separated. While a task is blinded, animal IDs, groups and file names are left out.",
                       "文件为英文、UTF-8 编码、逗号分隔。任务处于盲态时，动物编号、组别和文件名不会导出。"))
            }

            Section {
                LabeledContent(L("Folder", "文件夹")) {
                    HStack(spacing: 8) {
                        if let folder {
                            Text(folder.path)
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary)
                                .help(folder.path)
                        } else {
                            Text(L("Not chosen yet", "尚未选择")).foregroundStyle(Palette.warning)
                        }
                        Button(L("Choose…", "选择…")) { chooseFolder() }
                    }
                }
            } header: {
                Text(L("Destination", "保存位置"))
            } footer: {
                Text(L("A new folder “RodentLimb_<scope>_<date>” is created inside the chosen folder. The folder is remembered for the next export.",
                       "将在所选文件夹中新建“RodentLimb_<范围>_<日期>”文件夹；下次导出时会记住该位置。"))
            }
        }
        .formStyle(.grouped)
        .disabled(running)
    }

    private func option(_ value: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: value) {
            Text(title)
            Text(detail)
        }
    }

    private var anyFileChosen: Bool {
        let o = options
        return o.summary || o.segments || o.ethogram || o.timeBins || o.details || o.frameLabels || o.boris
            || o.qc || o.methods || o.poseCSV || o.poseDLC || o.perVideoFolders
    }

    // MARK: Footer

    private var footer: some View {
        let p = ExportService.preview(request.scope, options: options, store: app.store)
        let empty = p.analyses == 0 && p.recordings == 0
        return VStack(alignment: .leading, spacing: 10) {
            if running {
                ProgressView(value: min(1, max(0, progress.fraction.finiteOr(0))))
                Text(progress.step.isEmpty ? L("Writing…", "正在写入…") : progress.step)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                if empty {
                    Text(L("Nothing to export in this scope.", "该范围内没有可导出的内容。"))
                        .font(.callout).foregroundStyle(Palette.warning)
                } else if !anyFileChosen {
                    Text(L("Choose at least one kind of file.", "请至少选择一种文件。"))
                        .font(.callout).foregroundStyle(Palette.warning)
                }
                Spacer()
                Button(L("Cancel", "取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(running)
                Button {
                    runExport()
                } label: {
                    Text(folder == nil ? L("Choose Folder and Export…", "选择文件夹并导出…") : L("Export", "导出"))
                        .frame(minWidth: 70)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(running || empty || !anyFileChosen)
                .help(L("Export (⌘↩)", "导出（⌘↩）"))
            }
        }
        .padding(16)
    }

    // MARK: Finished

    private func finished(_ r: ExportReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Export finished", "导出完成")).font(.title3.weight(.semibold))
                    Text(String(format: L("%d files · %d analyses · %d videos", "%d 个文件 · %d 个分析 · %d 段视频"),
                                r.files.count, r.analyses, r.recordings))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            GroupBox {
                HStack {
                    Text(r.folder.path).font(.callout).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(4)
            }
            if !r.warnings.isEmpty {
                Text(String(format: L("%d warning(s)", "%d 条警告"), r.warnings.count)).font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(r.warnings.enumerated()), id: \.offset) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Palette.warning).frame(width: 6, height: 6)
                                Text(item.element).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 170)
            } else {
                Text(L("Every file was written without warnings. README.txt in the folder describes each file and column.",
                       "所有文件均已写入，没有警告。文件夹中的 README.txt 说明了每个文件和每一列。"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L("Show in Finder", "在访达中显示")) { reveal(r.folder) }
                Button(L("Done", "完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: Scope

    private var scopeTitle: String {
        switch request.scope {
        case .library:
            return L("Whole library", "整个资料库")
        case .study(let id):
            return String(format: L("Task “%@”", "任务“%@”"), app.store.experiment(id)?.name ?? L("(deleted)", "（已删除）"))
        case .task(let t):
            return String(format: L("Task “%@” (%@)", "任务“%@”（%@）"), app.store.taskTitle(t), t.assay.name.text)
        case .assay(let a):
            return String(format: L("All %@ analyses", "全部 %@ 分析"), a.name.text)
        case .selection(let analyses, let recordings):
            if analyses.isEmpty {
                return String(format: L("%d selected video(s) with all their analyses", "所选 %d 段视频及其全部分析"), recordings.count)
            }
            if recordings.isEmpty {
                return String(format: L("%d selected analysis(es)", "所选 %d 个分析"), analyses.count)
            }
            return String(format: L("%d selected analyses and %d videos", "所选 %d 个分析与 %d 段视频"), analyses.count, recordings.count)
        }
    }

    // MARK: Folder

    /// The last export folder (security-scoped bookmark), if it still exists.
    private func restoreFolder() {
        guard !restored else { return }
        restored = true
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: SettingsKey.lastExportFolder) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            defaults.removeObject(forKey: SettingsKey.lastExportFolder)
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        folder = url
        if stale { remember(url) }
    }

    private func remember(_ url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: SettingsKey.lastExportFolder)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose", "选择")
        panel.message = L("Choose where to save the export. A new folder is created inside it.",
                          "选择导出的保存位置，将在其中新建一个文件夹。")
        if let folder {
            panel.directoryURL = folder
        } else if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        remember(url)
    }

    private func reveal(_ exported: URL) {
        let parent = folder
        let access = parent?.startAccessingSecurityScopedResource() ?? false
        NSWorkspace.shared.activateFileViewerSelecting([exported])
        if access { parent?.stopAccessingSecurityScopedResource() }
    }

    // MARK: Export

    private func runExport() {
        guard !running else { return }
        if folder == nil { chooseFolder() }
        guard let parent = folder else { return }
        options.save()
        running = true
        errorText = nil
        progress = ExportProgress(fraction: 0, step: L("Preparing…", "正在准备…"))
        let scope = request.scope
        let opts = options
        let store = app.store
        Task { @MainActor in
            let access = parent.startAccessingSecurityScopedResource()
            defer { if access { parent.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await ExportService.run(scope, options: opts, into: parent, store: store) { p in
                    self.progress = p
                }
                report = result
            } catch {
                errorText = error.localizedDescription
            }
            running = false
        }
    }
}
