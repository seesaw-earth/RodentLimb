// AnalysisDetailView.swift — one analysis (one task applied to one video) on the Mac.
// Header (task, animal, group · timepoint, video file, status, link to the video & QC), then the
// three tabs of the iPhone app chosen in the toolbar — Summary, Review, Measures. Parameters live
// in the window's inspector (live re-analysis), calibration in a sheet (cylinder, gait).
// States: deleted · waiting for tracking · failed · needs calibration · loading · re-analysing.
//
// Smoothness: this page never observes the player. The result is loaded with `.task(id:)` and
// re-read when the analysis changes (`updatedAt`); the pose and the player are created only when
// the Review tab is first shown, and released when the page goes away.

import SwiftUI

@MainActor
struct AnalysisDetailView: View {
    let id: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager

    @State private var tab: AnalysisDetailTab = .summary
    @State private var result: AnalysisResult?
    @State private var resultLoaded = false
    @State private var requestedAnalysis = false
    @State private var track: PoseTrack?
    @State private var poseUnreadable = false
    // Held without observing it (an ObservableObject in @State is not subscribed to): the page
    // must not redraw on every player tick. ReviewPlayer and the small playhead views observe it
    // (or the coarse clock) themselves.
    @State private var controller: PlayerController?
    @State private var clock = ResultsPlaybackClock()
    /// A seek asked for before the player exists (chart clicked on the Summary tab).
    @State private var pendingSeek: Double?
    @State private var visible = false
    @State private var showCalibration = false
    @State private var confirmDelete = false

    private var store: SessionStore { app.store }

    private struct ResultKey: Hashable {
        var stamp: Date?
        var hasPose: Bool
    }

    private struct ReviewKey: Hashable {
        var active: Bool
        var hasPose: Bool
        var recordingID: UUID?
    }

