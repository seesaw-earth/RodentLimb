// MainView.swift — the main window: sidebar (tasks → groups, then the lists) · page. A task page
// pushes detail pages (a session, a video) on the stack; sheets for New Task, Add Videos, Export and
// Move to Task can be opened from anywhere. Files and folders dropped on the window are added to the
// task on screen (or, without one, New Task opens first).

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Which recordings a table shows.
enum RecordingFilter: Hashable {
    case all
    /// Tracked, waiting for an include / exclude decision.
    case needsReview
    case failed
    /// Queued or being tracked.
    case queue
    case study(UUID)
    /// Videos in no task.
    case unassigned
}

struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var dropTargeted = false
    /// The inspector was hidden because the window became narrow (it comes back when it is wide again).
    @State private var inspectorAutoHidden = false
    /// Last measured width and the pending fit (see `fitInspector`). A plain object, not view state:
    /// it changes on every frame of a live resize, and must not make the window's view update.
    @State private var resize = ResizeTracker()

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            SidebarView()
                .pageFrame()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 340)
        } detail: {
            NavigationStack(path: $app.path) {
                // Every page fills the detail column and keeps the minimum size of its content to
                // itself: a page that needs more room scrolls, it never makes the window resize
                // (see AdaptiveLayout.swift — the "Update Constraints in Window" exception).
                page
                    .pageFrame()
                    .navigationDestination(for: DetailRoute.self) { route in
                        Group {
                            switch route {
                            case .recording(let id): RecordingDetailView(id: id)
                            case .analysis(let id): AnalysisDetailView(id: id)
                            }
                        }
                        .pageFrame()
                    }
            }
        }
        .toolbar { GlobalToolbar() }
        .background {
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size, initial: true) { _, size in
                    // Never act during layout: remember the width, and react on a later turn.
                    resize.width = size.width
                    WindowSizing.scheduleSheetSpaceRefresh()
                    scheduleInspectorFit()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
            WindowSizing.scheduleSheetSpaceRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            WindowSizing.scheduleSheetSpaceRefresh()
        }
        // Presented views get the model explicitly: on macOS a sheet / popover / inspector / table
        // cell is not guaranteed to inherit the window's environment objects (a missing one crashes).
        .sheet(item: $app.importRequest) { ImportSheet(request: $0).environment(app) }
        .sheet(item: $app.exportRequest) { ExportSheet(request: $0).environment(app) }
        .sheet(item: $app.assignRequest) { MoveToTaskSheet(request: $0).environment(app) }
        .sheet(item: $app.newTaskRequest) { NewTaskSheet(request: $0).environment(app) }
        .sheet(isPresented: $app.showRecentlyDeleted) { RecentlyDeletedSheet().environment(app) }
        .alert(app.alert?.title ?? "", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } }),
               presenting: app.alert) { _ in
            Button(L("OK", "好")) { app.alert = nil }
        } message: { a in
            Text(a.message)
        }
        .alert(L("Relaunch to switch the menus too?", "重新启动以同时切换菜单？"), isPresented: $app.languageRelaunchSuggested) {
            Button(L("Relaunch Now", "立即重新启动")) { Task { await LanguageSwitch.relaunch(app) } }
            Button(L("Later", "稍后"), role: .cancel) {}
        } message: {
            Text(L("RodentLimb's windows have switched already. Menus and file panels provided by macOS switch after a relaunch. Everything is saved first and a running batch continues where it stopped.",
                   "RodentLimb 的窗口已经切换。macOS 提供的菜单和文件面板将在重新启动后切换。重新启动前会保存所有数据，正在运行的批处理会从停止处继续。"))
        }
        .toast($app.toast, action: $app.toastAction)
        .overlay {
            if app.isOpening {
                ProgressView(L("Opening library…", "正在打开资料库…"))
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        Text(dropText)
                            .font(.title3.weight(.semibold))
                            .padding(16)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter { $0.isFileURL }
            // A drop that reaches the window while a sheet is open must not replace that sheet.
            guard !files.isEmpty, !app.anySheetOpen else { return false }
            app.beginImport(files)
            return true
        } isTargeted: { dropTargeted = $0 }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private var page: some View {
        switch app.sidebar {
        case nil: WelcomeView()
        case .task(let t)?: TaskPage(task: t, group: nil)
        case .taskGroup(let t, let g)?: TaskPage(task: t, group: g).id(g)
        case .queue?: QueueView()
        case .videos?: RecordingsPage(filter: .all)
        case .review?: RecordingsPage(filter: .needsReview)
        case .failed?: RecordingsPage(filter: .failed)
        case .unassigned?: UnassignedPage()
        }
    }

    private var title: String {
        switch app.sidebar {
        case nil: return "RodentLimb"
        case .task(let t)?, .taskGroup(let t, _)?: return app.store.taskTitle(t)
        case .queue?: return L("Processing", "处理队列")
        case .videos?: return L("All Videos", "全部视频")
        case .review?: return L("Needs Review", "待复核")
        case .failed?: return L("Failed", "失败")
        case .unassigned?: return L("Not in a Task", "未归入任务")
        }
    }

    /// Applies `fitInspector` once the window has kept its size for a moment (not on every frame of a
    /// live resize, and never inside a layout pass: showing or hiding a column re-lays out the window).
    private func scheduleInspectorFit() {
        resize.pending?.cancel()
        let tracker = resize
        resize.pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            fitInspector(to: tracker.width)
        }
    }

    /// On a narrow window the inspector would squeeze the page below a usable width: it is hidden,
    /// and shown again when the window is widened (unless the user changed it meanwhile).
    private func fitInspector(to width: CGFloat) {
        guard width > 0 else { return }
        if width < 1040 {
            if app.showInspector {
                app.showInspector = false
                inspectorAutoHidden = true
            }
        } else if width >= 1120, inspectorAutoHidden {
            if !app.showInspector { app.showInspector = true }
            inspectorAutoHidden = false
        }
    }

    private var dropText: String {
        if let t = app.currentTask {
            return String(format: L("Drop to add videos to “%@”", "拖入以添加视频到“%@”"), app.store.taskTitle(t))
        }
        return L("Drop videos — then choose their task", "拖入视频——然后选择所属任务")
    }

    private var subtitle: String {
        let name = app.libraryURL.lastPathComponent
        return name == "RodentLimb" && app.libraryURL.standardizedFileURL == LibraryLocation.defaultURL.standardizedFileURL
            ? "" : name
    }
}

