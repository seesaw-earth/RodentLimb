// ReviewPlayer.swift — video player with live keypoint overlay drawn from the stored pose track
// (no re-rendering needed), frame stepping, playback rate, and assay-specific overlays.

import SwiftUI
import AVFoundation
import QuartzCore

/// Wraps AVPlayer and exposes time on the *pose-track* clock (0 = first decoded frame), so
/// analysis events, charts and the overlay all share one time base.
///  • `time` (published, ≤ 10 Hz while playing) drives the slider and labels; while the user
///    scrubs it follows the finger.
///  • `frameTime` is the track time of the frame actually on screen when paused — it changes
///    only when a seek has *finished*, so the keypoints never run ahead of the picture.
///  • `displayTime()` asks AVPlayerItemVideoOutput which frame is on screen during playback;
///    the overlay reads it every display refresh, so keypoints stay locked to the picture.
/// Scrubbing uses the "chase seek" pattern (Apple Technical Q&A QA1820): only one seek is in
/// flight; while it runs, newer targets replace each other and the latest is sought next.
/// Seeks are only issued once the item is `.readyToPlay`: AVPlayer raises an uncaught
/// NSInvalidArgumentException ("AVPlayerItem cannot service a seek request with a completion
/// handler until its status is AVPlayerItemStatusReadyToPlay") otherwise, which crashed the app
/// when a chart or event was tapped right after opening a session. Earlier targets are kept and
/// sought as soon as the item becomes ready.
@MainActor
final class PlayerController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var time: Double = 0
    @Published private(set) var frameTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isScrubbing = false
    /// The video item can be played and sought.
    @Published private(set) var isReady = false
    /// The video could not be opened (missing or unreadable file).
    @Published private(set) var failed = false
    @Published var rate: Float = 1
    let fps: Double
    /// Video-timeline time of the first frame (track time = player time − offset).
    let offset: Double
    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    /// Removes the periodic time observer when released (no `deinit` needed on this main-actor class).
    private var timeObserver: TimeObserverToken?
    private var statusObservation: NSKeyValueObservation?
    private var seeking = false
    private var pendingTarget: Double?
    private var resumeAfterScrub = false

    init(url: URL, fps: Double, offset: Double) {
        let item = AVPlayerItem(url: url)
        item.add(videoOutput)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.fps = fps.isFinite && fps > 1 ? fps : 30
        self.offset = offset.isFinite ? offset : 0
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.statusChanged(status) }
            }
        }
        addTimeObserver()
    }

    private func addTimeObserver() {
        guard timeObserver == nil else { return }
        let token = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t) }
        }
        timeObserver = TimeObserverToken(player: player, token: token)
    }

    private func statusChanged(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            guard !isReady else { return }
            isReady = true
            failed = false
            // Run the seek that was requested while the item was still loading.
            if pendingTarget != nil && !seeking { seekNext() }
        case .failed:
            isReady = false
            failed = true
            pendingTarget = nil
            seeking = false
            isPlaying = false
        default:
            break
        }
    }

    private func tick(_ t: CMTime) {
        let playing = player.timeControlStatus == .playing
        if playing != isPlaying { isPlaying = playing }
        // While scrubbing or seeking, the slider shows the target, not the player's old time.
        guard !isScrubbing, !seeking, pendingTarget == nil else { return }
        let s = t.seconds
        guard s.isFinite else { return }
        let v = max(0, s - offset)
        if abs(v - time) > 0.0005 { time = v }
        if !playing, abs(v - frameTime) > 0.0005 { frameTime = v }
    }

    /// Track time of the frame currently displayed (playback).
    func displayTime() -> Double {
        let t = videoOutput.itemTime(forHostTime: CACurrentMediaTime()).seconds
        if t.isFinite, t >= 0 { return max(0, t - offset) }
        let c = player.currentTime().seconds
        return c.isFinite ? max(0, c - offset) : frameTime
    }

    /// Stops playback for good (session deleted or tracking re-run). For leaving the screen
    /// temporarily (switching tabs), use `pause()`: the controller is kept and must keep its
    /// time observer, otherwise the clock freezes when the user comes back.
    /// Stops and releases the video now (not whenever the last reference goes away): pending seeks are
    /// cancelled and the item is taken off the player, so its decoder and file are closed at once.
    /// Opening and closing sessions quickly otherwise leaves half-open players decoding the same file.
    func teardown() {
        player.pause()
        isPlaying = false
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        pendingTarget = nil
        seeking = false
        isReady = false
        if let item = player.currentItem {
            item.cancelPendingSeeks()
            if item.outputs.contains(where: { $0 === videoOutput }) { item.remove(videoOutput) }
            item.asset.cancelLoading()
        }
        player.replaceCurrentItem(with: nil)
    }

    func toggle() {
        guard !failed else { return }
        if player.timeControlStatus == .playing {
            pause()
        } else {
            if let d = player.currentItem?.duration.seconds, d.isFinite, time + offset >= d - 0.05 { seek(0) }
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        let c = player.currentTime().seconds
        if c.isFinite { frameTime = max(0, c - offset); time = frameTime }
    }

    func setRate(_ r: Float) {
        rate = r
        if isPlaying { player.rate = r }
    }

    /// Jump to a track time (exact frame).
    func seek(_ t: Double) {
        guard t.isFinite else { return }
        time = max(0, t)
        chase(time)
    }

    func step(_ frames: Int) {
        if isPlaying { pause() }
        // Land in the middle of the target frame so rounding never shows the neighbour.
        let base = pendingTarget ?? time
        let frame = (base * fps).rounded(.down) + Double(frames)
        seek(max(0, (frame + 0.5) / fps))
    }

    // MARK: Scrubbing

    func beginScrub() {
        guard !isScrubbing else { return }
        resumeAfterScrub = player.timeControlStatus == .playing
        if resumeAfterScrub { player.pause(); isPlaying = false }
        isScrubbing = true
    }

    func scrub(to t: Double) {
        guard t.isFinite else { return }
        time = max(0, t)
        chase(time)
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        chase(time)
        if resumeAfterScrub {
            resumeAfterScrub = false
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
    }

    private func chase(_ target: Double) {
        guard !failed else { return }
        pendingTarget = target
        if !seeking { seekNext() }
    }

    private func seekNext() {
        // Not ready yet: keep the target; `statusChanged` seeks to it once the item is ready.
        guard isReady, player.currentItem?.status == .readyToPlay else { seeking = false; return }
        guard let target = pendingTarget else { seeking = false; return }
        pendingTarget = nil
        let seconds = target + offset
        guard seconds.isFinite else { seeking = false; return }
        seeking = true
        let ct = CMTime(seconds: seconds, preferredTimescale: 6000)
        player.seek(to: ct, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let c = self.player.currentTime().seconds
                    if c.isFinite { self.frameTime = max(0, c - self.offset) }
                    self.seeking = false
                    if self.pendingTarget != nil {
                        self.seekNext()
                    } else if !self.isScrubbing {
                        self.time = self.frameTime
                    }
                }
            }
        }
    }
}

