// AppModel.swift — the app's state: the open library (SessionStore), the batch engine, navigation
// (task first: sidebar Tasks → Groups, plus the lists), and the sheets that can be opened from
// anywhere (new task, add videos to a task, export, move videos to a task).
//
// Views read it from the environment:  @Environment(AppModel.self) private var app
// and reach the data through `app.store` (re-read each time: the store is replaced when another
// library is opened).

import SwiftUI
import Observation
import AppKit
import UniformTypeIdentifiers

/// Sidebar destinations: a task (or one of its groups), or one of the lists.
enum SidebarItem: Hashable {
    case task(TaskRef)
    case taskGroup(TaskRef, String)
    case queue
    case review
    case failed
    case videos
    case unassigned

    /// The task shown (also for one of its groups).
    var task: TaskRef? {
        switch self {
        case .task(let t), .taskGroup(let t, _): return t
        default: return nil
        }
    }
}

/// Pages pushed on the detail stack (double-click a row, or a link).
enum DetailRoute: Hashable {
    case recording(UUID)
    case analysis(UUID)
}

/// Add Videos request: videos always go into a task (files may already be chosen, e.g. dropped).
struct ImportRequest: Identifiable {
    let id = UUID()
    var task: TaskRef
    var urls: [URL] = []
    /// Group preselected for the videos (Add Videos from a group's page).
    var group: String = ""
}

/// New Task request; files dropped before any task was chosen are added to it once it is created.
struct NewTaskRequest: Identifiable {
    let id = UUID()
    var pendingURLs: [URL] = []
}

struct ExportRequest: Identifiable {
    let id = UUID()
    var scope: ExportScope
}

/// Move to Task request: the videos, and the task they leave when moved from a task's page.
struct AssignRequest: Identifiable {
    let id = UUID()
    var recordings: Set<UUID>
    var source: TaskRef? = nil
}

/// A button shown in the toast (Undo after a delete, Review after a batch).
struct ToastAction {
    var title: String
    var run: @MainActor () -> Void
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

@MainActor
@Observable
final class AppModel {
    private(set) var store: SessionStore
    private(set) var batch: BatchEngine
    private(set) var libraryURL: URL
    private(set) var isOpening = true

    // Navigation
    var sidebar: SidebarItem?
    var path: [DetailRoute] = []
    var showInspector = true
    var search = ""

    // Sheets
    var importRequest: ImportRequest?
    var exportRequest: ExportRequest?
    var assignRequest: AssignRequest?
    var newTaskRequest: NewTaskRequest?
    var showRecentlyDeleted = false
    /// The interface language changed in a way the system menus only follow after a relaunch.
    var languageRelaunchSuggested = false
    /// Same, when the language was changed in the Settings window (asked there; kept here because the
    /// Settings view is rebuilt in the new language).
    var languageRelaunchSuggestedInSettings = false
    var alert: AppAlert?
    var toast: String?
    var toastAction: ToastAction?
    /// The recording / analysis selected in the current table (drives the inspector).
    var selectedRecordings: Set<UUID> = []
    var selectedAnalyses: Set<UUID> = []

    @ObservationIgnored let system = SystemIntegration()
    /// Identifies this run of the app in the library lock.
    @ObservationIgnored private let lockToken = UUID().uuidString
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var lockedLibrary: URL?

    init() {
        let url = LibraryLocation.current()
        libraryURL = url
        let store = SessionStore(base: url)
        self.store = store
        batch = BatchEngine(store: store, makeRunner: { PoseRunner(choice: ComputeChoice.current) })
        wire()
        Task { await self.finishOpening() }
    }

    // MARK: Library

