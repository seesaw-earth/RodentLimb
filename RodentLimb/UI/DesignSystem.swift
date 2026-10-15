// DesignSystem.swift — palette, components and helpers shared with the RodentPose / RodentFlow
// family: system grouped surfaces, 20-pt cards, one blue accent for interactive elements,
// Okabe–Ito colors for data. Left limbs are always blue and right limbs always orange, in video
// overlays, charts and tables, so laterality reads at a glance (also for color-vision deficiency).

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

    // Status — always paired with an icon and words.
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
        }
    }

    /// Deep fill for badges carrying white symbols.
    static func assayFill(_ a: Assay) -> Color {
        switch a {
        case .tailSuspension: return Color(uiColor: UIColor(hex: 0x7C4DDB))
        case .cylinder: return Color(uiColor: UIColor(hex: 0x0B7480))
        case .gait: return Color(uiColor: UIColor(hex: 0xAB4F08))
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
    var symbol: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
            }
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
    init(_ title: String, symbol: String? = nil, subtitle: String? = nil) {
        self.title = title; self.symbol = symbol; self.subtitle = subtitle; self.trailing = EmptyView()
    }
}

@MainActor
struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
        }
    }
}

@MainActor
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

@MainActor
struct AssayBadge: View {
    let assay: Assay
    var size: CGFloat = 40
    var body: some View { IconBadge(symbol: assay.symbol, color: Palette.assayFill(assay), size: size) }
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
        Label {
            Text(text).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: Self.icon(level)).foregroundStyle(Self.color(level))
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.color(level).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Self.color(level).opacity(0.25), lineWidth: 1) }
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
                        Image(systemName: Banner.icon(top)).foregroundStyle(Banner.color(top))
                        Text(String(format: L("%d notes", "%d 条提示"), notes.count)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(expanded ? sorted : Array(sorted.prefix(1))) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Banner.icon(n.level)).font(.caption).foregroundStyle(Banner.color(n.level))
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
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Banner.color(top).opacity(0.25), lineWidth: 1) }
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

/// Card-sized buttons scale slightly on press.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

/// RodentLimb glyph: a body with four limbs ending in colored paws (left blue, right orange).
@MainActor
struct LimbGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (size.width - s) / 2 + x * s, y: (size.height - s) / 2 + y * s) }
            let body = Path(ellipseIn: CGRect(x: p(0.34, 0.2).x, y: p(0.34, 0.2).y, width: s * 0.32, height: s * 0.56))
            ctx.fill(body, with: .color(.white.opacity(0.22)))
            let joints = [p(0.42, 0.34), p(0.58, 0.34), p(0.42, 0.66), p(0.58, 0.66)]
            let paws = [p(0.2, 0.26), p(0.8, 0.26), p(0.22, 0.8), p(0.78, 0.8)]
            let colors: [Kp] = [.lf, .rf, .lh, .rh]
            for i in 0..<4 {
                var path = Path()
                path.move(to: joints[i]); path.addLine(to: paws[i])
                ctx.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))
            }
            for i in 0..<4 {
                let r = s * 0.075
                let rect = CGRect(x: paws[i].x - r, y: paws[i].y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -s * 0.018, dy: -s * 0.018)), with: .color(.white))
                ctx.fill(Path(ellipseIn: rect), with: .color(KeypointColors.color(colors[i])))
            }
            let nose = p(0.5, 0.14)
            ctx.fill(Path(ellipseIn: CGRect(x: nose.x - s * 0.05, y: nose.y - s * 0.05, width: s * 0.1, height: s * 0.1)), with: .color(KeypointColors.color(.nose)))
        }
        .accessibilityHidden(true)
    }
}

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
                    Label(shown, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.bottom, 12)
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

// MARK: - v1.1 components (simpler, friendlier layout)

extension Palette {
    /// The icon's sky-to-cobalt gradient, used once per screen at most (Home hero).
    static let brandGradient = LinearGradient(
        colors: [Color(uiColor: UIColor(hex: 0x7FE6F6)), Color(uiColor: UIColor(hex: 0x3D9BF7)), Color(uiColor: UIColor(hex: 0x1F5BEF))],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

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

/// Friendly empty state with the mascot.
struct EmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            AppMark(size: 72)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

/// Closes the keyboard from anywhere (decimal pads have no return key).
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
