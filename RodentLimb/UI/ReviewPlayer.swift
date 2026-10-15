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
@MainActor
final class PlayerController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var time: Double = 0
    @Published private(set) var frameTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isScrubbing = false
    @Published var rate: Float = 1
    let fps: Double
    /// Video-timeline time of the first frame (track time = player time − offset).
    let offset: Double
    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    private var observer: Any?
    private var seeking = false
    private var pendingTarget: Double?
    private var resumeAfterScrub = false

    init(url: URL, fps: Double, offset: Double) {
        let item = AVPlayerItem(url: url)
        item.add(videoOutput)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.fps = fps > 1 ? fps : 30
        self.offset = offset
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t) }
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

    func teardown() {
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
    }

    func toggle() {
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
        pendingTarget = target
        if !seeking { seekNext() }
    }

    private func seekNext() {
        guard let target = pendingTarget else { seeking = false; return }
        pendingTarget = nil
        seeking = true
        let ct = CMTime(seconds: target + offset, preferredTimescale: 6000)
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
        uiView.playerLayer.player = player
    }
}

/// Status chip shown on top of the video for the current frame.
struct OverlayChip: Identifiable {
    let id = UUID()
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
                Button { controller.step(-1); stepTick += 1 } label: { Image(systemName: "backward.frame.fill").frame(width: 44, height: 36) }
                    .accessibilityLabel(L("Previous frame", "上一帧"))
                Button { controller.toggle() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 52, height: 36)
                }
                .accessibilityLabel(controller.isPlaying ? L("Pause", "暂停") : L("Play", "播放"))
                Button { controller.step(1); stepTick += 1 } label: { Image(systemName: "forward.frame.fill").frame(width: 44, height: 36) }
                    .accessibilityLabel(L("Next frame", "下一帧"))
                Spacer()
                Menu {
                    ForEach([Float(0.25), 0.5, 1, 2, 4], id: \.self) { r in
                        Button { controller.setRate(r) } label: {
                            if controller.rate == r { Label(String(format: "%g×", r), systemImage: "checkmark") } else { Text(String(format: "%g×", r)) }
                        }
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
