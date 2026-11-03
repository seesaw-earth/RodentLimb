// ReviewPlayer.swift — video player with the keypoints drawn live from the stored pose track, frame
// stepping, playback rate, keyboard control and a timeline with the analysis' events.
//
// The controller is the iPhone app's (RodentLimb 1.2.1+, crash-fixed), unchanged in behaviour:
//  • time is on the *pose-track* clock (0 = first decoded frame), so events, charts and overlay
//    share one time base;
//  • `frameTime` changes only when a seek has finished, so keypoints never run ahead of the picture;
//    during playback the overlay asks AVPlayerItemVideoOutput which frame is on screen;
//  • scrubbing uses the chase-seek pattern (Apple QA1820), and seeks are only issued once the item
//    is ready (seeking earlier raises an uncaught exception in AVPlayer).
// Mac: AVPlayerLayer in an NSView, keyboard shortcuts (Space, ←/→ frame, ⇧←/→ 1 s, J/K/L), the
// controller keeps the video's security-scoped access alive while it exists.

import SwiftUI
import AVFoundation
import AppKit
import QuartzCore

@MainActor
final class PlayerController: ObservableObject {
    let player: AVPlayer
    @Published private(set) var time: Double = 0
    @Published private(set) var frameTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isScrubbing = false
    @Published private(set) var isReady = false
    @Published private(set) var failed = false
    @Published var rate: Float = 1
    let fps: Double
    /// Video-timeline time of the first frame (track time = player time − offset).
    let offset: Double
    let duration: Double
    private let access: VideoAccess?
    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    private var timeObserver: TimeObserverToken?
    private var statusObservation: NSKeyValueObservation?
    private var seeking = false
    private var pendingTarget: Double?
    private var resumeAfterScrub = false

    /// `access` keeps a referenced video readable while the player exists (nil = no video: the
    /// controller reports `failed`).
    init(access: VideoAccess?, fps: Double, offset: Double, duration: Double) {
        self.access = access
        self.fps = fps.isFinite && fps > 1 ? fps : 30
        self.offset = offset.isFinite ? offset : 0
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        if let url = access?.url {
            let item = AVPlayerItem(url: url)
            item.add(videoOutput)
            player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.automaticallyWaitsToMinimizeStalling = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.statusChanged(status) }
                }
            }
            addTimeObserver()
        } else {
            player = AVPlayer()
            failed = true
        }
    }

    /// Player for a recording of the store, at the track's time base.
    static func make(store: SessionStore, recording: Recording, track: PoseTrack) -> PlayerController {
        PlayerController(access: store.videoAccess(recording), fps: track.fps, offset: track.timeOffset ?? 0, duration: track.duration)
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

    /// The time the overlay should show now.
    var overlayTime: Double { isPlaying ? displayTime() : frameTime }

    /// Stops and releases the video now (not whenever the last reference goes away): pending seeks are
    /// cancelled and the item is taken off the player, so its decoder and file are closed at once.
    /// Opening and closing pages quickly otherwise leaves several half-open players decoding the
    /// same file (FigFilePlayer errors in the log, and a busy main thread).
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

    func play() { if !isPlaying { toggle() } }

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
        time = max(0, duration > 0 ? min(t, duration) : t)
        chase(time)
    }

    func step(_ frames: Int) {
        if isPlaying { pause() }
        let base = pendingTarget ?? time
        let frame = (base * fps).rounded(.down) + Double(frames)
        seek(max(0, (frame + 0.5) / fps))
    }

    func jump(_ seconds: Double) {
        if isPlaying { pause() }
        seek(max(0, (pendingTarget ?? time) + seconds))
    }

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
        guard isReady, player.currentItem?.status == .readyToPlay else { seeking = false; return }
        guard let target = pendingTarget else { seeking = false; return }
        pendingTarget = nil
        let seconds = target + offset
        guard seconds.isFinite else { seeking = false; return }
        seeking = true
        let ct = CMTime(seconds: seconds, preferredTimescale: 60_000)
        player.seek(to: ct, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
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

/// AVPlayerLayer hosted in an NSView (aspect fit, black letterbox).
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> LayerView {
        let v = LayerView(frame: .zero)
        v.playerLayer.player = player
        return v
    }

    func updateNSView(_ v: LayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }

    /// The layer lets go of the player when the view goes away (a layer kept alive by AppKit for a
    /// moment would otherwise keep rendering a torn-down player).
    static func dismantleNSView(_ v: LayerView, coordinator: ()) {
        v.playerLayer.player = nil
    }
}

