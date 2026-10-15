// ResultSections.swift — result cards. Each card is a small view with one job, so the session
// screen can place them per tab (Summary / Review / Measures) and the Swift type checker stays
// fast.

import SwiftUI
import Charts

// MARK: - Tail suspension

@MainActor
struct TSTMotionCard: View {
    let detail: TSTDetail
    let seek: (Double) -> Void

    private var ymax: Double { max(detail.threshold * 4, min(3, detail.motion.map(\.v).max() ?? 1)) }

    var body: some View {
        Card {
            CardHeader(L("Motion over time", "运动随时间变化"), symbol: "waveform.path",
                       subtitle: L("Shaded = immobile · dashed line = threshold. Tap the chart to jump to that moment.",
                                   "阴影 = 不动，虚线 = 阈值。轻点图表可跳到该时刻。"))
            chart
        }
    }

    private var chart: some View {
        let top = ymax
        return Chart {
            RectangleMark(xStart: .value("t", detail.window.start), xEnd: .value("t", detail.window.end),
                          yStart: .value("v", 0), yEnd: .value("v", top))
                .foregroundStyle(Color.accentColor.opacity(0.05))
            ForEach(Array(detail.bouts.enumerated()), id: \.offset) { item in
                RectangleMark(xStart: .value("t", item.element.start), xEnd: .value("t", item.element.end),
                              yStart: .value("v", 0), yEnd: .value("v", top))
                    .foregroundStyle(Palette.assay(.tailSuspension).opacity(0.22))
            }
            ForEach(Array(detail.motion.enumerated()), id: \.offset) { item in
                LineMark(x: .value("t", item.element.t), y: .value("v", min(item.element.v, top)))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            RuleMark(y: .value("thr", detail.threshold))
                .foregroundStyle(Palette.right)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0...top)
        .chartXAxisLabel(L("Time (s)", "时间（秒）"))
        .chartYAxisLabel(L("BL/s", "体长/秒"))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard let plot = proxy.plotFrame else { return }
                        let x = loc.x - geo[plot].origin.x
                        if let t: Double = proxy.value(atX: x) { seek(max(0, t)) }
                    }
            }
        }
        .frame(height: 190)
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
                    BarMark(x: .value("min", "\(item.offset + 1)"), y: .value("s", item.element))
                        .foregroundStyle(inWindow(item.offset) ? Palette.assay(.tailSuspension) : Palette.gray.opacity(0.4))
                        .cornerRadius(5)
                }
            }
            .chartYScale(domain: 0...60)
            .chartXAxisLabel(L("Minute", "分钟"))
            .chartYAxisLabel(L("s", "秒"))
            .frame(height: 160)
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
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.label(rows[i].0))
                                .frame(width: max(4, geo.size.width * CGFloat(rows[i].1) / CGFloat(total) - 3))
                        }
                    }
                }
            }
            .frame(height: 26)
            .accessibilityHidden(true)
            HStack(spacing: 18) {
                ForEach(rows.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(Palette.label(rows[i].0)).frame(width: 8, height: 8)
                            Text(rows[i].0.name).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("\(rows[i].1)").font(.title3.weight(.semibold)).monospacedDigit()
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
    var body: some View {
        Card {
            CardHeader(L("Contacts over time", "触壁时间分布"), symbol: "timeline.selection")
            Chart {
                ForEach(detail.events) { e in
                    PointMark(x: .value("t", e.onset), y: .value("paw", e.label.name))
                        .foregroundStyle(e.counted ? Palette.label(e.label) : Palette.gray.opacity(0.4))
                        .symbolSize(e.edited ? 90 : 50)
                }
            }
            .chartXAxisLabel(L("Time (s)", "时间（秒）"))
            .frame(height: 130)
        }
    }
}

@MainActor
struct CylinderEventList: View {
    let detail: CylinderDetail
    let currentTime: Double
    let seek: (Double) -> Void
    let relabel: (Int, PawLabel?) -> Void

    @State private var filter: PawLabel?
    @State private var showAll = false

    private var list: [CylinderEvent] { detail.events.filter { filter == nil || $0.label == filter } }

    var body: some View {
        Card {
            CardHeader(L("Check each contact", "逐个复核触壁"), symbol: "checklist",
                       subtitle: L("Tap a row to play it. Fix the label if the automatic call is wrong — edits are kept.",
                                   "轻点行即可播放该片段；如自动判断有误，可修改标签，修改会保留。"))
            Picker(L("Filter", "筛选"), selection: $filter) {
                Text(L("All", "全部")).tag(PawLabel?.none)
                ForEach(PawLabel.allCases) { Text($0.short).tag(PawLabel?.some($0)) }
            }
            .pickerStyle(.segmented)
            if list.isEmpty {
                Text(L("No contacts yet. Check the calibration and parameters.", "尚未检测到触壁，请检查标定和参数。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(showAll ? list : Array(list.prefix(10))) { e in
                    EventRow(event: e, active: currentTime >= e.onset - 0.05 && currentTime <= e.offset,
                             seek: seek, relabel: relabel)
                }
            }
            if list.count > 10 {
                Button(showAll ? L("Show fewer", "收起") : String(format: L("Show all %d", "显示全部 %d 条"), list.count)) {
                    withAnimation(Motion.snappy) { showAll.toggle() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }
}

@MainActor
private struct EventRow: View {
    let event: CylinderEvent
    let active: Bool
    let seek: (Double) -> Void
    let relabel: (Int, PawLabel?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { seek(max(0, event.onset - 0.5)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: active ? "waveform.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.label(event.label))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Fmt.clockPrecise(event.onset)).font(.subheadline.monospacedDigit().weight(.medium))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                ForEach(PawLabel.allCases) { l in
                    Button { relabel(event.id, l == event.auto ? nil : l) } label: {
                        if l == event.label { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                    }
                }
            } label: {
                Text(event.label.short)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(event.label == .ignore ? Color.secondary : Color.white)
                    .frame(minWidth: 54, minHeight: 32)
                    .background(event.label == .ignore ? Palette.inset : Palette.label(event.label), in: Capsule())
            }
            .accessibilityLabel(String(format: L("Label: %@. Change", "标签：%@，更改"), event.label.name))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(event.counted || event.label == .ignore ? 1 : 0.55)
    }

    private var subtitle: String {
        var parts = [String(format: L("Rear %d", "第 %d 次竖立"), event.rear)]
        if event.edited { parts.append(L("edited", "已修改")) }
        if !event.counted && event.label != .ignore { parts.append(L("over limit", "超出上限")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Gait

struct FootfallBar: Identifiable {
    let id: Int
    let paw: Kp
    let start: Double
    let end: Double
}

@MainActor
struct FootfallCard: View {
    let detail: GaitDetail
    let currentTime: Double
    var follow = false

    @State private var windowStart: Double = 0
    private let windowLength = 2.0
    private var lastTime: Double { detail.speed.last?.t ?? 0 }

    /// While following the video, the window tracks playback.
    private var start: Double {
        guard follow else { return windowStart }
        return max(0, min(currentTime - windowLength / 2, max(0, lastTime - windowLength)))
    }

    private var bars: [FootfallBar] {
        let a = start, b = start + windowLength
        var out: [FootfallBar] = []
        for paw in Kp.paws {
            for iv in detail.stances[paw.code] ?? [] where iv.end > a && iv.start < b {
                out.append(FootfallBar(id: out.count, paw: paw, start: max(iv.start, a), end: min(iv.end, b)))
            }
        }
        return out
    }

    private var nowMarker: Double? {
        if follow { return currentTime }
        return currentTime >= start && currentTime <= start + windowLength ? currentTime : nil
    }

    var body: some View {
        Card {
            CardHeader(L("Footfall pattern", "足落模式"), symbol: "chart.bar.doc.horizontal",
                       subtitle: L("Bars = paw on the ground (stance); gaps = swing.", "色条 = 爪着地（支撑相）；空隙 = 摆动相。"))
            FootfallChart(bars: bars, start: start, length: windowLength, now: nowMarker)
            if !follow && lastTime > windowLength {
                Slider(value: $windowStart, in: 0...max(0, lastTime - windowLength))
                    .accessibilityLabel(L("Time window", "时间窗"))
            }
        }
    }
}

@MainActor
struct FootfallChart: View {
    let bars: [FootfallBar]
    let start: Double
    let length: Double
    let now: Double?

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(xStart: .value("t", bar.start), xEnd: .value("t", bar.end),
                        y: .value("paw", bar.paw.code), height: .ratio(0.62))
                    .foregroundStyle(KeypointColors.color(bar.paw))
                    .cornerRadius(4)
            }
            if let now {
                RuleMark(x: .value("now", now)).foregroundStyle(Color.primary.opacity(0.45))
            }
        }
        .chartXScale(domain: start...(start + length))
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
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color(p.key))
                                .frame(width: max(4, geo.size.width * CGFloat(p.count) / CGFloat(total) - 3))
                        }
                    }
                }
            }
            .frame(height: 22)
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                ForEach(patterns) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(color(p.key)).frame(width: 8, height: 8)
                            Text(p.label.text).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.0f%%", Double(p.count) / Double(total) * 100))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
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
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                header
                Divider()
                ForEach(detail.paws, id: \.paw) { PawRow(p: $0) }
            }
        }
    }

    private var header: some View {
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
    }
}

@MainActor
struct PawRow: View {
    let p: PawSummary

    var body: some View {
        GridRow {
            HStack(spacing: 6) {
                Circle().fill(KeypointColors.color(p.paw)).frame(width: 9, height: 9)
                Text(p.paw.code).font(.subheadline.weight(.semibold))
            }
            Text("\(p.strides)")
            Text(Fmt.num(p.strideLength, 2))
            Text(Fmt.num(p.stance, 3))
            Text(Fmt.num(p.swing, 3))
            Text(dutyText)
        }
        .font(.subheadline.monospacedDigit())
    }

    private var dutyText: String {
        guard let d = p.duty else { return "—" }
        return String(format: "%.0f%%", d * 100)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(detail.phases, id: \.key) { PhaseDial(phase: $0) }
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
            FootprintChart(prints: detail.footprints, videoSize: videoSize)
            PawLegend()
        }
    }
}

