// DesignSystem.swift — the RodentLimb look on the Mac: same names and colors as the iPhone app
// (Okabe–Ito data colors, left limbs blue / right limbs red, one blue accent), with Mac sizes —
// denser cards, 12-pt corners, standard control heights — and native materials. The result cards
// ported from the iPhone (Results/) use these components unchanged.

import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    // Okabe–Ito (Wong 2011).
    static let blue = Color(hex: 0x0072B2)
    static let sky = Color(hex: 0x56B4E9)
    static let vermillion = Color(hex: 0xD55E00)
    static let orange = Color(hex: 0xE69F00)
    static let green = Color(hex: 0x009E73)
    static let purple = Color(hex: 0xCC79A7)
    static let yellow = Color(hex: 0xF0E442)
    static let gray = Color(nsColor: .systemGray)

    /// Laterality colors for text and marks.
    static let left = adaptive(0x1767B8, 0x6CB4FF)
    static let right = adaptive(0xC42B3B, 0xFF7C88)
    static let both = adaptive(0x0B7480, 0x3CC3CD)

    // Status — always paired with an icon and words.
    static let success = adaptive(0x0A7A44, 0x3DD27F)
    static let warning = adaptive(0xA65700, 0xFFB547)
    static let danger = adaptive(0xD12E2E, 0xFF6E6E)

    /// Card surface on the window background.
    static let card = Color(nsColor: .controlBackgroundColor)
    /// Inset surface inside a card.
    static let inset = adaptive(0xF2F2F5, 0x2A2A2E)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)

    /// Assay identity colors (same family as RodentPose categories).
    static func assay(_ a: Assay) -> Color {
        switch a {
        case .tailSuspension: return adaptive(0x7C4DDB, 0xB593FF)
        case .cylinder: return adaptive(0x0B7480, 0x3CC3CD)
        case .gait: return adaptive(0xAB4F08, 0xF2A04E)
        case .itch: return adaptive(0xB0306A, 0xFF79B0)
        case .pain: return adaptive(0xC62828, 0xFF7A7A)
        case .grooming: return adaptive(0x2E7D32, 0x66BB6A)
        case .seizure: return adaptive(0x3949AB, 0x8C9EFF)
        }
    }

    /// Color of a behavior event class (hex from the analyzer); very dark classes get a light
    /// variant in Dark Mode.
    static func event(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luma < 0.2 ? adaptive(hex, 0xE0E0E0) : Color(hex: hex)
    }

    /// Deep fill for badges carrying white symbols.
    static func assayFill(_ a: Assay) -> Color {
        switch a {
        case .tailSuspension: return Color(hex: 0x7C4DDB)
        case .cylinder: return Color(hex: 0x0B7480)
        case .gait: return Color(hex: 0xAB4F08)
        case .itch: return Color(hex: 0xB0306A)
        case .pain: return Color(hex: 0xC62828)
        case .grooming: return Color(hex: 0x2E7D32)
        case .seizure: return Color(hex: 0x3949AB)
        }
    }

    static func label(_ l: PawLabel) -> Color {
        switch l {
        case .left: return left
        case .right: return right
        case .both: return both
        case .ignore: return gray
        }
    }

    static func qc(_ v: QCVerdict) -> Color {
        switch v {
        case .pass: return success
        case .warn: return warning
        case .fail: return danger
        }
    }

    static func decision(_ d: InclusionDecision) -> Color {
        switch d {
        case .pending: return warning
        case .included: return success
        case .excluded: return gray
        }
    }

    /// The icon's sky-to-cobalt gradient (used once per screen at most).
    static let brandGradient = LinearGradient(colors: [Color(hex: 0x7FE6F6), Color(hex: 0x3D9BF7), Color(hex: 0x1F5BEF)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Colours of groups in charts: the Okabe–Ito colour-blind-safe palette, in an order that keeps
/// neighbouring groups distinct (yellow last: weak on white).
enum GroupPalette {
    static let colors: [Color] = [
        Color(hex: 0x0072B2), Color(hex: 0xE69F00), Color(hex: 0x009E73), Color(hex: 0xCC79A7),
        Color(hex: 0x56B4E9), Color(hex: 0xD55E00), Palette.adaptive(0x444444, 0xBBBBBB), Color(hex: 0xF0E442),
    ]

    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

enum KeypointColors {
    /// Matches the app icon: left fore blue, right fore red, left hind green, right hind violet,
    /// pink tail.
    static func hex(_ k: Kp) -> UInt32 {
        switch k {
        case .lf: return 0x1E7FD8
        case .rf: return 0xE5404F
        case .lh: return 0x12A05A
        case .rh: return 0x8A4FE0
        case .tail: return 0xE58FA6
        case .nose: return 0xF2A500
        case .mouth: return 0x5FC3E8
        }
    }
    static func ns(_ k: Kp) -> NSColor { NSColor(hex: hex(k)) }
    static func cg(_ k: Kp) -> CGColor { NSColor(hex: hex(k)).cgColor }
    static func color(_ k: Kp) -> Color { Color(hex: hex(k)) }
}

enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var snappy: Animation? { reduced ? nil : .snappy(duration: 0.25) }
    static var gentle: Animation? { reduced ? .easeInOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86) }
}

enum Fmt {
    static func clock(_ s: Double) -> String {
        guard s.isFinite else { return "—" }
        let v = max(0, Int(safe: s.rounded()))
        if v >= 3600 { return String(format: "%d:%02d:%02d", v / 3600, (v / 60) % 60, v % 60) }
        return String(format: "%d:%02d", v / 60, v % 60)
    }
    static func clockPrecise(_ s: Double) -> String {
        guard s.isFinite else { return "—" }
        let m = Int(safe: max(0, s) / 60)
        return String(format: "%d:%05.2f", m, max(0, s) - Double(m) * 60)
    }
    static func num(_ v: Double?, _ d: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.\(d)f", v)
    }
    static func percent(_ v: Double?, _ d: Int = 0) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.\(d)f%%", v * 100)
    }
    static func date(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Lang.isChinese ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")))
    }
    static func day(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Lang.isChinese ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")))
    }
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static func remaining(_ s: Double?) -> String {
        guard let s, s.isFinite else { return L("Estimating…", "估算中…") }
        if s < 60 { return String(format: L("about %d s left", "约剩 %d 秒"), max(1, Int(safe: s))) }
        if s < 5400 { return String(format: L("about %d min left", "约剩 %d 分钟"), Int(safe: (s / 60).rounded())) }
        return String(format: L("about %.1f h left", "约剩 %.1f 小时"), s / 3600)
    }
    static func fps(_ v: Double?) -> String {
        guard let v, v.isFinite, v > 0 else { return "—" }
        return v >= 100 ? String(format: "%.0f fps", v) : String(format: "%.1f fps", v)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5) }
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    /// `symbol` is accepted for older call sites and not drawn: headers are text only.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil, subtitle: String? = nil) {
        self.title = title; self.symbol = symbol; self.subtitle = subtitle; self.trailing = EmptyView()
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.link)
            }
        }
    }
}