/// Status chip shown on top of the video for the current frame. Identified by its text (chips are
/// rebuilt for every frame shown: a new random id each time would replace the chip views each time).
struct OverlayChip: Identifiable {
    var id: String { text }
    var text: String
    var color: Color
}

/// A colored stretch of the timeline (events, ethogram, QC loss). Drawn in one Canvas; no per-mark
/// identity is needed (and none is made: thousands of marks are rebuilt with the page).
struct TimelineMark {
    var start: Double
    var end: Double
    var color: Color
    var row: Int = 0
}

/// What the player draws besides the keypoints.
struct PlayerDecorations {
    /// Cylinder rim (bottom view) and the wall margin (fraction of the radius), display pixels.
    var circle: CircleCal?
    var wallMargin: Double = 0.15
    /// Floor line (side view), display pixels.
    var floorY: Double?
    /// Paws drawn larger (gait stance), at a given time.
    var emphasized: ((Double) -> Set<Kp>)?
    /// Chips for a given time.
    var chips: ((Double) -> [OverlayChip])?
    /// Colored stretches shown under the scrubber (click to jump).
    var marks: [TimelineMark] = []
    var markRows = 1
}

struct ReviewPlayer: View {
    @ObservedObject var controller: PlayerController
    let track: PoseTrack
    var threshold: Double = 0.3
    var decorations = PlayerDecorations()
    /// Show keypoints below the threshold too (QC: what the model really found).
    var showRaw = false
    var maxHeight: CGFloat = .infinity

    @AppStorage(SettingsKey.showSkeleton) private var showSkeleton = true
    @State private var scrubStart: Double?
    @FocusState private var focused: Bool

    private var videoSize: CGSize { CGSize(width: max(1, track.width), height: max(1, track.height)) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: controller.player)
                GeometryReader { geo in
                    let rect = aspectFitRect(videoSize, in: geo.size)
                    TimelineView(.animation(minimumInterval: nil, paused: !controller.isPlaying)) { _ in
                        let t = controller.overlayTime
                        Canvas { ctx, _ in draw(ctx, rect: rect, time: t) }
                    }
                    .allowsHitTesting(false)
                }
                chips.padding(8)
                if controller.failed {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2)
                        Text(L("This video can't be played. The file may be missing, on a drive that is not connected, or damaged.",
                               "无法播放该视频。文件可能已丢失、所在磁盘未连接或已损坏。"))
                            .multilineTextAlignment(.center)
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            .aspectRatio(videoSize.width / videoSize.height, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { focused = true; controller.toggle() }
            .gesture(videoScrub)
            .overlay(alignment: .bottom) {
                if controller.isScrubbing {
                    Text(Fmt.clockPrecise(controller.time))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .accessibilityLabel(L("Video with pose overlay", "带姿态叠加的视频"))

            controls
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { controller.toggle(); return .handled }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let dir = press.key == .leftArrow ? -1 : 1
            if press.modifiers.contains(.shift) { controller.jump(Double(dir)) } else { controller.step(dir) }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "jklJKL,.")) { press in
            switch press.characters.lowercased() {
            case "j": controller.jump(-5)
            case "k": controller.pause()
            case "l": controller.play()
            case ",": controller.step(-1)
            case ".": controller.step(1)
            default: return .ignored
            }
            return .handled
        }
        .onDisappear { controller.pause() }
    }

