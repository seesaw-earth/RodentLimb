// RootView.swift — tabs (Home · Data · Settings), first-launch onboarding, new-analysis sheet.

import SwiftUI

@MainActor
struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var queue: ProcessingQueue
    @EnvironmentObject private var engine: PoseEngine
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("rl.onboarded") private var onboarded = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $app.tab) {
            HomeView()
                .tabItem { Label(L("Home", "首页"), systemImage: "house.fill") }
                .tag(AppTab.home)
            LibraryView()
                .tabItem { Label(L("Data", "数据"), systemImage: "tray.full.fill") }
                .tag(AppTab.library)
            SettingsView()
                .tabItem { Label(L("Settings", "设置"), systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .minimizingTabBar()
        .fontDesign(.rounded)
        .sheet(item: $app.newSession) { req in
            NewSessionSheet(initialAssay: req.assay)
                .environmentObject(app)
                .environmentObject(app.store)
                .environmentObject(app.queue)
                .fontDesign(.rounded)
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { onboarded = true }) {
            OnboardingView().fontDesign(.rounded)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.store.flush() }
            queue.scenePhaseChanged(phase)
        }
        .task {
            if !onboarded { showOnboarding = true }
            queue.kick()
            if engine.isInstalled, engine.state == .notLoaded { _ = await engine.load() }
        }
    }
}

/// One row used in Home and Data lists. `card` adds its own background (Home); in a List the
/// system provides the cell.
@MainActor
struct SessionRow: View {
    let session: Session
    var card = true
    @EnvironmentObject private var queue: ProcessingQueue

    var body: some View {
        HStack(spacing: 12) {
            AssayBadge(assay: session.assay, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    if !session.group.isEmpty {
                        Text(session.group).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                statusLine
            }
            Spacer(minLength: 4)
            if card {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, card ? 12 : 2)
        .padding(.horizontal, card ? 14 : 0)
        .background {
            if card { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch session.status {
        case .done:
            if let m = session.summary.first {
                HStack(spacing: 4) {
                    Text(m.label.text).foregroundStyle(.secondary)
                    Text(m.formatted + (m.unit.isEmpty ? "" : " " + m.unit)).monospacedDigit().foregroundStyle(.primary)
                    if session.worstNote == .warning || session.worstNote == .error {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                            .accessibilityLabel(L("Has warnings", "有警告"))
                    }
                }
                .font(.footnote)
                .lineLimit(1)
            } else {
                Label(session.status.title, systemImage: session.status.symbol).font(.footnote).foregroundStyle(Palette.success)
            }
        case .processing:
            LiveProgress(progress: queue.progress) { p in
                let f = queue.currentID == session.id ? p.fraction : 0
                HStack(spacing: 6) {
                    ProgressView(value: f).frame(maxWidth: 90)
                    Text(String(format: "%.0f%%", f * 100)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        case .needsSetup:
            Label(session.status.title, systemImage: session.status.symbol).font(.footnote).foregroundStyle(Palette.warning)
        case .failed:
            Label(session.status.title, systemImage: session.status.symbol).font(.footnote).foregroundStyle(Palette.danger)
        case .queued:
            Label(session.status.title, systemImage: session.status.symbol).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
