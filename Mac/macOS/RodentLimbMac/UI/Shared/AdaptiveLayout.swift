// AdaptiveLayout.swift — layout that fits the Mac it runs on, so every button stays reachable:
//
//  • WindowSizing — the main window's default size from the screen (never larger than it), and a
//    minimum that fits the smallest Mac screens (13-inch at "Larger Text": 1024 × 640 points usable).
//  • .sheetFrame(…) — sheets on macOS hang from the window's title bar and cannot be moved: a sheet
//    taller than the space below that point puts its buttons off screen. Every sheet asks for its
//    usual size, but never more than the space between the window's toolbar and the bottom of the
//    screen (and never wider than the screen around the window). Sheet bodies scroll; their buttons
//    sit in a footer outside the scrolling part.
//    The space is measured outside of layout (when the window moves or resizes, on the next turn of
//    the run loop) and cached: reading AppKit window geometry while SwiftUI lays out a view can
//    make AppKit lay the window out again, and again — "more Update Constraints in Window passes
//    than there are views in the window" (an exception that ends the app).
//  • AdaptiveColumns — two columns side by side when there is room, stacked when the page is narrow
//    (a page never clips its side column or its buttons at a small window size).
//  • FlowLayout — a row of items that wraps onto more lines instead of running off the edge.
//  • .pageFrame() — every page, pushed page and inspector fills the space it is given and reports no
//    minimum size of its own. Without it, the minimum of whatever is inside (a long text that wraps,
//    a row of buttons) becomes a minimum of the window: when that minimum is larger than the window
//    or changes while AppKit lays the window out, AppKit lays the window out again and again
//    (the "Update Constraints in Window" exception). A page that needs more space scrolls instead.

import SwiftUI
import AppKit

// MARK: - Window and screen space

@MainActor
enum WindowSizing {
    /// Smallest main window: sidebar (210) + a usable page (≈ 650); fits a 1024 × 640 screen.
    static let minWidth: CGFloat = 860
    static let minHeight: CGFloat = 560

    /// Usable part of the main screen (menu bar and Dock excluded).
    static var screen: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 760)
    }

    /// The first window: 1440 × 900 on a large screen, otherwise the screen less a margin.
    static var defaultSize: CGSize {
        let s = screen.size
        return CGSize(width: max(minWidth, min(1440, s.width - 40)),
                      height: max(minHeight, min(900, s.height - 30)))
    }

    /// Space a sheet of the main window can use (cached; see `refreshSheetSpace`). Never read
    /// AppKit geometry here: this is called from view bodies.
    /// Starts conservative (fits a 1280 × 800 screen below a window's toolbar) until the first
    /// measurement, which happens as soon as the main window appears.
    private(set) static var sheetSpace = CGSize(width: 1000, height: 600)

    /// Measures the space a sheet can use — from below the window's toolbar to the bottom of the
    /// screen, and as wide as the screen allows around the window's centre (a sheet is centred on
    /// its window and cannot move). Call it outside of layout only: it is scheduled on the next turn
    /// of the run loop by `scheduleSheetSpaceRefresh()`.
    private static func refreshSheetSpace() {
        let candidates = [NSApp.mainWindow, NSApp.keyWindow].compactMap { $0 }
        guard let w = candidates.map({ $0.sheetParent ?? $0 }).first(where: { $0.isVisible }) else {
            let s = screen.size
            sheetSpace = CGSize(width: max(360, s.width - 40), height: max(300, s.height - 60))
            return
        }
        let visible = (w.screen ?? NSScreen.main)?.visibleFrame ?? screen
        // Top of the content area: the window's top less the title bar and toolbar (frame minus
        // content rect, computed from stored frames only — no layout is triggered).
        let chrome = max(0, w.frame.height - w.contentRect(forFrameRect: w.frame).height)
        let contentTop = w.frame.maxY - max(chrome, 52)
        let height = contentTop - visible.minY - 12
        let centre = w.frame.midX
        let half = min(centre - visible.minX, visible.maxX - centre) - 12
        let space = CGSize(width: max(360, (half * 2).rounded()), height: max(300, height.rounded()))
        if space != sheetSpace { sheetSpace = space }
    }

    private static var refreshScheduled = false

    /// Measures the sheet space on the next turn of the run loop (never during layout), at most once
    /// per turn however often it is asked.
    static func scheduleSheetSpaceRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async {
            refreshScheduled = false
            refreshSheetSpace()
        }
    }
}

/// Sizes a sheet: its usual (ideal) size, capped by the space available (see WindowSizing).
@MainActor
private struct SheetFrame: ViewModifier {
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat?
    let minHeight: CGFloat
    let idealHeight: CGFloat
    let maxHeight: CGFloat?

    func body(content: Content) -> some View {
        // The cached value: no AppKit geometry is read while SwiftUI lays out the sheet.
        let space = WindowSizing.sheetSpace
        let w = space.width, h = space.height
        content.frame(minWidth: min(minWidth, w), idealWidth: min(idealWidth, w), maxWidth: min(maxWidth ?? idealWidth, w),
                      minHeight: min(minHeight, h), idealHeight: min(idealHeight, h), maxHeight: min(maxHeight ?? idealHeight, h))
    }
}

