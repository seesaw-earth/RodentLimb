// RodentLimbMacApp.swift — entry point, menus, quitting safely.
//
// One main window (sidebar · page · inspector) and a Settings window. Closing the window does not
// quit: a batch keeps running in the background (Dock icon shows progress); quitting while videos
// are being tracked asks first, then stops them after their current frame and saves everything —
// they continue from there next time.

import SwiftUI
import AppKit

@main
struct RodentLimbMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(AppLanguage.storageKey) private var uiLanguage = "system"

    var body: some Scene {
        Window("RodentLimb", id: "main") {
            MainView()
                .id(uiLanguage)
                .environment(\.locale, AppLanguage.locale(for: uiLanguage))
                .environment(delegate.model)
                // Fits the smallest Mac screens (1024 × 640 usable); pages adapt below their usual width.
                // Min *and* max: the window's minimum is exactly this, whatever a page inside asks for.
                // (With only a minimum, a larger minimum of the content became the window's minimum —
                // and a minimum that changes while AppKit lays out the window makes it lay the window
                // out again and again, until it stops the app: "Update Constraints in Window passes".)
                .frame(minWidth: WindowSizing.minWidth, maxWidth: .infinity,
                       minHeight: WindowSizing.minHeight, maxHeight: .infinity)
        }
        .defaultSize(WindowSizing.defaultSize)
        .commands {
            AppCommands(app: delegate.model)
            SidebarCommands()
            InspectorCommands()
            ToolbarCommands()
        }

        Settings {
            SettingsView()
                .id(uiLanguage)
                .environment(\.locale, AppLanguage.locale(for: uiLanguage))
                .environment(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var sleepObserver: NSObjectProtocol?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = LanguageSwitch.systemMenusChinese   // the language the system menus were built in
        _ = model
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.model.store.trimMemory()
                ThumbnailCache.shared.trim()
            }
        }
        source.resume()
        memoryPressure = source
        // Nothing waits for the debounce when the Mac sleeps (a laptop lid can mean a dead battery).
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.saveNow() }
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        model.saveNow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // One check at a time (switching apps quickly must not stack up file checks on slow drives).
        guard !model.isOpening, !checkingAvailability else { return }
        checkingAvailability = true
        Task { @MainActor in
            await model.store.refreshAvailability()
            model.batch.kick()
            checkingAvailability = false
        }
    }
    private var checkingAvailability = false

    /// Keep running (and tracking) when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        let busy = model.batch.isActive
        if busy {
            let alert = NSAlert()
            alert.messageText = L("Videos are being tracked", "正在识别视频")
            alert.informativeText = L("Quit now? The running videos stop after their current frame and continue from there the next time you open RodentLimb.",
                                      "现在退出吗？正在处理的视频会在当前帧后停止，下次打开 RodentLimb 时从该处继续。")
            alert.addButton(withTitle: L("Quit", "退出"))
            alert.addButton(withTitle: L("Cancel", "取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        quitting = true
        Task { @MainActor in
            await model.prepareForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Menu bar commands.
struct AppCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    /// Read so the menus are rebuilt in the new language right away.
    @AppStorage(AppLanguage.storageKey) private var uiLanguage = "system"

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            LanguagePicker(app: app, onRelaunchSuggested: {
                // The question appears in the main window: bring it up (it may be closed).
                openWindow(id: "main")
                app.languageRelaunchSuggested = true
            })
        }

        CommandGroup(replacing: .newItem) {
            Button(L("New Task…", "新建任务…")) { app.newTaskRequest = NewTaskRequest() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(app.anySheetOpen)
            Button(L("Add Videos to Task…", "添加视频到任务…")) { app.chooseFilesToImport() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(app.anySheetOpen || app.currentTask == nil)
            Divider()
            Button(L("Open Library…", "打开资料库…")) { openLibraryPanel() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button(L("Show Library in Finder", "在访达中显示资料库")) { app.revealLibraryInFinder() }
            Button(L("Recently Deleted…", "最近删除…")) { app.showRecentlyDeleted = true }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
            Divider()
            Button(L("Export…", "导出…")) { app.export(app.defaultExportScope) }
                .disabled(app.anySheetOpen)
                .keyboardShortcut("e", modifiers: .command)
        }

        CommandMenu(L("Processing", "处理")) {
            Button(L("Start Tracking", "开始识别")) { app.batch.start() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(app.batch.state == .running)
            Button(L("Pause", "暂停")) { app.batch.pause() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!app.batch.isActive)
            Divider()
            Button(L("Retry Failed Videos", "重试失败的视频")) {
                app.retry(Set(app.store.recordings.filter { $0.status == .failed }.map(\.id)))
            }
            .disabled(!app.store.recordings.contains { $0.status == .failed })
            Divider()
            Button(L("Show Processing Queue", "显示处理队列")) { app.show(.queue) }
                .keyboardShortcut("2", modifiers: .command)
            Button(L("Show Videos Needing Review", "显示待复核视频")) { app.show(.review) }
                .keyboardShortcut("3", modifiers: .command)
        }

        CommandGroup(before: .sidebar) {
            Button(L("Latest Task", "最近的任务")) {
                if let t = app.store.tasks.first { app.show(.task(t)) } else { app.sidebar = nil }
            }
            .keyboardShortcut("1", modifiers: .command)
            Button(L("All Videos", "全部视频")) { app.show(.videos) }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
        }

        CommandGroup(after: .windowArrangement) {
            Button(L("Main Window", "主窗口")) { openWindow(id: "main") }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button(L("Show Activity Log", "显示活动日志")) {
                NSWorkspace.shared.activateFileViewerSelecting([app.store.log.currentFile])
            }
        }
    }

    @MainActor
    private func openLibraryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Open Library", "打开资料库")
        panel.message = L("Choose a RodentLimb library folder (from this Mac or copied from an iPhone), or an empty folder for a new library.",
                          "选择 RodentLimb 资料库文件夹（本机的或从 iPhone 拷贝来的），或选择一个空文件夹以新建资料库。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // An iPhone "RodentLimb" folder is opened as it is; a folder that contains one is opened inside.
        var target = url
        let inner = url.appendingPathComponent("RodentLimb", isDirectory: true)
        if !LibraryLocation.isLibrary(url), LibraryLocation.isLibrary(inner) { target = inner }
        Task { await app.openLibrary(target) }
    }
}
