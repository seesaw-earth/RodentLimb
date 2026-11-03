// SettingsView.swift — Settings window (⌘,): General (language, library), Processing (how the batch
// runs on this Mac), Advanced (model, logs, storage). Settings are per Mac, not per library.

import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Text(L("General", "通用")) }
            ProcessingSettings()
                .tabItem { Text(L("Processing", "处理")) }
            AdvancedSettings()
                .tabItem { Text(L("Advanced", "高级")) }
        }
        .frame(width: 560)
        // A tall tab scrolls inside the window instead of growing past the screen.
        .frame(minHeight: 320, idealHeight: min(620, WindowSizing.screen.height - 120), maxHeight: WindowSizing.screen.height - 80)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(AppLanguage.storageKey) private var language = "system"
    @AppStorage(SettingsKey.copyVideos) private var copyVideos = false
    @AppStorage(SettingsKey.notifyWhenDone) private var notify = true

    var body: some View {
        Form {
            Picker(L("Language", "语言"), selection: Binding(get: { language }, set: { raw in
                guard raw != language else { return }
                if LanguageSwitch.set(AppLanguage(rawValue: raw) ?? .system) { app.languageRelaunchSuggestedInSettings = true }
            })) {
                ForEach(AppLanguage.allCases) { Text($0.pickerLabel).tag($0.rawValue) }
            }
            Text(L("Also in the menu bar (RodentLimb › Language) and at the bottom of the sidebar. Exported files are always in English.",
                   "也可在菜单栏（RodentLimb › Language）和侧边栏底部切换。导出文件始终为英文。"))
                .font(.caption).foregroundStyle(.secondary)

            Section(L("Library", "资料库")) {
                LabeledContent(L("Location", "位置")) {
                    Text(app.libraryURL.path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button(L("Show in Finder", "在访达中显示")) { app.revealLibraryInFinder() }
                    Button(L("Open Another Library…", "打开其他资料库…")) { chooseLibrary() }
                    if app.libraryURL.standardizedFileURL != LibraryLocation.defaultURL.standardizedFileURL {
                        Button(L("Use Default Library", "使用默认资料库")) {
                            Task { await app.openLibrary(LibraryLocation.defaultURL) }
                        }
                    }
                }
                Text(L("A library holds the tracking, QC, analyses and tasks. Videos stay where they are unless you copy them in. A library copied from the iPhone app (Files › On My iPhone › RodentLimb) opens here too.",
                       "资料库保存识别结果、QC、分析和任务。除非选择复制，视频保留在原处。从 iPhone App 拷贝的资料库（文件 › 我的 iPhone › RodentLimb）也可以在这里打开。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Section(L("Import", "导入")) {
                Toggle(L("Copy videos into the library by default", "默认将视频复制到资料库"), isOn: $copyVideos)
                Text(L("Off (recommended): videos are referenced where they are — no duplicate copies of large files. If you move a video, RodentLimb asks you to locate it.",
                       "关闭（推荐）：视频保留原位置引用，不重复占用空间。移动视频后，RodentLimb 会请你重新定位。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Section(L("Notifications", "通知")) {
                Toggle(L("Notify me when a batch is finished", "批处理完成时通知我"), isOn: $notify)
                    .onChange(of: notify) { _, on in if on { app.system.requestNotificationPermission() } }
            }
        }
        .formStyle(.grouped)
        .alert(L("Relaunch to switch the menus too?", "重新启动以同时切换菜单？"), isPresented: Binding(get: { app.languageRelaunchSuggestedInSettings },
                                                                                                     set: { app.languageRelaunchSuggestedInSettings = $0 })) {
            Button(L("Relaunch Now", "立即重新启动")) { Task { await LanguageSwitch.relaunch(app) } }
            Button(L("Later", "稍后"), role: .cancel) {}
        } message: {
            Text(L("RodentLimb's windows have switched already. Menus and file panels provided by macOS switch after a relaunch. Everything is saved first and a running batch continues where it stopped.",
                   "RodentLimb 的窗口已经切换。macOS 提供的菜单和文件面板将在重新启动后切换。重新启动前会保存所有数据，正在运行的批处理会从停止处继续。"))
        }
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Open Library", "打开资料库")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var target = url
        let inner = url.appendingPathComponent("RodentLimb", isDirectory: true)
        if !LibraryLocation.isLibrary(url), LibraryLocation.isLibrary(inner) { target = inner }
        Task { await app.openLibrary(target) }
    }
}

private struct ProcessingSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.simultaneous) private var simultaneous = SystemIntegration.recommendedSimultaneous
    @AppStorage(SettingsKey.boxThreshold) private var boxThreshold = 0.25
    @AppStorage(SettingsKey.autoStart) private var autoStart = true
    @AppStorage(SettingsKey.preventSleep) private var preventSleep = true
    @AppStorage(SettingsKey.computeUnits) private var compute = ComputeChoice.all.rawValue
    @AppStorage(SettingsKey.defaultPoseModel) private var defaultModel = PoseModelID.standard.rawValue

    var body: some View {
        Form {
            Section(L("Batch", "批处理")) {
                Toggle(L("Start tracking automatically after import", "导入后自动开始识别"), isOn: $autoStart)
                Stepper(value: $simultaneous, in: 1...3) {
                    LabeledContent(L("Videos processed at the same time", "同时处理的视频数"), value: "\(simultaneous)")
                }
                Text(String(format: L("Recommended for this Mac: %d. More videos at once help when decoding is the bottleneck (4K, HEVC); the Neural Engine runs one model at a time.",
                                      "本机推荐：%d。解码较慢（4K、HEVC）时同时处理多个视频更快；神经网络引擎一次只运行一个模型。"),
                            SystemIntegration.recommendedSimultaneous))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle(L("Keep the Mac awake while tracking", "识别时保持 Mac 唤醒"), isOn: $preventSleep)
                Text(L("The display may still sleep. Pausing, quitting or a power cut lose at most a few seconds: every video continues from its last saved frame.",
                       "显示器仍可休眠。暂停、退出或断电最多丢失几秒：每个视频都会从最后保存的帧继续。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Section(L("Pose model", "姿态模型")) {
                Picker(L("Preselected for new videos", "新视频默认使用"), selection: Binding(
                    get: { PoseModelID(rawValue: defaultModel)?.isAvailable == true ? defaultModel : PoseModelID.standard.rawValue },
                    set: { defaultModel = $0 })) {
                    ForEach(PoseModelID.choices) { m in
                        Text(m.title.text + (PoseModelLoader.isInstalled(m) ? "" : L(" — missing", " — 缺失"))).tag(m.rawValue)
                    }
                }
                Text(L("Chosen again whenever videos are added (visible light or near-infrared dark box); a video can be tracked again with the other model from its page. Both store the same keypoints, so every analysis and export works with either; use one model per task.",
                       "每次添加视频时都可重新选择（可见光或近红外暗箱）；也可在视频页面换用另一个模型重新识别。两者保存相同格式的关键点，分析和导出都可通用；同一任务请只用一个模型。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $boxThreshold, in: 0.05...0.8, step: 0.05) {
                        Text(L("Detection threshold", "检测阈值"))
                    }
                    Text(String(format: L("%.2f — frames where the mouse is found with lower confidence count as \"no mouse\". Changing it applies to videos tracked afterwards (re-run tracking for others).",
                                          "%.2f——置信度低于此值的帧视为“未检测到小鼠”。修改后对之后识别的视频生效（其他视频需重新识别）。"), boxThreshold))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Picker(L("Processors", "处理器"), selection: $compute) {
                    ForEach(ComputeChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text(L("Takes effect for the next video.", "从下一个视频开始生效。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: simultaneous) { _, _ in app.applySettings() }
        .onChange(of: boxThreshold) { _, _ in app.applySettings() }
        .onChange(of: autoStart) { _, _ in app.applySettings() }
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var app
    @State private var bytes: Int64?
    @State private var free: Int64?
    @State private var backups: [BackupInfo] = []
    @State private var restoreTarget: BackupInfo?
    @State private var working = false
    @State private var restoredText: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section(L("Data safety", "数据安全")) {
                LabeledContent(L("Recently Deleted", "最近删除")) {
                    Button(L("Open…", "打开…")) {
                        openWindow(id: "main")
                        app.showRecentlyDeleted = true
                    }
                }
                Text(String(format: L("Deleted videos, analyses and tasks are kept for %d days and can be restored (File › Recently Deleted…, ⌥⌘⌫). Changes are saved within half a second, and at once when the app goes to the background or the Mac sleeps.",
                                      "删除的视频、分析和任务会保留 %d 天并可恢复（文件 › 最近删除…，⌥⌘⌫）。更改会在半秒内保存；App 切到后台或 Mac 睡眠时立即保存。"), RecentlyDeleted.keepDays))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LabeledContent(L("Backups", "备份")) {
                    HStack {
                        Button(L("Back Up Now", "立即备份")) {
                            app.store.backup(MetadataBackup.Reason.manual)
                            Task { try? await Task.sleep(nanoseconds: 600_000_000); await reloadBackups() }
                        }
                        Button(L("Show in Finder", "在访达中显示")) {
                            let url = MetadataBackup.root(app.store.base)
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
                if backups.isEmpty {
                    Text(L("No backup yet — one is made every day the library is opened.", "还没有备份——每天打开资料库时都会自动备份一次。"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(backups.prefix(8)) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Fmt.date(b.createdAt)).monospacedDigit()
                                Text(b.reasonLabel + " · " + Fmt.bytes(b.bytes)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Restore…", "恢复…")) { restoreTarget = b }
                                .disabled(working)
                        }
                    }
                }
                Text(String(format: L("A backup holds every task, the design information and decisions of the videos, and the settings and labels of the analyses (not the tracking, which edits never change). Made daily and before deletes and bulk changes; the last %d daily ones are kept. Restoring never deletes anything and backs up the current state first.",
                                      "备份包含所有任务、视频的设计信息与纳入决定，以及分析的参数和标签（不含识别结果，编辑不会改变它）。每天以及删除、批量修改前自动备份；保留最近 %d 个每日备份。恢复不会删除任何内容，并会先备份当前状态。"), MetadataBackup.keepDaily))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("Storage", "存储")) {
                LabeledContent(L("Library size", "资料库大小"), value: bytes.map(Fmt.bytes) ?? "…")
                LabeledContent(L("Free on this disk", "磁盘剩余空间"), value: free.map(Fmt.bytes) ?? "—")
                Text(L("Pose, QC and results are small (a few MB per hour of video). Referenced videos are not counted.",
                       "姿态、QC 和结果很小（每小时视频约几 MB）。引用的视频不计入。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Diagnostics", "诊断")) {
                Button(L("Show Activity Log", "显示活动日志")) {
                    NSWorkspace.shared.activateFileViewerSelecting([app.store.log.currentFile])
                }
                Text(L("The log records imports, every tracked video, failures and recoveries — useful after an overnight batch and for bug reports.",
                       "日志记录导入、每个识别的视频、失败与恢复——便于查看通宵批处理的情况和反馈问题。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LabeledContent(L("Version", "版本"), value: AppInfo.version)
            }
        }
        .formStyle(.grouped)
        .task {
            await reloadBackups()
            bytes = await app.store.storageBytes()
            free = app.store.freeSpace()
        }
        .confirmationDialog(L("Restore this backup?", "恢复此备份？"),
                            isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }),
                            titleVisibility: .visible, presenting: restoreTarget) { b in
            Button(L("Restore", "恢复")) {
                working = true
                Task { @MainActor in
                    let text = await app.store.restoreBackup(b.url)
                    working = false
                    restoredText = text
                    await reloadBackups()
                }
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: { b in
            Text(String(format: L("Tasks, video design information, decisions and analysis settings go back to %@. Tracking is not changed, nothing is deleted, and the current state is backed up first.",
                                  "任务、视频设计信息、纳入决定和分析参数将恢复到 %@ 的状态。识别结果不变，不会删除任何内容，并会先备份当前状态。"), Fmt.date(b.createdAt)))
        }
        .alert(L("Backup restored", "备份已恢复"), isPresented: restoredAlert) {
            Button(L("OK", "好")) { restoredText = nil }
        } message: {
            Text(restoredText ?? "")
        }
    }

    private func reloadBackups() async {
        backups = await app.store.backups()
    }

    private var restoredAlert: Binding<Bool> {
        Binding(get: { restoredText != nil }, set: { if !$0 { restoredText = nil } })
    }
}
