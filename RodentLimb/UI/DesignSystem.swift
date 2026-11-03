// DesignSystem.swift — palette, components and helpers shared with the RodentPose / RodentFlow
// family: system grouped surfaces, 20-pt cards, one blue accent for interactive elements,
// Okabe–Ito colors for data. Left limbs are always blue and right limbs always orange, in video
// overlays, charts and tables, so laterality reads at a glance (also for color-vision deficiency).
//
// 1.4: no decorative icons (TASK_FIRST_SPEC §4). Status is short coloured text or a small dot, a
// paradigm is a text chip; glyphs remain only for playback controls, the tab bar and the "+" button.

import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    // Okabe–Ito (Wong 2011).
    static let blue = Color(uiColor: UIColor(hex: 0x0072B2))
    static let sky = Color(uiColor: UIColor(hex: 0x56B4E9))
    static let vermillion = Color(uiColor: UIColor(hex: 0xD55E00))
    static let orange = Color(uiColor: UIColor(hex: 0xE69F00))
    static let green = Color(uiColor: UIColor(hex: 0x009E73))
    static let purple = Color(uiColor: UIColor(hex: 0xCC79A7))
    static let yellow = Color(uiColor: UIColor(hex: 0xF0E442))
    static let gray = Color(uiColor: .systemGray)

    /// Laterality colors for text and marks (AA on cards in both appearances).
    static let left = adaptive(0x1767B8, 0x6CB4FF)
    static let right = adaptive(0xC42B3B, 0xFF7C88)
    static let both = adaptive(0x0B7480, 0x3CC3CD)

    // Status — always paired with words.
    static let success = adaptive(0x0A7A44, 0x3DD27F)
    static let warning = adaptive(0xA65700, 0xFFB547)
    static let danger = adaptive(0xD12E2E, 0xFF6E6E)

    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let hairline = Color(uiColor: .separator)

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

    /// Color of a behavior event class (hex from the analyzer). Very dark classes get a light
    /// variant in Dark Mode so they stay visible on cards.
    static func event(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luma < 0.2 ? adaptive(hex, 0xE0E0E0) : Color(uiColor: UIColor(hex: hex))
    }

    /// Deep fill of a paradigm (primary buttons in its screens).
    static func assayFill(_ a: Assay) -> Color {
        switch a {
        case .tailSuspension: return Color(uiColor: UIColor(hex: 0x7C4DDB))
        case .cylinder: return Color(uiColor: UIColor(hex: 0x0B7480))
        case .gait: return Color(uiColor: UIColor(hex: 0xAB4F08))
        case .itch: return Color(uiColor: UIColor(hex: 0xB0306A))
        case .pain: return Color(uiColor: UIColor(hex: 0xC62828))
        case .grooming: return Color(uiColor: UIColor(hex: 0x2E7D32))
        case .seizure: return Color(uiColor: UIColor(hex: 0x3949AB))
        }
    }

    /// Group colours in design order (Okabe–Ito, Wong 2011): blue, orange, bluish green, reddish
    /// purple, sky blue, vermillion, yellow, black (white in Dark Mode).
    static let groupHex: [UInt32] = [0x0072B2, 0xE69F00, 0x009E73, 0xCC79A7, 0x56B4E9, 0xD55E00, 0xF0E442, 0x000000]
    static func group(_ i: Int) -> Color {
        let hex = groupHex[((i % groupHex.count) + groupHex.count) % groupHex.count]
        return hex == 0x000000 ? adaptive(0x000000, 0xFFFFFF) : Color(uiColor: UIColor(hex: hex))
    }

    static func label(_ l: PawLabel) -> Color {
        switch l {
        case .left: return left
        case .right: return right
        case .both: return both
        case .ignore: return gray
        }
    }
}

enum KeypointColors {
    /// Matches the app icon: left fore blue, right fore red, left hind green, right hind
    /// violet, pink tail. Fore/hind and left/right pairs differ in both hue and lightness.
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
    static func ui(_ k: Kp) -> UIColor { UIColor(hex: hex(k)) }
    static func color(_ k: Kp) -> Color { Color(uiColor: ui(k)) }
}

enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
    static var snappy: Animation? { reduced ? nil : .snappy }
    static var gentle: Animation? { reduced ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86) }
}

enum Fmt {
    static func clock(_ s: Double) -> String {
        guard s.isFinite else { return "—" }
        let v = max(0, Int(s.rounded()))
        if v >= 3600 { return String(format: "%d:%02d:%02d", v / 3600, (v / 60) % 60, v % 60) }
        return String(format: "%d:%02d", v / 60, v % 60)
    }
    static func clockPrecise(_ s: Double) -> String {
        guard s.isFinite else { return "—" }
        let m = Int(max(0, s) / 60)
        return String(format: "%d:%05.2f", m, max(0, s) - Double(m) * 60)
    }
    static func num(_ v: Double?, _ d: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.\(d)f", v)
    }
    static func date(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Lang.isChinese ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")))
    }
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
    static func remaining(_ s: Double?) -> String {
        guard let s, s.isFinite else { return L("Estimating…", "估算中…") }
        if s < 60 { return String(format: L("about %d s left", "约剩 %d 秒"), max(1, Int(s))) }
        return String(format: L("about %d min left", "约剩 %d 分钟"), Int((s / 60).rounded()))
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.trailing = EmptyView()
    }
}