    private func wire() {
        applySettings()
        batch.hooks.activeChanged = { [weak self] active in
            guard let self else { return }
            self.system.setWorking(active, preventSleep: UserDefaults.standard.object(forKey: SettingsKey.preventSleep) as? Bool ?? true)
            // "Notify when done" is on by default: ask once (later calls return without a prompt),
            // otherwise the end-of-batch notification is silently dropped.
            if active, UserDefaults.standard.object(forKey: SettingsKey.notifyWhenDone) as? Bool ?? true {
                self.system.requestNotificationPermission()
            }
        }
        batch.hooks.progressChanged = { [weak self] fraction in
            self?.system.setDockProgress(fraction, queued: self?.store.queuedCount ?? 0)
        }
        batch.hooks.finished = { [weak self] summary in
            guard let self else { return }
            let notify = UserDefaults.standard.object(forKey: SettingsKey.notifyWhenDone) as? Bool ?? true
            if notify { self.system.notifyBatchFinished(summary) }
            self.system.setDockProgress(nil, queued: self.store.queuedCount)
            // In the window too, with the next step one click away.
            guard summary.finished + summary.failed > 0 else { return }
            let review = self.store.recordings.filter { $0.status == .ready && $0.decision == .pending && $0.qc != nil }.count
            var text = String(format: L("Tracking finished: %d video(s)", "识别完成：%d 段视频"), summary.finished)
            if summary.failed > 0 { text += String(format: L(" · %d failed", " · %d 段失败"), summary.failed) }
            if review > 0 { text += String(format: L(" · %d to review", " · %d 段待复核"), review) }
            self.notify(text, action: ToastAction(title: review > 0 ? L("Review", "复核") : L("Show", "查看")) { [weak self] in
                self?.show(review > 0 ? .review : .queue)
            })
        }
        store.onRecordingChanged = { [weak self] _ in
            guard let self else { return }
            self.system.setBadge(self.store.recordings.filter { $0.status == .ready && $0.decision == .pending }.count)
        }
    }

    private func finishOpening() async {
        isOpening = true
        let other = await acquireLock(store.base)
        await store.load()
        batch.recoverAfterLaunch()
        isOpening = false
        selectDefaultPage()
        if let other {
            let ago = max(0, Int(Date().timeIntervalSince(other.updated)))
            alert = AppAlert(title: L("This library is open on another Mac", "该资料库正在另一台 Mac 上打开"),
                             message: String(format: L("“%@” (%@) had it open %d s ago. Working on the same library from two Macs at once can overwrite changes: close it there, or open another library (File › Open Library…).",
                                                       "“%@”（%@）在 %d 秒前打开了它。两台 Mac 同时编辑同一个资料库可能会互相覆盖更改：请先在那里关闭，或打开其他资料库（文件 › 打开资料库…）。"),
                                             other.host, other.user, ago))
        }
        system.setBadge(store.recordings.filter { $0.status == .ready && $0.decision == .pending }.count)
        if !store.loadWarnings.isEmpty {
            toast = String(format: L("%d damaged file(s) were skipped (see the log).", "跳过了 %d 个损坏的文件（详见日志）。"), store.loadWarnings.count)
            for w in store.loadWarnings { store.log.write("Load warning: \(w)") }
        }
        if !PoseModelLoader.isInstalled {
            alert = AppAlert(title: L("Pose model missing", "缺少姿态模型"),
                             message: PoseRunError.modelMissing.errorDescription ?? "")
        }
        batch.kick()
    }

    /// Opens another library folder (an empty folder becomes a new library). The batch is stopped
    /// and everything is saved first.
    func openLibrary(_ url: URL) async {
        await prepareForQuit()
        LibraryLocation.remember(url)
        libraryURL = url
        path = []
        sidebar = nil
        selectedRecordings = []
        selectedAnalyses = []
        let s = SessionStore(base: url)
        store = s
        batch = BatchEngine(store: s, makeRunner: { PoseRunner(choice: ComputeChoice.current) })
        wire()
        await finishOpening()
    }

    /// Shows a short message at the bottom of the window, optionally with one button.
    func notify(_ message: String, action: ToastAction? = nil) {
        toastAction = action
        toast = message
    }

    /// Stops the batch after the current frame of each running video, writes everything to disk and
    /// releases the library lock. Used before quitting, relaunching (language change) and opening
    /// another library.
    func prepareForQuit(timeout: TimeInterval = 10) async {
        await batch.shutdown(timeout: timeout)
        await store.flushAndWait()
        await releaseLock()
    }

    /// The relaunch for a language change did not start a new instance: keep working here.
    func relaunchFailed() {
        alert = AppAlert(title: L("Could not relaunch", "无法重新启动"),
                         message: L("Quit RodentLimb (⌘Q) and open it again to switch the menus too. Everything is saved.",
                                    "请退出 RodentLimb（⌘Q）后重新打开，菜单才会切换。所有数据都已保存。"))
        Task { @MainActor in
            _ = await acquireLock(store.base)
            if store.queuedCount > 0, batch.autoStart { batch.start() }
        }
    }

    /// Saves pending changes now (the app goes to the background, the Mac goes to sleep).
    func saveNow() {
        store.flush()
    }

    // MARK: Library lock

