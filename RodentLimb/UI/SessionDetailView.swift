// SessionDetailView.swift — one session. While tracking runs it shows progress; afterwards
// three tabs keep the screen calm (progressive disclosure):
//   Summary  — the 2–4 numbers that matter, notes, one chart
//   Review   — video with live keypoints + the events behind the numbers
//   Measures — every measure, grouped, and the detailed charts
// Parameters and Export sit in a bottom bar (Liquid Glass on iOS 26).

import SwiftUI
import Combine

/// Low-rate clock (≈4 Hz) for views that only need to know roughly where playback is, so charts
/// are not redrawn at video frame rate.
@MainActor
final class CoarseClock: ObservableObject {
    @Published var time: Double = 0
}

enum DetailTab: String, CaseIterable, Identifiable {
    case summary, review, measures
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return L("Summary", "概览")
        case .review: return L("Review", "回放")
        case .measures: return L("Measures", "全部指标")
        }
    }
}

@MainActor
struct SessionDetailView: View {
    let id: UUID

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @Environment(\.dismiss) private var dismiss

    @State private var track: PoseTrack?
    @State private var controller: PlayerController?
    // @State, not @StateObject: this screen must NOT redraw when the clock ticks; only the
    // small SummaryClockHost views observe it.
    @State private var clock = CoarseClock()
    @State private var tab: DetailTab = .summary
    @State private var sheet: DetailSheet?
    @State private var share: SharePayload?
    @State private var confirmDelete = false
    @State private var toast: String?

    enum DetailSheet: String, Identifiable {
        case params, calibration, info, export
        var id: String { rawValue }
    }

    private var session: Session? { store.session(id) }