/// A small coloured square (kept for older call sites; no pictogram).
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.opacity(0.9))
            .frame(width: size * 0.4, height: size * 0.4)
            .accessibilityHidden(true)
    }
}

/// The paradigm as text: its short code on a tinted chip ("GAIT", "CYL").
struct AssayBadge: View {
    let assay: Assay
    var size: CGFloat = 28
    var body: some View {
        Text(assay.code)
            .font(.system(size: max(9, size * 0.36), weight: .bold).monospaced())
            .foregroundStyle(Palette.assay(assay))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.assay(assay).opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(assay.name.text)
    }
}

/// Short coloured text on a tinted capsule. `symbol` is accepted for older call sites and not drawn.
struct Tag: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?
    var body: some View {
        Text(text).lineLimit(1)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
    }
}

struct InfoRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

struct Banner: View {
    let text: String
    var level: NoteLevel = .info

    var body: some View {
        // Wraps at the width it is given. No fixedSize: asked for its minimum at width 0, a banner
        // would answer with the height of its text one word per line — a minimum height that can
        // travel up to the window. The colour bar is an overlay (as tall as the text), not a
        // stretchable sibling that would make the banner grow into the free space of the page.
        Text(text).foregroundStyle(.primary).lineLimit(nil).textSelection(.enabled)
            .padding(.leading, 13)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(Self.color(level)).frame(width: 3)
            }
            .layoutPriority(1)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.color(level).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Self.color(level).opacity(0.25), lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }

    static func icon(_ l: NoteLevel) -> String {
        switch l {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    static func color(_ l: NoteLevel) -> Color {
        switch l {
        case .info: return .accentColor
        case .warning: return Palette.warning
        case .error: return Palette.danger
        }
    }
}

/// Several notes collapse into one expandable box, most severe first.
struct NoteList: View {
    let notes: [Note]
    @State private var expanded = false

    private var sorted: [Note] { notes.sorted { rank($0.level) > rank($1.level) } }
    private func rank(_ l: NoteLevel) -> Int { l == .error ? 2 : l == .warning ? 1 : 0 }

    var body: some View {
        if notes.count == 1 {
            Banner(text: notes[0].text.text, level: notes[0].level)
        } else if notes.count > 1 {
            let top = sorted[0].level
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(Motion.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Banner.color(top)).frame(width: 7, height: 7)
                        Text(String(format: L("%d notes", "%d 条提示"), notes.count)).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(expanded ? sorted : Array(sorted.prefix(1))) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Banner.color(n.level)).frame(width: 6, height: 6)
                        Text(n.text.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                if !expanded {
                    Text(String(format: L("%d more", "还有 %d 条"), notes.count - 1)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Banner.color(top).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Banner.color(top).opacity(0.25), lineWidth: 1) }
        }
    }
}

// MARK: - Metrics

struct MetricTile: View {
    let metric: Metric
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.formatted)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if !metric.unit.isEmpty && metric.value != nil {
                    Text(metric.unit).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .padding(10)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if metric.highlight {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

struct MetricGrid: View {
    let metrics: [Metric]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(metrics) { MetricTile(metric: $0) }
        }
    }
}

/// Up to four headline numbers, large and calm: the first thing a result shows.
struct HeroMetrics: View {
    let metrics: [Metric]
    var tint: Color = .accentColor

    var body: some View {
        let shown = Array(metrics.prefix(4))
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Divider().padding(.vertical, 4) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.label.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(m.formatted)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        if !m.unit.isEmpty && m.value != nil {
                            Text(m.unit).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5) }
        .overlay(alignment: .topLeading) {
            Capsule().fill(tint).frame(width: 28, height: 3).padding(.leading, 14).padding(.top, 6)
                .accessibilityHidden(true)
        }
    }
}

