// RecordingViews.swift — one video: tracking status (and the pose model), the QC report with the
// video and keypoints, the include / exclude decision, and the task(s) it belongs to.

import SwiftUI

// MARK: - Row

@MainActor
struct RecordingRow: View {
    let recording: Recording
    var card = true
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.displayName(recording)).font(.body.weight(.semibold)).lineLimit(1)
                    let g = store.groupLabel(recording)
                    if !g.isEmpty {
                        Text(g).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                statusLine
            }
            Spacer(minLength: 4)
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
        switch recording.status {
        case .queued:
            Text(recording.status.title).font(.footnote).foregroundStyle(.secondary)
        case .processing:
            LiveProgress(progress: queue.progress) { p in
                let f = queue.currentID == recording.id ? p.fraction : 0
                HStack(spacing: 6) {
                    ProgressView(value: f).frame(maxWidth: 90)
                    Text(String(format: "%.0f%%", f * 100)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        case .failed:
            Text(recording.failure ?? recording.status.title)
                .font(.footnote).foregroundStyle(Palette.danger).lineLimit(1)
        case .ready:
            HStack(spacing: 8) {
                if let qc = recording.qc {
                    QCBadge(verdict: qc.verdict, compact: true)
                } else {
                    Text(L("QC…", "QC…")).font(.footnote).foregroundStyle(.secondary)
                }
                DecisionTag(decision: recording.decision)
            }
            .lineLimit(1)
        }
    }
}

@MainActor
struct QCBadge: View {
    let verdict: QCVerdict
    var compact = false

    static func color(_ v: QCVerdict) -> Color {
        switch v {
        case .pass: return Palette.success
        case .warn: return Palette.warning
        case .fail: return Palette.danger
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Self.color(verdict)).frame(width: compact ? 7 : 9, height: compact ? 7 : 9).accessibilityHidden(true)
            Text(verdict.label.text)
        }
        .font(compact ? Font.footnote.weight(.medium) : Font.subheadline.weight(.semibold))
        .foregroundStyle(Self.color(verdict))
    }
}

@MainActor
struct DecisionTag: View {
    let decision: InclusionDecision
    var body: some View {
        switch decision {
        case .included: Tag(text: decision.label, color: Palette.success)
        case .excluded: Tag(text: decision.label, color: Palette.danger)
        case .pending: Tag(text: decision.label, color: Palette.warning)
        }
    }
}

// MARK: - Detail

@MainActor
struct RecordingDetailView: View {
    let id: UUID

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var track: PoseTrack?
    @State private var controller: PlayerController?
    @State private var sheet: RecordingSheet?
    @State private var share: SharePayload?
    @State private var confirmDelete = false
    @State private var reason = ""
    @FocusState private var reasonFocused: Bool
    @State private var toast: String?

    enum RecordingSheet: String, Identifiable {
        case info, move
        var id: String { rawValue }
    }

    private var recording: Recording? { store.recording(id) }