    var body: some View {
        Group {
            if let s = session {
                content(s)
            } else {
                ContentUnavailableView(L("Session deleted", "该记录已删除"), systemImage: "trash")
            }
        }
        .background(Palette.canvas)
        .navigationTitle(session?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $sheet) { which in sheetContent(which).fontDesign(.rounded) }
        .sheet(item: $share) { ShareSheet(items: $0.items) }
        .confirmationDialog(L("Delete this session and its files?", "删除该记录及其文件？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete", "删除"), role: .destructive) {
                controller?.teardown()
                if queue.currentID == id { queue.cancelCurrent() }
                store.delete([id])
                dismiss()
            }
        }
        .toast($toast)
        .task(id: session?.hasPose) { await loadPose() }
        .onChange(of: tab) { _, new in if new != .review, controller?.isPlaying == true { controller?.pause() } }
        .onDisappear { controller?.teardown() }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ s: Session) -> some View {
        let result = s.hasPose ? store.results[id] : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(s)
                statusBlock(s)
                if let r = result {
                    Picker(L("View", "视图"), selection: $tab) {
                        ForEach(DetailTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch tab {
                    case .summary: summary(s, r)
                    case .review: review(s, r)
                    case .measures: measures(s, r)
                    }
                }
            }
            .screenContent()
            .padding(.vertical, 12)
        }
        .chromeBar(.bottom) {
            if result != nil { bottomBar(s) }
        }
    }

    private func header(_ s: Session) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AssayBadge(assay: s.assay, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.displayName).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text([s.assay.name.text, s.group, Fmt.date(s.createdAt)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private func summary(_ s: Session, _ r: AnalysisResult) -> some View {
        HeroMetrics(metrics: r.metrics.filter { $0.highlight }, tint: Palette.assay(s.assay))
        NoteList(notes: r.notes)
        if let d = r.tst {
            TSTMotionCard(detail: d) { t in goReview(t) }
        }
        if let d = r.cylinder {
            CylinderUseCard(detail: d)
        }
        if let d = r.gait {
            SummaryClockHost(clock: clock) { time in
                FootfallCard(detail: d, currentTime: time)
            }
            if let p = d.patterns { GaitPatternCard(patterns: p) }
        }
    }

    @ViewBuilder
    private func review(_ s: Session, _ r: AnalysisResult) -> some View {
        if let c = controller, let t = track {
            ReviewPlayer(controller: c, session: s, track: t, result: r)
                .onReceive(c.$time.throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)) { clock.time = $0 }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
        if let d = r.cylinder {
            SummaryClockHost(clock: clock) { time in
                CylinderEventList(detail: d, currentTime: time, seek: { controller?.seek($0) }, relabel: relabel)
            }
        }
        if let d = r.gait {
            SummaryClockHost(clock: clock) { time in
                FootfallCard(detail: d, currentTime: time, follow: true)
            }
        }
        if let d = r.tst {
            TSTMotionCard(detail: d) { t in controller?.seek(t) }
        }
    }

    @ViewBuilder
    private func measures(_ s: Session, _ r: AnalysisResult) -> some View {
        MeasureList(metrics: r.metrics)
        if let d = r.tst { TSTPerMinuteCard(detail: d) }
        if let d = r.cylinder { CylinderTimelineCard(detail: d) }
        if let d = r.gait {
            PawTableCard(detail: d)
            PhaseCard(detail: d)
            FootprintCard(detail: d, videoSize: CGSize(width: track?.width ?? 1, height: track?.height ?? 1))
        }
        Text(String(format: L("Model %@ (%@) · %@ fps · analyzed %@", "模型 %@（%@）· %@ fps · 分析于 %@"),
                    kPoseModelName, s.modelVersion ?? "—", Fmt.num(s.fps, 1), Fmt.date(r.analyzedAt)))
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func bottomBar(_ s: Session) -> some View {
        HStack(spacing: 10) {
            Button { sheet = .params } label: { Label(L("Parameters", "参数"), systemImage: "slider.horizontal.3") }
                .buttonStyle(SecondaryButtonStyle())
            if s.assay != .tailSuspension {
                Button { sheet = .calibration } label: { Label(L("Calibrate", "标定"), systemImage: "scope") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button { sheet = .export } label: { Label(L("Export", "导出"), systemImage: "square.and.arrow.up") }
                .buttonStyle(SecondaryButtonStyle())
        }
        .labelStyle(CompactLabelStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func goReview(_ t: Double) {
        tab = .review
        controller?.seek(t)
    }

    private func relabel(_ eid: Int, _ label: PawLabel?) {
        store.update(id) { $0.overrides[eid] = label }
        store.analyze(id)
    }

    @ViewBuilder
    private func statusBlock(_ s: Session) -> some View {
        switch s.status {
        case .queued, .processing:
            let running = queue.currentID == s.id
            Card {
                HStack(spacing: 16) {
                    LiveProgress(progress: queue.progress) { p in
                        ZStack {
                            ProgressRing(fraction: running ? p.fraction : 0)
                            if running {
                                Text(String(format: "%.0f%%", p.fraction * 100)).font(.headline.monospacedDigit())
                            } else {
                                Image(systemName: "clock").font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 72, height: 72)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(running ? L("Tracking every frame", "正在逐帧识别") : L("Waiting in queue", "排队等待中"))
                            .font(.headline)
                        if running {
                            LiveProgress(progress: queue.progress) { p in
                                Text(Fmt.remaining(p.secondsLeft)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Text(L("Keep the app open; it pauses in the background and resumes by itself.",
                               "请保持 App 在前台；切到后台会暂停，回来后自动继续。"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    if s.assay == .cylinder && !s.isCalibrated {
                        Button { sheet = .calibration } label: { Label(L("Calibrate now", "先做标定"), systemImage: "scope") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    if running {
                        Button(L("Cancel", "取消"), role: .destructive) { queue.cancelCurrent() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        case .failed:
            VStack(spacing: 10) {
                Banner(text: s.failure ?? L("Tracking failed.", "识别失败。"), level: .error)
                Button { queue.retry(s.id) } label: { Label(L("Try again", "重试"), systemImage: "arrow.clockwise") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .needsSetup:
            Card {
                CardHeader(L("One step left: calibration", "还差一步：标定"), symbol: "scope",
                           subtitle: s.params.cylinder.view == .bottom
                           ? L("Drag the circle onto the cylinder rim so wall contacts can be found.", "拖动圆圈与圆筒边缘重合，以便检测触壁。")
                           : L("Drag the line onto the floor of the cylinder.", "拖动横线到圆筒底面。"))
                Button { sheet = .calibration } label: { Text(L("Calibrate", "开始标定")).frame(maxWidth: .infinity) }
                    .primaryAction(Palette.assayFill(s.assay))
            }
        case .done:
            if let from = s.calibration.copiedFrom, s.assay != .tailSuspension {
                Button { sheet = .calibration } label: {
                    Banner(text: String(format: L("Calibration reused from %@ — tap to check.", "标定沿用自 %@，轻点检查。"), from))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Toolbar & sheets

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .info } label: { Label(L("Edit subject info", "编辑动物信息"), systemImage: "pencil") }
                if session?.hasPose == true {
                    Button {
                        controller?.teardown(); controller = nil; track = nil
                        store.update(id) { $0.hasPose = false }
                        queue.retry(id)
                    } label: { Label(L("Re-run tracking", "重新识别"), systemImage: "arrow.clockwise") }
                }
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: { Label(L("Delete", "删除"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(L("More", "更多"))
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: DetailSheet) -> some View {
        if let s = session {
            switch which {
            case .params:
                ParamsSheet(sessionID: s.id)
                    .environmentObject(store)
            case .calibration:
                CalibrationView(sessionID: s.id, track: track)
                    .environmentObject(store)
            case .info:
                EditInfoSheet(sessionID: s.id)
                    .environmentObject(store)
            case .export:
                ExportSheet(session: s, track: track) { urls in
                    sheet = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        share = SharePayload(items: urls)
                    }
                }
                .environmentObject(store)
                .presentationDetents([.medium])
            }
        }
    }

    private func loadPose() async {
        guard let s = session, s.hasPose else { return }
        if track == nil { track = await store.pose(id) }
        if controller == nil, let t = track {
            controller = PlayerController(url: store.videoURL(s), fps: t.fps, offset: t.timeOffset ?? 0)
        }
        // Recompute results made by an older analyzer version.
        if let r = store.loadResult(id), (r.version ?? 0) >= AnalysisResult.currentVersion { return }
        store.analyze(id)
    }
}

/// Re-renders only its content when the coarse playback clock ticks.
@MainActor
struct SummaryClockHost<Content: View>: View {
    @ObservedObject var clock: CoarseClock
    @ViewBuilder var content: (Double) -> Content
    var body: some View { content(clock.time) }
}

/// Icon above a short title, for compact bottom-bar buttons.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title.lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Edit info

@MainActor
struct EditInfoSheet: View {
    let sessionID: UUID
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var group = ""
    @State private var notes = ""
    @FocusState private var focus: Int?

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Subject ID", "动物编号"), text: $subject)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: 0).submitLabel(.next).onSubmit { focus = 1 }
                TextField(L("Group", "组别"), text: $group)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: 1).submitLabel(.next).onSubmit { focus = 2 }
                TextField(L("Notes", "备注"), text: $notes, axis: .vertical).lineLimit(2...6)
                    .focused($focus, equals: 2)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Subject info", "动物信息"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "保存")) {
                        store.update(sessionID) {
                            $0.subject = subject.trimmingCharacters(in: .whitespaces)
                            $0.group = group.trimmingCharacters(in: .whitespaces)
                            $0.notes = notes
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let s = store.session(sessionID) { subject = s.subject; group = s.group; notes = s.notes }
                focus = 0
            }
        }
    }
}

// MARK: - Export

@MainActor
struct ExportSheet: View {
    let session: Session
    let track: PoseTrack?
    let done: ([URL]) -> Void
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var includePose = true
    @State private var includeVideo = true
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(L("Summary, events and methods text (CSV / TXT, English)", "汇总、事件与方法描述（CSV / TXT，英文）"), systemImage: "doc.text")
                    Toggle(L("Frame-by-frame pose CSV", "逐帧姿态 CSV"), isOn: $includePose)
                    if session.hasSkeletonVideo {
                        Toggle(L("Skeleton video (MP4)", "骨架视频（MP4）"), isOn: $includeVideo)
                    }
                } footer: {
                    Text(L("Exports are always in English so they can go straight into analysis scripts and papers.", "导出文件始终为英文，可直接用于分析脚本和论文。"))
                }
            }
            .navigationTitle(L("Export", "导出"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button(L("Share", "分享")) { export() }
                    }
                }
            }
        }
    }

    private func export() {
        guard let r = store.loadResult(session.id) else { return }
        working = true
        let s = session, t = track, pose = includePose, video = includeVideo
        Task { @MainActor in
            var urls = Exporter.sessionFiles(s, result: r, track: t, store: store, includePose: false, includeVideo: video)
            if pose, let t, let u = await Exporter.poseFile(s, track: t, nextTo: urls.first) { urls.append(u) }
            working = false
            done(urls)
        }
    }
}
