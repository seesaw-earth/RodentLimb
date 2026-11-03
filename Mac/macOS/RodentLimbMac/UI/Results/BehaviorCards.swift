// BehaviorCards.swift — result cards shared by the behavior assays (itch, spontaneous pain,
// self-grooming, seizure scoring), ported from the iPhone. They read a `BehaviorDetail`, so each
// assay gets the same ethogram, time course, detection signal and composition. The event review
// list lives in AnalysisEventList.swift (one list for every assay on the Mac).
// Mac: click a chart to go to that moment; the ethogram's playhead is its own tiny view observing
// the coarse ResultsPlaybackClock, so the (possibly thousands of) bars are not rebuilt during playback.

import SwiftUI
import Charts

/// Time axis for behavior charts: minutes (or seconds for short videos) from the injection.
struct BehaviorTimeAxis {
    let origin: Double
    let scale: Double

    init(_ d: BehaviorDetail) {
        origin = d.origin.finiteOr(0)
        scale = d.window.duration.finiteOr(0) >= 180 ? 60 : 1
    }

    func x(_ t: Double) -> Double { (t - origin) / scale }
    func t(_ x: Double) -> Double { x * scale + origin }

    var title: String {
        let unit = scale == 60 ? L("min", "分钟") : L("s", "秒")
        return origin > 0
            ? String(format: L("Time after injection (%@)", "注射后时间（%@）"), unit)
            : String(format: L("Time (%@)", "时间（%@）"), unit)
    }
}

// MARK: - Ethogram

@MainActor
struct BehaviorEthogramCard: View {
    let detail: BehaviorDetail
    /// Review tab: playhead over the chart (only that thin line observes the clock).
    var clock: ResultsPlaybackClock? = nil
    let seek: (Double) -> Void

    private struct Bar: Identifiable {
        let id: Int
        let row: String
        let start: Double
        let end: Double
        let color: UInt32
    }

    private var axis: BehaviorTimeAxis { BehaviorTimeAxis(detail) }
    private var rows: [String] {
        var seen = Set<String>(), out: [String] = []
        for tr in detail.tracks where !seen.contains(tr.label.text) {
            seen.insert(tr.label.text)
            out.append(tr.label.text)
        }
        return out
    }

    private func bars(lo: Double, hi: Double) -> [Bar] {
        let ax = axis
        // Keep very short events (jerks, flinches) visible.
        let minW = 0.004 * max(1, hi - lo)
        var out: [Bar] = []
        for tr in detail.tracks {
            for iv in tr.intervals where iv.start.isFinite && iv.end.isFinite {
                let a = ax.x(iv.start), b = max(ax.x(iv.end), a + minW)
                out.append(Bar(id: out.count, row: tr.label.text, start: a, end: b, color: tr.color))
            }
        }
        return out
    }

    var body: some View {
        let rowList = rows
        Card {
            CardHeader(L("Ethogram", "行为时间轴"), symbol: "chart.bar.xaxis",
                       subtitle: L("Each row is one behavior over the session. Click to go to that moment in the video.",
                                   "每一行是一种行为在整个记录中的分布。点击可跳到视频中的该时刻。"))
            if rowList.isEmpty {
                Text(L("Nothing to show.", "暂无内容。")).font(.callout).foregroundStyle(.secondary)
            } else {
                chart(rowList)
            }
            if !detail.phases.isEmpty { phaseLegend }
        }
    }

