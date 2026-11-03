// StudyCompareCard.swift — group comparison of one measure (port of the iPhone StudyCompareView,
// on the Results tab of a task, whose paradigm is fixed; a legacy study with several paradigms
// can still pick one): the measure
// (metrics present in the results), the grouping (cells / one factor / sex / cells × sex) and a
// timepoint or the time course. Bars or points show mean ± SEM per group with every animal as a
// dot; the time course shows a line per group with an SEM band. The animal is the experimental
// unit: `groupStats` averages the trials of an animal first, so n counts animals. Included videos
// only. While blinded, only the overall distribution of all animals is shown (no groups).

import SwiftUI
import Charts

private enum StudyCompareStyle: String, Hashable {
    case bars, points
}

/// What the results were loaded for; a change (other task, re-analysed videos) reloads them.
private struct StudyCompareLoadKey: Hashable {
    var assay: Assay?
    var ids: [UUID]
    var stamp: Date
}

struct StudyCompareCard: View {
    let experiment: Experiment
    /// The task's paradigm (no paradigm picker).
    let fixedAssay: Assay?

    @Environment(AppModel.self) private var app
    @State private var assaySelection: Assay?
    @State private var metricKey = ""
    @State private var grouping: Grouping = .cells
    @State private var timepoint: String?
    @State private var style: StudyCompareStyle = .points
    @State private var results: [UUID: AnalysisResult] = [:]
    @State private var loading = false

    init(experiment: Experiment, assay: Assay? = nil) {
        self.experiment = experiment
        self.fixedAssay = assay
    }

