// RecordingsShared.swift — pieces shared by the video tables, the inspector and the video page:
// the rows a table shows (values precomputed from the store so every column can sort), filters and
// search, batch actions (include / exclude / back to review / delete / show in Finder) with their
// confirmation texts, the exclusion-reason sheet with the quick reasons of the iPhone app, lazy
// thumbnails, task badges, the live status cell and the QC coverage strip.

import SwiftUI
import AppKit

// MARK: - Rows

/// One video as the tables show it. Built on every update of the store (cheap: a few hundred rows).
struct RecordingsRow: Identifiable {
    let id: UUID
    let recording: Recording
    let animal: String
    let study: String
    let groupTimepoint: String
    let trial: Int
    let file: String
    let duration: Double
    let fps: Double
    let missing: Bool
    let statusRank: Int
    /// Share of frames with the mouse tracked (QC), -1 while there is no QC report.
    let coverage: Double
    let decisionRank: Int
    let assays: [Assay]
    let planned: [Assay]
    let taskCount: Int
    let created: Date
    /// Position in the processing queue (queue filter), Int.max when not queued.
    let queueOrder: Int
}

@MainActor
enum RecordingsQuery {
    static func matches(_ filter: RecordingFilter, _ r: Recording) -> Bool {
        switch filter {
        case .all: return true
        case .needsReview: return r.status == .ready && r.decision == .pending
        case .failed: return r.status == .failed
        case .queue: return r.status == .queued || r.status == .processing
        case .study(let id): return r.experimentID == id
        case .unassigned: return true
        }
    }

    /// Text search over animal, file name, study, timepoint and group (blinding respected: the
    /// labels used are the ones shown).
    static func matchesSearch(_ text: String, _ r: Recording, store: SessionStore) -> Bool {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let fields = [store.subjectLabel(r), store.fileLabel(r), store.experiment(for: r)?.name ?? "",
                      r.timepoint, store.groupLabel(r)]
        return fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Animal shown for a video: the animal (blind code while blinded), else the file name — but never
    /// the file name of a video in a blinded study (it often names the animal).
    static func animalLabel(_ r: Recording, store: SessionStore) -> String {
        let s = store.subjectLabel(r).trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        if store.experiment(for: r)?.blinded == true { return L("Animal ?", "动物 ?") }
        return r.originalName
    }

    static func rows(_ store: SessionStore, filter: RecordingFilter, search: String) -> [RecordingsRow] {
        var tasks: [UUID: Set<Assay>] = [:]
        for s in store.sessions {
            if let rid = s.recordingID { tasks[rid, default: []].insert(s.assay) }
        }
        var queueIndex: [UUID: Int] = [:]
        if case .queue = filter {
            for (i, r) in store.queuedRecordings.enumerated() { queueIndex[r.id] = i }
        }
        let missingSet = store.missingVideos
        var outside: Set<UUID>?
        if case .unassigned = filter { outside = Set(store.recordingsNotInTask.map(\.id)) }
        var out: [RecordingsRow] = []
        out.reserveCapacity(store.recordings.count)
        for r in store.recordings where matches(filter, r) && matchesSearch(search, r, store: store) {
            if let outside, !outside.contains(r.id) { continue }
            let own = tasks[r.id] ?? []
            let assays = Assay.allCases.filter { own.contains($0) }
            let planned = Assay.allCases.filter { r.plannedAssays.contains($0) && !own.contains($0) }
            let missing = missingSet.contains(r.id)
            let order = r.status == .processing ? -1 : (queueIndex[r.id] ?? Int.max)
            out.append(RecordingsRow(
                id: r.id, recording: r, animal: animalLabel(r, store: store),
                study: store.experiment(for: r)?.name ?? "",
                groupTimepoint: store.groupLabel(r), trial: r.trial, file: store.fileLabel(r),
                duration: (r.duration ?? 0).finiteOr(0), fps: (r.fps ?? 0).finiteOr(0), missing: missing,
                statusRank: statusRank(r, missing: missing),
                coverage: r.qc.map { $0.coreCoverage.finiteOr(0) } ?? -1,
                decisionRank: decisionRank(r.decision), assays: assays, planned: planned,
                taskCount: assays.count, created: r.createdAt, queueOrder: order))
        }
        return out
    }

    /// Problems first, then work in progress, then decisions.
    static func statusRank(_ r: Recording, missing: Bool) -> Int {
        if missing && r.status != .ready { return 1 }
        switch r.status {
        case .failed: return 0
        case .processing: return 2
        case .queued: return 3
        case .ready:
            switch r.decision {
            case .pending: return r.qc?.verdict == .fail ? 4 : 5
            case .included: return 6
            case .excluded: return 7
            }
        }
    }

    static func decisionRank(_ d: InclusionDecision) -> Int {
        switch d {
        case .pending: return 0
        case .included: return 1
        case .excluded: return 2
        }
    }

    static func defaultSort(_ filter: RecordingFilter) -> [KeyPathComparator<RecordingsRow>] {
        if case .queue = filter { return [KeyPathComparator(\RecordingsRow.queueOrder)] }
        return [KeyPathComparator(\RecordingsRow.created, order: .reverse)]
    }

    /// Visible ids in table order (for "next video" in review mode).
    static func orderedIDs(_ store: SessionStore, filter: RecordingFilter, search: String,
                           sort: [KeyPathComparator<RecordingsRow>]) -> [UUID] {
        rows(store, filter: filter, search: search).sorted(using: sort).map(\.id)
    }
}

// MARK: - Actions

@MainActor
enum RecordingsActions {
    /// Includes the tracked videos among `ids`. Returns how many were included.
    @discardableResult
    static func include(_ ids: Set<UUID>, app: AppModel) -> Int {
        let ready = Set(ids.filter { app.store.recording($0)?.isProcessed == true })
        guard !ready.isEmpty else {
            app.toast = L("Only tracked videos can be included", "只有已识别的视频才能纳入")
            return 0
        }
        app.store.setDecision(ready, .included)
        app.toast = ready.count == 1 ? L("Included", "已纳入")
            : String(format: L("%d videos included", "已纳入 %d 段视频"), ready.count)
        return ready.count
    }