    private func chart(_ rowList: [String]) -> some View {
        let ax = axis
        // From the start of the video, so a pre-injection baseline is visible too.
        let rawLo = ax.x(min(0, detail.window.start.finiteOr(0)))
        let rawHi = ax.x(detail.window.end.finiteOr(0))
        let lo = rawLo.isFinite ? rawLo : 0
        let hi = rawHi.isFinite && rawHi > lo + 0.01 ? rawHi : lo + 0.01
        let list = bars(lo: lo, hi: hi)
        let phases = detail.phases.filter { $0.interval.start.isFinite && $0.interval.end.isFinite }
        return Chart {
            ForEach(Array(phases.enumerated()), id: \.offset) { item in
                ForEach(rowList, id: \.self) { row in
                    RectangleMark(xStart: .value("t", ax.x(item.element.interval.start)), xEnd: .value("t", ax.x(item.element.interval.end)),
                                  y: .value("row", row), height: .ratio(1))
                        .foregroundStyle(Color.primary.opacity(item.offset % 2 == 0 ? 0.05 : 0.09))
                }
            }
            ForEach(list) { b in
                BarMark(xStart: .value("t", b.start), xEnd: .value("t", b.end), y: .value("row", b.row), height: .ratio(0.62))
                    .foregroundStyle(Palette.event(b.color))
                    .cornerRadius(2)
            }
            if detail.origin > 0 {
                RuleMark(x: .value("injection", 0.0))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(L("Injection", "注射")).font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: lo...hi)
        .chartYScale(domain: rowList)
        .chartXAxisLabel(ax.title)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        if let x = ResultsChartMath.value(at: loc, proxy: proxy, geo: geo) { seek(max(0, ax.t(x))) }
                    }
                if let clock {
                    ChartPlayheadLine(clock: clock, proxy: proxy, geo: geo, x: { ax.x($0) }, lo: lo, hi: hi)
                }
            }
        }
        .frame(height: CGFloat(max(2, rowList.count)) * 28 + 54)
        .help(L("Click to go to this moment in the video", "点击跳到视频中的该时刻"))
        .accessibilityLabel(L("Ethogram", "行为时间轴"))
    }

    private var phaseLegend: some View {
        HStack(spacing: 12) {
            ForEach(Array(detail.phases.enumerated()), id: \.offset) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(item.offset % 2 == 0 ? 0.12 : 0.2)).frame(width: 12, height: 8)
                    Text(item.element.label.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Time course

@MainActor
struct BehaviorTimeCourseCard: View {
    let detail: BehaviorDetail
    var tint: Color = .accentColor
    @State private var selected: String?

    private var series: BinSeries? {
        detail.bins.first { $0.key == selected } ?? detail.bins.first
    }

    private var binSize: Double { ResultsChartMath.top(detail.binSize, fallback: 60) }
    private var unit: Double { binSize >= 60 ? 60 : 1 }

    var body: some View {
        if let s = series {
            Card {
                CardHeader(title: L("Time course", "时间进程"), symbol: "chart.bar",
                           subtitle: String(format: L("%@, in %@ bins.", "%@，每 %@ 一段。"), s.label.text, binText)) {
                    if detail.bins.count > 1 {
                        Picker(L("Measure", "指标"), selection: Binding(get: { s.key }, set: { selected = $0 })) {
                            ForEach(detail.bins) { Text($0.label.text).tag($0.key) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        .help(L("Measure shown", "显示的指标"))
                    }
                }
                chart(s)
            }
        }
    }

    private var binText: String {
        let b = binSize
        if b >= 60 { return String(format: L("%g-min", "%g 分钟"), b / 60) }
        return String(format: L("%g-s", "%g 秒"), b)
    }

    /// Bin edges on the axis (minutes or seconds after the injection), with a small gap.
    private func edges(_ i: Int) -> (Double, Double) {
        let a = Double(i) * binSize / unit, w = binSize / unit
        return (a + 0.06 * w, a + 0.94 * w)
    }

    private func chart(_ s: BinSeries) -> some View {
        let xmax = ResultsChartMath.top(Double(s.values.count) * binSize / unit, fallback: 1)
        let ymax = ResultsChartMath.top((s.values.filter { $0.isFinite }.max() ?? 0) * 1.1, fallback: 1)
        return Chart {
            ForEach(Array(s.values.enumerated()), id: \.offset) { item in
                RectangleMark(xStart: .value("t", edges(item.offset).0), xEnd: .value("t", edges(item.offset).1),
                              yStart: .value("v", 0.0), yEnd: .value("v", item.element.isFinite ? max(0, item.element) : 0))
                    .foregroundStyle(tint.opacity(inPhase(item.offset) ? 1 : 0.55))
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: 0...xmax)
        .chartYScale(domain: 0...ymax)
        .chartXAxisLabel(binSize >= 60
                         ? (detail.origin > 0 ? L("Minutes after injection", "注射后分钟") : L("Minute", "分钟"))
                         : (detail.origin > 0 ? L("Seconds after injection", "注射后秒") : L("Second", "秒")))
        .chartYAxisLabel(unitText(s.unit))
        .frame(height: 180)
    }

    private func unitText(_ u: String) -> String {
        switch u {
        case "s": return L("s", "秒")
        case "n": return L("count", "次")
        case "stage": return L("stage", "级")
        default: return u
        }
    }

    /// Bars inside a shaded phase are drawn solid; others lighter.
    private func inPhase(_ i: Int) -> Bool {
        guard !detail.phases.isEmpty else { return true }
        let a = detail.origin + Double(i) * binSize, b = a + binSize
        return detail.phases.contains { $0.interval.start < b - 1e-6 && $0.interval.end > a + 1e-6 }
    }
}

// MARK: - Detection signal

@MainActor
struct BehaviorSignalCard: View {
    let detail: BehaviorDetail
    let seek: (Double) -> Void

    var body: some View {
        let ax = BehaviorTimeAxis(detail)
        let pts = ResultsChartMath.envelope(detail.signal)
        Card {
            CardHeader(L("Detection signal", "检测信号"), symbol: "waveform.path.ecg",
                       subtitle: detail.signalLabel.text + (detail.signalThreshold != nil ? L(" · dashed line = threshold", " · 虚线 = 阈值") : ""))
            if pts.isEmpty {
                Text(L("Nothing to show.", "暂无内容。")).font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(Array(pts.enumerated()), id: \.offset) { item in
                        LineMark(x: .value("t", ax.x(item.element.t)), y: .value("v", item.element.v))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    if let thr = detail.signalThreshold, thr.isFinite {
                        RuleMark(y: .value("thr", thr))
                            .foregroundStyle(Palette.right)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if detail.origin > 0 {
                        RuleMark(x: .value("injection", 0.0)).foregroundStyle(Color.primary.opacity(0.5))
                    }
                }
                .chartXAxisLabel(ax.title)
                .chartYAxisLabel(detail.signalUnit)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { loc in
                                if let x = ResultsChartMath.value(at: loc, proxy: proxy, geo: geo) { seek(max(0, ax.t(x))) }
                            }
                    }
                }
                .frame(height: 180)
                .help(L("Click to go to this moment in the video", "点击跳到视频中的该时刻"))
            }
        }
    }
}

// MARK: - Composition (time per track)

@MainActor
struct BehaviorCompositionCard: View {
    let detail: BehaviorDetail
    let title: String

    private var rows: [(BehaviorTrack, Double)] {
        let w0 = detail.window.start, w1 = detail.window.end
        return detail.tracks.map { tr in
            (tr, tr.intervals.reduce(0) { acc, iv in
                let d = min(iv.end, w1) - max(iv.start, w0)
                return acc + (d.isFinite ? max(0, d) : 0)
            })
        }
    }

    var body: some View {
        let r = rows
        let sum = r.map(\.1).reduce(0, +)
        let total = max(1e-9, sum.finiteOr(0))
        if total > 0.01 {
            Card {
                CardHeader(title, symbol: "chart.pie")
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(r.indices, id: \.self) { i in
                            if r[i].1 > 0 {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Palette.event(r[i].0.color))
                                    .frame(width: max(4, geo.size.width * CGFloat(r[i].1 / total) - 3))
                            }
                        }
                    }
                }
                .frame(height: 20)
                .accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(r.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle().fill(Palette.event(r[i].0.color)).frame(width: 8, height: 8)
                                Text(r[i].0.label.text).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(String(format: L("%.1f s · %.0f%%", "%.1f 秒 · %.0f%%"), r[i].1, r[i].1 / total * 100))
                                .font(.headline).monospacedDigit()
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
