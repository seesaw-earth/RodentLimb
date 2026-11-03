// AnalysisReviewTab.swift — the Review tab: the video with live keypoints and the analysis'
// overlay (ReviewOverlay) on the left, the events behind the numbers on the right (HSplitView).
// Under the video, a resizable strip shows the one chart that helps checking (motion for tail
// suspension, wall-contact counts for the cylinder, the footfall window following playback for
// gait, the ethogram for behavior assays). Also builds the event list of every assay.
//
// Smoothness: the player view observes its controller; everything else observes only the coarse
// ResultsPlaybackClock (≈ 5 Hz), fed here from the controller's time.

import SwiftUI
import Combine

@MainActor
struct AnalysisReviewTab: View {
    let session: Session
    let result: AnalysisResult
    let track: PoseTrack?
    let controller: PlayerController?
    let clock: ResultsPlaybackClock
    /// The pose file exists but could not be read.
    let poseUnreadable: Bool
    let relabel: (Set<Int>, String) -> Void
    let restore: (Set<Int>) -> Void

    @Environment(AppModel.self) private var app

    /// Side by side needs about 720 points (video ≥ 420 + events ≥ 280); the list moves under the
    /// video below 720 and comes back beside it from 800 (a gap, so a width near the limit — or the
    /// inspector sliding in — never flips the layout back and forth).
    private static let stackBelow: CGFloat = 720
    private static let sideBySideFrom: CGFloat = 800

    /// Starts stacked: the stacked layout has no minimum width, so the first pass can never ask for
    /// more room than the window has; it changes to side by side as soon as the width is known.
    @State private var wide = false
    @State private var decided = false
    /// The pending layout change. A plain object, not view state: it is replaced on every frame of a
    /// resize, and must not rebuild the page (and its event list) each time.
    @State private var layoutChange = PendingChange()

    var body: some View {
        Group {
            if wide {
                HSplitView {
                    playerPane(compact: false)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    eventList
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 560, maxHeight: .infinity)
                }
            } else {
                // Narrow: video above the events; the chart strip is left out to keep both usable.
                VSplitView {
                    playerPane(compact: true)
                        .frame(minHeight: 200, maxHeight: .infinity)
                    eventList
                        .frame(minHeight: 140, idealHeight: 240, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Measures only; the layout is chosen on a later turn of the run loop, never during the
            // layout pass that measured it (switching recreates the split view and the video layer).
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size.width, initial: true) { _, w in chooseLayout(for: w) }
            }
        }
        .onDisappear { layoutChange.task?.cancel() }
    }