extension View {
    /// A page (or a pushed page, or an inspector) fills the space it is given and does not pass the
    /// minimum size of its content on to the window (see the note at the top of this file).
    func pageFrame(alignment: Alignment = .center) -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: alignment)
    }

    /// The size of a sheet: `ideal` when there is room, down to `min` on a small screen or window
    /// (the content scrolls), and never beyond the screen. `max` nil = the sheet does not grow.
    func sheetFrame(minWidth: CGFloat, idealWidth: CGFloat, maxWidth: CGFloat? = nil,
                    minHeight: CGFloat, idealHeight: CGFloat, maxHeight: CGFloat? = nil) -> some View {
        modifier(SheetFrame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                            minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight))
    }
}

// MARK: - Two columns that stack when narrow

/// Two subviews: side by side when the width is at least `threshold`, otherwise the second below
/// the first, both at full width.
struct AdaptiveColumns: Layout {
    enum Side {
        /// The second column has this width.
        case fixed(CGFloat)
        /// The second column takes its ideal width.
        case ideal
        /// Both columns share the width equally.
        case half
    }

    var side: Side
    var threshold: CGFloat
    var spacing: CGFloat = 16

    private func widths(_ total: CGFloat, _ subviews: Subviews) -> (CGFloat, CGFloat) {
        switch side {
        case .fixed(let w):
            return (max(0, total - w - spacing), w)
        case .ideal:
            let w = min(subviews[1].sizeThatFits(.unspecified).width, total * 0.6)
            return (max(0, total - w - spacing), w)
        case .half:
            let w = max(0, (total - spacing) / 2)
            return (w, w)
        }
    }

    private func sideBySide(_ width: CGFloat?) -> Bool {
        guard let width, width.isFinite, width > 1 else { return true }
        return width >= threshold
    }

    /// Ideal size side by side (unspecified and infinite proposals).
    private func idealSize(_ subviews: Subviews) -> CGSize {
        let a = subviews[0].sizeThatFits(.unspecified), b = subviews[1].sizeThatFits(.unspecified)
        return CGSize(width: a.width + spacing + b.width, height: max(a.height, b.height))
    }

    /// Minimum size (a zero proposal — how SwiftUI and AppKit ask for a minimum): as narrow as the
    /// narrower arrangement allows, and as tall as the two columns stacked at their usual height.
    /// Never the height of text wrapped at width 0 (a huge minimum the window could not satisfy).
    private func minimumSize(_ subviews: Subviews) -> CGSize {
        let a = subviews[0].sizeThatFits(.zero), b = subviews[1].sizeThatFits(.zero)
        let ia = subviews[0].sizeThatFits(.unspecified), ib = subviews[1].sizeThatFits(.unspecified)
        return CGSize(width: max(a.width, b.width), height: ia.height + spacing + ib.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }
        guard let total = proposal.width, total.isFinite else { return idealSize(subviews) }
        guard total > 1 else { return minimumSize(subviews) }
        if sideBySide(total) {
            let (a, b) = widths(total, subviews)
            let ha = subviews[0].sizeThatFits(ProposedViewSize(width: a, height: proposal.height)).height
            let hb = subviews[1].sizeThatFits(ProposedViewSize(width: b, height: proposal.height)).height
            return CGSize(width: total, height: max(ha, hb))
        }
        let ha = subviews[0].sizeThatFits(ProposedViewSize(width: total, height: nil)).height
        let hb = subviews[1].sizeThatFits(ProposedViewSize(width: total, height: nil)).height
        return CGSize(width: total, height: ha + spacing + hb)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
            return
        }
        if sideBySide(bounds.width) || bounds.width < 1 {
            let (a, b) = widths(bounds.width, subviews)
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: a, height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY),
                              proposal: ProposedViewSize(width: b, height: bounds.height))
        } else {
            let ha = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: ha))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + ha + spacing),
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

// MARK: - Wrapping row

/// Items in a row that continue on the next line when the width runs out.
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
        // Zero width (a minimum-size query): the widest item on one line. Never every item stacked
        // at width 0 — that minimum height would be forced on the window.
        if let w = proposal.width, w <= 1 {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
        }
        // Unspecified or infinite width: one line (its ideal size).
        let usable = proposal.width.map { $0.isFinite && $0 > 1 } ?? false
        let width = usable ? proposal.width! : .greatestFiniteMagnitude
        let lines = rows(width, subviews)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (n, line) in lines.enumerated() {
            let h = line.map(\.1.height).max() ?? 0
            height += h + (n > 0 ? lineSpacing : 0)
            let w = line.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, line.count - 1))
            widest = max(widest, w)
        }
        return CGSize(width: usable ? proposal.width! : widest, height: height)
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

// MARK: - Height-capped section

/// Content at its natural height, or — when it is taller than `maxHeight` — scrolling within that
/// height (a section never pushes the rest of the page out of the window).
///
/// The content is measured (outside of its own layout) and the scroll view takes that height up to
/// the cap. The same view stays on screen whatever the height: no switching between a plain and a
/// scrolling version while the content changes (a progress card updating every fraction of a
/// second would otherwise rebuild the section, or flip between the two, several times a second).
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .background {
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.height.rounded(.up), initial: true) { _, h in
                            if abs(h - contentHeight) >= 1 { contentHeight = h }
                        }
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
        .frame(maxHeight: maxHeight)
    }
}
