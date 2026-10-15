// RodentLimbApp.swift — entry point. Changing the language preference rebuilds the view tree
// (`.id`) so every L(...) string updates immediately, without relaunching.

import SwiftUI

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

enum AppTab: Hashable { case home, library, settings }

struct NewSessionRequest: Identifiable {
    let id = UUID()
    var assay: Assay
}

enum SettingsKey {
    static let boxThreshold = "rl.boxThreshold"
    static let renderSkeleton = "rl.renderSkeleton"
    static let lastAssay = "rl.lastAssay"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var newSession: NewSessionRequest?
    @Published var homePath: [UUID] = []
    @Published var libraryPath: [UUID] = []

    let store: SessionStore
    let engine: PoseEngine
    let queue: ProcessingQueue

    init() {
        let store = SessionStore()
        let engine = PoseEngine()
        self.store = store
        self.engine = engine
        queue = ProcessingQueue(store: store, engine: engine)
        queue.renderSkeleton = {
            let d = UserDefaults.standard
            var s = InferenceSettings()
            if d.object(forKey: SettingsKey.boxThreshold) != nil { s.boxThreshold = d.double(forKey: SettingsKey.boxThreshold) }
            s.renderSkeletonVideo = d.bool(forKey: SettingsKey.renderSkeleton)
            return s
        }
        engine.checkInstalled()
    }

    var lastAssay: Assay {
        Assay(rawValue: UserDefaults.standard.string(forKey: SettingsKey.lastAssay) ?? "") ?? .tailSuspension
    }

    func startNew(_ assay: Assay? = nil) {
        newSession = NewSessionRequest(assay: assay ?? lastAssay)
    }

    /// Opens a session in the tab the user is on (Home if coming from elsewhere).
    func open(_ id: UUID) {
        switch tab {
        case .library:
            libraryPath.append(id)
        default:
            tab = .home
            homePath.append(id)
        }
    }
}
