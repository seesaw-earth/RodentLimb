// RecordingDetailView.swift — one video: who and where it is (animal, study, group, timepoint, the
// file and its location), tracking status (queue position, live progress, failure and retry), the
// QC report with the video and the raw keypoints, the include / exclude decision, the tasks
// analysed from it, editable design information, and the record's actions (re-run tracking,
// export, delete). The pose is loaded off the main thread; the player exists only while the page
// is on screen and the video is reachable.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct RecordingDetailView: View {
    let id: UUID

    @Environment(AppModel.self) private var app
    @State private var track: PoseTrack?
    @State private var controller: PlayerController?
    @State private var poseUnreadable = false
    @State private var excludeRequest: RecordingsExcludeRequest?
    @State private var confirmRerun = false
    @State private var confirmDelete = false
    @State private var exportingFrames = false

    private struct LoadKey: Equatable {
        var exists: Bool
        var hasPose: Bool
        var missing: Bool
    }

    var body: some View {
        let store = app.store
        let r = store.recording(id)
        Group {
            if let r {
                content(r)
            } else {
                EmptyState(title: L("Video deleted", "该视频已删除"),
                           message: L("This video record is no longer in the library.", "资料库中已没有这条视频记录。"),
                           symbol: "trash")
            }
        }
        .navigationTitle(r.map { RecordingsQuery.animalLabel($0, store: store) } ?? L("Video", "视频"))
        .toolbar { detailToolbar(r) }
        .sheet(item: $excludeRequest) { req in
            RecordingsExcludeSheet(count: req.ids.count, initialReason: req.initialReason) { reason in
                RecordingsActions.exclude(req.ids, reason: reason, app: app)
            }
        }
        .confirmationDialog(L("Re-run tracking for this video?", "重新识别该视频？"), isPresented: $confirmRerun,
                            titleVisibility: .visible) {
            ForEach(PoseModelID.choices) { m in
                Button(String(format: L("Re-run with %@", "使用%@重新识别"), m.shortTitle.text)
                       + (m == app.store.poseModel(id) ? L(" (current)", "（当前）") : "")) {
                    dropPlayer()
                    track = nil
                    app.rerunTracking([id], model: m)
                }
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("The pose model runs again on the whole video; the QC report is recomputed and every analysis of this video waits for the new pose. The decision, tasks and parameters are kept. Choose the model that matches the lighting: visible light (room light; FP16 default, or FP32 to match the iPhone) or near-infrared (dark box, filmed from below).",
                   "将对整段视频重新运行姿态模型；QC 报告会重新计算，该视频的所有分析会等待新的姿态数据。纳入决定、任务和参数保持不变。请按拍摄光线选择模型：可见光（室内光；默认 FP16，或与 iPhone 一致的 FP32）或近红外（暗箱、从下方拍摄）。"))
        }
        .confirmationDialog(RecordingsActions.deleteTitle(1), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("Delete", "删除"), role: .destructive) {
                dropPlayer()
                track = nil
                RecordingsActions.delete([id], app: app)
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(RecordingsActions.deleteMessage([id], store: store))
        }
        .task(id: LoadKey(exists: r != nil, hasPose: r?.hasPose ?? false, missing: store.missingVideos.contains(id))) {
            await loadPose()
        }
        .onDisappear { dropPlayer() }
    }

    // MARK: Layout

    private func content(_ r: Recording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(r)
                // The decision and info column sits beside the player when there is room, below it
                // on a narrow window.
                AdaptiveColumns(side: .fixed(340), threshold: 800, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        RecordingDetailTrackingCard(recordingID: r.id)
                        if r.isProcessed {
                            playerSection(r)
                            qcSection(r)
                        }
                        RecordingDetailMissingFramesGuide()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 16) {
                        decisionCard(r)
                        tasksCard(r)
                        RecordingDetailInfoCard(recordingID: r.id)
                        actionsCard(r)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .pageContent(maxWidth: 1280)
            .padding(.vertical, 16)
        }
        .background(Palette.canvas)
    }

    private func header(_ r: Recording) -> some View {
        let store = app.store
        let e = store.experiment(for: r)
        let blinded = e?.blinded == true
        let missing = store.missingVideos.contains(r.id)
        let src = store.source(r.id)
        let design = [store.groupLabel(r), r.trial > 1 ? String(format: L("trial %d", "第 %d 次试验"), r.trial) : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let fileLine = blinded ? store.fileLabel(r) : (src?.path.isEmpty == false ? (src?.path ?? r.originalName) : r.originalName)
        return HStack(alignment: .top, spacing: 14) {
            RecordingsThumbnail(recording: r, store: store, width: 120, height: 75)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(RecordingsQuery.animalLabel(r, store: store)).font(.largeTitle.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .textSelection(.enabled)
                        .layoutPriority(1)
                    RecordingsStatusCell(recording: r, missing: missing, batch: app.batch)
                        .fixedSize()
                    if r.qc != nil { QCBadge(report: r.qc).fixedSize() }
                }
                FlowLayout(spacing: 10, lineSpacing: 4) {
                    if let e, let t = store.tasks.first(where: { $0.experimentID == e.id }) {
                        Button(store.taskTitle(t)) {
                            app.show(.task(t))
                        }
                        .buttonStyle(.link)
                        .help(L("Open the task", "打开该任务"))
                    }
                    if !design.isEmpty { Text(design).foregroundStyle(.secondary) }
                    Text(Fmt.date(r.recordedOn ?? r.createdAt)).foregroundStyle(.secondary)
                        .help(r.recordedOn == nil ? L("Imported on", "导入时间") : L("Recorded on", "录制时间"))
                }
                .font(.callout)
                HStack(spacing: 6) {
                    Text(src?.mode == .copied ? L("Copied:", "已复制：") : L("File:", "文件："))
                        .help(src?.mode == .copied ? L("Copied into the library", "已复制到资料库")
                              : L("Referenced in place (the file stays where it is)", "原位引用（文件保留在原处）"))
                    Text(fileLine).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Button(L("Show in Finder", "在访达中显示")) { app.revealVideo(r) }
                        .disabled(missing)
                    Button(L("Locate…", "定位…")) { app.locateVideo(r.id) }
                        .help(L("Point this record at the video's new location", "将该记录指向视频的新位置"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .controlSize(.small)
                if missing {
                    Banner(text: L("The video file cannot be found right now: the drive may not be connected, or the file was moved or renamed. Use Locate… to point to it.",
                                   "目前找不到视频文件：所在磁盘可能未连接，或文件已被移动或重命名。可用“定位…”重新指定。"),
                           level: .warning)
                        .frame(maxWidth: 640)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func playerSection(_ r: Recording) -> some View {
        if let c = controller, let t = track {
            RecordingDetailQCPlayer(controller: c, track: t, lost: r.qc?.lostSegments ?? [])
        } else if poseUnreadable {
            Card {
                Banner(text: L("The pose file of this video could not be read. Re-run tracking to create it again.",
                               "无法读取该视频的姿态文件。请重新识别以重新生成。"), level: .error)
                Button(L("Re-run Tracking…", "重新识别…")) { confirmRerun = true }
            }
        } else if app.store.missingVideos.contains(r.id) {
            Card {
                CardHeader(L("Video with the raw keypoints", "视频与原始关键点"), symbol: "play.rectangle")
                Text(L("The player needs the video file. Connect its drive or locate the file.", "播放器需要视频文件。请连接其所在磁盘或重新定位文件。"))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L("Locate Video…", "定位视频…")) { app.locateVideo(r.id) }
            }
        } else {
            Card {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Loading the pose…", "正在载入姿态数据…")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func qcSection(_ r: Recording) -> some View {
        if let qc = r.qc {
            RecordingDetailQCSummaryCard(qc: qc)
            RecordingDetailQCDetailCard(qc: qc, exporting: exportingFrames) { exportFrames(r, qc) }
        } else {
            Card {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Checking tracking quality…", "正在检查追踪质量…")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Decision

    private func decisionCard(_ r: Recording) -> some View {
        Card {
            CardHeader(L("Include in the analysis?", "是否纳入分析？"), symbol: "checkmark.shield",
                       subtitle: L("Decide from the QC report and the video. Exclusions and their reasons are listed in every export (ARRIVE 2.0).",
                                   "根据 QC 报告和视频决定。排除的视频及原因会写入所有导出文件（ARRIVE 2.0）。"))
            HStack(spacing: 8) {
                Tag(text: r.decision.label, color: Palette.decision(r.decision))
                if let v = r.qc?.verdict, r.decision == .pending {
                    Text(v == .pass ? L("QC passed", "QC 通过") : v == .warn ? L("QC warning — check the video", "QC 警告——请查看视频")
                         : L("QC failed — usually excluded", "QC 未通过——通常予以排除"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if r.decision == .excluded && !r.exclusionReason.isEmpty {
                Text(RecordingsExclusion.display(r.exclusionReason))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    RecordingsActions.include([r.id], app: app)
                } label: {
                    Text(L("Include", "纳入"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!r.isProcessed || r.decision == .included)
                Button {
                    excludeRequest = RecordingsExcludeRequest(ids: [r.id], initialReason: r.exclusionReason)
                } label: {
                    Text(r.decision == .excluded ? L("Change Reason…", "修改原因…") : L("Exclude…", "排除…"))
                }
                Spacer()
            }
            if r.decision != .pending {
                Button(L("Back to Needs Review", "退回待复核")) { RecordingsActions.backToReview([r.id], app: app) }
                    .buttonStyle(.link)
            }
            if !r.isProcessed {
                Text(L("A video can be included once it is tracked.", "视频识别完成后才能纳入。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Tasks

    private func tasksCard(_ r: Recording) -> some View {
        let sessions = app.store.sessions(of: r.id)
        return Card {
            CardHeader(L("Tasks", "任务"), symbol: "square.stack.3d.up",
                       subtitle: L("The pose is detected once; each task analyses it with its own parameters.",
                                   "姿态只识别一次；每个任务用各自的参数分析。"))
            if sessions.isEmpty {
                Text(r.plannedAssays.isEmpty ? L("No task yet.", "还没有任务。")
                     : String(format: L("Planned: %@ — created once the video is included.", "计划：%@——视频纳入后自动创建。"),
                              r.plannedAssays.map { $0.name.text }.joined(separator: ", ")))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sessions) { s in
                RecordingDetailTaskRow(session: s)
            }
            if !sessions.isEmpty && !r.plannedAssays.isEmpty {
                Text(String(format: L("Also planned: %@", "另有计划：%@"), r.plannedAssays.map { $0.name.text }.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if r.decision != .included && !sessions.isEmpty {
                Text(L("Videos that are not included can still be analysed, but are left out of group comparisons.",
                       "未纳入的视频仍可分析，但不会参与任务中的组间比较。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                app.assignRequest = AssignRequest(recordings: [r.id])
            } label: {
                Text(L("Move to Task…", "移到任务…"))
            }
        }
    }

    private func actionsCard(_ r: Recording) -> some View {
        Card {
            CardHeader(L("Video record", "视频记录"), symbol: "film")
            Button {
                app.export(.selection(analyses: [], recordings: [r.id]))
            } label: {
                Text(L("Export…", "导出…"))
            }
            Button {
                confirmRerun = true
            } label: {
                Text(L("Re-run Tracking…", "重新识别…"))
            }
            .disabled(r.status == .processing || r.status == .queued)
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text(L("Delete Video Record…", "删除视频记录…"))
            }
            Text(L("Deleting removes the library's record, its pose, QC and analyses. A referenced video file is never deleted.",
                   "删除会移除资料库中的记录及其姿态、QC 和分析；被引用的视频文件不会被删除。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func detailToolbar(_ r: Recording?) -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if let r {
                Button {
                    RecordingsActions.include([r.id], app: app)
                } label: {
                    Text(L("Include", "纳入"))
                }
                .disabled(!r.isProcessed || r.decision == .included)
                .help(L("Include this video in the analysis", "将该视频纳入分析"))
                Button {
                    excludeRequest = RecordingsExcludeRequest(ids: [r.id], initialReason: r.exclusionReason)
                } label: {
                    Text(L("Exclude…", "排除…"))
                }
                .help(L("Exclude this video with a reason", "排除该视频并填写原因"))
                Button {
                    app.assignRequest = AssignRequest(recordings: [r.id])
                } label: {
                    Text(L("Move to Task…", "移到任务…"))
                }
                .help(L("Put this video into a task", "将该视频放入某个任务"))
                Menu {
                    Button(L("Re-run Tracking…", "重新识别…")) { confirmRerun = true }
                        .disabled(r.status == .processing || r.status == .queued)
                    Button(L("Locate Video…", "定位视频…")) { app.locateVideo(r.id) }
                    Button(L("Show in Finder", "在访达中显示")) { app.revealVideo(r) }
                    Divider()
                    Button(L("Delete Video Record…", "删除视频记录…"), role: .destructive) { confirmDelete = true }
                } label: {
                    Text(L("More", "更多"))
                }
                .help(L("More actions", "更多操作"))
            }
        }
    }

    // MARK: Pose and player

    private func loadPose() async {
        let store = app.store
        guard let r = store.recording(id), r.hasPose else {
            dropPlayer()
            track = nil
            poseUnreadable = false
            return
        }
        let loaded = await store.recordingPose(id)
        if Task.isCancelled { return }
        guard let current = store.recording(id), current.hasPose else { return }
        guard let t = loaded else {
            poseUnreadable = true
            return
        }
        poseUnreadable = false
        track = t
        if controller == nil, !store.missingVideos.contains(id) {
            controller = PlayerController.make(store: store, recording: current, track: t)
        }
    }

    private func dropPlayer() {
        controller?.teardown()
        controller = nil
    }

    // MARK: Frames to label

    /// Untracked stretches and low-confidence frames as CSV, to label them and refine the model.
    private func exportFrames(_ r: Recording, _ qc: QCReport) {
        guard !exportingFrames else { return }
        exportingFrames = true
        let store = app.store
        let name = Exporter.safeName(RecordingsQuery.animalLabel(r, store: store)) + "_frames_to_label.csv"
        Task { @MainActor in
            var pose = track
            if pose == nil { pose = await store.recordingPose(id) }
            guard let pose else {
                exportingFrames = false
                app.alert = AppAlert(title: L("Nothing to export", "没有可导出的内容"),
                                     message: L("The pose of this video could not be loaded.", "无法载入该视频的姿态数据。"))
                return
            }
            let text = await Task.detached(priority: .userInitiated) {
                QualityControl.refinementCSV(track: pose, report: qc)
            }.value
            exportingFrames = false
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.canCreateDirectories = true
            panel.message = L("Frames worth labelling to refine the pose model (frame, time, reason).",
                              "值得补充标注以改进姿态模型的帧（帧号、时间、原因）。")
            panel.prompt = L("Save", "保存")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let written = await Task.detached(priority: .userInitiated) { Exporter.write(text, url) }.value
            if let written {
                app.toast = L("Frames to label saved", "已保存待标注帧")
                NSWorkspace.shared.activateFileViewerSelecting([written])
            } else {
                app.alert = AppAlert(title: L("Could not save the file", "无法保存文件"),
                                     message: L("Choose another location and try again.", "请选择其他位置后重试。"))
            }
        }
    }
}

// MARK: - Task row

/// One analysis of the video: task, status and its highlighted measures. Click opens the analysis.
@MainActor
private struct RecordingDetailTaskRow: View {
    let session: Session
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.open(.analysis(session.id))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AssayBadge(assay: session.assay, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.assay.name.text).font(.callout.weight(.semibold))
                        if app.store.analysing.contains(session.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Circle()
                                .fill(session.status == .failed ? Palette.danger
                                      : session.status == .needsSetup ? Palette.warning
                                      : session.status == .done ? Palette.success : Color.secondary)
                                .frame(width: 7, height: 7)
                                .help(session.status.title)
                        }
                        if let level = session.worstNote, level != .info {
                            Text(level == .error ? L("error", "错误") : L("warning", "警告"))
                                .font(.caption).foregroundStyle(Banner.color(level))
                        }
                    }
                    if session.summary.isEmpty {
                        Text(session.status.title).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(session.summary.prefix(3)) { m in
                            HStack(spacing: 4) {
                                Text(m.label.text).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(m.formatted).monospacedDigit()
                                if !m.unit.isEmpty && m.value != nil { Text(m.unit).foregroundStyle(.secondary) }
                            }
                            .font(.caption)
                        }
                    }
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(8)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Open this analysis", "打开该分析"))
    }
}

// MARK: - Tracking status

/// Queue position, live progress or the failure of the video (only this card follows the batch).
@MainActor
private struct RecordingDetailTrackingCard: View {
    let recordingID: UUID
    @Environment(AppModel.self) private var app

    var body: some View {
        if let r = app.store.recording(recordingID) {
            let missing = app.store.missingVideos.contains(r.id)
            switch r.status {
            case .queued, .processing:
                if let job = app.batch.jobs[r.id] {
                    running(job, r)
                } else {
                    queued(r, missing: missing)
                }
            case .failed:
                Card {
                    Banner(text: r.failure ?? L("Tracking failed.", "识别失败。"), level: .error)
                    HStack {
                        Button {
                            app.retry([r.id])
                        } label: {
                            Text(L("Retry", "重试"))
                        }
                        .buttonStyle(.borderedProminent)
                        if missing {
                            Button(L("Locate Video…", "定位视频…")) { app.locateVideo(r.id) }
                        }
                    }
                }
            case .ready:
                EmptyView()
            }
        }
    }

    private func running(_ job: BatchEngine.Job, _ r: Recording) -> some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(fraction: job.fraction)
                    Text(Fmt.percent(job.fraction)).font(.callout.weight(.semibold).monospacedDigit())
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(phaseTitle(job.phase)).font(.headline)
                    if job.framesTotal > 0 {
                        Text(String(format: L("Frame %d of %d", "第 %d / %d 帧"), job.framesDone, job.framesTotal))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(Fmt.remaining(job.secondsLeft)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Text(L("A QC report follows. Tracking continues in the background; if you quit, it resumes from the same frame next time.",
                           "完成后会生成 QC 报告。识别在后台进行；退出 App 后，下次会从同一帧继续。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("Stop", "停止")) { app.batch.cancel(r.id) }
                    .help(L("Stop tracking this video (Retry continues from the saved frame)", "停止识别该视频（重试时从已保存的帧继续）"))
            }
        }
    }

    private func queued(_ r: Recording, missing: Bool) -> some View {
        let queuedCount = app.store.queuedCount
        let position = app.store.queuePosition(of: r.id)
        return Card {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(missing ? L("Waiting for the video file", "等待视频文件") : L("Waiting in the queue", "排队等待中"))
                        .font(.headline)
                    if let position {
                        Text(String(format: L("Position %d of %d", "第 %d 位，共 %d 个"), position + 1, queuedCount))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if missing {
                        Text(L("The file cannot be found; it is skipped until its drive is connected or the file is located.",
                               "找不到该文件；在连接其所在磁盘或重新定位文件之前会被跳过。"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if missing {
                    Button(L("Locate Video…", "定位视频…")) { app.locateVideo(r.id) }
                } else if !app.batch.isActive {
                    Button {
                        app.batch.start()
                    } label: {
                        Text(L("Start Tracking", "开始识别"))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func phaseTitle(_ p: RunProgress.Phase) -> String {
        switch p {
        case .opening: return L("Opening the video", "正在打开视频")
        case .tracking: return L("Tracking every frame", "正在逐帧识别")
        case .finishing: return L("Saving the pose", "正在保存姿态数据")
        }
    }
}