/// All measures as a quiet grouped list (label · value unit), one box per section.
struct MeasureList: View {
    let metrics: [Metric]

    private var sections: [(String, [Metric])] {
        var order: [String] = []
        var map: [String: (LText?, [Metric])] = [:]
        for m in metrics {
            let key = m.group?.en ?? "_other"
            if map[key] == nil { order.append(key); map[key] = (m.group, []) }
            map[key]?.1.append(m)
        }
        return order.compactMap { k in map[k].map { ($0.0?.text ?? L("Other", "其他"), $0.1) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let all = sections
            ForEach(all.indices, id: \.self) { idx in
                let title = all[idx].0, items = all[idx].1
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                            HStack(alignment: .firstTextBaseline) {
                                Text(m.label.text).font(.callout)
                                Spacer(minLength: 12)
                                Text(m.formatted).font(.callout.weight(.semibold)).monospacedDigit()
                                if !m.unit.isEmpty && m.value != nil {
                                    Text(m.unit).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .textSelection(.enabled)
                            .accessibilityElement(children: .combine)
                            if i < items.count - 1 { Divider().padding(.leading, 12) }
                        }
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5) }
                }
            }
        }
    }
}

// MARK: - Progress, status

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 4
    var color: Color = .accentColor
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction.finiteOr(0))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // No animation: progress arrives several times a second, and an animated shape is
                // redrawn on every display frame — with a few cards on screen, a busy main thread.
        }
    }
}

/// Status of a recording in lists: tracking state, QC verdict and inclusion decision in one tag.
struct RecordingStatusTag: View {
    let recording: Recording
    var missing = false

    var body: some View {
        let s = Self.describe(recording, missing: missing)
        Tag(text: s.text, color: s.color, symbol: s.symbol)
            .help(recording.failure ?? s.text)
    }