/// Owns an AVPlayer periodic time observer and removes it when released.
final class TimeObserverToken {
    private let player: AVPlayer
    private let token: Any
    init(player: AVPlayer, token: Any) {
        self.player = player
        self.token = token
    }
    deinit { player.removeTimeObserver(token) }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: LayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    /// The layer lets go of the player when the view goes away.
    static func dismantleUIView(_ uiView: LayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}

/// Status chip shown on top of the video for the current frame.
struct OverlayChip: Identifiable {
    /// Identified by its text: chips are rebuilt for every frame shown, and a new random id each time
    /// would replace the chip views each time.
    var id: String { text }
    var text: String
    var color: Color
}

@MainActor
struct ReviewPlayer: View {
    @ObservedObject var controller: PlayerController
    let session: Session
    let track: PoseTrack
    let result: AnalysisResult?

    @AppStorage("rl.showSkeleton") private var showSkeleton = true
    @State private var scrubStart: Double?
    @State private var stepTick = 0
    @State private var scrubFrame = 0

    private var videoSize: CGSize { CGSize(width: track.width, height: track.height) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: controller.player)
                GeometryReader { geo in
                    let rect = aspectFitRect(videoSize, in: geo.size)
                    // Redraw on every display refresh while playing, reading the frame actually on
                    // screen; when paused, redraw only when the (seek) time changes.
                    TimelineView(.animation(minimumInterval: nil, paused: !controller.isPlaying)) { _ in
                        let t = controller.isPlaying ? controller.displayTime() : controller.frameTime
                        Canvas { ctx, _ in draw(ctx, rect: rect, time: t) }
                    }
                    .allowsHitTesting(false)
                }
                chips.padding(8)
                if controller.failed {
                    Text(L("This video can't be played. The file may be missing or damaged.",
                           "无法播放该视频，文件可能已丢失或损坏。"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(videoSize.width / max(1, videoSize.height), contentMode: .fit)
            .frame(maxHeight: 460)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { controller.toggle() }
            .simultaneousGesture(videoScrub)
            .overlay(alignment: .bottom) {
                if controller.isScrubbing {
                    Text(Fmt.clockPrecise(controller.time))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
            .accessibilityLabel(L("Video with pose overlay", "带姿态叠加的视频"))
            .accessibilityHint(L("Double-tap to play or pause. Swipe sideways to move frame by frame.", "轻点两下播放或暂停；左右滑动可逐帧移动。"))

            controls
        }
        .sensoryFeedback(.selection, trigger: stepTick)
        .animation(Motion.snappy, value: controller.isScrubbing)
    }

    /// Horizontal swipe on the video: 6 pt per frame, for precise frame-by-frame review.
    private var videoScrub: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { g in
                guard abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
                if scrubStart == nil {
                    controller.beginScrub()
                    scrubStart = controller.time
                }
                let frames = Int((g.translation.width / 6).rounded())
                if frames != scrubFrame { scrubFrame = frames }
                let t = (scrubStart ?? 0) + Double(frames) / controller.fps
                controller.scrub(to: min(max(0, t), track.duration))
            }
            .onEnded { _ in
                if scrubStart != nil { controller.endScrub() }
                scrubStart = nil
                scrubFrame = 0
            }
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, rect: CGRect, time: Double) {
        let sx = rect.width / max(1, videoSize.width), sy = rect.height / max(1, videoSize.height)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy) }

        // Calibration overlays.
        switch session.assay {
        case .cylinder:
            if session.params.cylinder.view == .bottom, let c = session.calibration.circle {
                let center = map(CGPoint(x: c.cx, y: c.cy))
                let r = c.r * sx
                let inner = r * (1 - session.params.cylinder.wallMargin)
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.7)), lineWidth: 1.5)
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner)),
                           with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            } else if session.params.cylinder.view == .side, let f = session.calibration.floorY {
                let y = rect.minY + f * sy
                var p = Path(); p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
                ctx.stroke(p, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        default:
            break
        }

        guard showSkeleton, let i = track.frameIndex(at: time) else { return }
        let thr = session.params.common.keypointThreshold
        let stanceNow = gaitStance(at: time)
        for (a, b) in Kp.bones {
            guard let p = track.point(a, i, threshold: thr), let q = track.point(b, i, threshold: thr) else { continue }
            var path = Path(); path.move(to: map(p)); path.addLine(to: map(q))
            ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 2)
        }
        for k in Kp.allCases {
            guard let p = track.point(k, i, threshold: thr) else { continue }
            let c = map(p)
            let r: CGFloat = stanceNow.contains(k) ? 7.5 : 5
            let rr = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rr), with: .color(KeypointColors.color(k)))
            ctx.stroke(Path(ellipseIn: rr), with: .color(.white), lineWidth: stanceNow.contains(k) ? 2.5 : 1.2)
        }
    }

    private func gaitStance(at t: Double) -> Set<Kp> {
        guard session.assay == .gait, let g = result?.gait else { return [] }
        var out = Set<Kp>()
        for paw in Kp.paws {
            let src = session.params.gait.swapLR ? paw.mirrored : paw
            if (g.stances[paw.code] ?? []).contains(where: { t >= $0.start && t < $0.end }) { out.insert(src) }
        }
        return out
    }

    // MARK: Chips

    private var currentChips: [OverlayChip] {
        let t = controller.isPlaying ? controller.time : controller.frameTime
        var out: [OverlayChip] = []
        switch session.assay {
        case .tailSuspension:
            guard let d = result?.tst else { break }
            if d.climbing.contains(where: { t >= $0.start && t < $0.end }) {
                out.append(OverlayChip(text: L("Climbing", "爬尾"), color: Palette.orange))
            } else if d.bouts.contains(where: { t >= $0.start && t < $0.end }) {
                out.append(OverlayChip(text: L("Immobile", "不动"), color: Palette.purple))
            } else {
                out.append(OverlayChip(text: L("Mobile", "挣扎"), color: Palette.green))
            }
        case .cylinder:
            guard let d = result?.cylinder else { break }
            if d.leftContacts.contains(where: { t >= $0.start && t < $0.end }) { out.append(OverlayChip(text: L("L on wall", "左爪触壁"), color: Palette.blue)) }
            if d.rightContacts.contains(where: { t >= $0.start && t < $0.end }) { out.append(OverlayChip(text: L("R on wall", "右爪触壁"), color: Palette.vermillion)) }
        case .gait:
            let st = gaitStance(at: t)
            if !st.isEmpty {
                let codes = Kp.paws.filter { st.contains(session.params.gait.swapLR ? $0.mirrored : $0) }.map(\.code)
                out.append(OverlayChip(text: L("Stance ", "支撑 ") + codes.joined(separator: " "), color: Color.black.opacity(0.55)))
            }
        case .itch, .pain, .grooming, .seizure:
            guard let d = result?.behavior else { break }
            // Brief events (flinches, jerks) stay visible for at least 0.3 s.
            for e in d.events where e.label != EventClass.ignore.key && t >= e.onset - 0.02 && t < max(e.offset, e.onset + 0.3) {
                let c = d.eventClass(e.label)
                out.append(OverlayChip(text: c.label.text, color: Color(uiColor: UIColor(hex: c.color))))
            }
            for tr in d.tracks where !d.classes.contains(where: { $0.key == tr.key }) {
                // Tracks that are not events (e.g. grooming regions) show what is happening now.
                if tr.intervals.contains(where: { t >= $0.start && t < $0.end }) {
                    out.append(OverlayChip(text: tr.label.text, color: Color(uiColor: UIColor(hex: tr.color))))
                }
            }
            if d.origin > 0 {
                out.append(OverlayChip(text: String(format: L("%@ after injection", "注射后 %@"), Fmt.clock(max(0, t - d.origin))),
                                       color: Color.black.opacity(0.55)))
            }
        }
        return out
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(currentChips) { c in
                Text(c.text)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(c.color, in: Capsule())
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { controller.time }, set: { controller.scrub(to: $0) }),
                   in: 0...max(0.1, track.duration),
                   onEditingChanged: { editing in editing ? controller.beginScrub() : controller.endScrub() })
                .accessibilityLabel(L("Position", "播放位置"))
                .accessibilityValue(Fmt.clockPrecise(controller.time))
            HStack(spacing: 4) {
                Text(Fmt.clockPrecise(controller.time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button { controller.step(-1); stepTick += 1 } label: { Image(systemName: "backward.frame.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("Previous frame", "上一帧"))
                Button { controller.toggle() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 52, height: 44)
                }
                .accessibilityLabel(controller.isPlaying ? L("Pause", "暂停") : L("Play", "播放"))
                Button { controller.step(1); stepTick += 1 } label: { Image(systemName: "forward.frame.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("Next frame", "下一帧"))
                Spacer()
                Menu {
                    Picker(L("Speed", "速度"), selection: Binding(get: { controller.rate }, set: { controller.setRate($0) })) {
                        ForEach([Float(0.25), 0.5, 1, 2, 4], id: \.self) { r in Text(String(format: "%g×", r)).tag(r) }
                    }
                    Divider()
                    Toggle(L("Show keypoints", "显示关键点"), isOn: $showSkeleton)
                } label: {
                    Text(String(format: "%g×", controller.rate)).font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Palette.inset, in: Capsule())
                }
                .accessibilityLabel(L("Playback options", "播放选项"))
            }
        }
    }
}