    /// Writes this Mac's lock and returns the live lock of another app instance, if there was one.
    private func acquireLock(_ base: URL) async -> LibraryLockInfo? {
        let token = lockToken
        let app = AppInfo.version
        let other = await Task.detached(priority: .userInitiated) { () -> LibraryLockInfo? in
            let o = LibraryLock.otherHolder(base, token: token)
            LibraryLock.write(base, token: token, host: SystemIntegration.computerName, app: app)
            return o
        }.value
        lockedLibrary = base
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            var beats = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self, self.lockedLibrary == base else { return }
                await Task.detached(priority: .utility) {
                    LibraryLock.write(base, token: token, host: SystemIntegration.computerName, app: app)
                }.value
                beats += 1
                // A daily backup also for an app that stays open for days.
                if beats % 360 == 0 { await self.store.dailyBackupIfNeeded() }
            }
        }
        return other
    }

    private func releaseLock() async {
        heartbeat?.cancel()
        heartbeat = nil
        guard let base = lockedLibrary else { return }
        lockedLibrary = nil
        let token = lockToken
        await Task.detached(priority: .userInitiated) { LibraryLock.release(base, token: token) }.value
    }

    // MARK: Deleting with Undo

    /// Shows what was deleted with an Undo button (restores from Recently Deleted).
    func deleted(_ entry: UUID?, message: String) {
        guard let entry else { toast = message; return }
        notify(message, action: ToastAction(title: L("Undo", "撤销")) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let text = await self.store.restoreDeleted(entry)
                self.batch.kick()
                self.toast = text
            }
        })
    }

    /// Reads processing settings (called on launch and when Settings change).
    func applySettings() {
        let d = UserDefaults.standard
        batch.boxThreshold = d.object(forKey: SettingsKey.boxThreshold) as? Double ?? 0.25
        batch.maxSimultaneous = max(1, min(3, d.object(forKey: SettingsKey.simultaneous) as? Int ?? SystemIntegration.recommendedSimultaneous))
        batch.autoStart = d.object(forKey: SettingsKey.autoStart) as? Bool ?? true
    }

    // MARK: Actions

    /// The task on screen (selected in the sidebar, or the task of the open session).
    var currentTask: TaskRef? {
        if let t = sidebar?.task, store.taskExists(t) { return t }
        if case .analysis(let id)? = path.last, let s = store.session(id), let r = store.recording(for: s),
           let eid = r.experimentID {
            let t = TaskRef(experimentID: eid, assay: s.assay)
            if store.taskExists(t) { return t }
        }
        return nil
    }

    /// Adds videos to a task (the task on screen by default). Without a task, New Task opens first and
    /// the videos are added to the task it creates.
    func beginImport(_ urls: [URL] = [], task: TaskRef? = nil, group: String = "") {
        // Never replace a sheet that is open (it would lose its edits).
        guard !anySheetOpen else { return }
        if let t = task ?? currentTask {
            var g = group
            if g.isEmpty, case .taskGroup(let gt, let name)? = sidebar, gt == t { g = name }
            importRequest = ImportRequest(task: t, urls: urls, group: g)
        } else {
            newTaskRequest = NewTaskRequest(pendingURLs: urls)
        }
    }

    /// Open panel for videos and folders, then Add Videos for the task on screen.
    func chooseFilesToImport(task: TaskRef? = nil) {
        guard !anySheetOpen else { return }
        guard let t = task ?? currentTask else {
            newTaskRequest = NewTaskRequest()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder]
        panel.message = String(format: L("Choose videos, or folders of videos, for “%@”.", "为“%@”选择视频或包含视频的文件夹。"),
                               store.taskTitle(t))
        panel.prompt = L("Add", "添加")
        guard panel.runModal() == .OK else { return }
        beginImport(panel.urls, task: t)
    }

    /// A task was created: show it, and add the videos that were waiting for it.
    func taskCreated(_ t: TaskRef, pendingURLs: [URL]) {
        show(.task(t))
        if !pendingURLs.isEmpty { importAfterSheetCloses(ImportRequest(task: t, urls: pendingURLs)) }
    }

    /// Opens Add Videos once the sheet that asked for it (New Task) has gone: macOS does not present
    /// a sheet while another one is still closing.
    func importAfterSheetCloses(_ request: ImportRequest) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.importRequest == nil, self.store.taskExists(request.task) else { return }
            self.importRequest = request
        }
    }

    func export(_ scope: ExportScope) { exportRequest = ExportRequest(scope: scope) }

    /// A sheet is open (menu commands that open another one wait).
    var anySheetOpen: Bool {
        importRequest != nil || exportRequest != nil || assignRequest != nil || newTaskRequest != nil || showRecentlyDeleted
    }

    /// What Export (⌘E) exports from the page on screen: the selected sessions or videos, else the
    /// task, else the whole library.
    var defaultExportScope: ExportScope {
        if let t = sidebar?.task, store.taskExists(t) {
            return selectedAnalyses.isEmpty ? .task(t) : .selection(analyses: selectedAnalyses, recordings: [])
        }
        if !selectedRecordings.isEmpty { return .selection(analyses: [], recordings: selectedRecordings) }
        return .library
    }

    /// Opens a detail page. A page already on the stack is returned to (the pages above it close),
    /// never pushed a second time: the same view twice on one stack has one identity for two places.
    func open(_ route: DetailRoute) {
        if let i = path.firstIndex(of: route) {
            if i < path.count - 1 { path.removeSubrange((i + 1)...) }
        } else {
            path.append(route)
        }
    }

    func openRecording(_ id: UUID) { open(.recording(id)) }
    func openAnalysis(_ id: UUID) { open(.analysis(id)) }

    func show(_ item: SidebarItem) {
        sidebar = item
        path = []
        selectedRecordings = []
        selectedAnalyses = []
    }

    func revealLibraryInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
    }

    func revealVideo(_ r: Recording) {
        guard let access = store.videoAccess(r) else {
            alert = AppAlert(title: L("Video not found", "找不到视频"), message: PoseRunError.videoMissing.errorDescription ?? "")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([access.url])
    }

    /// Asks for the new location of a moved video.
    func locateVideo(_ id: UUID) {
        guard let r = store.recording(id) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video]
        panel.message = String(format: L("Locate “%@”", "定位“%@”"), r.originalName)
        if let path = store.source(id)?.path {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let warning = await store.relinkVideo(id, to: url) {
                alert = AppAlert(title: L("Video relinked", "已重新关联视频"), message: warning)
            } else {
                toast = L("Video found", "已找到视频")
            }
            batch.kick()
        }
    }

    /// Re-queues videos and starts the batch.
    func retry(_ ids: Set<UUID>) {
        store.requeue(ids)
        batch.start()
    }

    /// Tracks videos again — with the same pose model, or with `model` (e.g. near-infrared).
    func rerunTracking(_ ids: Set<UUID>, model: PoseModelID? = nil) {
        for id in ids where store.recording(id)?.status != .processing { store.rerunDetection(id, model: model) }
        batch.start()
    }

    /// Counts for the sidebar badges.
    var counts: (queue: Int, review: Int, failed: Int, videos: Int) {
        let recs = store.recordings
        var q = 0, r = 0, f = 0
        for x in recs {
            switch x.status {
            case .queued, .processing: q += 1
            case .failed: f += 1
            case .ready: if x.decision == .pending && x.qc != nil { r += 1 }
            }
        }
        return (q, r, f, recs.count)
    }

    /// Opens the newest task when nothing valid is selected (after opening a library or deleting).
    func selectDefaultPage() {
        if let item = sidebar {
            if let t = item.task {
                if store.taskExists(t) { return }
            } else {
                return
            }
        }
        sidebar = store.tasks.first.map { SidebarItem.task($0) }
    }
}

