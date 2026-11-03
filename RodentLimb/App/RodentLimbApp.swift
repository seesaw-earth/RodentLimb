// RodentLimbApp.swift — entry point. Changing the language preference rebuilds the view tree
// (`.id`) so every L(...) string updates immediately, without relaunching.

import SwiftUI
import UIKit

@main
struct RodentLimbApp: App {
    @StateObject private var app = AppModel()
    @AppStorage(AppLanguage.storageKey) private var uiLanguage = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(uiLanguage)
                .environment(\.locale, AppLanguage.locale(for: uiLanguage))
                .environmentObject(app)
                .environmentObject(app.store)
                .environmentObject(app.engine)
                .environmentObject(app.queue)
        }
    }
}

/// Tabs (TASK_FIRST_SPEC §3): Tasks · Processing · Settings.
enum AppTab: Hashable { case tasks, processing, settings }

/// Screens pushed on a tab's navigation stack.
enum Route: Hashable {
    case task(TaskRef)
    case session(UUID)
    case recording(UUID)
    case allVideos
    case unassigned
    case needsReview
    case recentlyDeleted
}

/// Opens the Add Videos sheet of a task.
struct AddVideosRequest: Identifiable {
    let id = UUID()
    var task: TaskRef
}

/// What Undo puts back.
enum UndoAction {
    /// Items moved to Recently Deleted.
    case restore(UUID)
    /// Videos moved into or out of a task.
    case move(TaskMove)
    /// A task deleted (a whole study, or one paradigm of an older study).
    case deleteTask(TaskDeletion)
}

/// "Deleted — Undo", shown for a few seconds after a delete or a move.
struct UndoItem: Identifiable {
    let id = UUID()
    var message: String
    var action: UndoAction
}

enum SettingsKey {
    static let boxThreshold = "rl.boxThreshold"
    static let renderSkeleton = "rl.renderSkeleton"
    static let lastAssay = "rl.lastAssay"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: AppTab = .tasks
    @Published var addVideosRequest: AddVideosRequest?
    @Published var showNewTask = false
    @Published var tasksPath: [Route] = []
    @Published var processingPath: [Route] = []
    @Published var undo: UndoItem?
    /// Short confirmation shown at the bottom of the screen.
    @Published var notice: String?

    let store: SessionStore
    let engine: PoseEngine
    let queue: ProcessingQueue
    private var memoryObserver: NSObjectProtocol?

    init() {
        let store = SessionStore()
        let engine = PoseEngine()
        let queue = ProcessingQueue(store: store, engine: engine)
        self.store = store
        self.engine = engine
        self.queue = queue
        queue.renderSkeleton = {
            let d = UserDefaults.standard
            var s = InferenceSettings()
            if d.object(forKey: SettingsKey.boxThreshold) != nil { s.boxThreshold = d.double(forKey: SettingsKey.boxThreshold) }
            s.renderSkeletonVideo = d.bool(forKey: SettingsKey.renderSkeleton)
            return s
        }
        engine.checkInstalled()
        // Parse the optional scratch model off the main thread now, instead of on first use
        // (opening the Itch parameters would otherwise stall while the JSON is decoded).
        Task.detached(priority: .utility) { _ = ScratchModel.bundled }
        // Under memory pressure drop caches that can be reloaded (pose tracks, old results, a pose
        // model not in use) instead of letting iOS terminate the app.
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { [weak store, weak engine, weak queue] _ in
            MainActor.assumeIsolated {
                store?.trimMemory()
                let running = queue?.currentID.flatMap { store?.poseModel($0).runnable }
                engine?.trimMemory(keeping: running)
            }
        }
    }

    /// Opens the Add Videos sheet of a task.
    func addVideos(to t: TaskRef) { addVideosRequest = AddVideosRequest(task: t) }

    func open(_ id: UUID) { push(.session(id)) }
    func openRecording(_ id: UUID) { push(.recording(id)) }
    func openTask(_ t: TaskRef) { push(.task(t)) }

    /// Pushes on the stack of the tab the user is on (Tasks when coming from Settings).
    func push(_ r: Route) {
        switch tab {
        case .tasks: tasksPath.append(r)
        case .processing: processingPath.append(r)
        case .settings:
            tab = .tasks
            tasksPath.append(r)
        }
    }

    /// Shows the Undo toast for a delete (nothing when nothing was deleted).
    func deleted(_ entry: UUID?, _ message: String) {
        guard let entry else { return }
        undo = UndoItem(message: message, action: .restore(entry))
    }

    /// Shows the Undo toast for a move into or out of a task.
    func moved(_ m: TaskMove, _ message: String) {
        undo = UndoItem(message: message, action: .move(m))
    }

    /// Shows the Undo toast for a deleted task (also when it had no session).
    func deletedTask(_ d: TaskDeletion, _ message: String) {
        undo = UndoItem(message: message, action: .deleteTask(d))
    }

    /// Deletes a task (see `SessionStore.deleteTask`) and offers Undo.
    func deleteTask(_ t: TaskRef, keepVideos: Bool) {
        let name = store.taskName(t)
        if !keepVideos, let cur = queue.currentID, store.recording(cur)?.experimentID == t.experimentID { queue.cancelCurrent() }
        let d = store.deleteTask(t, keepVideos: keepVideos)
        deletedTask(d, String(format: L("Deleted \u{201C}%@\u{201D}", "已删除“%@”"), name))
    }

    /// Puts back what the last delete or move changed.
    func undoDelete(_ item: UndoItem) {
        undo = nil
        Task { @MainActor in
            switch item.action {
            case .restore(let entry): notice = await store.restoreDeleted(entry)
            case .move(let m):
                await store.undoMove(m)
                notice = L("Undone", "已撤销")
            case .deleteTask(let d):
                await store.undoDeleteTask(d)
                notice = L("Task restored", "任务已恢复")
            }
            queue.kick()
        }
    }
}
