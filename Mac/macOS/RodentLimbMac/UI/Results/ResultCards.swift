// ResultCards.swift — result cards of tail suspension, cylinder and gait (port of the iPhone's
// ResultSections.swift). Each card is a small view with one job, so the analysis page can place
// them per tab (Summary / Review / Measures) and the type checker stays fast.
// Mac: clicks instead of taps, denser sizes, hover tooltips; charts never observe the player —
// the playhead is a separate tiny view observing the coarse ResultsPlaybackClock.

import Foundation
import SwiftUI
import Charts

// MARK: - Chart helpers

/// Small numeric helpers shared by the result charts (Mac Results module).
enum ResultsChartMath {
    /// At most `maxPoints` points: each bucket keeps its minimum and maximum (in time order), so
    /// peaks and threshold crossings survive. Non-finite points are dropped.
    static func envelope(_ points: [SeriesPoint], maxPoints: Int = 1600) -> [SeriesPoint] {
        let pts = points.filter { $0.t.isFinite && $0.v.isFinite }
        guard maxPoints >= 4, pts.count > maxPoints else { return pts }
        let buckets = max(1, maxPoints / 2)
        let size = max(1, (pts.count + buckets - 1) / buckets)
        var out: [SeriesPoint] = []
        out.reserveCapacity(buckets * 2 + 2)
        var i = 0
        while i < pts.count {
            let end = min(pts.count, i + size)
            var lo = pts[i], hi = pts[i]
            var j = i
            while j < end {
                let p = pts[j]
                if p.v < lo.v { lo = p }
                if p.v > hi.v { hi = p }
                j += 1
            }
            if lo.t <= hi.t { out.append(lo); if hi != lo { out.append(hi) } } else { out.append(hi); out.append(lo) }
            i = end
        }
        return out
    }

    /// A finite, positive upper bound for a chart axis.
    static func top(_ v: Double, fallback: Double = 1) -> Double {
        v.isFinite && v > 0 ? v : fallback
    }

    /// Chart x value at a click inside the plot area (main actor: only called from the charts' tap
    /// handlers, and ChartProxy / GeometryProxy may be main-actor bound in recent SDKs).
    @MainActor
    static func value(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Double? {
        guard let plot = proxy.plotFrame else { return nil }
        let x = location.x - geo[plot].origin.x
        guard let v: Double = proxy.value(atX: x), v.isFinite else { return nil }
        return v
    }
}

/// Vertical line at the playback position over a chart's plot area. Only this view observes the
/// clock, so the chart itself is never rebuilt during playback.
@MainActor
struct ChartPlayheadLine: View {
    @ObservedObject var clock: ResultsPlaybackClock
    let proxy: ChartProxy
    let geo: GeometryProxy
    /// Track time → chart x value.
    let x: (Double) -> Double
    let lo: Double
    let hi: Double

    var body: some View {
        let v = x(clock.time)
        if v.isFinite, v >= lo, v <= hi, let plot = proxy.plotFrame, let px = proxy.position(forX: v) {
            let frame = geo[plot]
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: frame.height)
                .position(x: frame.minX + px, y: frame.midY)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Tail suspension

@MainActor
struct TSTMotionCard: View {
    let detail: TSTDetail
    /// Review tab: playhead over the chart.
    var clock: ResultsPlaybackClock? = nil
    var height: CGFloat = 200
    let seek: (Double) -> Void

    var body: some View {
        Card {
            CardHeader(L("Motion over time", "运动随时间变化"), symbol: "waveform.path",
                       subtitle: L("Shaded = immobile · dashed line = threshold. Click the chart to go to that moment in the video.",
                                   "阴影 = 不动，虚线 = 阈值。点击图表可跳到视频中的该时刻。"))
            chart
        }
    }

    private var chart: some View {
        let points = ResultsChartMath.envelope(detail.motion)
        let peak = points.map(\.v).max() ?? 1
        let top = ResultsChartMath.top(max(detail.threshold.finiteOr(0.25) * 4, min(3, peak)))
        let lastT = max(detail.window.end.finiteOr(0), points.last?.t ?? 0)
        let xmax = ResultsChartMath.top(lastT)
        let bouts = detail.bouts.filter { $0.start.isFinite && $0.end.isFinite }
        return Chart {
            if detail.window.start.isFinite && detail.window.end.isFinite && detail.window.end > detail.window.start {
                RectangleMark(xStart: .value("t", detail.window.start), xEnd: .value("t", detail.window.end),
                              yStart: .value("v", 0.0), yEnd: .value("v", top))
                    .foregroundStyle(Color.accentColor.opacity(0.05))
            }
            ForEach(Array(bouts.enumerated()), id: \.offset) { item in
                RectangleMark(xStart: .value("t", item.element.start), xEnd: .value("t", item.element.end),
                              yStart: .value("v", 0.0), yEnd: .value("v", top))
                    .foregroundStyle(Palette.assay(.tailSuspension).opacity(0.22))
            }
            ForEach(Array(points.enumerated()), id: \.offset) { item in
                LineMark(x: .value("t", item.element.t), y: .value("v", min(item.element.v, top)))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            if detail.threshold.isFinite {
                RuleMark(y: .value("thr", detail.threshold))
                    .foregroundStyle(Palette.right)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: 0...xmax)
        .chartYScale(domain: 0...top)
        .chartXAxisLabel(L("Time (s)", "时间（秒）"))
        .chartYAxisLabel(L("BL/s", "体长/秒"))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        if let t = ResultsChartMath.value(at: loc, proxy: proxy, geo: geo) { seek(max(0, t)) }
                    }
                if let clock {
                    ChartPlayheadLine(clock: clock, proxy: proxy, geo: geo, x: { $0 }, lo: 0, hi: xmax)
                }
            }
        }
        .frame(height: height)
        .help(L("Click to go to this moment in the video", "点击跳到视频中的该时刻"))
        .accessibilityLabel(L("Motion chart", "运动曲线图"))
    }
}

@MainActor
struct TSTPerMinuteCard: View {
    let detail: TSTDetail

