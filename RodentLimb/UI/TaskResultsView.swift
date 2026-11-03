// TaskResultsView.swift — Results of a task (TASK_FIRST_SPEC §2.6, §4): the group comparison of one
// measure (each animal one jittered dot, group mean as a short thick bar with ± SEM whiskers, n per
// group, Okabe–Ito colours), the course across timepoints, and the time course per group for binned
// measures (mean line with a ± SEM band). Included sessions only; descriptive statistics.

import SwiftUI
import Charts

@MainActor
struct TaskResultsSections: View {
    let task: TaskRef
    @EnvironmentObject private var store: SessionStore
    @State private var results: [UUID: AnalysisResult] = [:]
    /// `updatedAt` of each session when its result was read (only changed ones are read again).
    @State private var stamps: [UUID: Date] = [:]
    @State private var loaded = false
    @State private var metricKey = ""
    @State private var timepoint: String?
    @State private var binKey = ""
    /// Everything the charts show, computed after a change (never while the view redraws).
    @State private var model = ResultsModel()

    struct ResultsModel {
        var measures: [MeasureOption] = []
        var groups: [GroupSummary] = []
        var course: [CoursePoint] = []
        var bins: [BinOption] = []
        var binned: [CoursePoint] = []
        var leftOut = 0
    }

    private var experiment: Experiment? { store.experiment(task.experimentID) }
    private var measure: MeasureOption? { model.measures.first { $0.key == metricKey } ?? model.measures.first }
    private var series: BinOption? { model.bins.first { $0.key == binKey } ?? model.bins.first }