    static func exclude(_ ids: Set<UUID>, reason: String, app: AppModel) {
        let existing = Set(ids.filter { app.store.recording($0) != nil })
        guard !existing.isEmpty else { return }
        app.store.setDecision(existing, .excluded, reason: reason)
        app.toast = existing.count == 1 ? L("Excluded", "已排除")
            : String(format: L("%d videos excluded", "已排除 %d 段视频"), existing.count)
    }

    static func backToReview(_ ids: Set<UUID>, app: AppModel) {
        let decided = Set(ids.filter { app.store.recording($0).map { $0.decision != .pending } ?? false })
        guard !decided.isEmpty else { return }
        app.store.setDecision(decided, .pending)
        app.toast = String(format: L("%d video(s) back to Needs Review", "%d 段视频已退回待复核"), decided.count)
    }

    /// Deletes the library records (running tracking is stopped first). Referenced video files stay.
    static func delete(_ ids: Set<UUID>, app: AppModel) {
        guard !ids.isEmpty else { return }
        for id in ids where app.batch.jobs[id] != nil { app.batch.cancel(id) }
        let entry = app.store.deleteRecordings(ids)
        app.selectedRecordings.subtract(ids)
        if let last = app.path.last, case .recording(let rid) = last, ids.contains(rid) {
            app.path.removeLast()
        }
        app.deleted(entry, message: String(format: L("%d video record(s) moved to Recently Deleted", "已将 %d 条视频记录移到“最近删除”"), ids.count))
    }