    var body: some View {
        Card {
            CardHeader(L("Immobility per minute", "每分钟不动时间"), symbol: "chart.bar",
                       subtitle: L("Gray minutes are outside the analysis window.", "灰色为分析窗口之外的分钟。"))
            Chart {
                ForEach(Array(detail.perMinute.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("min", "\(item.offset + 1)"), y: .value("s", item.element.isFinite ? min(60, max(0, item.element)) : 0))
                        .foregroundStyle(inWindow(item.offset) ? Palette.assay(.tailSuspension) : Palette.gray.opacity(0.4))
                        .cornerRadius(4)
                }
            }
            .chartYScale(domain: 0...60)
            .chartXAxisLabel(L("Minute", "分钟"))
            .chartYAxisLabel(L("s", "秒"))
            .frame(height: 170)
        }
    }

    private func inWindow(_ minute: Int) -> Bool {
        let a = Double(minute) * 60, b = a + 60
        return b > detail.window.start + 1 && a < detail.window.end - 1
    }
}

// MARK: - Cylinder

@MainActor
struct CylinderUseCard: View {
    let detail: CylinderDetail

    private var counts: [(PawLabel, Int)] {
        let c = detail.events.filter { $0.counted }
        return [PawLabel.left, .right, .both].map { l in (l, c.filter { $0.label == l }.count) }
    }

    var body: some View {
        let rows = counts
        let total = max(1, rows.map(\.1).reduce(0, +))
        Card {
            CardHeader(L("Forelimb use", "前爪使用"), symbol: "hand.raised")
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(rows.indices, id: \.self) { i in
                        if rows[i].1 > 0 {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Palette.label(rows[i].0))
                                .frame(width: max(4, geo.size.width * CGFloat(rows[i].1) / CGFloat(total) - 3))
                        }
                    }
                }
            }
            .frame(height: 22)
            .accessibilityHidden(true)
            HStack(spacing: 22) {
                ForEach(rows.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(Palette.label(rows[i].0)).frame(width: 8, height: 8)
                            Text(rows[i].0.name).font(.callout).foregroundStyle(.secondary)
                        }
                        Text("\(rows[i].1)").font(.title3.weight(.semibold)).monospacedDigit().textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

@MainActor
struct CylinderTimelineCard: View {
    let detail: CylinderDetail
    var seek: ((Double) -> Void)? = nil

    var body: some View {
        let events = detail.events.filter { $0.onset.isFinite }
        Card {
            CardHeader(L("Contacts over time", "触壁时间分布"), symbol: "timeline.selection")
            Chart {
                ForEach(events) { e in
                    PointMark(x: .value("t", e.onset), y: .value("paw", e.label.name))
                        .foregroundStyle(e.counted ? Palette.label(e.label) : Palette.gray.opacity(0.4))
                        .symbolSize(e.edited ? 80 : 44)
                }
            }
            .chartXAxisLabel(L("Time (s)", "时间（秒）"))
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let seek {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { loc in
                                if let t = ResultsChartMath.value(at: loc, proxy: proxy, geo: geo) { seek(max(0, t)) }
                            }
                    }
                }
            }
            .frame(height: 140)
        }
    }
}

// MARK: - Gait

private struct FootfallBar: Identifiable {
    let id: Int
    let paw: Kp
    let start: Double
    let end: Double
}

@MainActor
struct FootfallCard: View {
    let detail: GaitDetail
    /// Playback position (nil on the Summary tab).
    var currentTime: Double? = nil
    /// Review tab: the window follows playback.
    var follow = false