/// Window width seen during a resize, and the inspector fit waiting for the resize to pause.
@MainActor
private final class ResizeTracker {
    var width: CGFloat = 0
    var pending: Task<Void, Never>?
}

/// New Task and start / pause tracking, on every page (export is on each page and under ⌘E).
/// Few items, so a narrow window keeps them visible; page actions follow them.
struct GlobalToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(L("New Task", "新建任务")) {
                app.newTaskRequest = NewTaskRequest()
            }
            .help(L("Create a task: choose the paradigm, then add its videos (⇧⌘N)", "新建任务：先选择范式，再添加视频（⇧⌘N）"))

            BatchToolbarButton()
        }
    }
}

/// Start / pause tracking. Its content changes only when the batch starts or stops (or the number
/// of waiting videos changes) — never with the progress: a toolbar item redrawn several times a
/// second makes AppKit lay the toolbar and the window out again each time. The progress is shown in
/// the sidebar, on the Processing page and in the Dock.
struct BatchToolbarButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let batch = app.batch
        if batch.isActive {
            Button(L("Pause Tracking", "暂停识别")) {
                batch.pause()
            }
            .help(L("Stop after the current frame; progress is kept (⌘.)", "在当前帧后停止，进度会保留（⌘.）"))
        } else {
            let queued = app.store.queuedCount
            Button(queued > 0 ? String(format: L("Track %d", "识别 %d 个"), queued) : L("Track", "识别")) {
                batch.start()
            }
            .disabled(queued == 0)
            .help(L("Run the pose model on the queued videos (⌘R)", "对排队的视频运行姿态模型（⌘R）"))
        }
    }
}