    static func showInFinder(_ ids: Set<UUID>, app: AppModel) {
        let recs = ids.compactMap { app.store.recording($0) }
        if recs.count == 1, let r = recs.first { app.revealVideo(r); return }
        var urls: [URL] = []
        for r in recs.prefix(200) {
            if let access = app.store.videoAccess(r) { urls.append(access.url) }
        }
        guard !urls.isEmpty else {
            app.alert = AppAlert(title: L("Video not found", "找不到视频"),
                                 message: L("None of these videos can be found right now. The drive may not be connected, or the files were moved.",
                                            "目前找不到这些视频：所在磁盘可能未连接，或文件已被移动。"))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// The video to select after `ids` were decided (the next one below, else the one above).
    static func next(after ids: Set<UUID>, in ordered: [UUID]) -> UUID? {
        let positions = ordered.indices.filter { ids.contains(ordered[$0]) }
        guard let lo = positions.min(), let hi = positions.max() else { return nil }
        var i = hi + 1
        while i < ordered.count {
            if !ids.contains(ordered[i]) { return ordered[i] }
            i += 1
        }
        var j = lo - 1
        while j >= 0 {
            if !ids.contains(ordered[j]) { return ordered[j] }
            j -= 1
        }
        return nil
    }

    static func deleteTitle(_ count: Int) -> String {
        count == 1 ? L("Delete this video record?", "删除这条视频记录？")
            : String(format: L("Delete %d video records?", "删除 %d 条视频记录？"), count)
    }

    static func deleteMessage(_ ids: Set<UUID>, store: SessionStore) -> String {
        let analyses = store.sessions.filter { s in s.recordingID.map { ids.contains($0) } ?? false }.count
        let copies = ids.filter { store.source($0)?.mode == .copied }.count
        var text = L("Removes the library's record: the tracking (pose), the QC report and the inclusion decision",
                     "将删除资料库中的记录：姿态识别结果、QC 报告和纳入决定")
        if analyses > 0 {
            text += String(format: L(", and %d analyses made from these videos.", "，以及由这些视频生成的 %d 个分析。"), analyses)
        } else {
            text += L(".", "。")
        }
        text += " " + L("The video files themselves are NOT deleted — they stay where they are on disk.",
                        "视频文件本身不会被删除，仍保留在磁盘原处。")
        if copies > 0 {
            text += " " + String(format: L("%d of them were copied into the library; those copies are removed.",
                                           "其中 %d 段是复制到资料库中的副本，副本会被删除。"), copies)
        }
        return text
    }
}

// MARK: - Exclusion reasons

enum RecordingsExclusion {
    /// Quick reasons (stored in English so study exports stay English; shown translated).
    static var quick: [LText] {
        [LText("Poor tracking (failed QC)", "追踪质量差（QC 未通过）"),
         LText("Wrong animal", "动物不符"),
         LText("Camera moved", "相机移动"),
         LText("Video too short", "视频过短"),
         LText("Animal escaped / out of view", "动物逃出或离开画面")]
    }

    /// A stored reason in the interface language (quick reasons are translated).
    static func display(_ reason: String) -> String {
        for q in quick {
            if reason == q.en { return q.text }
            if reason.hasPrefix(q.en + " — ") { return q.text + String(reason.dropFirst(q.en.count)) }
        }
        return reason
    }
}

/// Request for the exclusion sheet: the videos, the reason to start from and the video to select
/// afterwards (review mode).
struct RecordingsExcludeRequest: Identifiable {
    let id = UUID()
    var ids: Set<UUID>
    var initialReason: String = ""
    var next: UUID?
}

/// Asks for the reason of an exclusion (ARRIVE 2.0 item 3: every exclusion is reported with its reason).
@MainActor
struct RecordingsExcludeSheet: View {
    let count: Int
    var initialReason: String = ""
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice = 0
    @State private var details = ""
    @State private var loaded = false
    @FocusState private var detailsFocused: Bool

    private var options: [LText] { RecordingsExclusion.quick + [LText("Other", "其他")] }
    private var isOther: Bool { choice >= RecordingsExclusion.quick.count }

    private var reason: String {
        let d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let quick = RecordingsExclusion.quick
        if choice >= 0, choice < quick.count {
            let base = quick[choice].en
            return d.isEmpty ? base : base + " — " + d
        }
        return d
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? L("Exclude this video", "排除该视频")
                         : String(format: L("Exclude %d videos", "排除 %d 段视频"), count))
                        .font(.headline)
                    Text(L("Excluded videos are left out of group comparisons. The exclusion and its reason are listed in every export (ARRIVE 2.0).",
                           "排除的视频不参与任务中的比较，排除及其原因会写入所有导出文件（ARRIVE 2.0）。"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker(L("Reason", "原因"), selection: $choice) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].text).tag(i)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            TextField(isOther ? L("Reason for exclusion", "排除原因") : L("Details (optional)", "补充说明（可选）"),
                      text: $details, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($detailsFocused)
            HStack {
                Spacer()
                Button(L("Cancel", "取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Exclude", "排除")) {
                    let text = reason
                    dismiss()
                    onConfirm(text)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reason.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: load)
        .onChange(of: choice) { _, _ in
            if isOther { detailsFocused = true }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let text = initialReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        for (i, q) in RecordingsExclusion.quick.enumerated() {
            if text == q.en { choice = i; return }
            if text.hasPrefix(q.en + " — ") {
                choice = i
                details = String(text.dropFirst(q.en.count + 3))
                return
            }
        }
        choice = RecordingsExclusion.quick.count
        details = text
    }
}

// MARK: - Thumbnails

/// Small frame of a video, loaded lazily (disk cache in the recording folder, else grabbed from the video).
/// Used in table cells: it takes the store as a parameter, never from the environment (on macOS a
/// TableColumn cell can be built without the window's environment objects, which crashed the app).
@MainActor
struct RecordingsThumbnail: View {
    let recording: Recording
    let store: SessionStore
    var width: CGFloat = 48
    var height: CGFloat = 30

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.inset)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
        .task(id: recording.id) { image = await Self.load(recording, store: store) }
    }

    /// Thumbnail from the shared cache; retries briefly while another view is loading the same one.
    static func load(_ r: Recording, store: SessionStore) async -> NSImage? {
        let cache = ThumbnailCache.shared
        if let i = cache.cached(r.id) { return i }
        let folder = store.recordingFolder(r.id)
        let video = store.missingVideos.contains(r.id) ? nil : store.videoURL(r)
        let scoped = store.source(r.id)?.mode == .referenced
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }
            if let i = await cache.load(r.id, folder: folder, video: video, scoped: scoped) { return i }
            if let i = cache.cached(r.id) { return i }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 450_000_000) }
        }
        return nil
    }
}