    var body: some View {
        if let e = experiment {
            if e.blinded {
                Section {
                    Text(L("Group results are hidden while the task is blinded. Unblind it in Design once every session is scored and every inclusion decision is made.",
                           "盲法期间隐藏组结果。请在所有实验评分、纳入决定完成后，在“设计”中揭盲。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                // One row that also loads and computes (a modifier on a Section would repeat per row).
                Section {
                    controls(e)
                        .task(id: store.revision) { await refresh(debounce: loaded) }
                        .onChange(of: metricKey) { _, _ in recompute() }
                        .onChange(of: timepoint) { _, _ in recompute() }
                        .onChange(of: binKey) { _, _ in recompute() }
                }
                if let measure { comparison(e, measure) }
                if let series { binnedSection(series) }
            }
        }
    }

    @ViewBuilder
    private func controls(_ e: Experiment) -> some View {
        if !loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        } else if model.measures.isEmpty {
            Text(L("Results appear here once the first sessions are tracked and analysed.", "首批实验识别并分析后，结果会显示在这里。"))
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                Picker(L("Measure", "指标"), selection: $metricKey) {
                    ForEach(model.measures) { m in Text(m.axisTitle).tag(m.key) }
                }
                if e.timepoints.count > 1 {
                    Divider()
                    Picker(L("Timepoint", "时间点"), selection: $timepoint) {
                        ForEach(e.timepoints, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func comparison(_ e: Experiment, _ measure: MeasureOption) -> some View {
        Section {
            if model.groups.isEmpty {
                Text(L("No included session has this measure yet.", "尚无包含该指标的已纳入实验。")).font(.footnote).foregroundStyle(.secondary)
            } else {
                GroupComparisonChart(groups: model.groups, yTitle: measure.axisTitle)
                    .padding(.vertical, 8)
                StatsTable(groups: model.groups)
            }
        } header: {
            Text(measure.label.text)
        } footer: {
            Text(String(format: L("Each dot is one animal (trials averaged); bar = group mean, whiskers = SEM. Included sessions only (%d left out: excluded or waiting for review). Descriptive only: run the tests on the exported CSV.",
                                  "每个点代表一只动物（多次试验取平均）；横线 = 组均值，误差线 = 标准误。只含已纳入的实验（%d 个未计入：已排除或待审核）。仅为描述性统计，统计检验请使用导出的 CSV。"), model.leftOut))
        }
        if e.timepoints.count > 1 && !model.course.isEmpty {
            Section {
                TimepointChart(points: model.course, timepoints: e.timepoints, yTitle: measure.axisTitle)
                    .padding(.vertical, 8)
            } header: {
                Text(L("Across timepoints", "各时间点变化"))
            } footer: {
                Text(L("Group mean ± SEM at each timepoint.", "各时间点的组均值 ± 标准误。"))
            }
        }
    }

    @ViewBuilder
    private func binnedSection(_ series: BinOption) -> some View {
        Section {
            if model.bins.count > 1 {
                Picker(L("Series", "序列"), selection: $binKey) {
                    ForEach(model.bins) { b in Text(b.label.text).tag(b.key) }
                }
                .pickerStyle(.menu)
            }
            if model.binned.isEmpty {
                Text(L("No included session has this series yet.", "尚无包含该序列的已纳入实验。")).font(.footnote).foregroundStyle(.secondary)
            } else {
                BinnedCourseChart(points: model.binned, yTitle: series.axisTitle,
                                  xTitle: series.key == BinOption.tstPerMinute
                                  ? L("Minute of the test", "测试分钟") : L("Time from injection (min)", "注射后时间（分钟）"))
                    .padding(.vertical, 8)
            }
        } header: {
            Text(L("Time course", "时间进程"))
        } footer: {
            Text(String(format: L("Group mean (line) ± SEM (band) per %.0f-min bin.", "每 %.0f 分钟分箱的组均值（线）± 标准误（带）。"), series.binSize / 60))
        }
    }

    /// Reads the results of sessions that are new or changed since the last read (after a short
    /// pause, so a burst of saves reads once; a newer change cancels this one), then recomputes.
    private func refresh(debounce: Bool) async {
        if debounce {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
        }
        let list = store.sessions(in: task).filter(\.hasPose)
        let changed = list.filter { stamps[$0.id] != $0.updatedAt || results[$0.id] == nil }
        var fresh = results
        if !changed.isEmpty {
            let read = await store.loadResults(changed.map(\.id))
            guard !Task.isCancelled else { return }
            for s in changed { fresh[s.id] = read[s.id]; stamps[s.id] = s.updatedAt }
        }
        let present = Set(list.map(\.id))
        fresh = fresh.filter { present.contains($0.key) }
        stamps = stamps.filter { present.contains($0.key) }
        results = fresh
        loaded = true
        recompute()
    }

    /// The charts' numbers for the current choices.
    private func recompute() {
        guard let e = experiment else { return }
        var m = ResultsModel()
        m.measures = store.measureOptions(task, results: results)
        m.bins = store.binOptions(task, results: results)
        if !e.timepoints.isEmpty, timepoint == nil || !e.timepoints.contains(timepoint ?? "") { timepoint = e.timepoints.first }
        if !m.measures.contains(where: { $0.key == metricKey }) { metricKey = m.measures.first?.key ?? "" }
        if !m.bins.contains(where: { $0.key == binKey }) { binKey = m.bins.first?.key ?? "" }
        if !metricKey.isEmpty {
            m.groups = store.groupSummaries(task, metric: metricKey, timepoint: timepoint, results: results)
            m.course = store.timepointCourse(task, metric: metricKey, results: results)
        }
        if let b = m.bins.first(where: { $0.key == binKey }) {
            m.binned = store.binnedCourse(task, series: b, timepoint: timepoint, results: results)
        }
        m.leftOut = store.inclusionCounts(task).leftOut
        model = m
    }
}

// MARK: - Charts

/// Each animal a dot (jittered), group mean as a short thick bar, ± SEM whiskers; n under each group.
struct GroupComparisonChart: View {
    let groups: [GroupSummary]
    let yTitle: String

    var body: some View {
        let positions = Array(groups.indices)
        Chart {
            ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                let color = Palette.group(g.index)
                let x = Double(i)
                ForEach(g.points) { p in
                    PointMark(x: .value("Group", x + p.jitter * 0.36), y: .value("Value", p.value))
                        .foregroundStyle(color.opacity(0.7))
                        .symbolSize(34)
                }
                if let sem = g.sem, sem.isFinite, sem > 0 {
                    RuleMark(x: .value("Group", x), yStart: .value("Low", g.mean - sem), yEnd: .value("High", g.mean + sem))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    RuleMark(xStart: .value("Group", x - 0.07), xEnd: .value("Group", x + 0.07), y: .value("High", g.mean + sem))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    RuleMark(xStart: .value("Group", x - 0.07), xEnd: .value("Group", x + 0.07), y: .value("Low", g.mean - sem))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                RuleMark(xStart: .value("Group", x - 0.24), xEnd: .value("Group", x + 0.24), y: .value("Mean", g.mean))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .chartXScale(domain: -0.6...(Double(max(1, groups.count)) - 0.4))
        .chartXAxis {
            AxisMarks(values: positions.map(Double.init)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self), groups.indices.contains(Int(v.rounded())) {
                        let i = Int(v.rounded())
                        VStack(spacing: 1) {
                            Text(groups[i].name).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            Text("n = \(groups[i].n)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) { Text(yTitle).font(.caption) }
        .chartLegend(.hidden)
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groups.map { g in
            String(format: L("%@: mean %@, n = %d", "%@：均值 %@，n = %d"), g.name, Fmt.num(g.mean, 2), g.n)
        }.joined(separator: "; "))
    }
}

/// n, mean, SD, SEM per group.
struct StatsTable: View {
    let groups: [GroupSummary]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text(L("Group", "组别")).gridColumnAlignment(.leading)
                Text("n"); Text(L("Mean", "均值")); Text("SD"); Text("SEM")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(groups) { g in
                GridRow {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.group(g.index)).frame(width: 8, height: 8)
                        Text(g.name).lineLimit(1)
                    }
                    Text("\(g.n)")
                    Text(Fmt.num(g.mean, 2))
                    Text(Fmt.num(g.sd, 2))
                    Text(Fmt.num(g.sem, 2))
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
    }
}

/// Group mean ± SEM across the task's timepoints.
struct TimepointChart: View {
    let points: [CoursePoint]
    let timepoints: [String]
    let yTitle: String

    var body: some View {
        let names = legendNames
        Chart {
            ForEach(points) { p in
                let name = names[p.group] ?? p.group
                LineMark(x: .value("Timepoint", p.label), y: .value("Mean", p.mean))
                    .foregroundStyle(by: .value("Group", name))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Timepoint", p.label), y: .value("Mean", p.mean))
                    .foregroundStyle(by: .value("Group", name))
                    .symbolSize(40)
                if let s = p.sem, s.isFinite, s > 0 {
                    RuleMark(x: .value("Timepoint", p.label), yStart: .value("Low", p.mean - s), yEnd: .value("High", p.mean + s))
                        .foregroundStyle(by: .value("Group", name))
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
        }
        .chartXScale(domain: timepoints)
        .chartForegroundStyleScale(domain: orderedNames, range: orderedColors)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) { Text(yTitle).font(.caption) }
        .chartXAxisLabel(position: .bottom, alignment: .center) { Text(L("Timepoint", "时间点")).font(.caption) }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 240)
    }

    /// "Control (n = 6)", using the largest n over the timepoints.
    private var legendNames: [String: String] {
        var n: [String: Int] = [:]
        for p in points { n[p.group] = max(n[p.group] ?? 0, p.n) }
        return n.reduce(into: [:]) { $0[$1.key] = "\($1.key) (n = \($1.value))" }
    }

    private var ordered: [(String, Int)] {
        var seen = Set<String>(), out: [(String, Int)] = []
        for p in points.sorted(by: { ($0.groupIndex, $0.group) < ($1.groupIndex, $1.group) }) where seen.insert(p.group).inserted {
            out.append((p.group, p.groupIndex))
        }
        return out
    }
    private var orderedNames: [String] { ordered.map { legendNames[$0.0] ?? $0.0 } }
    private var orderedColors: [Color] { ordered.map { Palette.group($0.1) } }
}

/// Group mean line with a ± SEM band per bin.
struct BinnedCourseChart: View {
    let points: [CoursePoint]
    let yTitle: String
    let xTitle: String

    var body: some View {
        let names = legendNames
        Chart {
            ForEach(points) { p in
                let name = names[p.group] ?? p.group
                if let s = p.sem, s.isFinite {
                    AreaMark(x: .value("Time", p.x), yStart: .value("Low", p.mean - s), yEnd: .value("High", p.mean + s))
                        .foregroundStyle(by: .value("Group", name))
                        .opacity(0.16)
                        .interpolationMethod(.monotone)
                }
                LineMark(x: .value("Time", p.x), y: .value("Mean", p.mean))
                    .foregroundStyle(by: .value("Group", name))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale(domain: orderedNames, range: orderedColors)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisTick()
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center) { Text(yTitle).font(.caption) }
        .chartXAxisLabel(position: .bottom, alignment: .center) { Text(xTitle).font(.caption) }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 240)
    }

    private var legendNames: [String: String] {
        var n: [String: Int] = [:]
        for p in points { n[p.group] = max(n[p.group] ?? 0, p.n) }
        return n.reduce(into: [:]) { $0[$1.key] = "\($1.key) (n = \($1.value))" }
    }

    private var ordered: [(String, Int)] {
        var seen = Set<String>(), out: [(String, Int)] = []
        for p in points.sorted(by: { ($0.groupIndex, $0.group) < ($1.groupIndex, $1.group) }) where seen.insert(p.group).inserted {
            out.append((p.group, p.groupIndex))
        }
        return out
    }
    private var orderedNames: [String] { ordered.map { legendNames[$0.0] ?? $0.0 } }
    private var orderedColors: [Color] { ordered.map { Palette.group($0.1) } }
}