    var body: some View {
        let e = experiment
        let available = availableAssays(e)
        let assay = currentAssay(available)
        let key = loadKey(e, assay: assay)
        Card {
            CardHeader(title: L("Group comparison", "组间比较"), symbol: "",
                       subtitle: L("Mean ± SEM per group; dots are individual animals (the experimental unit — trials of one animal are averaged first). Included videos only; descriptive statistics.",
                                   "各组均值 ± 标准误；点为单只动物（实验单位——同一动物的多次试验先取平均）。仅含已纳入的视频；描述性统计。")) {
                headerActions(e, assay: assay)
            }
            if let assay {
                controls(e, available: available, assay: assay)
                content(e, assay: assay)
            } else {
                Text(L("No results yet. Add videos to the task; once they are tracked, checked and analysed, results appear here by group.",
                       "还没有结果。向任务添加视频；视频识别、质控并分析后，结果会按组显示在此。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: key) {
            await load(key)
        }
    }

    // MARK: Choices

    private func availableAssays(_ e: Experiment) -> [Assay] {
        if let fixedAssay {
            return app.store.analyses(in: e, assay: fixedAssay).isEmpty ? [] : [fixedAssay]
        }
        return Assay.allCases.filter { !app.store.analyses(in: e, assay: $0).isEmpty }
    }

    private func currentAssay(_ available: [Assay]) -> Assay? {
        if let a = assaySelection, available.contains(a) { return a }
        return available.first
    }

    private func metricOptions(_ e: Experiment, assay: Assay) -> [Metric] {
        var seen = Set<String>(), out: [Metric] = []
        for s in app.store.analyses(in: e, assay: assay) {
            for m in results[s.id]?.metrics ?? [] where !seen.contains(m.key) {
                seen.insert(m.key)
                out.append(m)
            }
        }
        return out
    }

    /// The grouping actually used (a deleted factor or a design without cells falls back).
    private func effectiveGrouping(_ e: Experiment) -> Grouping {
        switch grouping {
        case .factor(let id): return e.activeFactors.contains { $0.id == id } ? grouping : .cells
        case .cellsBySex: return e.cells.isEmpty ? .sex : grouping
        case .cells, .sex: return grouping
        }
    }

    private func effectiveTimepoint(_ e: Experiment) -> String? {
        guard let t = timepoint, e.timepoints.contains(t) else { return nil }
        return t
    }

    private func isTimeCourse(_ e: Experiment) -> Bool {
        StudyText.unique(e.timepoints).count > 1 && effectiveTimepoint(e) == nil
    }

    // MARK: Loading

    private func loadKey(_ e: Experiment, assay: Assay?) -> StudyCompareLoadKey {
        guard let assay else { return StudyCompareLoadKey(assay: nil, ids: [], stamp: .distantPast) }
        let list = app.store.analyses(in: e, assay: assay)
        return StudyCompareLoadKey(assay: assay, ids: list.map(\.id), stamp: list.map(\.updatedAt).max() ?? .distantPast)
    }

    private func load(_ key: StudyCompareLoadKey) async {
        guard let assay = key.assay, !key.ids.isEmpty else {
            results = [:]
            loading = false
            return
        }
        loading = true
        let loaded = await app.store.loadResults(key.ids)
        // Another task was picked (or the analyses changed) while loading: the newer load wins.
        guard !Task.isCancelled else { return }
        results = loaded
        loading = false
        let options = metricOptions(experiment, assay: assay)
        if !options.contains(where: { $0.key == metricKey }) {
            metricKey = options.first { $0.highlight }?.key ?? options.first?.key ?? ""
        }
    }

    // MARK: Statistics

    private func computeStats(_ e: Experiment, assay: Assay) -> [GroupStat] {
        guard !metricKey.isEmpty else { return [] }
        let tp = isTimeCourse(e) ? nil : effectiveTimepoint(e)
        if e.blinded { return overallStats(e, assay: assay, timepoint: tp) }
        return app.store.groupStats(e, assay: assay, metric: metricKey, grouping: effectiveGrouping(e), timepoint: tp, results: results)
    }

    /// All animals as one group (blinded studies): same rules as `groupStats` — included videos,
    /// trials of an animal averaged first, split by timepoint when `timepoint` is nil.
    private func overallStats(_ e: Experiment, assay: Assay, timepoint tp: String?) -> [GroupStat] {
        let store = app.store
        var perUnit: [String: [String: [Double]]] = [:]
        var unitOrder: [String: [String]] = [:]
        var order: [String] = []
        for s in store.analyses(in: e, assay: assay) {
            guard let r = store.recording(for: s), r.decision == .included else { continue }
            if let tp, r.timepoint != tp { continue }
            guard let v = results[s.id]?.metric(metricKey)?.value, v.isFinite else { continue }
            let key = tp == nil ? r.timepoint : ""
            let unit = r.animalID?.uuidString ?? r.id.uuidString
            if perUnit[key] == nil { order.append(key) }
            if perUnit[key]?[unit] == nil { unitOrder[key, default: []].append(unit) }
            perUnit[key, default: [:]][unit, default: []].append(v)
        }
        let name = L("All animals", "全部动物")
        var out: [GroupStat] = []
        for key in order {
            let units = perUnit[key] ?? [:]
            let values = (unitOrder[key] ?? []).compactMap { units[$0].flatMap { Signal.mean($0) } }
            guard let m = Signal.mean(values) else { continue }
            out.append(GroupStat(name: name, timepoint: key, values: values, mean: m, sd: Signal.sd(values)))
        }
        let tpOrder = e.timepoints
        return out.sorted { (tpOrder.firstIndex(of: $0.timepoint) ?? tpOrder.count) < (tpOrder.firstIndex(of: $1.timepoint) ?? tpOrder.count) }
    }

    // MARK: Header actions

    @ViewBuilder
    private func headerActions(_ e: Experiment, assay: Assay?) -> some View {
        if let assay {
            HStack(spacing: 6) {
                Button(L("Copy Table", "拷贝表格")) {
                    copyTable(computeStats(e, assay: assay))
                }
                .disabled(metricKey.isEmpty)
                .help(L("Copy the group statistics as tab-separated text (paste into a spreadsheet)", "将各组统计量拷贝为制表符分隔文本（可粘贴到电子表格）"))
            }
            .controlSize(.small)
        }
    }

    // MARK: Controls

    private func controls(_ e: Experiment, available: [Assay], assay: Assay) -> some View {
        let options = metricOptions(e, assay: assay)
        let timepoints = StudyText.unique(e.timepoints)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if fixedAssay == nil && available.count > 1 {
                    Picker(L("Paradigm", "范式"), selection: Binding(get: { assay }, set: { assaySelection = $0 })) {
                        ForEach(available) { a in
                            Text(a.name.text).tag(a)
                        }
                    }
                    .fixedSize()
                }
                Picker(L("Measure", "指标"), selection: $metricKey) {
                    if options.isEmpty {
                        Text(loading ? L("Loading…", "加载中…") : "—").tag("")
                    }
                    ForEach(options) { m in
                        Text(m.label.text + (m.unit.isEmpty ? "" : " (\(m.unit))")).tag(m.key)
                    }
                }
                .frame(maxWidth: 380)
                .disabled(options.isEmpty)
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                if !e.blinded {
                    Picker(L("Group by", "分组方式"), selection: Binding(get: { effectiveGrouping(e) }, set: { grouping = $0 })) {
                        Text(L("Groups", "组别")).tag(Grouping.cells)
                        ForEach(e.activeFactors) { f in
                            Text(f.name).tag(Grouping.factor(f.id))
                        }
                        Text(L("Sex", "性别")).tag(Grouping.sex)
                        if !e.cells.isEmpty {
                            Text(L("Groups × sex", "组别 × 性别")).tag(Grouping.cellsBySex)
                        }
                    }
                    .fixedSize()
                }
                if timepoints.count > 1 {
                    Picker(L("Timepoint", "时间点"), selection: Binding(get: { effectiveTimepoint(e) }, set: { timepoint = $0 })) {
                        Text(L("All (time course)", "全部（时间进程）")).tag(String?.none)
                        ForEach(timepoints, id: \.self) { t in
                            Text(t).tag(String?.some(t))
                        }
                    }
                    .fixedSize()
                }
                if !isTimeCourse(e) {
                    Picker(L("Chart", "图表"), selection: $style) {
                        Text(L("Dots", "散点")).tag(StudyCompareStyle.points)
                        Text(L("Bars", "柱状图")).tag(StudyCompareStyle.bars)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help(L("Mean as a bar or as a point; whiskers show ± SEM", "均值以柱或点表示；误差线为 ± 标准误"))
                }
                Spacer(minLength: 0)
            }
        }
        .controlSize(.small)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ e: Experiment, assay: Assay) -> some View {
        let stats = computeStats(e, assay: assay)
        let metric = metricOptions(e, assay: assay).first { $0.key == metricKey }
        let yTitle = metric.map { $0.label.text + ($0.unit.isEmpty ? "" : " (\($0.unit))") } ?? ""
        let digits = max(2, metric?.decimals ?? 2)
        let timeCourse = isTimeCourse(e)
        if e.blinded {
            Banner(text: L("Blinded: only the overall distribution of all animals is shown. Groups are revealed after unblinding (when every video has been scored and every decision made).",
                           "盲法中：仅显示全部动物的整体分布。揭盲后（所有视频评分、决定完成后）才显示各组。"), level: .info)
        }
        if loading && results.isEmpty {
            ProgressView(L("Loading results…", "正在加载结果…"))
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if stats.isEmpty {
            Text(L("No included analyses with this measure yet.", "尚无包含该指标的已纳入分析。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            if timeCourse {
                let domain = StudyText.unique(e.timepoints)
                StudyTimeCourseChart(stats: stats.filter { domain.contains($0.timepoint) }, timepoints: domain, yTitle: yTitle)
                Text(L("Lines = group mean across timepoints; band = ± SEM.", "线 = 各时间点的组均值；阴影带 = ± 标准误。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                StudyGroupChart(stats: stats, style: style, tint: Palette.assay(assay), yTitle: yTitle)
                Text(L("Dots = individual animals; horizontal line = group mean; whiskers = ± SEM.", "点 = 单只动物；横线 = 组均值；误差线 = ± 标准误。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            statsTable(stats, digits: digits)
        }
        footnote(e, assay: assay)
    }

    private func statsTable(_ stats: [GroupStat], digits: Int) -> some View {
        let showTimepoint = stats.contains { !$0.timepoint.isEmpty }
        return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 5) {
            GridRow {
                Text(L("Group", "组别")).gridColumnAlignment(.leading)
                if showTimepoint {
                    Text(L("Timepoint", "时间点")).gridColumnAlignment(.leading)
                }
                Text(L("n (animals)", "n（动物）"))
                Text(L("Mean", "均值"))
                Text("SD")
                Text("SEM")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(stats) { g in
                GridRow {
                    Text(g.name).lineLimit(1)
                    if showTimepoint {
                        Text(g.timepoint.isEmpty ? "—" : g.timepoint).lineLimit(1)
                    }
                    Text("\(g.values.count)")
                    Text(Fmt.num(g.mean, digits))
                    Text(Fmt.num(g.sd, digits))
                    Text(Fmt.num(g.sem, digits))
                }
                .font(.callout.monospacedDigit())
            }
        }
        .textSelection(.enabled)
        .padding(.top, 4)
    }

    private func footnote(_ e: Experiment, assay: Assay) -> some View {
        let store = app.store
        let left = store.analyses(in: e, assay: assay).filter { store.recording(for: $0)?.decision != .included }.count
        return Text(String(format: L("Included videos only (%d left out: excluded or awaiting review). The animal is the experimental unit: several trials of one animal at one timepoint are averaged first, so n counts animals. Descriptive only — for inference use the exported long-format CSV (e.g. two-way or mixed ANOVA, or a linear mixed model with animal as random effect for repeated measures).",
                                  "仅含已纳入视频（%d 个未计入：已排除或待审核）。实验单位为动物：同一动物在同一时间点的多次试验先取平均，因此 n 为动物数。仅为描述性统计——推断请使用导出的长格式 CSV（如双因素或混合方差分析；重复测量可用以动物为随机效应的线性混合模型）。"), left))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyTable(_ stats: [GroupStat]) {
        guard !stats.isEmpty else { return }
        var t = "group\ttimepoint\tn\tmean\tsd\tsem\n"
        for g in stats {
            t += [g.name, g.timepoint, "\(g.values.count)", Fmt.num(g.mean, 4), Fmt.num(g.sd, 4), Fmt.num(g.sem, 4)].joined(separator: "\t") + "\n"
        }
        StudyClipboard.copy(t)
        app.toast = L("Table copied", "已拷贝表格")
    }
}

// MARK: - Charts

/// Mean ± SEM per group with every animal as a dot (jittered), one colour-blind-safe colour per
/// group (Okabe–Ito); "Bars" adds a light bar for the mean.
private struct StudyGroupChart: View {
    let stats: [GroupStat]
    let style: StudyCompareStyle
    let tint: Color
    let yTitle: String

    init(stats: [GroupStat], style: StudyCompareStyle, tint: Color, yTitle: String) {
        self.stats = stats
        self.style = style
        self.tint = tint
        self.yTitle = yTitle
    }

    /// Category label, e.g. "KO · Drug".
    private static func label(_ g: GroupStat) -> String {
        g.timepoint.isEmpty ? g.name : g.name + " · " + g.timepoint
    }

    /// Small horizontal spread of the dots so animals with equal values stay visible.
    private static func jitter(_ i: Int) -> CGFloat {
        CGFloat((i % 7) - 3) * 3.5
    }

    /// Colour of a group: by its name, so a group keeps its colour across timepoints and charts.
    private var groupNames: [String] {
        var out: [String] = []
        for g in stats where !out.contains(g.name) { out.append(g.name) }
        return out
    }

    var body: some View {
        let names = groupNames
        Chart {
            ForEach(stats) { g in
                groupMarks(g, color: GroupPalette.color(names.firstIndex(of: g.name) ?? 0))
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self), let g = stats.first(where: { Self.label($0) == name }) {
                        VStack(spacing: 1) {
                            Text(name).font(.callout.weight(.medium)).foregroundStyle(.primary)
                            Text("n = \(g.values.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline.opacity(0.6))
                AxisValueLabel().font(.caption.monospacedDigit())
            }
        }
        .chartYAxisLabel(yTitle)
        .frame(height: 300)
        .padding(.top, 4)
    }
}

extension StudyGroupChart {
    /// One group: the animals as dots, the mean as a short line, ± SEM whiskers (split out so the
    /// compiler type-checks the chart quickly).
    @ChartContentBuilder
    fileprivate func groupMarks(_ g: GroupStat, color: Color) -> some ChartContent {
        let x = Self.label(g)
        if style == .bars {
            BarMark(x: .value(L("Group", "组别"), x), y: .value(L("Mean", "均值"), g.mean), width: .ratio(0.55))
                .foregroundStyle(color.opacity(0.22))
                .cornerRadius(3)
        }
        ForEach(Array(g.values.enumerated()), id: \.offset) { item in
            PointMark(x: .value(L("Group", "组别"), x), y: .value(L("Animal", "动物"), item.element))
                .foregroundStyle(color.opacity(0.78))
                .symbolSize(30)
                .offset(x: Self.jitter(item.offset))
        }
        if let sem = g.sem {
            RuleMark(x: .value(L("Group", "组别"), x),
                     yStart: .value(L("Mean − SEM", "均值 − 标准误"), g.mean - sem),
                     yEnd: .value(L("Mean + SEM", "均值 + 标准误"), g.mean + sem))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        PointMark(x: .value(L("Group", "组别"), x), y: .value(L("Mean", "均值"), g.mean))
            .symbol {
                Capsule().fill(Color.primary).frame(width: 26, height: 3)
            }
    }
}

/// Time course: one line per group across timepoints with a ± SEM band (Okabe–Ito colours).
private struct StudyTimeCourseChart: View {
    let stats: [GroupStat]
    let timepoints: [String]
    let yTitle: String

    init(stats: [GroupStat], timepoints: [String], yTitle: String) {
        self.stats = stats
        self.timepoints = timepoints
        self.yTitle = yTitle
    }

    private var groups: [String] {
        var out: [String] = []
        for g in stats where !out.contains(g.name) { out.append(g.name) }
        return out
    }

    var body: some View {
        let names = groups
        Chart {
            ForEach(stats) { g in
                if let sem = g.sem {
                    AreaMark(x: .value(L("Timepoint", "时间点"), g.timepoint),
                             yStart: .value(L("Mean − SEM", "均值 − 标准误"), g.mean - sem),
                             yEnd: .value(L("Mean + SEM", "均值 + 标准误"), g.mean + sem),
                             series: .value(L("Group", "组别"), g.name))
                        .foregroundStyle(by: .value(L("Group", "组别"), g.name))
                        .opacity(0.14)
                }
                LineMark(x: .value(L("Timepoint", "时间点"), g.timepoint), y: .value(L("Mean", "均值"), g.mean),
                         series: .value(L("Group", "组别"), g.name))
                    .foregroundStyle(by: .value(L("Group", "组别"), g.name))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value(L("Timepoint", "时间点"), g.timepoint), y: .value(L("Mean", "均值"), g.mean))
                    .foregroundStyle(by: .value(L("Group", "组别"), g.name))
                    .symbolSize(36)
            }
        }
        .chartForegroundStyleScale(domain: names, range: names.indices.map { GroupPalette.color($0) })
        .chartXScale(domain: timepoints)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline.opacity(0.6))
                AxisValueLabel().font(.caption.monospacedDigit())
            }
        }
        .chartYAxisLabel(yTitle)
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: 300)
    }
}