/// Larger frame for the inspector (keeps the video's aspect ratio).
@MainActor
struct RecordingsPreviewImage: View {
    let recording: Recording
    @Environment(AppModel.self) private var app
    @State private var image: NSImage?

    private var aspect: CGFloat {
        if let w = recording.videoWidth, let h = recording.videoHeight, w > 0, h > 0 {
            return min(3, max(0.33, CGFloat(w) / CGFloat(h)))
        }
        return 16.0 / 9.0
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.inset)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Text(L("No preview", "无预览")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(image == nil ? 0 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
        .task(id: recording.id) {
            image = nil
            image = await RecordingsThumbnail.load(recording, store: app.store)
        }
    }
}

// MARK: - Cells

/// Tasks of a video: created analyses as badges, planned ones faded.
@MainActor
struct RecordingsTaskBadges: View {
    let assays: [Assay]
    let planned: [Assay]
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 3) {
            ForEach(assays) { a in
                AssayBadge(assay: a, size: size).help(a.name.text)
            }
            ForEach(planned) { a in
                AssayBadge(assay: a, size: size)
                    .opacity(0.35)
                    .help(String(format: L("%@ — planned: created when the video is included", "%@——计划中：视频纳入后创建"), a.name.text))
            }
            if assays.isEmpty && planned.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}

/// Status tag, or live progress while the video is being tracked (only this cell follows the batch).
@MainActor
struct RecordingsStatusCell: View {
    let recording: Recording
    let missing: Bool
    /// Passed in (not read from the environment): the cell is used inside tables.
    let batch: BatchEngine

    var body: some View {
        if recording.status == .processing, let job = batch.jobs[recording.id] {
            HStack(spacing: 6) {
                ProgressView(value: min(1, max(0, job.fraction.finiteOr(0))))
                    .controlSize(.small)
                    .frame(width: 56)
                // Fixed width: the cell does not change size as the number grows.
                Text(Fmt.percent(job.fraction)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 36, alignment: .trailing)
            }
            .help(L("Tracking — see Processing for the time left", "识别中——剩余时间见“处理队列”"))
        } else {
            RecordingStatusTag(recording: recording, missing: missing)
        }
    }
}

/// Inclusion decision with the reason (translated when it is a quick reason).
@MainActor
struct RecordingsDecisionCell: View {
    let recording: Recording

    var body: some View {
        if recording.status == .ready || recording.decision != .pending {
            HStack(spacing: 6) {
                Tag(text: recording.decision.label, color: Palette.decision(recording.decision))
                if recording.decision == .excluded && !recording.exclusionReason.isEmpty {
                    Text(RecordingsExclusion.display(recording.exclusionReason))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .help(recording.exclusionReason.isEmpty ? recording.decision.label
                  : RecordingsExclusion.display(recording.exclusionReason))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

/// Mouse tracked along the video, one thin bar per bin (green tracked, amber partly, red lost).
struct RecordingsQCTimeline: View {
    let timeline: [Double]
    var height: CGFloat = 16

    var body: some View {
        Canvas { ctx, size in
            let n = timeline.count
            guard n > 0, size.width > 0 else { return }
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.inset))
            let w = size.width / CGFloat(n)
            for (i, v) in timeline.enumerated() {
                let f = max(0, min(1, v.isFinite ? v : 0))
                let color = f >= 0.9 ? Palette.success : f >= 0.5 ? Palette.warning : Palette.danger
                let rect = CGRect(x: CGFloat(i) * w, y: 0, width: max(1, w + 0.5), height: size.height)
                ctx.fill(Path(rect), with: .color(color.opacity(0.35 + 0.65 * (f >= 0.9 ? 1 : 1 - f))))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityLabel(L("Tracking timeline", "追踪时间轴"))
        .help(L("Tracking along the video: green = mouse tracked, red = lost.", "沿视频的追踪情况：绿 = 已追踪，红 = 丢失。"))
    }
}