    static func describe(_ r: Recording, missing: Bool) -> (text: String, color: Color, symbol: String) {
        if missing && r.status != .ready { return (L("Video offline", "视频离线"), Palette.warning, "externaldrive.badge.exclamationmark") }
        switch r.status {
        case .queued: return (L("Queued", "排队中"), .secondary, "clock")
        case .processing: return (L("Tracking", "识别中"), .accentColor, "waveform.path.ecg")
        case .failed: return (L("Failed", "失败"), Palette.danger, "exclamationmark.triangle.fill")
        case .ready:
            switch r.decision {
            case .included: return (L("Included", "已纳入"), Palette.success, "checkmark.circle.fill")
            case .excluded: return (L("Excluded", "已排除"), Palette.gray, "minus.circle.fill")
            case .pending:
                if let v = r.qc?.verdict { return (v == .fail ? L("QC failed", "QC 未通过") : L("Needs review", "待复核"), Palette.qc(v), v.symbol) }
                return (L("Checking", "检查中"), .secondary, "hourglass")
            }
        }
    }
}

struct QCBadge: View {
    let report: QCReport?
    var body: some View {
        if let q = report {
            Tag(text: q.verdict.label.text, color: Palette.qc(q.verdict), symbol: q.verdict.symbol)
                .help(String(format: L("Mouse tracked in %.0f%% of frames; longest loss %.1f s", "小鼠可用帧 %.0f%%；最长丢失 %.1f 秒"),
                             q.coreCoverage * 100, q.longestLost))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Inputs

/// Labeled slider with live value and unit.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var unit: String = ""
    var decimals: Int = 2
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.\(decimals)f", value) + (unit.isEmpty ? "" : " \(unit)"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.\(decimals)f \(unit)", value))
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(help ?? title)
    }
}

/// A number typed on the keyboard (commits on Return or when focus leaves).
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit = ""
    var width: CGFloat = 80

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 6)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...4)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
                .textFieldStyle(.roundedBorder)
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
        }
        .font(.callout)
    }
}

// MARK: - Brand

/// RodentLimb mark (the app icon artwork).
struct AppMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image("BrandMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Empty state: a title and one or two sentences. `symbol` is accepted for older call sites and
/// not drawn (no decorative pictograms).
struct EmptyState: View {
    let title: String
    let message: String
    var symbol: String?
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

// MARK: - Layout helpers

func aspectFitRect(_ content: CGSize, in container: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let s = min(container.width / content.width, container.height / content.height)
    let w = content.width * s, h = content.height * s
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

extension View {
    /// Readable width for document-like pages (results, studies) in a wide window.
    func pageContent(maxWidth: CGFloat = 1100) -> some View {
        self.frame(maxWidth: maxWidth, alignment: .leading).padding(.horizontal, 20).frame(maxWidth: .infinity)
    }

    /// The most important action of a page: Liquid Glass prominent on macOS 26+, the standard
    /// prominent button elsewhere.
    @ViewBuilder
    func primaryAction() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        }
        #else
        self.buttonStyle(.borderedProminent).controlSize(.large)
        #endif
    }

    func toast(_ message: Binding<String?>, action: Binding<ToastAction?> = .constant(nil)) -> some View {
        modifier(ToastModifier(message: message, action: action))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @Binding var action: ToastAction?
    @State private var shown: String?
    @State private var shownAction: ToastAction?
    @State private var generation = 0
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let shown {
                    HStack(spacing: 10) {
                        Text(shown)
                            .font(.callout.weight(.semibold))
                        if let a = shownAction {
                            Button(a.title) {
                                a.run()
                                withAnimation(Motion.gentle) { self.shown = nil; shownAction = nil }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(.bottom, 14)
                    .onHover { hovering = $0 }
                    .transition(Motion.reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                }
            }
            .onChange(of: message, initial: true) { _, new in
                guard let new else { return }
                generation += 1
                let mine = generation
                let act = action
                withAnimation(Motion.gentle) { shown = new; shownAction = act }
                message = nil
                action = nil
                Task { @MainActor in
                    // Longer when there is a button to press; never while the pointer is on it.
                    try? await Task.sleep(nanoseconds: act == nil ? 2_200_000_000 : 7_000_000_000)
                    while hovering && mine == generation { try? await Task.sleep(nanoseconds: 500_000_000) }
                    if mine == generation { withAnimation(Motion.gentle) { shown = nil; shownAction = nil } }
                }
            }
    }
}