/// A paradigm as text on a tinted chip ("Gait analysis"; `short` = the code, e.g. GAIT).
@MainActor
struct AssayChip: View {
    let assay: Assay
    var short = false
    var body: some View {
        Text(short ? assay.code : assay.name.text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(Palette.assay(assay))
            .background(Palette.assay(assay).opacity(0.12), in: Capsule())
            .accessibilityLabel(assay.name.text)
    }
}

@MainActor
struct Tag: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

@MainActor
struct InfoRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit().textSelection(.enabled)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct Banner: View {
    let text: String
    var level: NoteLevel = .info

    var body: some View {
        Text(text)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .font(.subheadline)
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Capsule().fill(Self.color(level)).frame(width: 3).padding(.vertical, 10).padding(.leading, 5)
                    .accessibilityHidden(true)
            }
            .background(Self.color(level).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    static func color(_ l: NoteLevel) -> Color {
        switch l {
        case .info: return .accentColor
        case .warning: return Palette.warning
        case .error: return Palette.danger
        }
    }
}

/// Several notes collapse into one expandable card, most severe first.
@MainActor
struct NoteList: View {
    let notes: [Note]
    @State private var expanded = false

    private var sorted: [Note] {
        notes.sorted { rank($0.level) > rank($1.level) }
    }
    private func rank(_ l: NoteLevel) -> Int { l == .error ? 2 : l == .warning ? 1 : 0 }

    var body: some View {
        if notes.count == 1 {
            Banner(text: notes[0].text.text, level: notes[0].level)
        } else if notes.count > 1 {
            let top = sorted[0].level
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(Motion.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Banner.color(top)).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(String(format: L("%d notes", "%d 条提示"), notes.count)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Spacer()
                        Text(expanded ? L("Show fewer", "收起") : L("Show all", "全部显示")).font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(expanded ? sorted : Array(sorted.prefix(1))) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Banner.color(n.level)).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            .accessibilityHidden(true)
                        Text(n.text.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !expanded {
                    Text(String(format: L("%d more", "还有 %d 条"), notes.count - 1)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Banner.color(top).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Metrics

@MainActor
struct MetricTile: View {
    let metric: Metric
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.label.text)
                .font(.footnote)
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
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if metric.highlight {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct MetricGrid: View {
    let metrics: [Metric]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(metrics) { MetricTile(metric: $0) }
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View { PrimaryBody(configuration: configuration, color: color) }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(isEnabled ? color.opacity(configuration.isPressed ? 0.82 : 1) : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { SecondaryBody(configuration: configuration) }

    private struct SecondaryBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isEnabled ? Color.accentColor.opacity(configuration.isPressed ? 0.18 : 0.11) : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

@MainActor
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 8
    var color: Color = .accentColor
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
    }
}

// MARK: - Inputs

/// Labeled slider with live value and unit; the value text is tappable for VoiceOver.
@MainActor
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var unit: String = ""
    var decimals: Int = 2
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.\(decimals)f", value) + (unit.isEmpty ? "" : " \(unit)"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.\(decimals)f \(unit)", value))
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit = ""
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline)
            Spacer(minLength: 6)
            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
                .focused($focused)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(.secondary) }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, t in
            let s = t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            if let v = Double(s), v.isFinite, v != value { value = v }
        }
        .onChange(of: value) { _, v in if !focused { text = Self.format(v) } }
    }

