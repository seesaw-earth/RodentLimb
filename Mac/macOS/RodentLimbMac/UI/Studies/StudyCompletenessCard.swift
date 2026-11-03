// StudyCompletenessCard.swift — completeness of the design: one row per animal, one column per
// timepoint (one column when the study has none, plus "Other" for videos whose timepoint is not
// in the design). Each cell shows the state of that animal's video there, with the colors and
// symbols of RecordingStatusTag (included / excluded / needs review / QC failed / tracking /
// queued / failed / missing); click opens the video, several trials show a count and a list.
// While blinded, rows are ordered by blind code and no group is shown.

import SwiftUI

private enum StudyGridMetrics {
    static let cellWidth: CGFloat = 64
    static let cellHeight: CGFloat = 26
    static let otherColumn = "\u{1F}other"
}

/// Everything the grid shows, computed once per render.
private struct StudyGridModel {
    var columns: [String] = []
    var animals: [Animal] = []
    /// animal id → column → recordings
    var cells: [UUID: [String: [Recording]]] = [:]
    var unlinked: [Recording] = []
    var expected = 0
    var complete = 0
    var missing = 0
    var attention = 0

    static func build(_ e: Experiment, recordings recs: [Recording]) -> StudyGridModel {
        var m = StudyGridModel()
        let timepoints = StudyText.unique(e.timepoints)
        let known = Set(timepoints)
        let animalIDs = Set(e.animals.map(\.id))
        var hasOther = false
        for r in recs {
            guard let aid = r.animalID, animalIDs.contains(aid) else {
                m.unlinked.append(r)
                continue
            }
            let column: String
            if timepoints.isEmpty {
                column = ""
            } else if known.contains(r.timepoint) {
                column = r.timepoint
            } else {
                column = StudyGridMetrics.otherColumn
                hasOther = true
            }
            m.cells[aid, default: [:]][column, default: []].append(r)
        }
        let designColumns = timepoints.isEmpty ? [""] : timepoints
        m.columns = designColumns + (hasOther ? [StudyGridMetrics.otherColumn] : [])

        if e.blinded {
            // Ordered by the random codes, so the order reveals nothing.
            m.animals = e.animals.sorted {
                e.displayCode($0).localizedStandardCompare(e.displayCode($1)) == .orderedAscending
            }
        } else {
            let cellOrder = e.cells.map { $0.joined(separator: " · ") }
            func rank(_ a: Animal) -> Int { cellOrder.firstIndex(of: e.groupLabel(a)) ?? cellOrder.count }
            m.animals = e.animals.sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                return a.code.localizedStandardCompare(b.code) == .orderedAscending
            }
        }

        for a in m.animals {
            for c in designColumns {
                m.expected += 1
                guard let best = StudyVideoState.best(m.cells[a.id]?[c] ?? []) else {
                    m.missing += 1
                    continue
                }
                if best.status == .ready && best.decision == .included {
                    m.complete += 1
                } else if StudyVideoState.needsAttention(best) {
                    m.attention += 1
                }
            }
        }
        return m
    }
}

struct StudyCompletenessCard: View {
    let experiment: Experiment

    @Environment(AppModel.self) private var app

    init(experiment: Experiment) { self.experiment = experiment }

