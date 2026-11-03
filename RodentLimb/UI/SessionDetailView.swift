// SessionDetailView.swift — one session of a task (one video of one animal, at one timepoint and
// trial). While tracking runs it shows progress; afterwards three tabs keep the screen calm
// (progressive disclosure). Behavior assays (itch, pain, grooming, seizure) share the cards in
// BehaviorCards.swift.
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

    @EnvironmentObject private var app: AppModel
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
    /// The session has a pose but its file could not be read.
    @State private var poseUnreadable = false

    enum DetailSheet: String, Identifiable {
        case params, calibration, info, export
        var id: String { rawValue }
    }

    private var session: Session? { store.session(id) }

    /// The session has a pose but its result is not in memory (yet, or any more).
    private var resultMissing: Bool { session?.hasPose == true && store.results[id] == nil }

    var body: some View {
        Group {
            if let s = session {
                content(s)
            } else {
                ContentUnavailableView {
                    Text(L("Session deleted", "该实验已删除"))
                } description: {
                    Text(L("It can be restored from Settings › Recently Deleted.", "可在“设置 › 最近删除”中恢复。"))
                }
            }
        }
        .background(Palette.canvas)
        .navigationTitle(session?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $sheet) { which in sheetContent(which) }
        .sheet(item: $share) { ShareSheet(items: $0.items) }
        .confirmationDialog(L("Delete this session?", "删除该实验？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Remove from task, keep the video", "从任务中移除，保留视频")) {
                controller?.teardown()
                if let s = session, let rid = s.recordingID, let t = store.task(for: s) {
                    app.moved(store.removeFromTask([rid], task: t), L("Removed from the task", "已从任务中移除"))
                } else {
                    app.deleted(store.delete([id]), L("Session deleted", "实验已删除"))
                }
                dismiss()
            }
            if let rid = session?.recordingID {
                Button(L("Delete session and video", "删除实验和视频"), role: .destructive) {
                    controller?.teardown()
                    if queue.currentID == rid { queue.cancelCurrent() }
                    app.deleted(store.deleteRecordings([rid]), L("Session and video deleted", "实验和视频已删除"))
                    dismiss()
                }
            }
        } message: {
            Text(L("Deleted items stay in Recently Deleted for 30 days.", "删除的项目会在“最近删除”中保留 30 天。"))
        }
        .toast($toast)
        .task(id: session?.hasPose) { await loadPose() }
        .onChange(of: resultMissing) { _, missing in
            // The cached result was dropped (memory warning): reload it from disk.
            if missing { Task { _ = await store.result(id) } }
        }
        .onChange(of: tab) { _, new in if new != .review, controller?.isPlaying == true { controller?.pause() } }
        // Only pause: this also runs when another tab is selected, and the same controller is used
        // again when the user comes back.
        .onDisappear { controller?.pause() }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ s: Session) -> some View {
        let result = s.hasPose ? store.results[id] : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(s)
                if let rec = store.recording(for: s) { videoLink(rec) }
                statusBlock(s)
                if poseUnreadable && s.hasPose {
                    Banner(text: L("The pose data of this video could not be read. Use More › Track again.",
                                   "无法读取该视频的姿态数据，请通过“更多 › 重新识别”再次运行。"), level: .error)
                }
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
        let rec = store.recording(for: s)
        let line = [s.group, rec.map { store.sessionLine($0) } ?? Fmt.date(s.createdAt)].filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            Text(s.displayName).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(line.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 8) {
                AssayChip(assay: s.assay)
                if let t = store.task(for: s) {
                    Button { app.openTask(t) } label: {
                        Text(store.taskName(t)).font(.footnote.weight(.semibold)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityHint(L("Opens the task", "打开该任务"))
                }
            }
        }
    }

    /// The video this analysis was made from: QC verdict and inclusion decision, tap for details.
    private func videoLink(_ r: Recording) -> some View {
        Button { app.openRecording(r.id) } label: {
            HStack(spacing: 8) {
                Text(L("Video and quality", "视频与质量")).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if let qc = r.qc { QCBadge(verdict: qc.verdict, compact: true) }
                if r.isProcessed { DecisionTag(decision: r.decision) }
                Spacer(minLength: 4)
                Text(L("Open", "打开")).font(.footnote.weight(.semibold)).foregroundStyle(.tint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("Opens the video, its tracking quality and inclusion decision", "打开视频、识别质量和纳入决定"))
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
        if let d = r.behavior {
            BehaviorEthogramCard(detail: d) { t in goReview(t) }
            BehaviorTimeCourseCard(detail: d, tint: Palette.assay(s.assay))
            if s.assay == .grooming {
                BehaviorCompositionCard(detail: d, title: L("Grooming by body region", "各身体部位理毛时间"))
            }
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
        if let d = r.behavior {
            BehaviorEthogramCard(detail: d, clock: clock) { controller?.seek($0) }
            SummaryClockHost(clock: clock) { time in
                BehaviorEventList(detail: d, currentTime: time, seek: { controller?.seek($0) }, relabel: relabelEvent)
            }
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
        if let d = r.behavior {
            BehaviorTimeCourseCard(detail: d, tint: Palette.assay(s.assay))
            if s.assay != .seizure {
                BehaviorCompositionCard(detail: d, title: L("Time per behavior (analysis window)", "各行为时间（分析窗口内）"))
            }
            BehaviorSignalCard(detail: d) { goReview($0) }
        }
        Text(String(format: L("Model %@ (%@) · %@ fps · analyzed %@", "模型 %@（%@）· %@ fps · 分析于 %@"),
                    (s.recordingID.map { store.poseModel($0) } ?? .visible).displayName, s.modelVersion ?? "—",
                    Fmt.num(s.fps, 1), Fmt.date(r.analyzedAt)))
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func bottomBar(_ s: Session) -> some View {
        HStack(spacing: 10) {
            Button(L("Parameters", "参数")) { sheet = .params }
                .buttonStyle(SecondaryButtonStyle())
            if s.assay != .tailSuspension && !s.assay.isBehavior {
                Button(L("Calibrate", "标定")) { sheet = .calibration }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button(L("Export", "导出")) { sheet = .export }
                .buttonStyle(SecondaryButtonStyle())
        }
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

    /// Behavior assays: store the reviewer's label (nil = back to the automatic call) and re-analyze.
    private func relabelEvent(_ eid: Int, _ key: String?) {
        store.update(id) {
            var o = $0.eventOverrides ?? [:]
            o[eid] = key
            $0.eventOverrides = o.isEmpty ? nil : o
        }
        store.analyze(id)
    }

    @ViewBuilder
    private func statusBlock(_ s: Session) -> some View {
        switch s.status {
        case .queued, .processing:
            let running = queue.currentID != nil && queue.currentID == s.recordingID
            Card {
                HStack(spacing: 16) {
                    LiveProgress(progress: queue.progress) { p in
                        ZStack {
                            ProgressRing(fraction: running ? p.fraction : 0)
                            Text(running ? String(format: "%.0f%%", p.fraction * 100) : "–").font(.headline.monospacedDigit())
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
                        Text(L("Keep the app open. If you leave it, detection pauses and continues from the same frame when you come back.",
                               "请保持 App 在前台；离开时会暂停，回来后从中断的那一帧继续。"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    if s.assay == .cylinder && !s.isCalibrated {
                        Button(L("Calibrate now", "先做标定")) { sheet = .calibration }
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
                Button(L("Try again", "重试")) { queue.retry(recording: s.recordingID ?? s.id) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .needsSetup:
            Card {
                CardHeader(L("One step left: calibration", "还差一步：标定"),
                           subtitle: s.params.cylinder.view == .bottom
                           ? L("Drag the circle onto the cylinder rim so wall contacts can be found.", "拖动圆圈与圆筒边缘重合，以便检测触壁。")
                           : L("Drag the line onto the floor of the cylinder.", "拖动横线到圆筒底面。"))
                Button { sheet = .calibration } label: { Text(L("Calibrate", "开始标定")).frame(maxWidth: .infinity) }
                    .primaryAction(Palette.assayFill(s.assay))
            }
        case .done:
            if let from = s.calibration.copiedFrom, s.assay != .tailSuspension && !s.assay.isBehavior {
                Button { sheet = .calibration } label: {
                    Banner(text: String(format: L("Calibration reused from %@ of this task. Tap to check.", "标定沿用自本任务的 %@，轻点检查。"), from))
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
                if let rid = session?.recordingID {
                    Button(L("Video and quality check", "视频与质量检查")) { app.openRecording(rid) }
                }
                Button(L("Edit video information", "编辑视频信息")) { sheet = .info }
                if session?.hasPose == true || session?.status == .failed {
                    Menu(L("Track again", "重新识别")) {
                        ForEach(PoseModelID.choices) { m in
                            Button(m.shortTitle.text) {
                                controller?.teardown(); controller = nil; track = nil; poseUnreadable = false
                                queue.retry(recording: session?.recordingID ?? id, model: m)
                            }
                        }
                    }
                }
                Divider()
                Button(L("Delete session…", "删除实验…"), role: .destructive) { confirmDelete = true }
            } label: {
                Text(L("More", "更多"))
            }
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
                if let rid = s.recordingID {
                    RecordingInfoSheet(recordingID: rid)
                        .environmentObject(store)
                } else {
                    EditInfoSheet(sessionID: s.id)
                        .environmentObject(store)
                }
            case .export:
                ExportSheet(session: s, track: track) { urls in
                    sheet = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        share = SharePayload(items: urls)
                    }
                }
                .environmentObject(store)
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func loadPose() async {
        guard let s = session, s.hasPose else { return }
        // Result first (small) so the Summary appears quickly; the track is needed for Review.
        let stored = await store.result(id)
        // Always reloaded (cheap: cached): tracking may have been re-run from the video's screen.
        if let fresh = await store.pose(id) { track = fresh }
        guard session?.hasPose == true else { return }
        poseUnreadable = track == nil
        if controller == nil, let t = track {
            controller = PlayerController(url: store.videoURL(s), fps: t.fps, offset: t.timeOffset ?? 0)
        }
        // Recompute results made by an older analyzer version.
        if let r = stored, (r.version ?? 0) >= AnalysisResult.currentVersion { return }
        if track != nil { store.analyze(id) }
    }
}

/// Re-renders only its content when the coarse playback clock ticks.
@MainActor
struct SummaryClockHost<Content: View>: View {
    @ObservedObject var clock: CoarseClock
    @ViewBuilder var content: (Double) -> Content
    var body: some View { content(clock.time) }
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
                    Text(L("Summary, events and methods text (CSV / TXT, English)", "汇总、事件与方法描述（CSV / TXT，英文）"))
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
        guard !working else { return }
        working = true
        let s = session, pose = includePose, video = includeVideo
        let skeleton = store.skeletonURL(s.recordingID ?? s.id)
        Task { @MainActor in
            guard let r = await store.result(s.id) else { working = false; return }
            let design = store.exportRow(s, result: r)
            // The pose track may not have been loaded by the screen yet.
            var t = track
            if pose, t == nil { t = await store.pose(s.id) }
            // Files are built off the main thread (the skeleton video copy alone can take seconds).
            let model = s.recordingID.map { store.poseModel($0) } ?? .visible
            var urls = await Task.detached(priority: .userInitiated) { () -> [URL] in
                let files = Exporter.sessionFiles(s, result: r, track: nil, skeletonURL: skeleton, includePose: false, includeVideo: video, design: design)
                // The shared exporter names CylinderMousePoseV2: name the model that tracked this video.
                ExportFixes.apply(to: files, model: model, threshold: s.params.common.keypointThreshold)
                return files
            }.value
            if pose, let t, let u = await Exporter.poseFile(s, track: t, nextTo: urls.first) { urls.append(u) }
            working = false
            done(urls)
        }
    }
}