@MainActor
struct FootprintChart: View {
    let prints: [Footprint]
    let videoSize: CGSize

    private var w: Double { Double(max(1, videoSize.width)) }
    private var h: Double { Double(max(1, videoSize.height)) }

    var body: some View {
        Chart {
            ForEach(Array(prints.enumerated()), id: \.offset) { item in
                PointMark(x: .value("x", item.element.x), y: .value("y", -item.element.y))
                    .foregroundStyle(KeypointColors.color(item.element.paw))
                    .symbolSize(28)
            }
        }
        .chartXScale(domain: 0.0...w)
        .chartYScale(domain: (-h)...0.0)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .aspectRatio(CGFloat(w / h), contentMode: .fit)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
struct PawLegend: View {
    var body: some View {
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

@MainActor
struct PhaseDial: View {
    let phase: PhaseSummary

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in draw(ctx, size) }
                .frame(width: 92, height: 92)
            Text(phase.label.text).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            Text(phase.mean.map { String(format: "%.2f · R %.2f", $0, phase.r ?? 0) } ?? "—")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = min(size.width, size.height) / 2 - 6
        func point(_ cycle: Double, _ radius: CGFloat) -> CGPoint {
            let a = CGFloat(2 * Double.pi * cycle - Double.pi / 2)
            return CGPoint(x: c.x + radius * CGFloat(Foundation.cos(Double(a))),
                           y: c.y + radius * CGFloat(Foundation.sin(Double(a))))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(Color.secondary.opacity(0.35)), lineWidth: 1)
        for frac in [0.0, 0.25, 0.5, 0.75] {
            var p = Path()
            p.move(to: point(frac, 0.85 * r))
            p.addLine(to: point(frac, r))
            ctx.stroke(p, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)
        }
        for v in phase.values.suffix(200) {
            let pt = point(v, r)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                     with: .color(Color.accentColor.opacity(0.35)))
        }
        guard let m = phase.mean, let R = phase.r else { return }
        let pt = point(m, CGFloat(R) * r)
        var line = Path(); line.move(to: c); line.addLine(to: pt)
        ctx.stroke(line, with: .color(Color.accentColor), lineWidth: 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(Color.accentColor))
    }
}
