// QueueView.swift — the Processing page: what the pose model is doing and what comes next.
//   Header: state (tracking / paused / idle / waiting for the model / low disk) with the engine's
//           notice, overall progress, speed and time left, counts, Start / Pause, videos at once.
//   Running videos: live cards (QueueJobCard.swift).
//   Waiting: the queue in order — move to top / bottom (⌥⌘↑ / ⌥⌘↓), remove (⌫), locate offline
//            videos, show in Finder; double-click opens the video page.
//   Failed: the most recent failures with their reason, Retry / Retry All.
// Only small child views read the per-frame progress, so the table is not rebuilt on every tick.

import SwiftUI
import AppKit

@MainActor
struct QueueView: View {
    @Environment(AppModel.self) private var app
    @State private var selection = Set<UUID>()
    @State private var pendingRemoval: Set<UUID>?

    var body: some View {
        let store = app.store
        let queued = store.queuedRecordings
        let failed = store.recordings.filter { $0.status == .failed }.sorted { $0.updatedAt > $1.updatedAt }
        let processing = store.recordings.reduce(0) { $0 + ($1.status == .processing ? 1 : 0) }
        let offline = queued.reduce(0) { $0 + (store.missingVideos.contains($1.id) ? 1 : 0) }
        // The page shares its height: the running videos and the failed list get at most a part of it
        // (they scroll inside), so the waiting table and its buttons always stay on screen.
        GeometryReader { geo in
            VStack(spacing: 0) {
                QueueStatusHeader(waiting: queued.count - offline, offline: offline, processing: processing, failed: failed.count)
                Divider()
                if queued.isEmpty && failed.isEmpty && processing == 0 {
                    if store.recordings.contains(where: { $0.status == .ready }) {
                        // The queue is empty because everything is tracked — say so and show what is next,
                        // instead of a blank "nothing to track" page that looks as if the results were gone.
                        QueueFinishedState()
                    } else {
                        emptyState
                    }
                } else {
                    QueueRunningSection(maxHeight: max(150, geo.size.height * 0.36))
                    waitingBar(queued, offline: offline)
                    waitingTable(queued)
                        .frame(minHeight: 110)
                    if !failed.isEmpty {
                        Divider()
                        QueueFailedPanel(failed: failed, maxListHeight: max(60, min(190, geo.size.height * 0.2)))
                    }
                }
            }
        }
        .onChange(of: selection, initial: true) { _, s in app.selectedRecordings = s }
        .confirmationDialog(removalTitle,
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingRemoval) { ids in
            Button(L("Remove", "移除"), role: .destructive) { remove(ids) }
            Button(L("Cancel", "取消"), role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text(L("The video records, their saved progress and planned tasks are removed from the library. Video files kept in place are not deleted; copies inside the library are.",
                   "视频记录、已保存的进度和计划任务将从资料库中移除。保留在原位置的视频文件不会被删除；复制到资料库中的副本会被删除。"))
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            EmptyState(title: L("Nothing to track", "没有待识别的视频"),
                       message: L("Imported videos wait here and are tracked one after another by the pose model, in the background. Progress is saved as it goes: pausing, quitting or a crash loses nothing.",
                                  "导入的视频会在这里排队，由姿态模型在后台逐个识别。进度随时保存：暂停、退出或崩溃都不会丢失。"),
                       symbol: "tray")
                .fixedSize(horizontal: false, vertical: true)
            Button {
                app.chooseFilesToImport()
            } label: {
                Text(L("Import Videos…", "导入视频…"))
            }
            .primaryAction()
            Text(L("or drop videos and folders on the window", "或将视频和文件夹拖入窗口"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Waiting

    private func waitingBar(_ queued: [Recording], offline: Int) -> some View {
        let chosen = queued.contains { selection.contains($0.id) }
        return HStack(spacing: 8) {
            Text(L("Waiting", "等待中")).font(.headline)
            Text(waitingSummary(queued, offline: offline))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 12)
            Button {
                move(selection, toFront: true, queued)
            } label: {
                Text(L("Move to Top", "移到最前"))
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(!chosen)
            .help(L("Track the selected videos next (⌥⌘↑)", "下一个识别所选视频（⌥⌘↑）"))
            Button {
                move(selection, toFront: false, queued)
            } label: {
                Text(L("Move to Bottom", "移到最后"))
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(!chosen)
            .help(L("Track the selected videos last (⌥⌘↓)", "最后识别所选视频（⌥⌘↓）"))
            Button {
                askRemove(selection, queued)
            } label: {
                Text(L("Remove…", "移除…"))
            }
            .disabled(!chosen)
            .help(L("Remove the selected videos from the queue and the library (Delete)", "将所选视频从队列和资料库中移除（Delete）"))
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func waitingSummary(_ queued: [Recording], offline: Int) -> String {
        guard !queued.isEmpty else { return "" }
        var parts = [queued.count == 1 ? L("1 video", "1 个视频") : String(format: L("%d videos", "%d 个视频"), queued.count)]
        let seconds = queued.reduce(0.0) { sum, r in
            guard let d = r.duration, d.isFinite, d > 0 else { return sum }
            return sum + d
        }
        if seconds > 0 { parts.append(String(format: L("%@ of video", "共 %@ 视频"), ImportSheetModel.span(seconds))) }
        if offline > 0 { parts.append(String(format: L("%d offline", "%d 个离线"), offline)) }
        return parts.joined(separator: " · ")
    }

    private func waitingTable(_ queued: [Recording]) -> some View {
        let position = Dictionary(queued.enumerated().map { ($0.element.id, $0.offset + 1) }, uniquingKeysWith: { a, _ in a })
        return Table(queued, selection: $selection) {
            TableColumn("#") { r in
                Text(position[r.id].map { String($0) } ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 28, ideal: 38, max: 60)
            TableColumn(L("Video", "视频")) { r in videoCell(r) }
                .width(min: 160, ideal: 280)
            TableColumn(L("Task · group", "任务 · 组别")) { r in
                Text(studyLine(r)).lineLimit(1).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 190)
            TableColumn(L("Duration", "时长")) { r in
                Text(r.duration.map { Fmt.clock($0) } ?? "—").monospacedDigit()
            }
            .width(min: 56, ideal: 70, max: 90)
            TableColumn(L("Imported", "导入时间")) { r in
                Text(Fmt.date(r.createdAt)).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 140, max: 180)
            TableColumn(L("Status", "状态")) { r in statusCell(r) }
                .width(min: 90, ideal: 180)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            rowMenu(ids, queued)
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { app.open(.recording(id)) }
        }
        .onDeleteCommand { askRemove(selection, queued) }
        .overlay {
            if queued.isEmpty {
                Text(L("No other videos are waiting.", "没有其他等待中的视频。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func videoCell(_ r: Recording) -> some View {
        let store = app.store
        let name = store.displayName(r)
        let file = store.fileLabel(r)
        let blinded = store.experiment(for: r)?.blinded == true
        return HStack(spacing: 6) {
            Text(name).lineLimit(1)
            if file != name {
                Text(file).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .help(blinded ? file : (store.source(r.id)?.path ?? r.originalName))
    }

    private func studyLine(_ r: Recording) -> String {
        let store = app.store
        let parts = [store.experiment(for: r)?.name ?? "", store.groupLabel(r)]
        let s = parts.filter { !$0.isEmpty }.joined(separator: " · ")
        return s.isEmpty ? "—" : s
    }

    @ViewBuilder
    private func statusCell(_ r: Recording) -> some View {
        let store = app.store
        let missing = store.missingVideos.contains(r.id)
        let crashes = store.source(r.id)?.crashes ?? 0
        let attempts = store.source(r.id)?.attempts ?? 0
        HStack(spacing: 4) {
            if missing {
                Tag(text: L("Offline", "离线"), color: Palette.warning, symbol: "externaldrive.badge.exclamationmark")
                    .help(L("The file cannot be reached (drive not connected, moved or renamed). It waits and starts when the file is back; or use Locate Video…",
                            "无法访问该文件（磁盘未连接、已移动或重命名）。文件恢复后会自动开始；也可使用“定位视频…”。"))
            }
            if crashes > 0 {
                Tag(text: String(format: L("Stopped ×%d", "中断 ×%d"), crashes), color: Palette.danger, symbol: "exclamationmark.triangle.fill")
                    .help(L("The app stopped unexpectedly while this video was being tracked. It continues from its checkpoint; after two such stops it is set aside.",
                            "识别该视频时 App 意外退出。它会从检查点继续；累计两次后将被搁置。"))
            } else if attempts > 0 {
                Tag(text: L("Resumes", "继续"), color: .accentColor, symbol: "arrow.uturn.forward")
                    .help(String(format: L("Started %d time(s) before; continues from where it stopped.", "之前已开始 %d 次；将从中断处继续。"), attempts))
            }
            if !missing && crashes == 0 && attempts == 0 {
                Text(L("Waiting", "等待中")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UUID>, _ queued: [Recording]) -> some View {
        if !ids.isEmpty {
            Button(L("Move to Top", "移到最前")) { move(ids, toFront: true, queued) }
            Button(L("Move to Bottom", "移到最后")) { move(ids, toFront: false, queued) }
            Divider()
            if ids.count == 1, let id = ids.first, let r = app.store.recording(id) {
                Button(L("Open Video Page", "打开视频页面")) { app.open(.recording(id)) }
                Button(L("Show in Finder", "在访达中显示")) { app.revealVideo(r) }
                Button(L("Locate Video…", "定位视频…")) { app.locateVideo(id) }
                Divider()
            }
            Button(L("Remove from Queue…", "从队列中移除…"), role: .destructive) { askRemove(ids, queued) }
        }
    }

    // MARK: Actions

    /// Keeps the relative order of the moved videos.
    private func move(_ ids: Set<UUID>, toFront: Bool, _ queued: [Recording]) {
        let ordered = queued.map(\.id).filter { ids.contains($0) }
        guard !ordered.isEmpty else { return }
        app.store.reorderQueue(ordered, toFront: toFront)
    }

    private func askRemove(_ ids: Set<UUID>, _ queued: [Recording]) {
        let waiting = Set(queued.map(\.id)).intersection(ids)
        guard !waiting.isEmpty else { return }
        pendingRemoval = waiting
    }

    private var removalTitle: String {
        let n = pendingRemoval?.count ?? 0
        return n == 1 ? L("Remove 1 video from the queue?", "从队列中移除 1 个视频？")
            : String(format: L("Remove %d videos from the queue?", "从队列中移除 %d 个视频？"), n)
    }

    private func remove(_ ids: Set<UUID>) {
        pendingRemoval = nil
        let store = app.store
        // Never delete a video the engine has started in the meantime.
        let safe = Set(ids.filter { store.recording($0)?.status == .queued })
        guard !safe.isEmpty else { return }
        let entry = store.deleteRecordings(safe)
        selection.subtract(safe)
        app.deleted(entry, message: safe.count == 1 ? L("1 video removed (in Recently Deleted)", "已移除 1 个视频（可在“最近删除”中找回）")
            : String(format: L("%d videos removed (in Recently Deleted)", "已移除 %d 个视频（可在“最近删除”中找回）"), safe.count))
    }
}

// MARK: - Header

@MainActor
struct QueueStatusHeader: View {
    let waiting: Int
    let offline: Int
    let processing: Int
    let failed: Int
    @Environment(AppModel.self) private var app

    private struct Look {
        var title: String
        var detail: String
        var symbol: String
        var color: Color
    }

    var body: some View {
        let batch = app.batch
        let look = appearance(batch.state)
        VStack(alignment: .leading, spacing: 10) {
            // The controls stay beside the status when there is room, and move below it otherwise.
            AdaptiveColumns(side: .ideal, threshold: 620, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5).fill(look.color).frame(width: 4, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(look.title).font(.title3.weight(.semibold))
                        Text(batch.notice ?? look.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    simultaneousStepper
                    startPauseButton
                }
                .fixedSize()
            }
            if batch.state == .running || processing > 0 {
                QueueLiveProgress()
            }
            counts
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func appearance(_ state: BatchEngine.State) -> Look {
        switch state {
        case .running:
            if processing == 0 && waiting == 0 && offline > 0 {
                return Look(title: L("Waiting for offline videos", "正在等待离线视频"),
                            detail: L("Reconnect the drive, or use Locate Video… on a waiting video.", "请重新连接磁盘，或对等待中的视频使用“定位视频…”。"),
                            symbol: "externaldrive.badge.exclamationmark", color: Palette.warning)
            }
            return Look(title: L("Tracking", "正在识别"),
                        detail: L("The pose model runs in the background and saves its progress as it goes. You can keep working.",
                                  "姿态模型在后台运行并随时保存进度，你可以继续其他工作。"),
                        symbol: "waveform.path.ecg", color: .accentColor)
        case .paused:
            return Look(title: L("Paused", "已暂停"),
                        detail: L("Videos that were running kept their progress and continue from there when you resume.",
                                  "正在处理的视频已保存进度，继续后将从该处接着识别。"),
                        symbol: "pause.fill", color: Palette.gray)
        case .waitingForModel(let message):
            return Look(title: L("Waiting for the pose model", "正在等待姿态模型"), detail: message,
                        symbol: "exclamationmark.triangle.fill", color: Palette.danger)
        case .lowDisk:
            return Look(title: L("Paused — low disk space", "已暂停——磁盘空间不足"),
                        detail: L("Free some space on the library's disk, then press Try Again.", "请释放资料库所在磁盘的空间，然后点击“重试”。"),
                        symbol: "internaldrive", color: Palette.warning)
        case .idle:
            if waiting > 0 {
                return Look(title: L("Ready to track", "可以开始识别"),
                            detail: waiting == 1 ? L("1 video is waiting. Press Start to run the pose model.", "1 个视频正在等待。点击“开始”运行姿态模型。")
                                : String(format: L("%d videos are waiting. Press Start to run the pose model.", "%d 个视频正在等待。点击“开始”运行姿态模型。"), waiting),
                            symbol: "play.fill", color: .accentColor)
            }
            if offline > 0 {
                return Look(title: L("Waiting for offline videos", "正在等待离线视频"),
                            detail: L("Reconnect the drive, or use Locate Video… on a waiting video.", "请重新连接磁盘，或对等待中的视频使用“定位视频…”。"),
                            symbol: "externaldrive.badge.exclamationmark", color: Palette.warning)
            }
            return Look(title: L("All caught up", "全部完成"),
                        detail: L("Every imported video has been tracked.", "所有导入的视频都已识别。"),
                        symbol: "checkmark", color: Palette.success)
        }
    }

    private var isModelWait: Bool {
        if case .waitingForModel = app.batch.state { return true }
        return false
    }

    @ViewBuilder
    private var startPauseButton: some View {
        let batch = app.batch
        if batch.state == .running {
            Button {
                batch.pause()
            } label: {
                Text(L("Pause", "暂停")).frame(minWidth: 70)
            }
            .controlSize(.large)
            .help(L("Running videos stop after the current frame and keep their progress (⌘.)", "正在处理的视频会在当前帧后停止并保留进度（⌘.）"))
        } else {
            let title: String = {
                switch batch.state {
                case .paused: return L("Resume", "继续")
                case .lowDisk, .waitingForModel: return L("Try Again", "重试")
                default: return L("Start", "开始")
                }
            }()
            Button {
                batch.start()
            } label: {
                Text(title).frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(waiting == 0 && batch.state != .lowDisk && !isModelWait)
            .help(L("Run the pose model on the waiting videos (⌘R)", "对等待中的视频运行姿态模型（⌘R）"))
        }
    }

    private var simultaneousStepper: some View {
        let n = app.batch.maxSimultaneous
        return Stepper(value: Binding(get: { app.batch.maxSimultaneous }, set: { setSimultaneous($0) }), in: 1...3) {
            Text(n == 1 ? L("1 video at a time", "每次 1 个视频") : String(format: L("%d videos at once", "同时 %d 个视频"), n))
                .monospacedDigit()
        }
        .fixedSize()
        .help(L("Videos tracked at the same time. More can be faster on Macs with Apple silicon and plenty of memory; a change applies as soon as a slot is free.",
                "同时识别的视频数。在内存充足的 Apple 芯片 Mac 上，增加数量可能更快；更改会在有空位时生效。"))
    }

    private func setSimultaneous(_ v: Int) {
        let n = min(3, max(1, v))
        UserDefaults.standard.set(n, forKey: SettingsKey.simultaneous)
        app.applySettings()
        // Fill the new slots right away.
        if app.batch.state == .running { app.batch.start() }
    }

    private var counts: some View {
        let s = app.batch.summary
        let running = app.batch.state == .running
        return FlowLayout(spacing: 8, lineSpacing: 6) {
            QueueCountChip(value: processing, label: L("running", "运行中"), symbol: "waveform.path.ecg", color: .accentColor)
            QueueCountChip(value: waiting, label: L("waiting", "等待中"), symbol: "clock", color: .secondary)
            if offline > 0 {
                QueueCountChip(value: offline, label: L("waiting for an offline drive", "等待离线磁盘"),
                               symbol: "externaldrive.badge.exclamationmark", color: Palette.warning)
            }
            QueueCountChip(value: s.finished, label: running ? L("done this batch", "本批已完成") : L("done in the last batch", "上一批已完成"),
                           symbol: "checkmark.circle", color: Palette.success)
            if s.needsReview > 0 {
                Button {
                    app.show(.review)
                } label: {
                    QueueCountChip(value: s.needsReview, label: L("need QC review", "待 QC 复核"), symbol: "checklist", color: Palette.warning)
                }
                .buttonStyle(.plain)
                .help(L("Show the videos that need a QC decision", "显示需要 QC 决定的视频"))
            }
            QueueCountChip(value: failed, label: L("failed", "失败"), symbol: "exclamationmark.triangle",
                           color: failed > 0 ? Palette.danger : Color.secondary)
            if !running, s.seconds > 0, s.finished + s.failed > 0 {
                Text(String(format: L("Last batch took %@", "上一批用时 %@"), ImportSheetModel.span(s.seconds)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Overall progress, speed and time left — the only part of the header that changes every tick.
@MainActor
struct QueueLiveProgress: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let fraction = app.batch.overallFraction.map { min(1, max(0, $0.finiteOr(0))) }
        HStack(spacing: 10) {
            ProgressView(value: fraction)
                .frame(maxWidth: .infinity)
            Text(detail(fraction))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func detail(_ fraction: Double?) -> String {
        let batch = app.batch
        let speed = batch.jobs.values.reduce(0.0) { $0 + $1.fps.finiteOr(0) }
        var parts: [String] = []
        if let fraction { parts.append(Fmt.percent(fraction)) }
        if speed > 0.5 { parts.append(String(format: L("%.0f frames/s", "%.0f 帧/秒"), speed)) }
        parts.append(Fmt.remaining(batch.queueSecondsLeft))
        return parts.joined(separator: " · ")
    }
}

struct QueueCountChip: View {
    let value: Int
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text("\(value)").fontWeight(.semibold).monospacedDigit().foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Palette.inset, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Failed

@MainActor
struct QueueFailedPanel: View {
    /// Newest first.
    let failed: [Recording]
    /// Height of the list (it scrolls beyond).
    var maxListHeight: CGFloat = 190
    @Environment(AppModel.self) private var app

    private static let shown = 30

    var body: some View {
        let list = Array(failed.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(format: L("Failed (%d)", "失败（%d）"), failed.count))
                    .font(.headline)
                    .foregroundStyle(Palette.danger)
                Text(L("most recent first", "最新的在前")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Show All", "全部显示")) { app.show(.failed) }
                    .buttonStyle(.link)
                Button {
                    app.retry(Set(failed.map(\.id)))
                } label: {
                    Text(L("Retry All", "全部重试"))
                }
                .controlSize(.small)
                .help(L("Queue every failed video again; each continues from its checkpoint when it has one.", "将所有失败的视频重新排队；有检查点的会从检查点继续。"))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { r in
                        QueueFailedRow(recording: r)
                        Divider()
                    }
                }
            }
            .frame(height: min(maxListHeight, CGFloat(list.count) * 48 + 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

@MainActor
struct QueueFailedRow: View {
    let recording: Recording
    @Environment(AppModel.self) private var app

    var body: some View {
        let r = recording
        let store = app.store
        let missing = store.missingVideos.contains(r.id)
        let reason = r.failure ?? L("Unknown reason.", "原因未知。")
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName(r)).font(.callout.weight(.semibold)).lineLimit(1)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(reason)
            }
            Spacer(minLength: 8)
            Text(Fmt.date(r.updatedAt)).font(.caption).foregroundStyle(.secondary)
            if missing {
                Button(L("Locate…", "定位…")) { app.locateVideo(r.id) }
                    .controlSize(.small)
                    .help(L("The file cannot be found: choose where it is now", "找不到该文件：请选择它现在的位置"))
            }
            Button(L("Retry", "重试")) { app.retry([r.id]) }
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.open(.recording(r.id)) }
        .contextMenu {
            Button(L("Retry", "重试")) { app.retry([r.id]) }
            Button(L("Open Video Page", "打开视频页面")) { app.open(.recording(r.id)) }
            Button(L("Show in Finder", "在访达中显示")) { app.revealVideo(r) }
            Button(L("Locate Video…", "定位视频…")) { app.locateVideo(r.id) }
            Divider()
            Button(L("Copy Reason", "拷贝原因")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reason, forType: .string)
            }
        }
    }
}

// MARK: - Finished

/// The Processing page once every video is tracked: what the batch did, where the results are and
/// the next step (review the QC of videos that need it, assign tasks, open the analyses).
@MainActor
struct QueueFinishedState: View {
    @Environment(AppModel.self) private var app

    private struct Counts {
        var tracked = 0
        var review: [UUID] = []
        var checking = 0
        var included = 0
        var excluded = 0
        var noTask: [UUID] = []
        var analyses = 0
        /// The task of the most recently tracked video (where its results are).
        var latestTask: TaskRef?
    }

    private var counts: Counts {
        let store = app.store
        var c = Counts()
        let withAnalyses = Set(store.sessions.compactMap(\.recordingID))
        c.analyses = store.sessions.count
        var latest: (Date, TaskRef)?
        for s in store.sessions {
            guard let r = store.recording(for: s), r.status == .ready, let eid = r.experimentID else { continue }
            let t = TaskRef(experimentID: eid, assay: s.assay)
            let when = r.updatedAt
            if latest == nil || when > latest!.0, store.taskExists(t) { latest = (when, t) }
        }
        c.latestTask = latest?.1
        let outside = Set(store.recordingsNotInTask.map(\.id))
        for r in store.recordings where r.status == .ready {
            c.tracked += 1
            switch r.decision {
            case .pending:
                if r.qc == nil { c.checking += 1 } else { c.review.append(r.id) }
            case .included:
                c.included += 1
                if outside.contains(r.id) && !withAnalyses.contains(r.id) { c.noTask.append(r.id) }
            case .excluded:
                c.excluded += 1
            }
        }
        return c
    }

    var body: some View {
        let c = counts
        let s = app.batch.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("All videos are tracked", "全部视频已识别完成"))
                            .font(.title2.weight(.bold))
                        Text(summaryLine(c, s))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(L("The pose and the QC report are saved with each video. Videos that pass QC are included automatically; the others wait for your decision. Included videos are analysed by their task; results are on the task's page, by group.",
                       "姿态数据和 QC 报告已随每个视频保存。QC 通过的视频会自动纳入，其余视频等待你的决定。纳入的视频按所属任务分析，结果按组显示在任务页面。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    if !c.review.isEmpty {
                        step(symbol: "checklist", color: Palette.warning,
                             title: String(format: L("%d video(s) need a QC decision", "%d 段视频需要 QC 决定"), c.review.count),
                             detail: L("Check the tracking on the QC player, then include or exclude (keys I / E).",
                                       "在 QC 播放器中检查识别结果，然后纳入或排除（按键 I / E）。"),
                             button: L("Review Now", "立即复核"), primary: true) {
                            app.show(.review)
                        }
                    }
                    if c.checking > 0 {
                        step(symbol: "hourglass", color: .secondary,
                             title: String(format: L("Checking the quality of %d video(s)…", "正在检查 %d 段视频的质量…"), c.checking),
                             detail: L("Takes a few seconds per video.", "每段视频需要几秒钟。"),
                             button: nil, primary: false) {}
                    }
                    if !c.noTask.isEmpty {
                        step(symbol: "plus.square.on.square", color: .accentColor,
                             title: String(format: L("%d included video(s) are not in a task", "%d 段已纳入的视频不属于任何任务"), c.noTask.count),
                             detail: L("Move them into a task to analyse them with its paradigm and groups.",
                                       "将它们移到某个任务中，即可按该任务的范式和分组进行分析。"),
                             button: L("Move to Task…", "移到任务…"), primary: c.review.isEmpty) {
                            app.assignRequest = AssignRequest(recordings: Set(c.noTask))
                        }
                    }
                    if c.analyses > 0, let t = c.latestTask {
                        step(symbol: "chart.bar.xaxis", color: Palette.success,
                             title: String(format: L("%d analysis(es) ready", "%d 个分析已就绪"), c.analyses),
                             detail: L("Results, the behaviour segments and the review player are in each analysis; export them from there or with ⌘E.",
                                       "每个分析中都有结果、行为片段和复核播放器；可在其中导出，或使用 ⌘E。"),
                             button: L("Open Task", "打开任务"), primary: c.review.isEmpty && c.noTask.isEmpty) {
                            app.show(.task(t))
                        }
                    }
                    step(symbol: "film.stack", color: .secondary,
                         title: String(format: L("%d tracked video(s) in the library", "资料库中有 %d 段已识别视频"), c.tracked),
                         detail: String(format: L("%d included · %d excluded", "已纳入 %d · 已排除 %d"), c.included, c.excluded),
                         button: L("All Videos", "全部视频"), primary: false) {
                        app.show(.videos)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        app.chooseFilesToImport()
                    } label: {
                        Text(L("Import More Videos…", "导入更多视频…"))
                    }
                    Text(L("or drop videos and folders on the window", "或将视频和文件夹拖入窗口"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .pageContent(maxWidth: 760)
            .padding(.vertical, 28)
        }
    }

    private func summaryLine(_ c: Counts, _ s: BatchSummary) -> String {
        var parts: [String] = []
        if s.finished > 0 {
            parts.append(String(format: L("%d tracked in the last batch", "上一批识别了 %d 段"), s.finished))
            if s.seconds > 0 { parts.append(String(format: L("in %@", "用时 %@"), ImportSheetModel.span(s.seconds))) }
        } else {
            parts.append(String(format: L("%d tracked videos", "%d 段已识别视频"), c.tracked))
        }
        if s.failed > 0 { parts.append(String(format: L("%d failed", "%d 段失败"), s.failed)) }
        return parts.joined(separator: " · ")
    }

    private func step(symbol: String, color: Color, title: String, detail: String, button: String?, primary: Bool,
                      action: @escaping () -> Void) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if let button {
                    if primary {
                        Button(button, action: action).buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        Button(button, action: action).controlSize(.large)
                    }
                }
            }
        }
    }
}