    static func format(_ v: Double) -> String {
        abs(v - v.rounded()) < 1e-9 ? String(format: "%.0f", v) : String(format: "%g", v)
    }
}

// MARK: - Brand

@MainActor
struct AppMark: View {
    var size: CGFloat = 52
    var body: some View {
        Image("BrandMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Layout & sharing

func aspectFitRect(_ content: CGSize, in container: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let s = min(container.width / content.width, container.height / content.height)
    let w = content.width * s, h = content.height * s
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

extension View {
    func screenContent() -> some View {
        self.frame(maxWidth: 760, alignment: .leading).padding(.horizontal, 16).frame(maxWidth: .infinity)
    }

    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var shown: String?
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let shown {
                    Text(shown)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 60)
                        .transition(Motion.reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.success, trigger: generation)
            .onChange(of: message) { _, new in
                guard let new else { return }
                generation += 1
                let mine = generation
                withAnimation(Motion.gentle) { shown = new }
                AccessibilityNotification.Announcement(new).post()
                message = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    if mine == generation { withAnimation(Motion.gentle) { shown = nil } }
                }
            }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Bars and primary actions

extension View {
    /// A bar pinned to the top or bottom edge. On iOS 26 it uses the system scroll-edge effect
    /// (Liquid Glass) instead of a custom background, as Apple's adoption guide recommends;
    /// earlier systems get the standard bar material.
    @ViewBuilder
    func chromeBar<Bar: View>(_ edge: VerticalEdge, @ViewBuilder bar: () -> Bar) -> some View {
        let content = bar()
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: edge, spacing: 0) { content }
        } else {
            self.safeAreaInset(edge: edge, spacing: 0) { content.frame(maxWidth: .infinity).background(.bar) }
        }
        #else
        self.safeAreaInset(edge: edge, spacing: 0) { content.frame(maxWidth: .infinity).background(.bar) }
        #endif
    }

    /// The single most important action on a screen: Liquid Glass prominent button on iOS 26,
    /// the filled style elsewhere.
    @ViewBuilder
    func primaryAction(_ color: Color = .accentColor) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(color).controlSize(.large)
        } else {
            self.buttonStyle(PrimaryButtonStyle(color: color))
        }
        #else
        self.buttonStyle(PrimaryButtonStyle(color: color))
        #endif
    }

    /// Tab bar recedes while scrolling on iOS 26.
    @ViewBuilder
    func minimizingTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { self.tabBarMinimizeBehavior(.onScrollDown) } else { self }
        #else
        self
        #endif
    }
}

/// Up to four headline numbers, large and calm: the first thing a result screen shows.
struct HeroMetrics: View {
    let metrics: [Metric]
    var tint: Color = .accentColor

    var body: some View {
        let shown = Array(metrics.prefix(4))
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(shown) { m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.label.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(m.formatted)
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        if !m.unit.isEmpty && m.value != nil {
                            Text(m.unit).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            Capsule().fill(tint).frame(width: 28, height: 4).padding(.leading, 18).padding(.top, 8)
                .accessibilityHidden(true)
        }
    }
}

/// All measures as a quiet grouped list (label · value unit), one card per section.
struct MeasureList: View {
    let metrics: [Metric]

    private var sections: [(String, [Metric])] {
        var order: [String] = []
        var map: [String: (LText?, [Metric])] = [:]
        for m in metrics {
            let key = m.group?.en ?? "_other"
            if map[key] == nil { order.append(key); map[key] = (m.group, []) }
            map[key]!.1.append(m)
        }
        return order.map { k in (map[k]!.0?.text ?? L("Other", "其他"), map[k]!.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            let all = sections
            ForEach(all.indices, id: \.self) { idx in
                let title = all[idx].0, items = all[idx].1
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, m in
                            HStack(alignment: .firstTextBaseline) {
                                Text(m.label.text).font(.subheadline)
                                Spacer(minLength: 12)
                                Text(m.formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
                                if !m.unit.isEmpty && m.value != nil {
                                    Text(m.unit).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .accessibilityElement(children: .combine)
                            if i < items.count - 1 { Divider().padding(.leading, 14) }
                        }
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }
}

/// Closes the keyboard from anywhere (decimal pads have no return key).
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// A text field that saves on Return, when it loses focus and when the screen closes — never only
/// when a Save button is pressed — so a typed value is not lost.
@MainActor
struct CommitTextField: View {
    let title: String
    let value: String
    var axis: Axis = .horizontal
    let commit: (String) -> Void
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, axis: axis)
            .lineLimit(axis == .vertical ? 1...6 : 1...1)
            .focused($focused)
            .onAppear { if !loaded { text = value; loaded = true } }
            .onSubmit(save)
            .onChange(of: focused) { _, f in if !f { save() } }
            .onChange(of: value) { _, v in if !focused { text = v } }
            .onDisappear(perform: save)
    }

    private func save() {
        guard loaded, text != value else { return }
        commit(text)
    }
}


// MARK: - Wrapping row

/// Items in a row that continue on the next line when the width runs out (counts, chips), so
/// nothing is truncated or pushed off a narrow iPhone or by large text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [[(Int, CGSize)]] {
        var out: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                out.append([])
                x = 0
            }
            out[out.count - 1].append((i, size))
            x += size.width + spacing
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (n, line) in rows(width, subviews).enumerated() {
            height += (line.map(\.1.height).max() ?? 0) + (n > 0 ? lineSpacing : 0)
            widest = max(widest, line.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, line.count - 1)))
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in rows(bounds.width, subviews) {
            let h = line.map(\.1.height).max() ?? 0
            var x = bounds.minX
            for (i, size) in line {
                subviews[i].place(at: CGPoint(x: x, y: y + (h - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += h + lineSpacing
        }
    }
}
