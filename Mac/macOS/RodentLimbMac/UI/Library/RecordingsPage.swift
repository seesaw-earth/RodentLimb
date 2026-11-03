// RecordingsPage.swift — a page of videos (All Videos, Needs Review, Failed, Processing): the table,
// the page's toolbar (include, exclude, assign tasks, retry) and an inspector that summarises the
// selection — one video with its frame, facts, QC and decision; several with counts and batch
// buttons. Needs Review is a fast review mode: I includes, E excludes (with a reason), ↑/↓ move,
// and after a decision the next video is selected.

import SwiftUI
import AppKit

@MainActor
struct RecordingsPage: View {
    let filter: RecordingFilter

    @Environment(AppModel.self) private var app
    @State private var selection = Set<UUID>()
    @State private var sortOrder: [KeyPathComparator<RecordingsRow>]
    @State private var excludeRequest: RecordingsExcludeRequest?
    @FocusState private var tableFocused: Bool

    init(filter: RecordingFilter) {
        self.filter = filter
        self._sortOrder = State(initialValue: RecordingsQuery.defaultSort(filter))
    }

    private var isReview: Bool {
        if case .needsReview = filter { return true }
        return false
    }

    private var orderedIDs: [UUID] {
        RecordingsQuery.orderedIDs(app.store, filter: filter, search: app.search, sort: sortOrder)
    }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            if isReview { reviewBar }
            RecordingsTable(filter: filter, selection: $selection, sortOrder: $sortOrder)
                .focused($tableFocused)
                .onKeyPress(characters: CharacterSet(charactersIn: "ieIE"), phases: .down) { press in
                    handleKey(press)
                }
        }
        // No minimum of its own beside the inspector (see AdaptiveLayout.swift).
        .pageFrame()
        .toolbar { pageToolbar }
        .searchable(text: $app.search, placement: .toolbar,
                    prompt: L("Animal, file, task, timepoint", "动物、文件、任务、时间点"))
        // Only while this page is on top: a session pushed over it has its own inspector, and two
        // inspectors in one window fight over the same column.
        .inspector(isPresented: Binding(get: { app.showInspector && app.path.isEmpty },
                                        set: { v in if app.path.isEmpty, app.showInspector != v { app.showInspector = v } })) {
            RecordingsInspector(selection: selection, review: isReview,
                                include: { include($0) }, exclude: { beginExclude($0) })
                .environment(app)
                .pageFrame(alignment: .top)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 440)
        }
        .sheet(item: $excludeRequest) { req in
            RecordingsExcludeSheet(count: req.ids.count, initialReason: req.initialReason) { reason in
                RecordingsActions.exclude(req.ids, reason: reason, app: app)
                if isReview, let next = req.next { selection = [next] }
                tableFocused = true
            }
        }
        .onAppear {
            if isReview {
                if selection.isEmpty, let first = orderedIDs.first { selection = [first] }
                tableFocused = true
            }
        }
    }

    // MARK: Review mode

    private var reviewBar: some View {
        HStack(spacing: 10) {
            Text(L("Fast review: I include · E exclude with a reason · ↑ ↓ previous / next. Double-click a video to check it on the QC player.",
                   "快速复核：I 纳入 · E 排除并填写原因 · ↑ ↓ 上一个 / 下一个。双击视频可在 QC 播放器中查看。"))
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            let pending = app.counts.review
            Text(String(format: L("%d to review", "待复核 %d 段"), pending))
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.inset)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard isReview, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let ids = selection
        guard !ids.isEmpty else { return .ignored }
        switch press.characters.lowercased() {
        case "i":
            include(ids)
            return .handled
        case "e":
            beginExclude(ids)
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: Actions

    private func include(_ ids: Set<UUID>) {
        let next = RecordingsActions.next(after: ids, in: orderedIDs)
        if RecordingsActions.include(ids, app: app) > 0, isReview, let next { selection = [next] }
    }

    private func beginExclude(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let reasons = Set(ids.compactMap { app.store.recording($0)?.exclusionReason })
        let initial = reasons.count == 1 ? (reasons.first ?? "") : ""
        excludeRequest = RecordingsExcludeRequest(ids: ids, initialReason: initial,
                                                  next: RecordingsActions.next(after: ids, in: orderedIDs))
    }

    private var selectedRecordings: [Recording] { selection.compactMap { app.store.recording($0) } }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var pageToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            let recs = selectedRecordings
            let failed = Set(recs.filter { $0.status == .failed }.map(\.id))
            if case .failed = filter {
                Button {
                    let all = Set(app.store.recordings.filter { $0.status == .failed }.map(\.id))
                    let ids = failed.isEmpty ? all : failed
                    app.retry(ids)
                    app.toast = String(format: L("%d video(s) queued again", "%d 段视频已重新排队"), ids.count)
                } label: {
                    Text(failed.isEmpty ? L("Retry All", "全部重试") : L("Retry", "重试"))
                }
                .help(L("Queue the failed videos again and start tracking", "将失败的视频重新排队并开始识别"))
            }
            Button {
                include(selection)
            } label: {
                Text(L("Include", "纳入"))
            }
            .disabled(!recs.contains { $0.isProcessed && $0.decision != .included })
            .help(isReview ? L("Include the selected videos (I)", "纳入所选视频（I）") : L("Include the selected videos", "纳入所选视频"))

            Button {
                beginExclude(selection)
            } label: {
                Text(L("Exclude…", "排除…"))
            }
            .disabled(recs.isEmpty)
            .help(isReview ? L("Exclude the selected videos with a reason (E)", "排除所选视频并填写原因（E）")
                  : L("Exclude the selected videos with a reason", "排除所选视频并填写原因"))

        }
        ToolbarItem(placement: .automatic) {
            Button {
                app.showInspector.toggle()
            } label: {
                Text(L("Inspector", "检查器"))
            }
            .help(L("Show or hide the inspector", "显示或隐藏检查器"))
        }
    }
}