    private func chooseLayout(for width: CGFloat) {
        guard width > 0 else { return }
        let next = wide ? width >= Self.stackBelow : width >= Self.sideBySideFrom
        layoutChange.task?.cancel()
        guard next != wide || !decided else { return }
        // Stacking (the side-by-side minimum no longer fits) and the first decision come on the next
        // turn; going side by side again waits until the width has settled (resizing, the inspector
        // sliding in).
        let delay: UInt64 = (decided && next) ? 250_000_000 : 0
        layoutChange.task = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) } else { await Task.yield() }
            guard !Task.isCancelled else { return }
            decided = true
            if wide != next { wide = next }
        }
    }

    private var eventList: some View {
        AnalysisEventList(model: AnalysisEventModel.make(session: session, result: result), clock: clock,
                          controller: controller, relabel: relabel, restore: restore)
    }

    @ViewBuilder
    private func playerPane(compact: Bool) -> some View {
        if let c = controller, let t = track, compact {
            ReviewPlayer(controller: c, track: t, threshold: session.params.common.keypointThreshold,
                         decorations: ReviewOverlay.decorations(session: session, result: result))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(c.$time.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)) { clock.set($0) }
                .onAppear { clock.set(c.time) }
        } else if let c = controller, let t = track {
            VSplitView {
                ReviewPlayer(controller: c, track: t, threshold: session.params.common.keypointThreshold,
                             decorations: ReviewOverlay.decorations(session: session, result: result))
                    .padding(12)
                    .frame(minHeight: 260, maxHeight: .infinity)
                    .onReceive(c.$time.throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)) { clock.set($0) }
                    .onAppear { clock.set(c.time) }
                ScrollView {
                    companion(c)
                        .padding(12)
                }
                .frame(minHeight: 110, idealHeight: companionHeight, maxHeight: 520)
            }
        } else if poseUnreadable {
            VStack(spacing: 12) {
                EmptyState(title: L("Pose data could not be read", "无法读取姿态数据"),
                           message: L("The tracking file of this video is damaged or missing. Run tracking again from the video's page.",
                                      "该视频的识别文件已损坏或丢失。请在视频页面重新运行识别。"),
                           symbol: "exclamationmark.triangle")
                if let rid = session.recordingID {
                    Button(L("Re-run Tracking", "重新识别")) { app.rerunTracking([rid]) }
                        .padding(.bottom, 30)
                }
            }
        } else {
            ProgressView(L("Loading video and pose…", "正在加载视频和姿态…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var companionHeight: CGFloat {
        // Kept inside the frame's 110…520 range (ideal outside min…max is a contradictory frame).
        if let d = result.behavior { return min(520, CGFloat(max(2, d.tracks.count)) * 28 + 140) }
        if result.gait != nil { return 250 }
        if result.tst != nil { return 250 }
        return 160
    }

    @ViewBuilder
    private func companion(_ c: PlayerController) -> some View {
        if let d = result.tst {
            TSTMotionCard(detail: d, clock: clock, height: 150) { c.seek($0) }
        }
        if let d = result.cylinder {
            CylinderUseCard(detail: d)
        }
        if let d = result.gait {
            ResultsClockReader(clock: clock) { t in
                FootfallCard(detail: d, currentTime: t, follow: true)
            }
        }
        if let d = result.behavior {
            BehaviorEthogramCard(detail: d, clock: clock) { c.seek($0) }
        }
    }
}

// MARK: - Event lists of each assay

extension AnalysisEventModel {
    static func make(session s: Session, result r: AnalysisResult) -> AnalysisEventModel {
        if let d = r.cylinder { return cylinder(d) }
        if let d = r.behavior { return behavior(d) }
        if let d = r.tst { return tst(d) }
        if let d = r.gait { return gait(d) }
        return AnalysisEventModel(title: L("Events", "事件"), items: [], filters: [], choices: [], leadIn: 0,
                                emptyText: L("This analysis has no events to review.", "该分析没有可复核的事件。"))
    }

    /// Drops repeated ids (ForEach and selection need unique ids).
    private static func unique(_ items: [AnalysisEventItem]) -> [AnalysisEventItem] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }

    static func cylinder(_ d: CylinderDetail) -> AnalysisEventModel {
        let digits: [PawLabel: Int] = [.left: 1, .right: 2, .both: 3, .ignore: 0]
        let choices = PawLabel.allCases.map { l in
            AnalysisEventChoice(key: l.rawValue, title: l.name, color: Palette.label(l), digit: digits[l])
        }
        let items = d.events.filter { $0.onset.isFinite }.map { e -> AnalysisEventItem in
            var parts = [String(format: L("Rear %d", "第 %d 次竖立"), e.rear)]
            if e.offset.isFinite && e.offset > e.onset { parts.append(String(format: L("%.2f s", "%.2f 秒"), e.offset - e.onset)) }
            if e.edited { parts.append(L("edited", "已修改")) }
            if !e.counted && e.label != .ignore { parts.append(L("over limit", "超出上限")) }
            return AnalysisEventItem(id: e.id, onset: e.onset, offset: e.offset.finiteOr(e.onset), time: Fmt.clockPrecise(e.onset),
                              detail: parts.joined(separator: " · "), label: e.label.rawValue, labelText: e.label.name,
                              color: Palette.label(e.label), counted: e.counted || e.label == .ignore, edited: e.edited)
        }
        return AnalysisEventModel(title: L("Wall contacts", "触壁"), items: unique(items), filters: choices, choices: choices, leadIn: 0.5,
                                emptyText: L("No contacts yet. Check the calibration and parameters.", "尚未检测到触壁，请检查标定和参数。"))
    }

    static func behavior(_ d: BehaviorDetail) -> AnalysisEventModel {
        let ignore = EventClass.ignore.key
        let classes = d.classes.filter { $0.key != ignore }
        var choices = classes.enumerated().map { i, c in
            AnalysisEventChoice(key: c.key, title: c.label.text, color: Palette.event(c.color), digit: i < 9 ? i + 1 : nil)
        }
        choices.append(AnalysisEventChoice(key: ignore, title: EventClass.ignore.label.text, color: Palette.gray, digit: 0))
        let items = d.events.filter { $0.onset.isFinite }.map { e -> AnalysisEventItem in
            let cls = d.eventClass(e.label)
            let ignored = e.label == ignore
            var time = Fmt.clockPrecise(e.onset)
            if d.origin > 0 {
                let rel = e.onset - d.origin
                time += "  (" + (rel < 0 ? "−" : "+") + Fmt.clock(abs(rel)) + ")"
            }
            var parts = [String(format: L("%.1f s", "%.1f 秒"), max(0, e.duration.finiteOr(0)))]
            if let info = e.info, !info.isEmpty { parts.append(info) }
            if e.edited { parts.append(L("edited", "已修改")) }
            if !e.counted && !ignored {
                parts.append(e.onset < d.window.start ? L("before the window", "在分析窗口之前") : L("outside the window", "在分析窗口之外"))
            }
            return AnalysisEventItem(id: e.id, onset: e.onset, offset: e.offset.finiteOr(e.onset), time: time,
                              detail: parts.joined(separator: " · "), label: e.label,
                              labelText: ignored ? L("Ignored", "已忽略") : cls.label.text,
                              color: ignored ? Palette.gray : Palette.event(cls.color),
                              counted: e.counted || ignored, edited: e.edited)
        }
        return AnalysisEventModel(title: L("Events", "事件"), items: unique(items), filters: choices, choices: choices, leadIn: 1.0,
                                emptyText: L("No events. If the behavior is visible in the video, check the parameters and the pose coverage.",
                                             "没有事件。如果视频里能看到该行为，请检查参数和姿态覆盖率。"))
    }

    /// Tail suspension: immobility bouts and tail climbing (read only).
    static func tst(_ d: TSTDetail) -> AnalysisEventModel {
        let immobile = AnalysisEventChoice(key: "immobile", title: L("Immobile", "不动"), color: Palette.purple, digit: nil)
        let climbing = AnalysisEventChoice(key: "climbing", title: L("Climbing", "爬尾"), color: Palette.orange, digit: nil)
        var raw: [(Interval, Bool)] = d.bouts.map { ($0, false) } + d.climbing.map { ($0, true) }
        raw = raw.filter { $0.0.start.isFinite && $0.0.end.isFinite }
        raw.sort { $0.0.start < $1.0.start }
        var items: [AnalysisEventItem] = []
        for (i, x) in raw.enumerated() {
            let c = x.1 ? climbing : immobile
            let inside = x.0.end > d.window.start && x.0.start < d.window.end
            var detail = String(format: L("%.1f s", "%.1f 秒"), max(0, x.0.duration))
            if !inside { detail += " · " + L("outside the window", "在分析窗口之外") }
            items.append(AnalysisEventItem(id: i, onset: x.0.start, offset: x.0.end, time: Fmt.clockPrecise(x.0.start), detail: detail,
                                    label: c.key, labelText: c.title, color: c.color, counted: inside, edited: false))
        }
        return AnalysisEventModel(title: L("Immobility & climbing", "不动与爬尾"), items: items, filters: [immobile, climbing], choices: [],
                                leadIn: 0.5, emptyText: L("No immobility bouts were found.", "未发现不动片段。"))
    }

    /// Gait: every stride used in the measures (read only).
    static func gait(_ d: GaitDetail) -> AnalysisEventModel {
        let filters = Kp.paws.map { AnalysisEventChoice(key: $0.code, title: $0.label.text, color: KeypointColors.color($0), digit: nil) }
        let strides = d.strides.filter { $0.start.isFinite && $0.end.isFinite }.sorted { $0.start < $1.start }
        var items: [AnalysisEventItem] = []
        for (i, s) in strides.enumerated() {
            let detail = String(format: L("stance %.2f s · swing %.2f s · %@ %@", "支撑 %.2f 秒 · 摆动 %.2f 秒 · %@ %@"),
                                s.stance.finiteOr(0), s.swing.finiteOr(0), Fmt.num(s.length, 2), d.unit)
            items.append(AnalysisEventItem(id: i, onset: s.start, offset: s.end, time: Fmt.clockPrecise(s.start), detail: detail,
                                    label: s.paw.code, labelText: s.paw.code, color: KeypointColors.color(s.paw), counted: true, edited: false))
        }
        return AnalysisEventModel(title: L("Strides", "步幅"), items: items, filters: filters, choices: [], leadIn: 0.2,
                                emptyText: L("No strides were found. The mouse may not walk fast or straight enough; check the parameters.",
                                             "未发现步幅。小鼠可能走得不够快或不够直，请检查参数。"))
    }
}

/// A task that a view replaces often (a debounced layout change), kept outside of view state.
@MainActor
final class PendingChange {
    var task: Task<Void, Never>?
}