    var body: some View {
        @Bindable var app = app
        let s = store.session(id)
        // No minimum of its own beside the inspector (see AdaptiveLayout.swift).
        content(s)
            .pageFrame()
            .navigationTitle(title(s))
            .navigationSubtitle(s?.assay.name.text ?? "")
            .toolbar { toolbarContent(s) }
            // Only while this page is the top of the stack (one inspector per window). Only the page on
            // top writes the setting back: a page being covered or uncovered never turns it off.
            .inspector(isPresented: Binding(get: { app.showInspector && app.path.last == .analysis(id) },
                                            set: { v in if app.path.last == .analysis(id), app.showInspector != v { app.showInspector = v } })) {
                AnalysisParametersPanel(id: id, result: result)
                    .environment(app)
                    .pageFrame(alignment: .top)
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationSheet(id: id)
                    .environment(app)
            }
            .confirmationDialog(L("Delete this analysis?", "删除该分析？"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Delete Analysis", "删除分析"), role: .destructive) { deleteAnalysis() }
                Button(L("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(L("The video, its tracking and QC stay, and the other tasks of the video are not affected.",
                       "视频及其识别结果和 QC 会保留，该视频的其他任务不受影响。"))
            }
            .task(id: ResultKey(stamp: s?.updatedAt, hasPose: s?.hasPose ?? false)) { await loadResult() }
            .task(id: ReviewKey(active: tab == .review && visible, hasPose: s?.hasPose ?? false, recordingID: s?.recordingID)) {
                await prepareReview()
            }
            .onChange(of: tab) { _, new in
                if new != .review { controller?.pause() }
            }
            .onChange(of: s == nil) { _, gone in
                if gone { releasePlayer() }
            }
            .onAppear { visible = true }
            .onDisappear {
                visible = false
                releasePlayer()
            }
            .background { tabShortcuts }
    }

    private func title(_ s: Session?) -> String {
        guard let s else { return L("Analysis", "分析") }
        return store.recording(for: s).map { store.displayName($0) } ?? s.displayName
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ s: Session?) -> some View {
        if let s {
            let rec = store.recording(for: s)
            VStack(spacing: 0) {
                AnalysisHeader(session: s, recording: rec)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                // The view switch belongs to the page (not the toolbar, where it would compete with the
                // actions and could be pushed into the overflow menu on a narrow window).
                HStack {
                    Picker(L("View", "视图"), selection: $tab) {
                        ForEach(AnalysisDetailTab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(result == nil)
                    .help(L("Summary · Review · Measures (⌥⌘1, ⌥⌘2, ⌥⌘3)", "概览 · 回放 · 全部指标（⌥⌘1、⌥⌘2、⌥⌘3）"))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                banners(s, rec)
                Divider()
                main(s, rec)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            EmptyState(title: L("Analysis deleted", "该分析已删除"),
                       message: L("This analysis no longer exists. The video and its other tasks are not affected.",
                                  "该分析已不存在；视频及其其他任务不受影响。"),
                       symbol: "trash")
        }
    }

    @ViewBuilder
    private func banners(_ s: Session, _ rec: Recording?) -> some View {
        let offline = rec.map { store.missingVideos.contains($0.id) } ?? false
        let needsCalibration = s.assay == .cylinder && !s.isCalibrated
        let copied = (s.assay == .cylinder || s.assay == .gait) ? (s.calibration.copiedFrom ?? "") : ""
        if offline || needsCalibration || !copied.isEmpty {
            VStack(spacing: 8) {
                if offline, let rec {
                    HStack(spacing: 10) {
                        Banner(text: L("The video file is offline (drive not connected, or the file was moved). Results stay available; the review player needs the file.",
                                       "视频文件离线（磁盘未连接或文件已移动）。结果仍可查看；回放需要该文件。"), level: .warning)
                        Button(L("Locate…", "定位…")) { app.locateVideo(rec.id) }
                    }
                }
                if needsCalibration {
                    HStack(spacing: 10) {
                        Banner(text: s.params.cylinder.view == .bottom
                               ? L("One step left: mark the cylinder rim so wall contacts can be found.", "还差一步：标定圆筒边缘，以便检测触壁。")
                               : L("One step left: mark the floor of the cylinder.", "还差一步：标定圆筒底面。"),
                               level: .warning)
                        Button(L("Calibrate…", "标定…")) { showCalibration = true }
                    }
                } else if !copied.isEmpty {
                    HStack(spacing: 10) {
                        Banner(text: String(format: L("Calibration reused from %@ (same camera). Check that it fits this video.",
                                                      "标定沿用自 %@（同一相机）。请检查是否适合本视频。"), copied))
                        Button(L("Check…", "检查…")) { showCalibration = true }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func main(_ s: Session, _ rec: Recording?) -> some View {
        if !s.hasPose {
            switch s.status {
            case .failed:
                failure(s, rec)
            case .queued, .processing:
                AnalysisTrackingStatus(recordingID: s.recordingID)
            case .needsSetup, .done:
                if rec == nil { failure(s, rec) } else { AnalysisTrackingStatus(recordingID: s.recordingID) }
            }
        } else if let r = result {
            tabContent(s, r)
        } else if resultLoaded && !store.analysing.contains(id) {
            VStack(spacing: 12) {
                EmptyState(title: L("No result yet", "暂无结果"),
                           message: L("This analysis has not been computed yet.", "该分析尚未计算。"),
                           symbol: "chart.bar.xaxis")
                Button(L("Analyse Now", "立即分析")) { store.analyze(id) }
                    .padding(.bottom, 30)
            }
        } else {
            ProgressView(store.analysing.contains(id) ? L("Analysing…", "正在分析…") : L("Loading the result…", "正在加载结果…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tabContent(_ s: Session, _ r: AnalysisResult) -> some View {
        switch tab {
        case .summary:
            AnalysisSummaryTab(session: s, result: r, goReview: goReview)
        case .review:
            AnalysisReviewTab(session: s, result: r, track: track, controller: controller, clock: clock,
                              poseUnreadable: poseUnreadable, relabel: relabel, restore: restoreLabels)
        case .measures:
            AnalysisMeasuresTab(session: s, result: r, goReview: goReview)
        }
    }

    private func failure(_ s: Session, _ rec: Recording?) -> some View {
        VStack(spacing: 12) {
            Text(rec == nil ? L("The video is missing", "视频已丢失") : L("Tracking failed", "识别失败"))
                .font(.title3.weight(.semibold))
            Text(s.failure ?? rec?.failure ?? L("The pose model could not process this video.", "姿态模型无法处理该视频。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let rec {
                HStack(spacing: 10) {
                    Button {
                        app.retry([rec.id])
                    } label: {
                        Text(L("Retry", "重试"))
                    }
                    .keyboardShortcut(.defaultAction)
                    if store.missingVideos.contains(rec.id) {
                        Button(L("Locate Video…", "定位视频…")) { app.locateVideo(rec.id) }
                    }
                    Button(L("Video & QC", "视频与 QC")) { app.open(.recording(rec.id)) }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 480)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ s: Session?) -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if let s, s.assay == .cylinder || s.assay == .gait {
                Button {
                    showCalibration = true
                } label: {
                    Text(L("Calibrate", "标定"))
                }
                .help(s.assay == .gait ? L("Set the cm scale with a ruler in the video", "用视频中的标尺设定厘米比例")
                                       : L("Mark the cylinder rim or floor on a frame of the video", "在视频画面上标定圆筒边缘或底面"))
            }
            Menu {
                if let rid = s?.recordingID {
                    Button(L("Open Video & QC", "打开视频与 QC")) { app.open(.recording(rid)) }
                    Button(L("Show Video in Finder", "在访达中显示视频")) {
                        if let r = store.recording(rid) { app.revealVideo(r) }
                    }
                    Divider()
                }
                Button(L("Re-analyse Now", "立即重新分析")) { store.analyze(id) }
                    .disabled(s?.hasPose != true)
                Divider()
                Button(L("Delete Analysis…", "删除分析…"), role: .destructive) { confirmDelete = true }
                    .disabled(s == nil)
            } label: {
                Text(L("More", "更多"))
            }
            .help(L("More actions for this analysis", "该分析的更多操作"))
            Button {
                app.export(.selection(analyses: [id], recordings: []))
            } label: {
                Text(L("Export Analysis", "导出该分析"))
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(s == nil)
            .help(L("Export this analysis (⇧⌘E)", "导出该分析（⇧⌘E）"))
            Button {
                app.showInspector.toggle()
            } label: {
                Text(L("Parameters", "参数"))
            }
            .help(L("Show or hide the parameters (⌃⌘I)", "显示或隐藏参数（⌃⌘I）"))
        }
    }

    /// ⌥⌘1 / ⌥⌘2 / ⌥⌘3 switch tabs (⌘1…⌘4 are the sidebar's).
    private var tabShortcuts: some View {
        HStack(spacing: 0) {
            Button("") { selectTab(.summary) }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("") { selectTab(.review) }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("") { selectTab(.measures) }.keyboardShortcut("3", modifiers: [.command, .option])
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Loading

    private func loadResult() async {
        guard let s = store.session(id) else { return }
        guard s.hasPose else {
            result = nil
            resultLoaded = false
            requestedAnalysis = false
            return
        }
        let r = await store.result(id)
        guard !Task.isCancelled else { return }
        if let r {
            if result?.analyzedAt != r.analyzedAt { result = r }
        } else if !requestedAnalysis && !store.analysing.contains(id) {
            // No stored result (never analysed, or the file is gone): compute it once.
            requestedAnalysis = true
            store.analyze(id)
        }
        resultLoaded = true
    }

    /// Loads the pose and creates the player the first time the Review tab is shown.
    private func prepareReview() async {
        guard let s = store.session(id), s.hasPose else {
            releasePlayer()
            track = nil
            poseUnreadable = false
            return
        }
        guard tab == .review, visible else { return }
        let loaded = await store.pose(id)
        guard !Task.isCancelled, tab == .review, visible else { return }
        poseUnreadable = loaded == nil
        guard let t = loaded else { return }
        track = t
        guard controller == nil, let rec = store.recording(for: s) else { return }
        let c = PlayerController.make(store: store, recording: rec, track: t)
        controller = c
        if let p = pendingSeek {
            c.seek(p)
            pendingSeek = nil
        }
    }

    private func releasePlayer() {
        controller?.teardown()
        controller = nil
    }

    // MARK: Actions

    private func selectTab(_ t: AnalysisDetailTab) {
        guard result != nil else { return }
        tab = t
    }

    /// Opens the Review tab at a track time (charts on the other tabs).
    private func goReview(_ t: Double) {
        guard t.isFinite else { return }
        tab = .review
        if let c = controller { c.seek(max(0, t)) } else { pendingSeek = max(0, t) }
    }

    private func deleteAnalysis() {
        releasePlayer()
        let entry = store.delete([id])
        if app.path.last == .analysis(id) { app.path.removeLast() }
        app.deleted(entry, message: L("Analysis moved to Recently Deleted", "分析已移到“最近删除”"))
    }

    /// Stores the reviewer's labels exactly like the iPhone app: cylinder → `overrides[event] =
    /// PawLabel`, behavior → `eventOverrides[event] = class key`; setting an event back to its
    /// automatic label removes the override. Then re-analyses (undoable with ⌘Z).
    private func relabel(_ ids: Set<Int>, _ key: String) {
        guard !ids.isEmpty, let r = result, let before = store.session(id) else { return }
        if let d = r.cylinder {
            guard let label = PawLabel(rawValue: key) else { return }
            var autos: [Int: PawLabel] = [:]
            for e in d.events where ids.contains(e.id) { autos[e.id] = e.auto }
            guard !autos.isEmpty else { return }
            store.update(id) { s in
                for (eid, auto) in autos { s.overrides[eid] = auto == label ? nil : label }
            }
        } else if let d = r.behavior {
            var autos: [Int: String] = [:]
            for e in d.events where ids.contains(e.id) { autos[e.id] = e.auto }
            guard !autos.isEmpty else { return }
            store.update(id) { s in
                var o = s.eventOverrides ?? [:]
                for (eid, auto) in autos { o[eid] = auto == key ? nil : key }
                s.eventOverrides = o.isEmpty ? nil : o
            }
        } else {
            return
        }
        finishEdit(before, name: ids.count > 1 ? L("Relabel Events", "修改事件标签") : L("Relabel Event", "修改事件标签"))
    }

    /// Removes the reviewer's labels of these events (back to the automatic call).
    private func restoreLabels(_ ids: Set<Int>) {
        guard !ids.isEmpty, let r = result, let before = store.session(id) else { return }
        if r.cylinder != nil {
            store.update(id) { s in for eid in ids { s.overrides[eid] = nil } }
        } else if r.behavior != nil {
            store.update(id) { s in
                var o = s.eventOverrides ?? [:]
                for eid in ids { o[eid] = nil }
                s.eventOverrides = o.isEmpty ? nil : o
            }
        } else {
            return
        }
        finishEdit(before, name: L("Restore Automatic Labels", "恢复自动标签"))
    }

    private func finishEdit(_ before: Session, name: String) {
        guard let after = store.session(id) else { return }
        guard after.overrides != before.overrides || after.eventOverrides != before.eventOverrides else { return }
        registerUndo(before, name: name)
        store.analyze(id)
    }

    private func registerUndo(_ before: Session, name: String) {
        guard let um = undoManager else { return }
        let sid = id
        let overrides = before.overrides
        let eventOverrides = before.eventOverrides
        um.registerUndo(withTarget: store) { target in
            MainActor.assumeIsolated {
                target.update(sid) { s in
                    s.overrides = overrides
                    s.eventOverrides = eventOverrides
                }
                target.analyze(sid)
            }
        }
        um.setActionName(name)
    }
}

// MARK: - Header

/// Task badge, animal, group · timepoint, video file and status, link to the video's page, and a
/// small spinner while the analysis is recomputed.
@MainActor
private struct AnalysisHeader: View {
    let session: Session
    let recording: Recording?
    @Environment(AppModel.self) private var app

    var body: some View {
        let store = app.store
        let name = recording.map { store.displayName($0) } ?? session.displayName
        let group = recording.map { store.groupLabel($0) } ?? session.group
        HStack(alignment: .center, spacing: 12) {
            AssayBadge(assay: session.assay, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if store.analysing.contains(session.id) {
                        ProgressView()
                            .controlSize(.small)
                            .help(L("Re-analysing…", "正在重新分析…"))
                    }
                }
                Text([session.assay.name.text, group].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let recording {
                    HStack(spacing: 8) {
                        Text(store.fileLabel(recording))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.fileLabel(recording))
                        RecordingStatusTag(recording: recording, missing: store.missingVideos.contains(recording.id))
                        if let qc = recording.qc { QCBadge(report: qc) }
                    }
                }
            }
            Spacer(minLength: 12)
            if let recording {
                Button {
                    app.open(.recording(recording.id))
                } label: {
                    Text(L("Video & QC", "视频与 QC"))
                }
                .buttonStyle(.link)
                .help(L("Open the video, its tracking quality and inclusion decision", "打开视频、识别质量和纳入决定"))
            }
        }
    }
}
