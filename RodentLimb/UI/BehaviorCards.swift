// BehaviorCards.swift — result cards shared by the behavior assays (itch, spontaneous pain,
// self-grooming, seizure scoring). They read a `BehaviorDetail`, so each assay gets the same
// ethogram, time course, detection signal and event review list.

import SwiftUI
import Charts

/// Time axis for behavior charts: minutes (or seconds for short videos) from the injection.
struct BehaviorTimeAxis {
    let origin: Double
    let scale: Double

    init(_ d: BehaviorDetail) {
        origin = d.origin
        scale = d.window.duration >= 180 ? 60 : 1
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

extension EventClass {
    var tint: Color { Palette.event(color) }
}

// MARK: - Ethogram

@MainActor
struct BehaviorEthogramCard: View {
    let detail: BehaviorDetail
    var currentTime: Double?
    /// Playback clock for the review tab. Only the thin playhead observes it, so the chart with
    /// its (possibly thousands of) bars is not rebuilt four times a second during playback.
    var clock: CoarseClock? = nil
    let seek: (Double) -> Void

    private struct Bar: Identifiable {
        let id: Int
        let row: String
        let start: Double
        let end: Double
        let color: UInt32
    }

    private var axis: BehaviorTimeAxis { BehaviorTimeAxis(detail) }
    private var rows: [String] { detail.tracks.map(\.label.text) }

    private var bars: [Bar] {
        let ax = axis
        var out: [Bar] = []
        for tr in detail.tracks {
            for iv in tr.intervals {
                // Keep very short events (jerks, flinches) visible.
                let minW = 0.004 * max(1, ax.x(detail.window.end) - ax.x(detail.window.start))
                let a = ax.x(iv.start), b = max(ax.x(iv.end), a + minW)
                out.append(Bar(id: out.count, row: tr.label.text, start: a, end: b, color: tr.color))
            }
        }
        return out
    }

    var body: some View {
        Card {
            CardHeader(L("Ethogram", "行为时间轴"),
                       subtitle: L("Each row is one behavior over the session. Tap to jump to that moment.",
                                   "每一行是一种行为在整个记录中的分布。轻点可跳到该时刻。"))
            if rows.isEmpty {
                Text(L("Nothing to show.", "暂无内容。")).font(.footnote).foregroundStyle(.secondary)
            } else {
                chart
            }
            if !detail.phases.isEmpty { phaseLegend }
        }
    }

    private var chart: some View {
        let ax = axis
        // From the start of the video, so a pre-injection baseline is visible too.
        let lo = ax.x(min(0, detail.window.start)), hi = ax.x(detail.window.end)
        return Chart {
            ForEach(Array(detail.phases.enumerated()), id: \.offset) { item in
                ForEach(rows, id: \.self) { row in
                    RectangleMark(xStart: .value("t", ax.x(item.element.interval.start)), xEnd: .value("t", ax.x(item.element.interval.end)),
                                  y: .value("row", row), height: .ratio(1))
                        .foregroundStyle(Color.primary.opacity(item.offset % 2 == 0 ? 0.05 : 0.09))
                }
            }
            ForEach(bars) { b in
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
            if let now = currentTime, ax.x(now) >= lo, ax.x(now) <= hi {
                RuleMark(x: .value("now", ax.x(now))).foregroundStyle(Color.accentColor)
            }
        }
        .chartXScale(domain: lo...max(hi, lo + 0.01))
        .chartYScale(domain: rows)
        .chartXAxisLabel(ax.title)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard let plot = proxy.plotFrame else { return }
                        if let x: Double = proxy.value(atX: loc.x - geo[plot].origin.x) { seek(max(0, ax.t(x))) }
                    }
                if let clock {
                    EthogramPlayhead(clock: clock, proxy: proxy, geo: geo, axis: ax, lo: lo, hi: hi)
                }
            }
        }
        .frame(height: CGFloat(max(2, rows.count)) * 30 + 54)
        .accessibilityLabel(L("Ethogram", "行为时间轴"))
    }