    @State private var windowStart: Double = 0
    @State private var windowLength: Double = 2

    private var lastTime: Double {
        var t = detail.speed.last?.t ?? 0
        for list in detail.stances.values { if let e = list.last?.end, e.isFinite { t = max(t, e) } }
        return t.isFinite ? max(0, t) : 0
    }

    private var start: Double {
        guard follow, let now = currentTime, now.isFinite else { return windowStart.finiteOr(0) }
        return max(0, min(now - windowLength / 2, max(0, lastTime - windowLength)))
    }

    private var bars: [FootfallBar] {
        let a = start, b = start + windowLength
        var out: [FootfallBar] = []
        for paw in Kp.paws {
            for iv in detail.stances[paw.code] ?? [] where iv.start.isFinite && iv.end.isFinite && iv.end > a && iv.start < b {
                out.append(FootfallBar(id: out.count, paw: paw, start: max(iv.start, a), end: min(iv.end, b)))
            }
        }
        return out
    }

    private var nowMarker: Double? {
        guard let now = currentTime, now.isFinite else { return nil }
        if follow { return now }
        return now >= start && now <= start + windowLength ? now : nil
    }

    var body: some View {
        let last = lastTime
        Card {
            CardHeader(title: L("Footfall pattern", "足落模式"), symbol: "chart.bar.doc.horizontal",
                       subtitle: L("Bars = paw on the ground (stance); gaps = swing.", "色条 = 爪着地（支撑相）；空隙 = 摆动相。")) {
                Picker(L("Window", "时间窗"), selection: $windowLength) {
                    Text(L("1 s", "1 秒")).tag(1.0)
                    Text(L("2 s", "2 秒")).tag(2.0)
                    Text(L("5 s", "5 秒")).tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help(L("Length of the time window shown", "显示的时间窗长度"))
            }
            FootfallChart(bars: bars, start: start, length: windowLength, now: nowMarker)
            if !follow && last > windowLength {
                Slider(value: $windowStart, in: 0...max(0.1, last - windowLength))
                    .controlSize(.small)
                    .accessibilityLabel(L("Time window", "时间窗"))
                    .help(L("Move the time window", "移动时间窗"))
            }
        }
    }
}

@MainActor
private struct FootfallChart: View {
    let bars: [FootfallBar]
    let start: Double
    let length: Double
    let now: Double?

    var body: some View {
        let a = start.finiteOr(0)
        let b = a + ResultsChartMath.top(length, fallback: 2)
        Chart {
            ForEach(bars) { bar in
                BarMark(xStart: .value("t", bar.start), xEnd: .value("t", bar.end),
                        y: .value("paw", bar.paw.code), height: .ratio(0.62))
                    .foregroundStyle(KeypointColors.color(bar.paw))
                    .cornerRadius(3)
            }
            if let now, now.isFinite {
                RuleMark(x: .value("now", now)).foregroundStyle(Color.primary.opacity(0.45))
            }
        }
        .chartXScale(domain: a...b)
        .chartYScale(domain: ["LF", "RF", "LH", "RH"])
        .chartXAxisLabel(L("Time (s)", "时间（秒）"))
        .frame(height: 150)
    }
}

@MainActor
struct GaitPatternCard: View {
    let patterns: [PatternShare]

    private func color(_ key: String) -> Color {
        switch key {
        case "walk": return KeypointColors.color(.lf)
        case "trot": return KeypointColors.color(.lh)
        case "gallop": return KeypointColors.color(.nose)
        default: return KeypointColors.color(.rf)
        }
    }

    var body: some View {
        let total = max(1, patterns.map(\.count).reduce(0, +))
        Card {
            CardHeader(L("Gait pattern", "步态模式"), symbol: "figure.walk.motion",
                       subtitle: L("Each hind stride, classified from interlimb phase (after Bellardita & Kiehn 2015).",
                                   "按每个后肢步幅的肢间相位分类（参考 Bellardita & Kiehn 2015）。"))
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(patterns) { p in
                        if p.count > 0 {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(p.key))
                                .frame(width: max(4, geo.size.width * CGFloat(p.count) / CGFloat(total) - 3))
                        }
                    }
                }
            }
            .frame(height: 20)
            .accessibilityHidden(true)
            HStack(spacing: 18) {
                ForEach(patterns) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(color(p.key)).frame(width: 8, height: 8)
                            Text(p.label.text).font(.callout).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.0f%%", Double(p.count) / Double(total) * 100))
                            .font(.headline).monospacedDigit().textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

@MainActor
struct PawTableCard: View {
    let detail: GaitDetail

    var body: some View {
        Card {
            CardHeader(L("Per paw", "各爪参数"), symbol: "tablecells")
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("n")
                    Text(L("Stride", "步幅") + " " + detail.unit)
                    Text(L("Stance", "支撑") + " s")
                    Text(L("Swing", "摆动") + " s")
                    Text(L("Duty", "占空比"))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(detail.paws, id: \.paw) { GaitPawRow(p: $0) }
            }
            .textSelection(.enabled)
        }
    }
}

@MainActor
private struct GaitPawRow: View {
    let p: PawSummary