/// Where the library lives. Default: Documents/RodentLimb in the app's container (Library ›
/// Containers › RodentLimb › Data › Documents); File › Open Library… chooses any folder (kept as a
/// security-scoped bookmark).
enum LibraryLocation {
    static var defaultURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
        return docs.appendingPathComponent("RodentLimb", isDirectory: true)
    }

    /// Started once per launch for a library outside the container (released when the app quits).
    private static var accessed: URL?

    static func current() -> URL {
        let d = UserDefaults.standard
        if let data = d.data(forKey: SettingsKey.libraryBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                accessed = url
                if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    d.set(fresh, forKey: SettingsKey.libraryBookmark)
                }
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        let url = defaultURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remember(_ url: URL) {
        let d = UserDefaults.standard
        if url.standardizedFileURL == defaultURL.standardizedFileURL {
            d.removeObject(forKey: SettingsKey.libraryBookmark)
            return
        }
        if let old = accessed, old != url { old.stopAccessingSecurityScopedResource() }
        _ = url.startAccessingSecurityScopedResource()
        accessed = url
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            d.set(data, forKey: SettingsKey.libraryBookmark)
        }
        d.set(url.path, forKey: SettingsKey.libraryPath)
    }

    /// Whether a folder looks like a RodentLimb library (Mac or iPhone).
    static func isLibrary(_ url: URL) -> Bool {
        let fm = FileManager.default
        return ["Recordings", "Sessions", "Experiments"].contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
    }
}