    private var phaseLegend: some View {
        FlowLayout(spacing: 12, lineSpacing: 4) {
            ForEach(Array(detail.phases.enumerated()), id: \.offset) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(item.offset % 2 == 0 ? 0.12 : 0.2)).frame(width: 12, height: 8)
                    Text(item.element.label.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Vertical line at the playback position, drawn over the ethogram's plot area.
@MainActor
private struct EthogramPlayhead: View {
    @ObservedObject var clock: CoarseClock
    let proxy: ChartProxy
    let geo: GeometryProxy
    let axis: BehaviorTimeAxis
    let lo: Double
    let hi: Double

    var body: some View {
        let x = axis.x(clock.time)
        if x.isFinite, x >= lo, x <= hi, let plot = proxy.plotFrame, let px = proxy.position(forX: x) {
            let frame = geo[plot]
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: frame.height)
                .position(x: frame.minX + px, y: frame.midY)
                .allowsHitTesting(false)
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

    var body: some View {
        if let s = series {
            Card {
                CardHeader(L("Time course", "时间进程"),
                           subtitle: String(format: L("%@, in %@ bins.", "%@，每 %@ 一段。"), s.label.text, binText))
                if detail.bins.count > 1 {
                    Picker(L("Measure", "指标"), selection: Binding(get: { s.key }, set: { selected = $0 })) {
                        ForEach(detail.bins) { Text($0.label.text).tag($0.key) }
                    }
                    .pickerStyle(.menu)
                }
                chart(s)
            }
        }
    }

    private var binText: String {
        let b = detail.binSize
        if b >= 60 { return String(format: L("%g-min", "%g 分钟"), b / 60) }
        return String(format: L("%g-s", "%g 秒"), b)
    }

    /// Bin edges on the axis (minutes or seconds after the injection), with a small gap.
    private func edges(_ i: Int) -> (Double, Double) {
        let unit = detail.binSize >= 60 ? 60.0 : 1.0
        let a = Double(i) * detail.binSize / unit, w = detail.binSize / unit
        return (a + 0.06 * w, a + 0.94 * w)
    }

    private func chart(_ s: BinSeries) -> some View {
        let unit = detail.binSize >= 60 ? 60.0 : 1.0
        let xmax = max(1e-6, Double(s.values.count) * detail.binSize / unit)
        let ymax = max(1e-6, (s.values.filter { $0.isFinite }.max() ?? 0) * 1.1)
        return Chart {
            ForEach(Array(s.values.enumerated()), id: \.offset) { item in
                RectangleMark(xStart: .value("t", edges(item.offset).0), xEnd: .value("t", edges(item.offset).1),
                              yStart: .value("v", 0.0), yEnd: .value("v", item.element.isFinite ? item.element : 0))
                    .foregroundStyle(tint.opacity(inPhase(item.offset) ? 1 : 0.55))
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: 0...xmax)
        .chartYScale(domain: 0...ymax)
        .chartXAxisLabel(detail.binSize >= 60
                         ? (detail.origin > 0 ? L("Minutes after injection", "注射后分钟") : L("Minute", "分钟"))
                         : (detail.origin > 0 ? L("Seconds after injection", "注射后秒") : L("Second", "秒")))
        .chartYAxisLabel(unitText(s.unit))
        .frame(height: 170)
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
        let a = detail.origin + Double(i) * detail.binSize, b = a + detail.binSize
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
        let pts = detail.signal.filter { $0.v.isFinite }
        Card {
            CardHeader(L("Detection signal", "检测信号"),
                       subtitle: detail.signalLabel.text + (detail.signalThreshold != nil ? L(" · dashed line = threshold", " · 虚线 = 阈值") : ""))
            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("t", ax.x(item.element.t)), y: .value("v", item.element.v))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                if let thr = detail.signalThreshold {
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
                            guard let plot = proxy.plotFrame else { return }
                            if let x: Double = proxy.value(atX: loc.x - geo[plot].origin.x) { seek(max(0, ax.t(x))) }
                        }
                }
            }
            .frame(height: 170)
        }
    }
}

// MARK: - Composition (time per track)

@MainActor
struct BehaviorCompositionCard: View {
    let detail: BehaviorDetail
    let title: String

    private var rows: [(BehaviorTrack, Double)] {
        detail.tracks.map { tr in
            (tr, tr.intervals.reduce(0) { acc, iv in
                acc + max(0, min(iv.end, detail.window.end) - max(iv.start, detail.window.start))
            })
        }
    }

    var body: some View {
        let r = rows
        let total = max(1e-9, r.map(\.1).reduce(0, +))
        if total > 0.01 {
            Card {
                CardHeader(title)
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(r.indices, id: \.self) { i in
                            if r[i].1 > 0 {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.event(r[i].0.color))
                                    .frame(width: max(4, geo.size.width * CGFloat(r[i].1 / total) - 3))
                            }
                        }
                    }
                }
                .frame(height: 22)
                .accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(r.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle().fill(Palette.event(r[i].0.color)).frame(width: 8, height: 8)
                                Text(r[i].0.label.text).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text(String(format: "%.1f s · %.0f%%", r[i].1, r[i].1 / total * 100))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: - Event review

@MainActor
struct BehaviorEventList: View {
    let detail: BehaviorDetail
    let currentTime: Double
    let seek: (Double) -> Void
    /// (event id, new class key — nil restores the automatic label)
    let relabel: (Int, String?) -> Void

    @State private var filter: String?
    @State private var showAll = false

    private var list: [BehaviorEvent] { detail.events.filter { filter == nil || $0.label == filter } }
    private var choices: [EventClass] { detail.classes.filter { $0.key != EventClass.ignore.key } }

    var body: some View {
        let items = list
        Card {
            CardHeader(L("Check each event", "逐个复核事件"),
                       subtitle: L("Tap a row to play it. Change the label if the automatic call is wrong — edits are kept and every measure updates.",
                                   "轻点行即可播放该片段；如自动判断有误，可修改标签，修改会保留，所有指标随之更新。"))
            Picker(L("Filter", "筛选"), selection: $filter) {
                Text(String(format: L("All (%d)", "全部（%d）"), detail.events.count)).tag(String?.none)
                ForEach(choices) { c in
                    Text("\(c.label.text) (\(detail.events.filter { $0.label == c.key }.count))").tag(String?.some(c.key))
                }
                Text(EventClass.ignore.label.text).tag(String?.some(EventClass.ignore.key))
            }
            .pickerStyle(.menu)
            if items.isEmpty {
                Text(L("No events. If the behavior is visible in the video, check the parameters and the pose coverage.",
                       "没有事件。如果视频里能看到该行为，请检查参数和姿态覆盖率。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            // Lazy: with "Show all" a long video can list thousands of events.
            LazyVStack(spacing: 2) {
                ForEach(showAll ? items : Array(items.prefix(12))) { e in
                    BehaviorEventRow(event: e, detail: detail,
                                     active: currentTime >= e.onset - 0.05 && currentTime <= max(e.offset, e.onset + 0.3),
                                     seek: seek, relabel: relabel)
                }
            }
            if items.count > 12 {
                Button(showAll ? L("Show fewer", "收起") : String(format: L("Show all %d", "显示全部 %d 条"), items.count)) {
                    withAnimation(Motion.snappy) { showAll.toggle() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }
}

@MainActor
private struct BehaviorEventRow: View {
    let event: BehaviorEvent
    let detail: BehaviorDetail
    let active: Bool
    let seek: (Double) -> Void
    let relabel: (Int, String?) -> Void

    private var cls: EventClass { detail.eventClass(event.label) }
    private var ignored: Bool { event.label == EventClass.ignore.key }

    var body: some View {
        HStack(spacing: 10) {
            Button { seek(max(0, event.onset - 1.0)) } label: {
                HStack(spacing: 10) {
                    // Playback control: plays the video from just before this event.
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(ignored ? Color.secondary : cls.tint)
                        .opacity(active ? 1 : 0.8)
                        .accessibilityLabel(L("Play from here", "从这里播放"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timeText).font(.subheadline.monospacedDigit().weight(.medium))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 6)
            Menu {
                Picker(L("Label", "标签"), selection: Binding(get: { event.label }, set: { k in relabel(event.id, k == event.auto ? nil : k) })) {
                    ForEach(detail.classes) { c in Text(c.label.text).tag(c.key) }
                }
            } label: {
                Text(ignored ? L("Ignored", "已忽略") : cls.label.text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(ignored ? Color.secondary : Color.white)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .frame(maxWidth: 150)
                    .background(ignored ? Palette.inset : Color(uiColor: UIColor(hex: cls.color)), in: Capsule())
            }
            .accessibilityLabel(String(format: L("Label: %@. Change", "标签：%@，更改"), cls.label.text))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(event.counted || ignored ? 1 : 0.55)
    }

    private var timeText: String {
        let t = Fmt.clockPrecise(event.onset)
        guard detail.origin > 0 else { return t }
        let rel = event.onset - detail.origin
        return t + "  (" + (rel < 0 ? "−" : "+") + Fmt.clock(abs(rel)) + ")"
    }

    private var subtitle: String {
        var parts = [String(format: L("%.1f s", "%.1f 秒"), event.duration)]
        if let info = event.info, !info.isEmpty { parts.append(info) }
        if event.edited { parts.append(L("edited", "已修改")) }
        if !event.counted && !ignored {
            parts.append(event.onset < detail.window.start ? L("before the window", "在分析窗口之前") : L("outside the window", "在分析窗口之外"))
        }
        return parts.joined(separator: " · ")
    }
}