// MARK: - Inspector

@MainActor
private struct RecordingsInspector: View {
    let selection: Set<UUID>
    let review: Bool
    let include: (Set<UUID>) -> Void
    let exclude: (Set<UUID>) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let recs = selection.compactMap { app.store.recording($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if recs.count == 1, let r = recs.first {
                    single(r)
                } else if recs.count > 1 {
                    multiple(recs)
                } else {
                    EmptyState(title: L("No selection", "未选择"),
                               message: L("Select a video to see its QC and decision here. Select several for batch actions.",
                                          "选择一段视频可在此查看 QC 与纳入决定；选择多段可进行批量操作。"),
                               symbol: "sidebar.trailing")
                        .padding(.top, 40)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: One video

    @ViewBuilder
    private func single(_ r: Recording) -> some View {
        let store = app.store
        let missing = store.missingVideos.contains(r.id)
        VStack(alignment: .leading, spacing: 16) {
            singleHeader(r, missing: missing)
            singleQC(r)
        }
        Divider()
        decision(r)
        Divider()
        tasks(r)
        openButtons(r)
    }

    @ViewBuilder
    private func singleHeader(_ r: Recording, missing: Bool) -> some View {
        let store = app.store
        RecordingsPreviewImage(recording: r)
        VStack(alignment: .leading, spacing: 4) {
            Text(RecordingsQuery.animalLabel(r, store: store)).font(.title3.weight(.semibold)).lineLimit(2).textSelection(.enabled)
            if let e = store.experiment(for: r) {
                Text(e.name).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            let g = store.groupLabel(r)
            if !g.isEmpty { Text(g).font(.callout).foregroundStyle(.secondary) }
            Text(store.fileLabel(r)).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
        HStack(spacing: 6) {
            RecordingsStatusCell(recording: r, missing: missing, batch: app.batch)
            if r.decision != .pending && r.status != .ready { RecordingsDecisionCell(recording: r) }
        }
        statusDetails(r, missing: missing)

        VStack(alignment: .leading, spacing: 5) {
            InfoRow(key: L("Pose model", "姿态模型"), value: store.poseModel(r.id).shortTitle.text)
            InfoRow(key: L("Duration", "时长"), value: r.duration.map { Fmt.clock($0) } ?? "—")
            InfoRow(key: L("Frame rate", "帧率"), value: Fmt.fps(r.fps))
            if let w = r.videoWidth, let h = r.videoHeight, w > 0, h > 0 {
                InfoRow(key: L("Frame size", "画面尺寸"), value: "\(w)×\(h)")
            }
            InfoRow(key: L("Trial", "试次"), value: "\(r.trial)")
            InfoRow(key: r.recordedOn == nil ? L("Imported", "导入于") : L("Recorded", "录制于"),
                    value: Fmt.day(r.recordedOn ?? r.createdAt))
        }
    }

    @ViewBuilder
    private func singleQC(_ r: Recording) -> some View {
        if let qc = r.qc {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    QCBadge(report: qc)
                    Spacer()
                }
                InfoRow(key: L("Mouse tracked", "小鼠可用帧"), value: Fmt.percent(qc.coreCoverage))
                InfoRow(key: L("Longest loss", "最长丢失"), value: String(format: L("%.1f s", "%.1f 秒"), qc.longestLost.finiteOr(0)))
                InfoRow(key: L("Implausible jumps", "不合理跳点"), value: Fmt.percent(qc.jumpRate, 1))
                RecordingsQCTimeline(timeline: qc.timeline, height: 12)
                NoteList(notes: qc.issues)
            }
        } else if r.isProcessed {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Checking tracking quality…", "正在检查追踪质量…")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func openButtons(_ r: Recording) -> some View {
        HStack {
            Button {
                app.open(.recording(r.id))
            } label: {
                Text(L("Open", "打开"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help(L("Open the video page with the QC player (double-click)", "打开视频页面与 QC 播放器（双击）"))
            Button(L("Export…", "导出…")) {
                app.export(.selection(analyses: [], recordings: [r.id]))
            }
            .help(L("Export this video's analyses and QC", "导出该视频的分析与 QC"))
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private func statusDetails(_ r: Recording, missing: Bool) -> some View {
        if missing {
            Banner(text: L("The video file cannot be found (drive not connected, or the file was moved).",
                           "找不到视频文件（磁盘未连接或文件已被移动）。"), level: .warning)
            Button(L("Locate Video…", "定位视频…")) { app.locateVideo(r.id) }
        }
        if r.status == .failed {
            Banner(text: r.failure ?? L("Tracking failed.", "识别失败。"), level: .error)
            Button {
                app.retry([r.id])
            } label: {
                Text(L("Retry", "重试"))
            }
        }
    }

    @ViewBuilder
    private func decision(_ r: Recording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Decision", "纳入决定")).font(.headline)
            HStack(spacing: 6) {
                Tag(text: r.decision.label, color: Palette.decision(r.decision))
                Spacer()
            }
            if r.decision == .excluded && !r.exclusionReason.isEmpty {
                Text(RecordingsExclusion.display(r.exclusionReason))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button {
                    include([r.id])
                } label: {
                    Text(review ? L("Include (I)", "纳入（I）") : L("Include", "纳入"))
                }
                .disabled(!r.isProcessed || r.decision == .included)
                Button {
                    exclude([r.id])
                } label: {
                    Text(review ? L("Exclude… (E)", "排除…（E）") : L("Exclude…", "排除…"))
                }
            }
            if r.decision != .pending {
                Button(L("Back to Needs Review", "退回待复核")) { RecordingsActions.backToReview([r.id], app: app) }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private func tasks(_ r: Recording) -> some View {
        let sessions = app.store.sessions(of: r.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Tasks", "任务")).font(.headline)
                Spacer()
                Button(L("Move to Task…", "移到任务…")) { app.assignRequest = AssignRequest(recordings: [r.id]) }
                    .controlSize(.small)
            }
            if sessions.isEmpty && r.plannedAssays.isEmpty {
                Text(L("No task yet.", "还没有任务。")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(sessions) { s in
                Button {
                    app.open(.analysis(s.id))
                } label: {
                    HStack(spacing: 8) {
                        AssayBadge(assay: s.assay, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.assay.name.text).font(.callout.weight(.medium))
                            if let m = s.summary.first {
                                Text(m.label.text + " " + m.formatted + (m.unit.isEmpty ? "" : " " + m.unit))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                            } else {
                                Text(s.status.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if app.store.analysing.contains(s.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !r.plannedAssays.isEmpty {
                Text(String(format: L("Planned: %@ — created when the video is included.", "计划：%@——视频纳入后创建。"),
                            r.plannedAssays.map { $0.name.text }.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Several videos

    @ViewBuilder
    private func multiple(_ recs: [Recording]) -> some View {
        let store = app.store
        let ids = Set(recs.map(\.id))
        let tracked = recs.filter { $0.isProcessed }
        let failed = Set(recs.filter { $0.status == .failed }.map(\.id))
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: L("%d videos selected", "已选择 %d 段视频"), recs.count)).font(.title3.weight(.semibold))
            let studies = Set(recs.compactMap { $0.experimentID })
            Text(studies.isEmpty ? L("Outside any task", "未归入任务")
                 : String(format: L("From %d task(s)", "来自 %d 个任务"), studies.count))
                .font(.callout).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(L("Status", "状态")).font(.headline)
            ForEach(statusCounts(recs, store: store), id: \.text) { item in
                HStack {
                    Tag(text: item.text, color: item.color, symbol: item.symbol)
                    Spacer()
                    Text("\(item.count)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }

        let qcs = recs.compactMap { $0.qc }
        if !qcs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Tracking quality", "追踪质量")).font(.headline)
                ForEach(QCVerdict.allCases, id: \.self) { v in
                    let n = qcs.filter { $0.verdict == v }.count
                    if n > 0 {
                        HStack {
                            Tag(text: v.label.text, color: Palette.qc(v), symbol: v.symbol)
                            Spacer()
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                let mean = qcs.map { $0.coreCoverage.finiteOr(0) }.reduce(0, +) / Double(max(1, qcs.count))
                InfoRow(key: L("Mean mouse tracked", "平均可用帧"), value: Fmt.percent(mean))
            }
        }

        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Batch actions", "批量操作")).font(.headline)
            Button {
                include(ids)
            } label: {
                Text(String(format: L("Include All Tracked (%d)", "全部纳入已识别的（%d）"),
                             tracked.filter { $0.decision != .included }.count))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!tracked.contains { $0.decision != .included })
            Button {
                exclude(ids)
            } label: {
                Text(L("Exclude…", "排除…")).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                RecordingsActions.backToReview(ids, app: app)
            } label: {
                Text(L("Back to Needs Review", "退回待复核"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!recs.contains { $0.decision != .pending })
            Button {
                app.assignRequest = AssignRequest(recordings: ids)
            } label: {
                Text(L("Move to Task…", "移到任务…")).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                app.export(.selection(analyses: [], recordings: ids))
            } label: {
                Text(L("Export…", "导出…")).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !failed.isEmpty {
                Button {
                    app.retry(failed)
                } label: {
                    Text(String(format: L("Retry Failed (%d)", "重试失败的（%d）"), failed.count))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .controlSize(.regular)
    }

    private struct StatusCount {
        var text: String
        var color: Color
        var symbol: String
        var count: Int
    }

    private func statusCounts(_ recs: [Recording], store: SessionStore) -> [StatusCount] {
        var order: [String] = []
        var map: [String: StatusCount] = [:]
        for r in recs {
            let d = RecordingStatusTag.describe(r, missing: store.missingVideos.contains(r.id))
            if map[d.text] == nil {
                order.append(d.text)
                map[d.text] = StatusCount(text: d.text, color: d.color, symbol: d.symbol, count: 0)
            }
            map[d.text]?.count += 1
        }
        return order.compactMap { map[$0] }.sorted { $0.count > $1.count }
    }
}