    var body: some View {
        let e = experiment
        let model = StudyGridModel.build(e, recordings: app.store.recordings(in: e.id))
        Card {
            CardHeader(L("Completeness", "完整性"), symbol: "tablecells",
                       subtitle: L("One cell per animal and timepoint, showing the state of its video. Click a cell to open the video.",
                                   "每个格子对应一只动物的一个时间点，显示其视频状态。点击格子打开视频。"))
            if e.animals.isEmpty {
                Text(L("Add animals to see which videos are still missing.", "添加动物后可查看还缺哪些视频。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary(model))
                    .font(.callout)
                    .textSelection(.enabled)
                grid(model, e)
                legend
            }
            unlinked(model)
        }
    }

    // MARK: Parts

    private func summary(_ m: StudyGridModel) -> String {
        var text = String(format: L("%d of %d animal × timepoint cells have an included video", "%d / %d 个“动物 × 时间点”格子已有纳入的视频"),
                          m.complete, m.expected)
        if m.missing > 0 { text += " · " + String(format: L("%d missing", "%d 个缺失"), m.missing) }
        if m.attention > 0 { text += " · " + String(format: L("%d need attention", "%d 个需处理"), m.attention) }
        return text + "."
    }

    private func columnTitle(_ c: String) -> String {
        if c == StudyGridMetrics.otherColumn { return L("Other", "其他") }
        if c.isEmpty { return L("Video", "视频") }
        return c
    }

    private func grid(_ m: StudyGridModel, _ e: Experiment) -> some View {
        let missingVideos = app.store.missingVideos
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                GridRow {
                    Text(L("Animal", "动物"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(m.columns, id: \.self) { c in
                        Text(columnTitle(c))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: StudyGridMetrics.cellWidth)
                            .help(c == StudyGridMetrics.otherColumn
                                  ? L("Videos whose timepoint is not (or no longer) in the design", "时间点不在（或已不在）设计中的视频")
                                  : columnTitle(c))
                    }
                }
                Divider()
                ForEach(m.animals) { a in
                    GridRow {
                        rowHeader(a, e)
                        ForEach(m.columns, id: \.self) { c in
                            StudyGridCell(recordings: m.cells[a.id]?[c] ?? [],
                                          missing: missingVideos,
                                          title: e.displayCode(a) + (c.isEmpty ? "" : " · " + columnTitle(c))) { id in
                                app.open(.recording(id))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rowHeader(_ a: Animal, _ e: Experiment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(e.displayCode(a)).font(.callout.weight(.semibold)).lineLimit(1)
                if a.sex != .unknown {
                    Text(a.sex.short).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
            }
            if !e.blinded {
                let g = e.groupLabel(a)
                Text(g.isEmpty ? (e.cells.isEmpty ? "" : L("not allocated", "未分组")) : g)
                    .font(.caption2)
                    .foregroundStyle(g.isEmpty ? Palette.warning : Color.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 96, maxWidth: 180, alignment: .leading)
    }

    private var legend: some View {
        let items: [(String, Color, String)] = [
            (L("Included", "已纳入"), Palette.success, "checkmark.circle.fill"),
            (L("Needs review", "待复核"), Palette.warning, "exclamationmark.triangle.fill"),
            (L("QC failed", "QC 未通过"), Palette.danger, "xmark.octagon.fill"),
            (L("Excluded", "已排除"), Palette.gray, "minus.circle.fill"),
            (L("Tracking", "识别中"), Color.accentColor, "waveform.path.ecg"),
            (L("Queued", "排队中"), Color.secondary, "clock"),
            (L("Failed", "失败"), Palette.danger, "exclamationmark.triangle.fill"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { item in
                HStack(spacing: 6) {
                    StudyGridPip(color: item.element.1, ring: StudyGridPip.isRing(item.element.2))
                    Text(item.element.0)
                }
                .font(.caption)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 12, height: 10)
                Text(L("No video", "无视频"))
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func unlinked(_ m: StudyGridModel) -> some View {
        if !m.unlinked.isEmpty {
            let store = app.store
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: L("%d videos are not linked to an animal of this task:", "%d 段视频未关联本任务的动物："), m.unlinked.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(Array(m.unlinked.prefix(10))) { r in
                    Button {
                        app.open(.recording(r.id))
                    } label: {
                        HStack(spacing: 8) {
                            Text(store.displayName(r)).lineLimit(1)
                            if !r.timepoint.isEmpty {
                                Text(r.timepoint).foregroundStyle(.secondary)
                            }
                            RecordingStatusTag(recording: r, missing: store.missingVideos.contains(r.id))
                            Spacer()
                        }
                        .font(.callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Open the video to set its animal ID", "打开视频以设置动物编号"))
                }
                if m.unlinked.count > 10 {
                    Text(String(format: L("and %d more", "还有 %d 段"), m.unlinked.count - 10))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Cell

private struct StudyGridCell: View {
    let recordings: [Recording]
    let missing: Set<UUID>
    let title: String
    let open: (UUID) -> Void

    @State private var showTrials = false

    init(recordings: [Recording], missing: Set<UUID>, title: String, open: @escaping (UUID) -> Void) {
        self.recordings = recordings
        self.missing = missing
        self.title = title
        self.open = open
    }

    var body: some View {
        let trials = StudyVideoState.sortedTrials(recordings)
        if let best = StudyVideoState.best(trials) {
            filledCell(best: best, trials: trials)
        } else {
            emptyCell
        }
    }

    // Split into small pieces: as one expression this body took the type checker too long.
    private func filledCell(best: Recording, trials: [Recording]) -> some View {
        let d = RecordingStatusTag.describe(best, missing: missing.contains(best.id))
        let helpText = cellHelp(status: d.text, trials: trials.count)
        let spoken: String = title + ": " + d.text
        return Button {
            if trials.count == 1 { open(best.id) } else { showTrials = true }
        } label: {
            StudyGridCellFace(color: d.color, symbol: d.symbol, trials: trials.count)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(spoken)
        .popover(isPresented: $showTrials, arrowEdge: .bottom) {
            trialList(trials)
        }
    }

    private func cellHelp(status: String, trials: Int) -> String {
        if trials > 1 {
            let detail = String(format: L("%d trials (best: %@). Click to choose.", "%d 次试验（最佳：%@）。点击选择。"), trials, status)
            return title + " — " + detail
        }
        return title + " — " + status
    }

    private var emptyCell: some View {
        let text: String = title + " — " + L("no video", "无视频")
        let spoken: String = title + ": " + L("no video", "无视频")
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: StudyGridMetrics.cellWidth, height: StudyGridMetrics.cellHeight)
            .help(text)
            .accessibilityLabel(spoken)
    }

    private func trialList(_ trials: [Recording]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(trials) { r in
                Button {
                    showTrials = false
                    open(r.id)
                } label: {
                    HStack(spacing: 8) {
                        Text(String(format: L("Trial %d", "第 %d 次"), r.trial)).monospacedDigit()
                        RecordingStatusTag(recording: r, missing: missing.contains(r.id))
                        Spacer(minLength: 8)
                        Text(Fmt.day(r.recordedOn ?? r.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(minWidth: 280)
    }
}

/// The coloured square of a grid cell: a dot in the state's colour (a ring for states that are not
/// final — queued, QC failed — so colour is never the only cue), the number of trials in the corner.
private struct StudyGridCellFace: View {
    let color: Color
    let symbol: String
    let trials: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.15))
            StudyGridPip(color: color, ring: StudyGridPip.isRing(symbol))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if trials > 1 {
                Text("\(trials)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.top, 1)
            }
        }
        .frame(width: StudyGridMetrics.cellWidth, height: StudyGridMetrics.cellHeight)
        .contentShape(Rectangle())
    }
}

/// The state mark of the grid and its legend: a filled dot, or a ring.
private struct StudyGridPip: View {
    let color: Color
    let ring: Bool

    /// Queued and QC-failed states are drawn as rings (same colours as tracking / failed).
    static func isRing(_ symbol: String) -> Bool { symbol == "clock" || symbol == "xmark.octagon.fill" }

    var body: some View {
        Group {
            if ring {
                Circle().strokeBorder(color, lineWidth: 2)
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: 9, height: 9)
    }
}