    /// Horizontal drag on the video: 4 pt per frame.
    private var videoScrub: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
                if scrubStart == nil {
                    controller.beginScrub()
                    scrubStart = controller.time
                }
                let frames = Int(safe: (g.translation.width / 4).rounded())
                let t = (scrubStart ?? 0) + Double(frames) / controller.fps
                controller.scrub(to: min(max(0, t), track.duration))
            }
            .onEnded { _ in
                if scrubStart != nil { controller.endScrub() }
                scrubStart = nil
            }
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, rect: CGRect, time: Double) {
        let sx = rect.width / videoSize.width, sy = rect.height / videoSize.height
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy) }

        if let c = decorations.circle {
            let center = map(CGPoint(x: c.cx, y: c.cy))
            let r = c.r * sx
            let inner = r * (1 - decorations.wallMargin)
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.white.opacity(0.7)), lineWidth: 1.5)
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner)),
                       with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        if let f = decorations.floorY {
            let y = rect.minY + f * sy
            var p = Path(); p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(p, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }

        guard showSkeleton, let i = track.frameIndex(at: time) else { return }
        let thr = showRaw ? 0.0001 : threshold
        let big = decorations.emphasized?(time) ?? []
        for (a, b) in Kp.bones {
            guard let p = track.point(a, i, threshold: thr), let q = track.point(b, i, threshold: thr) else { continue }
            var path = Path(); path.move(to: map(p)); path.addLine(to: map(q))
            ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 2)
        }
        for k in Kp.allCases {
            guard let p = track.point(k, i, threshold: thr) else { continue }
            let c = map(p)
            let low = showRaw && Double(track.c[k.rawValue][i]) < threshold
            let r: CGFloat = big.contains(k) ? 7.5 : 5
            let rr = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rr), with: .color(KeypointColors.color(k).opacity(low ? 0.35 : 1)))
            ctx.stroke(Path(ellipseIn: rr), with: .color(.white.opacity(low ? 0.5 : 1)), lineWidth: big.contains(k) ? 2.5 : 1.2)
        }
    }

    private var chips: some View {
        let t = controller.isPlaying ? controller.time : controller.frameTime
        let list = decorations.chips?(t) ?? []
        return HStack(spacing: 6) {
            ForEach(list) { c in
                Text(c.text)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(c.color, in: Capsule())
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 4) {
            if !decorations.marks.isEmpty {
                TimelineBar(duration: max(0.1, track.duration), marks: decorations.marks, rows: decorations.markRows,
                            time: controller.time) { controller.seek($0) }
                    .frame(height: CGFloat(max(1, decorations.markRows)) * 7 + 4)
            }
            Slider(value: Binding(get: { controller.time }, set: { controller.scrub(to: $0) }),
                   in: 0...max(0.1, track.duration),
                   onEditingChanged: { editing in editing ? controller.beginScrub() : controller.endScrub() })
                .controlSize(.small)
                .accessibilityLabel(L("Position", "播放位置"))
                .accessibilityValue(Fmt.clockPrecise(controller.time))
            HStack(spacing: 2) {
                Text(Fmt.clockPrecise(controller.time) + " / " + Fmt.clock(track.duration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(String(format: L("frame %d", "第 %d 帧"), track.frameIndex(at: controller.frameTime) ?? 0))
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    .padding(.leading, 6)
                Spacer()
                Button { controller.jump(-1) } label: { Image(systemName: "gobackward") }
                    .help(L("Back 1 s (⇧←)", "后退 1 秒（⇧←）"))
                Button { controller.step(-1) } label: { Image(systemName: "backward.frame.fill") }
                    .help(L("Previous frame (←)", "上一帧（←）"))
                Button { controller.toggle() } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").frame(width: 22)
                }
                .help(L("Play / pause (Space)", "播放 / 暂停（空格）"))
                Button { controller.step(1) } label: { Image(systemName: "forward.frame.fill") }
                    .help(L("Next frame (→)", "下一帧（→）"))
                Button { controller.jump(1) } label: { Image(systemName: "goforward") }
                    .help(L("Forward 1 s (⇧→)", "前进 1 秒（⇧→）"))
                Spacer()
                Menu {
                    ForEach([Float(0.1), 0.25, 0.5, 1, 2, 4, 8], id: \.self) { r in
                        Button { controller.setRate(r) } label: {
                            if controller.rate == r { Label(String(format: "%g×", r), systemImage: "checkmark") } else { Text(String(format: "%g×", r)) }
                        }
                    }
                    Divider()
                    Toggle(L("Show keypoints", "显示关键点"), isOn: $showSkeleton)
                } label: {
                    Text(String(format: "%g×", controller.rate)).font(.caption.weight(.semibold).monospacedDigit())
                }
                .menuStyle(.button)
                .fixedSize()
                .help(L("Playback speed and overlay", "播放速度与叠加显示"))
            }
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
    }
}

/// Colored stretches over the whole video; click or drag to jump.
struct TimelineBar: View {
    let duration: Double
    let marks: [TimelineMark]
    var rows = 1
    let time: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Canvas { ctx, size in
                let rowH = max(4, (size.height - 2) / CGFloat(max(1, rows)))
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(Palette.inset))
                for m in marks {
                    let x0 = CGFloat(max(0, m.start) / duration) * size.width
                    let x1 = CGFloat(min(duration, max(m.end, m.start + duration / 2000)) / duration) * size.width
                    let r = CGRect(x: x0, y: 1 + CGFloat(m.row) * rowH, width: max(1, x1 - x0), height: rowH - 1)
                    ctx.fill(Path(r), with: .color(m.color))
                }
                let x = CGFloat(min(max(0, time / duration), 1)) * size.width
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.primary))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                seek(Double(min(max(0, g.location.x / max(1, w)), 1)) * duration)
            })
        }
        .accessibilityHidden(true)
    }
}