    var body: some View {
        GridRow {
            HStack(spacing: 6) {
                Circle().fill(KeypointColors.color(p.paw)).frame(width: 9, height: 9)
                Text(p.paw.code).font(.callout.weight(.semibold))
            }
            Text("\(p.strides)")
            Text(Fmt.num(p.strideLength, 2))
            Text(Fmt.num(p.stance, 3))
            Text(Fmt.num(p.swing, 3))
            Text(Fmt.percent(p.duty))
        }
        .font(.callout.monospacedDigit())
    }
}

@MainActor
struct PhaseCard: View {
    let detail: GaitDetail

    var body: some View {
        Card {
            CardHeader(L("Interlimb coordination", "肢间协调"), symbol: "circle.dotted",
                       subtitle: L("0.5 = alternating, 0 / 1 = together. Distance from the center = consistency (R).",
                                   "0.5 = 交替，0/1 = 同步。离圆心越远，一致性（R）越高。"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(detail.phases, id: \.key) { GaitPhaseDial(phase: $0) }
            }
        }
    }
}

@MainActor
struct FootprintCard: View {
    let detail: GaitDetail
    let videoSize: CGSize

    var body: some View {
        Card {
            CardHeader(L("Footprints", "足印分布"), symbol: "pawprint",
                       subtitle: L("Where each paw was planted, in the video frame.", "每次着地的爪位置（视频画面坐标）。"))
            GaitFootprintChart(prints: detail.footprints, videoSize: videoSize)
                .frame(maxHeight: 360)
            HStack(spacing: 14) {
                ForEach(Kp.paws) { p in
                    HStack(spacing: 4) {
                        Circle().fill(KeypointColors.color(p)).frame(width: 8, height: 8)
                        Text(p.code).font(.caption)
                    }
                }
            }
        }
    }
}

@MainActor
private struct GaitFootprintChart: View {
    let prints: [Footprint]
    let videoSize: CGSize

    private var w: Double { max(1, Double(videoSize.width).finiteOr(1)) }
    private var h: Double { max(1, Double(videoSize.height).finiteOr(1)) }

    // Canvas rather than Swift Charts: a long gait video has thousands of footprints.
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / w, sy = size.height / h
            let r: CGFloat = 2.4
            var paths: [Kp: Path] = [:]
            for p in prints where p.x.isFinite && p.y.isFinite {
                let c = CGPoint(x: p.x * sx, y: p.y * sy)
                paths[p.paw, default: Path()].addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
            for paw in Kp.paws { if let path = paths[paw] { ctx.fill(path, with: .color(KeypointColors.color(paw))) } }
        }
        .aspectRatio(CGFloat(w / h), contentMode: .fit)
        .padding(6)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(String(format: L("%d footprints", "%d 个足印"), prints.count))
    }
}

@MainActor
private struct GaitPhaseDial: View {
    let phase: PhaseSummary

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in draw(ctx, size) }
                .frame(width: 86, height: 86)
            Text(phase.label.text).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            Text(phase.mean.map { String(format: "%.2f · R %.2f", $0, phase.r ?? 0) } ?? "—")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = min(size.width, size.height) / 2 - 6
        func point(_ cycle: Double, _ radius: CGFloat) -> CGPoint {
            let a = 2 * Double.pi * cycle - Double.pi / 2
            return CGPoint(x: c.x + radius * CGFloat(Foundation.cos(a)), y: c.y + radius * CGFloat(Foundation.sin(a)))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(Color.secondary.opacity(0.35)), lineWidth: 1)
        for frac in [0.0, 0.25, 0.5, 0.75] {
            var p = Path()
            p.move(to: point(frac, 0.85 * r))
            p.addLine(to: point(frac, r))
            ctx.stroke(p, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)
        }
        for v in phase.values.suffix(200) where v.isFinite {
            let pt = point(v, r)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                     with: .color(Color.accentColor.opacity(0.35)))
        }
        guard let m = phase.mean, let R = phase.r, m.isFinite, R.isFinite else { return }
        let pt = point(m, CGFloat(min(1, max(0, R))) * r)
        var line = Path(); line.move(to: c); line.addLine(to: pt)
        ctx.stroke(line, with: .color(Color.accentColor), lineWidth: 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(Color.accentColor))
    }
}
