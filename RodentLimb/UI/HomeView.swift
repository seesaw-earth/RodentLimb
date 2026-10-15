// HomeView.swift — one clear call to action, the three assays, what needs attention, recent
// results. Everything else lives one tap deeper.

import SwiftUI

@MainActor
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var engine: PoseEngine
    @EnvironmentObject private var queue: ProcessingQueue

    private var attention: [Session] {
        store.sessions.filter { $0.status == .needsSetup || $0.status == .failed }
    }
    private var recent: [Session] { Array(store.sessions.filter { $0.status == .done }.prefix(5)) }

    var body: some View {
        NavigationStack(path: $app.homePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    hero
                    modelBanner
                    QueueCard()
                    assayRow
                    if !attention.isEmpty { attentionSection }
                    recentSection
                }
                .screenContent()
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(Palette.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { SessionDetailView(id: $0) }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                AppMark(size: 64)
                    .overlay(RoundedRectangle(cornerRadius: 64 * 0.23, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("RodentLimb").font(.title.weight(.bold)).foregroundStyle(.white)
                    Text(L("Limb pose & motor behavior", "肢体姿态 · 运动行为分析"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            Button {
                app.startNew()
            } label: {
                Label(L("New analysis", "新建分析"), systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Color(uiColor: UIColor(hex: 0x1F5BEF)))
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
        }
        .padding(18)
        .background(Palette.brandGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(uiColor: UIColor(hex: 0x1F5BEF)).opacity(0.22), radius: 18, y: 8)
    }

    @ViewBuilder
    private var modelBanner: some View {
        switch engine.state {
        case .missing:
            Banner(text: L("The V2 pose model isn't installed yet. On your Mac run Tools/install_model.py, then rebuild.",
                           "尚未安装 V2 姿态模型。请在 Mac 上运行 Tools/install_model.py 后重新编译。"),
                   level: .error)
        case .failed(let msg):
            Banner(text: L("The pose model could not be loaded: ", "姿态模型无法加载：") + msg, level: .error)
        default:
            EmptyView()
        }
    }

    // MARK: Assays

    private var assayRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: L("Assays", "实验范式"))
            HStack(spacing: 10) {
                ForEach(Assay.allCases) { a in
                    Button { app.startNew(a) } label: { AssayTile(assay: a) }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityHint(L("Start a new analysis with this assay", "用该范式新建分析"))
                }
            }
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: L("To finish", "待完成"))
            ForEach(attention.prefix(4)) { s in
                Button { app.open(s.id) } label: { SessionRow(session: s) }.buttonStyle(.plain)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: L("Recent", "最近结果"), actionTitle: recent.isEmpty ? nil : L("See all", "全部")) {
                app.tab = .library
            }
            if recent.isEmpty {
                EmptyState(title: L("No results yet", "还没有结果"),
                           message: L("Tap New analysis and pick one or more videos. Everything stays on this iPhone.",
                                      "点“新建分析”，选择一个或多个视频。所有数据都保存在本机。"))
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                ForEach(recent) { s in
                    Button { app.open(s.id) } label: { SessionRow(session: s) }.buttonStyle(.plain)
                }
            }
        }
    }
}

@MainActor
struct AssayTile: View {
    let assay: Assay
    var body: some View {
        VStack(spacing: 10) {
            AssayBadge(assay: assay, size: 46)
            Text(assay.name.text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .padding(.horizontal, 6)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Running inference, shown on Home.
@MainActor
struct QueueCard: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @EnvironmentObject private var app: AppModel

    var body: some View {
        if let id = queue.currentID, let s = store.session(id) {
            Button { app.open(id) } label: {
                HStack(spacing: 14) {
                    LiveProgress(progress: queue.progress) { p in
                        ZStack {
                            ProgressRing(fraction: p.fraction, lineWidth: 6)
                            Text(String(format: "%.0f", p.fraction * 100)).font(.caption.weight(.bold)).monospacedDigit()
                        }
                        .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: L("Tracking %@", "正在识别 %@"), s.displayName)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        LiveProgress(progress: queue.progress) { p in
                            Text(detail(p)).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
        } else if queue.pausedForBackground {
            Banner(text: L("Tracking paused while RodentLimb was in the background. It resumes by itself.",
                           "RodentLimb 在后台时暂停了识别，回到前台后会自动继续。"))
        }
    }

    private func detail(_ p: ProgressInfo) -> String {
        var parts: [String] = [Fmt.remaining(p.secondsLeft)]
        let waiting = store.sessions.filter { $0.status == .queued }.count
        if waiting > 0 { parts.append(String(format: L("%d waiting", "还有 %d 个"), waiting)) }
        return parts.joined(separator: " · ")
    }
}