    var body: some View {
        Group {
            if let r = recording {
                content(r)
            } else {
                    ContentUnavailableView {
                    Text(L("Video deleted", "该视频已删除"))
                } description: {
                    Text(L("It can be restored from Settings › Recently Deleted.", "可在“设置 › 最近删除”中恢复。"))
                }
            }
        }
        .background(Palette.canvas)
        .navigationTitle(recording.map { store.displayName($0) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $sheet) { which in
            switch which {
            case .info: RecordingInfoSheet(recordingID: id).environmentObject(store)
            case .move: MoveToTaskSheet(recordingIDs: [id], source: store.currentTask(of: id)).environmentObject(store).environmentObject(app)
            }
        }
        .sheet(item: $share) { ShareSheet(items: $0.items) }
        .confirmationDialog(L("Delete this video, its tracking and its sessions?", "删除该视频、其识别结果及其实验？"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete", "删除"), role: .destructive) {
                controller?.teardown()
                if queue.currentID == id { queue.cancelCurrent() }
                app.deleted(store.deleteRecordings([id]), L("Video deleted", "视频已删除"))
                dismiss()
            }
        } message: {
            Text(L("It stays in Recently Deleted for 30 days.", "会在“最近删除”中保留 30 天。"))
        }
        .toast($toast)
        .task(id: recording?.hasPose) { await loadPose() }
        .onAppear { reason = recording?.exclusionReason ?? "" }
        .onDisappear {
            controller?.pause()
            saveReason()
            store.flush()
        }
    }

    private func content(_ r: Recording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(r)
                statusBlock(r)
                if r.isProcessed {
                    if let qc = r.qc {
                        QCSummaryCard(qc: qc)
                    } else {
                        Card {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(L("Checking tracking quality…", "正在检查追踪质量…")).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let c = controller, let t = track {
                        QCPlayer(controller: c, track: t, lost: r.qc?.lostSegments ?? [])
                    }
                    decisionCard(r)
                }
                taskCard(r)
                if r.isProcessed {
                    if let qc = r.qc {
                        QCDetailCard(qc: qc) { exportRefinement(r, qc) }
                    }
                    MissingFramesGuide()
                }
            }
            .screenContent()
            .padding(.vertical, 12)
        }
    }

    private func header(_ r: Recording) -> some View {
        let line = [store.groupLabel(r), Fmt.date(r.recordedOn ?? r.createdAt)].filter { !$0.isEmpty }
        let tasks = store.sessions(of: r.id).compactMap { store.task(for: $0) }
        return VStack(alignment: .leading, spacing: 3) {
            Text(store.displayName(r)).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            ForEach(tasks) { t in
                Button { app.openTask(t) } label: {
                    Text(store.taskName(t)).font(.footnote.weight(.semibold)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint(L("Opens the task", "打开该任务"))
            }
            if !line.isEmpty {
                Text(line.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            // The file name often carries the animal ID, so it is hidden while the study is blinded.
            Text(store.fileLabel(r) + " · " + store.poseModel(r.id).runnable.displayName)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func statusBlock(_ r: Recording) -> some View {
        switch r.status {
        case .queued, .processing:
            let running = queue.currentID == r.id
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
                        Text(running ? L("Tracking every frame", "正在逐帧识别") : L("Waiting in queue", "排队等待中")).font(.headline)
                        if running {
                            LiveProgress(progress: queue.progress) { p in
                                Text(Fmt.remaining(p.secondsLeft)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Text(L("A QC report follows. Keep the app open; if you leave it, tracking pauses and continues from the same frame.",
                               "完成后会生成 QC 报告。请保持 App 在前台；离开时会暂停，回来后从中断的那一帧继续。"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if running {
                    Button(L("Cancel", "取消"), role: .destructive) { queue.cancelCurrent() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        case .failed:
            VStack(spacing: 10) {
                Banner(text: r.failure ?? L("Tracking failed.", "识别失败。"), level: .error)
                Button(L("Try again", "重试")) { queue.retry(recording: r.id) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .ready:
            EmptyView()
        }
    }

    // MARK: Decision

    private func decisionCard(_ r: Recording) -> some View {
        Card {
            CardHeader(L("Include in the analysis?", "是否纳入分析？"),
                       subtitle: L("Decide from the QC report and the video. Exclusions and their reasons are listed in the task exports (ARRIVE 2.0).",
                                   "根据 QC 报告和视频决定。排除的视频及原因会写入任务导出文件（ARRIVE 2.0）。"))
            Picker(L("Decision", "决定"), selection: Binding(get: { r.decision }, set: { new in
                saveReason()
                store.setDecision(id, new, reason: reason)
            })) {
                ForEach(InclusionDecision.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if r.decision == .excluded {
                TextField(L("Reason for exclusion", "排除原因"), text: $reason, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($reasonFocused)
                    // Saved on Return, when the field loses focus and when the screen closes (not on
                    // every keystroke, which re-published the video and its sessions each time).
                    .onSubmit { saveReason() }
                    .onChange(of: reasonFocused) { _, focused in if !focused { saveReason() } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(exclusionReasons, id: \.self) { text in
                            Button(text) { reason = text; saveReason() }
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(reason == text ? Color.accentColor.opacity(0.18) : Palette.inset, in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var exclusionReasons: [String] {
        [L("Poor tracking (failed QC)", "追踪质量差（QC 未通过）"),
         L("Mouse out of view", "小鼠离开画面"),
         L("Video problem", "视频问题"),
         L("Protocol deviation", "操作偏离方案"),
         L("Health / welfare endpoint", "健康 / 福利终点")]
    }

    private func saveReason() {
        guard let r = recording, r.decision == .excluded else { return }
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if text != r.exclusionReason { store.updateRecording(id) { $0.exclusionReason = text } }
    }

    // MARK: Task

    private func taskCard(_ r: Recording) -> some View {
        let sessions = store.sessions(of: r.id)
        let tasks = sessions.compactMap { store.task(for: $0) }
        return Card {
            CardHeader(tasks.isEmpty ? L("Not in a task", "未归入任务") : L("Sessions", "实验"),
                       subtitle: L("The pose is tracked once; the session of its task analyses it with the task's parameters.",
                                   "姿态只识别一次；所属任务的实验用该任务的参数分析。"))
            ForEach(sessions) { s in
                Button { app.open(s.id) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.task(for: s).map { store.taskName($0) } ?? s.assay.name.text).font(.subheadline.weight(.semibold))
                            if let m = s.summary.first {
                                Text(m.label.text + " " + m.formatted + (m.unit.isEmpty ? "" : " " + m.unit))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            } else {
                                StateLabel(state: store.state(of: s))
                            }
                        }
                        Spacer()
                        AssayChip(assay: s.assay)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if r.decision != .included && !sessions.isEmpty {
                Text(L("Sessions of videos that are not included are left out of the group results.",
                       "未纳入视频的实验不计入组结果。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.canMoveOut(r.id) {
                Button(tasks.isEmpty ? L("Move to Task…", "移到任务…") : L("Move to Another Task…", "移到其他任务…")) { sheet = .move }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.tasks.filter { !tasks.contains($0) }.isEmpty)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(L("Edit video information", "编辑视频信息")) { sheet = .info }
                if recording?.hasPose == true || recording?.status == .failed {
                    Menu(L("Track again", "重新识别")) {
                        ForEach(PoseModelID.choices) { m in
                            Button(m.shortTitle.text) {
                                controller?.teardown(); controller = nil; track = nil
                                queue.retry(recording: id, model: m)
                            }
                        }
                    }
                }
                Divider()
                Button(L("Delete video…", "删除视频…"), role: .destructive) { confirmDelete = true }
            } label: {
                Text(L("More", "更多"))
            }
        }
    }

    // MARK: Actions

    private func loadPose() async {
        guard let r = recording, r.hasPose else { return }
        // Always reloaded (cheap: cached): tracking may have been re-run from another screen.
        if let fresh = await store.recordingPose(id) { track = fresh }
        guard recording?.hasPose == true else { return }
        if controller == nil, let t = track {
            controller = PlayerController(url: store.videoURL(r), fps: t.fps, offset: t.timeOffset ?? 0)
        }
    }

    private func exportRefinement(_ r: Recording, _ qc: QCReport) {
        Task { @MainActor in
            var t = track
            if t == nil { t = await store.recordingPose(id) }
            guard let pose = t else { return }
            let name = Exporter.safeName(store.displayName(r)) + "_frames_to_label.csv"
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                let text = QualityControl.refinementCSV(track: pose, report: qc)
                return Exporter.write(text, Exporter.exportDir().appendingPathComponent(name))
            }.value
            if let url { share = SharePayload(items: [url]) } else { toast = L("Nothing to export", "没有可导出的内容") }
        }
    }
}

// MARK: - QC cards

@MainActor
struct QCSummaryCard: View {
    let qc: QCReport

    var body: some View {
        Card {
            HStack {
                QCBadge(verdict: qc.verdict)
                Spacer()
                Text(String(format: "%.0f fps · %@", qc.fps, Fmt.clock(qc.duration)))
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                stat(L("Mouse tracked", "小鼠可用帧"), String(format: "%.0f%%", qc.coreCoverage * 100))
                stat(L("Mouse detected", "检测到小鼠"), String(format: "%.0f%%", qc.detection * 100))
                stat(L("Longest loss", "最长丢失"), String(format: L("%.1f s", "%.1f 秒"), qc.longestLost))
                stat(L("Gaps filled", "可填补缺失"), String(format: "%.0f%%", qc.recoverable * 100))
                stat(L("Implausible jumps", "不合理跳点"), String(format: "%.1f%%", qc.jumpRate * 100))
                stat(L("Body length", "体长"), qc.bodyLength.map { String(format: "%.0f px", $0) } ?? "—")
            }
            QCTimeline(timeline: qc.timeline)
            Text(L("Tracking along the video: green = mouse tracked, orange = partly, red = lost.", "沿视频的追踪情况：绿 = 已追踪，橙 = 部分，红 = 丢失。"))
                .font(.caption).foregroundStyle(.secondary)
            NoteList(notes: qc.issues)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Coverage along the video, one thin bar per bin.
@MainActor
struct QCTimeline: View {
    let timeline: [Double]

    var body: some View {
        Canvas { ctx, size in
            let n = timeline.count
            guard n > 0 else { return }
            let w = size.width / CGFloat(n)
            for (i, v) in timeline.enumerated() {
                let f = max(0, min(1, v.isFinite ? v : 0))
                let color = f >= 0.9 ? Palette.success : f >= 0.5 ? Palette.warning : Palette.danger
                let rect = CGRect(x: CGFloat(i) * w, y: 0, width: max(1, w + 0.5), height: size.height)
                ctx.fill(Path(rect), with: .color(color.opacity(0.35 + 0.65 * (f >= 0.9 ? 1 : 1 - f))))
            }
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel(L("Tracking timeline", "追踪时间轴"))
    }
}

@MainActor
struct QCDetailCard: View {
    let qc: QCReport
    let exportFrames: () -> Void

    var body: some View {
        Card {
            CardHeader(L("Keypoint coverage", "各关键点覆盖率"),
                       subtitle: L("Light bar: tracked by the model. Dark bar: after filling short gaps.", "浅色：模型识别到的帧；深色：填补短缺口之后。"))
            ForEach(Kp.allCases) { k in
                let raw = k.rawValue < qc.rawCoverage.count ? qc.rawCoverage[k.rawValue] : 0
                let filled = k.rawValue < qc.filledCoverage.count ? qc.filledCoverage[k.rawValue] : 0
                HStack(spacing: 8) {
                    Circle().fill(KeypointColors.color(k)).frame(width: 8, height: 8)
                    Text(k.label.text).font(.footnote).frame(width: 92, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.inset)
                            Capsule().fill(KeypointColors.color(k).opacity(0.35)).frame(width: geo.size.width * CGFloat(max(0, min(1, filled))))
                            Capsule().fill(KeypointColors.color(k)).frame(width: geo.size.width * CGFloat(max(0, min(1, raw))))
                        }
                    }
                    .frame(height: 10)
                    Text(String(format: "%.0f%%", filled * 100)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Divider()
            InfoRow(key: L("Untracked stretches (> gap limit)", "未追踪片段（超过可填补长度）"), value: "\(qc.longGaps)")
            InfoRow(key: L("Body length variability (CV)", "体长变异系数"), value: qc.bodyLengthCV.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
            InfoRow(key: L("Frame timing irregularity", "帧间隔不规则度"), value: String(format: "%.0f%%", qc.timingCV * 100))
            Button(L("Export frames to label (CSV)", "导出待标注帧（CSV）"), action: exportFrames)
                .buttonStyle(SecondaryButtonStyle())
            Text(L("Lists untracked stretches and low-confidence frames, for labelling them and refining the model (as with DeepLabCut's outlier frames).",
                   "列出未追踪片段和低置信度帧，可用于补充标注、重新训练模型（同 DeepLabCut 的 outlier frames）。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// What the app does with untracked frames, and what the user can do.
@MainActor
struct MissingFramesGuide: View {
    @State private var expanded = false

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    item("1", L("Low-confidence keypoints are treated as missing (confidence threshold, Parameters › Pose cleaning).",
                                "低置信度关键点视为缺失（置信度阈值，见 参数 › 姿态预处理）。"))
                    item("2", L("Implausible jumps — a keypoint leaping away from where the neighbouring frames put it, often a wrong detection or a left/right swap — can be removed as well (off by default).",
                                "不合理跳点——关键点偏离相邻帧给出的位置，通常是误检或左右互换——也可以剔除（默认关闭）。"))
                    item("3", L("Only short gaps are filled (default ≤ 0.25 s): linear, shape-preserving cubic, body-relative (moves the hidden paw with the body) or a Kalman smoother. Longer gaps are left missing and excluded from every measure — reconstructing them would invent behaviour.",
                                "只填补短缺口（默认 ≤ 0.25 秒）：线性、三次保形、身体相对坐标（被遮挡的爪随身体移动）或 Kalman 平滑。更长的缺口保持缺失、不参与任何指标——重建它们等于凭空制造行为。"))
                    item("4", L("Each task reports how much of its window was tracked; behaviour in untracked frames is not counted.",
                                "每个任务都会报告分析窗口内的追踪比例；未追踪帧中的行为不计入。"))
                    item("5", L("If too much is missing, fix the cause: camera view, light, a clean transparent floor, ≥ 30–60 fps; lower the detection threshold in Settings and re-run tracking.",
                                "缺失过多时应从源头解决：拍摄视角、光照、干净的透明底面、≥ 30–60 fps；也可在“设置”中降低检测阈值后重新识别。"))
                    item("6", L("Label the exported frames and retrain the model so it learns these situations (active learning).",
                                "标注导出的帧并重新训练模型，让模型学会这些情况（主动学习）。"))
                    item("7", L("Exclude the video when it fails the task's criteria set in advance, and report the reason.",
                                "若视频未达到任务事先设定的标准，予以排除并报告原因。"))
                }
                .padding(.top, 8)
            } label: {
                Text(L("What can be done about untracked frames?", "追踪不到的帧怎么办？"))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func item(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - QC player

/// The video with the raw keypoints the model found (no gap filling), to judge tracking quality.
@MainActor
struct QCPlayer: View {
    @ObservedObject var controller: PlayerController
    let track: PoseTrack
    let lost: [Interval]

    private var videoSize: CGSize { CGSize(width: track.width, height: track.height) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PlayerLayerView(player: controller.player)
                GeometryReader { geo in
                    let rect = aspectFitRect(videoSize, in: geo.size)
                    TimelineView(.animation(minimumInterval: nil, paused: !controller.isPlaying)) { _ in
                        let t = controller.isPlaying ? controller.displayTime() : controller.frameTime
                        Canvas { ctx, _ in draw(ctx, rect: rect, time: t) }
                    }
                    .allowsHitTesting(false)
                }
                if controller.failed {
                    Text(L("This video can't be played.", "无法播放该视频。"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                }
            }
            .aspectRatio(videoSize.width / max(1, videoSize.height), contentMode: .fit)
            .frame(maxHeight: 360)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { controller.toggle() }

            Slider(value: Binding(get: { controller.time }, set: { controller.scrub(to: $0) }),
                   in: 0...max(0.1, track.duration),
                   onEditingChanged: { editing in editing ? controller.beginScrub() : controller.endScrub() })
                .accessibilityLabel(L("Position", "播放位置"))
            HStack(spacing: 4) {
                Text(Fmt.clockPrecise(controller.time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { controller.step(-1) } label: { Image(systemName: "backward.frame.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("Previous frame", "上一帧"))
                Button { controller.toggle() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 52, height: 44)
                }
                .accessibilityLabel(controller.isPlaying ? L("Pause", "暂停") : L("Play", "播放"))
                Button { controller.step(1) } label: { Image(systemName: "forward.frame.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("Next frame", "下一帧"))
                Spacer()
                if !lost.isEmpty {
                    Menu {
                        ForEach(Array(lost.prefix(60).enumerated()), id: \.offset) { item in
                            Button(Fmt.clockPrecise(item.element.start) + "  (" + String(format: L("%.1f s", "%.1f 秒"), item.element.duration) + ")") {
                                controller.seek(item.element.start)
                            }
                        }
                    } label: {
                        Text(String(format: L("%d lost", "%d 段丢失"), lost.count))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Palette.inset, in: Capsule())
                    }
                    .accessibilityLabel(L("Jump to an untracked stretch", "跳到丢失片段"))
                }
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, rect: CGRect, time: Double) {
        guard let i = track.frameIndex(at: time) else { return }
        let sx = rect.width / max(1, videoSize.width), sy = rect.height / max(1, videoSize.height)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy) }
        for (a, b) in Kp.bones {
            guard let p = track.point(a, i, threshold: 0.3), let q = track.point(b, i, threshold: 0.3) else { continue }
            var path = Path(); path.move(to: map(p)); path.addLine(to: map(q))
            ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 2)
        }
        for k in Kp.allCases {
            guard let p = track.point(k, i, threshold: 0.3) else { continue }
            let c = map(p)
            let rr = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: rr), with: .color(KeypointColors.color(k)))
            ctx.stroke(Path(ellipseIn: rr), with: .color(.white), lineWidth: 1.2)
        }
    }
}

// MARK: - Sheets

/// Edit the animal, timepoint, trial, date and note of a video. Which task it belongs to changes
/// with Move to Task… (so its session is created there).
@MainActor
struct RecordingInfoSheet: View {
    let recordingID: UUID
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var animalID: UUID?
    @State private var newAnimal = ""
    @State private var timepoint = ""
    @State private var trial = 1
    @State private var subject = ""
    @State private var group = ""
    @State private var notes = ""
    @State private var hasDate = false
    @State private var recordedOn = Date()
    @State private var loaded = false

    private var experiment: Experiment? { store.recording(recordingID).flatMap { store.experiment(for: $0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let e = experiment {
                        Picker(L("Animal", "动物"), selection: $animalID) {
                            Text(L("Not set", "未设置")).tag(UUID?.none)
                            ForEach(e.animals) { a in
                                Text(e.displayCode(a) + (e.blinded || e.groupLabel(a).isEmpty ? "" : " · " + e.groupLabel(a)))
                                    .tag(UUID?.some(a.id))
                            }
                        }
                        HStack {
                            TextField(L("New animal ID", "新动物编号"), text: $newAnimal)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button(L("Add", "添加")) {
                                if let id = store.animalID(code: newAnimal, in: e.id) { animalID = id }
                                newAnimal = ""
                            }
                            .disabled(newAnimal.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !e.timepoints.isEmpty {
                            Picker(L("Timepoint", "时间点"), selection: $timepoint) {
                                Text(L("Not set", "未设置")).tag("")
                                ForEach(e.timepoints, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    } else {
                        TextField(L("Animal ID", "动物编号"), text: $subject)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField(L("Group", "组别"), text: $group)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Stepper(value: $trial, in: 1...20) {
                        HStack { Text(L("Trial", "试次")); Spacer(); Text("\(trial)").foregroundStyle(.secondary).monospacedDigit() }
                    }
                } header: {
                    Text(experiment?.name ?? L("Not in a task", "未归入任务"))
                }
                Section {
                    Toggle(L("Recording date", "录制日期"), isOn: $hasDate)
                    if hasDate {
                        DatePicker(L("Recorded on", "录制于"), selection: $recordedOn, displayedComponents: [.date, .hourAndMinute])
                    }
                    TextField(L("Notes", "备注"), text: $notes, axis: .vertical).lineLimit(2...6)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Video information", "视频信息"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Save", "保存")) { save(); dismiss() } }
            }
            .onAppear {
                guard !loaded, let r = store.recording(recordingID) else { return }
                loaded = true
                animalID = r.animalID
                timepoint = r.timepoint
                trial = r.trial
                subject = r.subject
                group = r.group
                notes = r.notes
                hasDate = r.recordedOn != nil
                recordedOn = r.recordedOn ?? r.createdAt
            }
        }
        .interactiveDismissDisabled(loaded && changed)
    }

    private var changed: Bool {
        guard let r = store.recording(recordingID) else { return false }
        return animalID != r.animalID || timepoint != r.timepoint || trial != r.trial || subject != r.subject
            || group != r.group || notes != r.notes || (hasDate ? recordedOn : nil) != r.recordedOn
    }

    private func save() {
        let inStudy = experiment != nil
        let aid = animalID, tp = timepoint, tr = trial
        let subj = subject.trimmingCharacters(in: .whitespaces), grp = group.trimmingCharacters(in: .whitespaces)
        let note = notes, date: Date? = hasDate ? recordedOn : nil
        store.updateRecording(recordingID) { r in
            if inStudy {
                r.animalID = aid
                r.timepoint = tp
            } else {
                r.subject = subj
                r.group = grp
            }
            r.trial = tr
            r.notes = note
            r.recordedOn = date
        }
        store.flush()
    }
}
