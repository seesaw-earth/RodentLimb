// RootView.swift — tabs (Tasks · Processing · Settings), first-launch onboarding, the New Task and
// Add Videos sheets, and the Undo toast after a delete.

import SwiftUI

@MainActor
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @EnvironmentObject private var engine: PoseEngine
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("rl.onboarded") private var onboarded = false
    @State private var showOnboarding = false

    private var waiting: Int { store.recordings.reduce(0) { $0 + ($1.status == .queued || $1.status == .processing ? 1 : 0) } }

    var body: some View {
        TabView(selection: $app.tab) {
            TasksView()
                .tabItem { Label(L("Tasks", "任务"), systemImage: "list.bullet.rectangle") }
                .tag(AppTab.tasks)
            ProcessingView()
                .tabItem { Label(L("Processing", "处理"), systemImage: "arrow.triangle.2.circlepath") }
                .badge(waiting)
                .tag(AppTab.processing)
            SettingsView()
                .tabItem { Label(L("Settings", "设置"), systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .minimizingTabBar()
        .sheet(item: $app.addVideosRequest) { req in
            AddVideosSheet(task: req.task)
                .environmentObject(app)
                .environmentObject(store)
                .environmentObject(queue)
                .environmentObject(engine)
        }
        .sheet(isPresented: $app.showNewTask) {
            NewTaskSheet { t in
                app.tab = .tasks
                app.tasksPath = [.task(t)]
            }
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { onboarded = true }) {
            OnboardingView()
        }
        .overlay(alignment: .bottom) { UndoToast().environmentObject(app) }
        .overlay {
            // The library is read off the main thread at launch (large libraries take a moment).
            if !store.isLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L("Opening library…", "正在打开资料库…")).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
            }
        }
        .toast($app.notice)
        .onChange(of: scenePhase) { _, phase in
            // Pause GPU work first, then save.
            queue.scenePhaseChanged(phase)
            switch phase {
            case .background: store.flushForBackground()
            case .inactive: store.flush()
            default: break
            }
        }
        .task {
            if !onboarded { showOnboarding = true }
            await store.waitUntilLoaded()
            queue.kick()
            let m = PoseModelID.defaultChoice
            if engine.isInstalled(m), engine.state(m) == .notLoaded { _ = await engine.load(m) }
        }
    }
}

/// "Moved to Recently Deleted — Undo" for six seconds after a delete.
@MainActor
struct UndoToast: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if let item = app.undo {
                HStack(spacing: 14) {
                    Text(item.message)
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button(L("Undo", "撤销")) { app.undoDelete(item) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 58)
                .transition(Motion.reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: item.id) {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if app.undo?.id == item.id { withAnimation(Motion.gentle) { app.undo = nil } }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .animation(Motion.gentle, value: app.undo?.id)
    }
}

extension View {
    /// Destinations shared by every tab's navigation stack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .task(let t): TaskView(task: t)
            case .session(let id): SessionDetailView(id: id)
            case .recording(let id): RecordingDetailView(id: id)
            case .allVideos: AllVideosView()
            case .unassigned: UnassignedView()
            case .needsReview: NeedsReviewView()
            case .recentlyDeleted: RecentlyDeletedView()
            }
        }
    }
}
