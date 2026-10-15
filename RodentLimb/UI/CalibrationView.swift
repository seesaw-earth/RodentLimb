// CalibrationView.swift — mark the cylinder rim (bottom view), the floor line (side view) or a
// cm ruler (gait) on a frame of the video. A loupe magnifies the touch point while dragging, and
// "Auto" proposes a starting position from the tracked keypoints.

import SwiftUI
import AVFoundation

@MainActor
struct CalibrationView: View {
    let sessionID: UUID
    let track: PoseTrack?

    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var videoSize = CGSize(width: 1920, height: 1080)
    @State private var duration: Double = 1
    @State private var frameTime: Double = 1
    @State private var circle = CircleCal(cx: 960, cy: 540, r: 400)
    @State private var floorY: Double = 900
    @State private var ruler = ScaleCal(x1: 600, y1: 900, x2: 1300, y2: 900, cm: 10)
    @State private var hasCircle = false
    @State private var hasFloor = false
    @State private var hasRuler = false
    @State private var loupe: CGPoint?        // video coordinates of the active touch
    @State private var dragMode: DragMode?
    @State private var dragStart: (CircleCal, ScaleCal, Double)?
    @State private var confirmAll = false
    @State private var imageTask: Task<Void, Never>?
    @State private var generator: AVAssetImageGenerator?
    /// Video time of the frame actually shown (the generator may return a nearby frame), so the
    /// keypoints drawn on it always belong to that exact frame.
    @State private var shownTime: Double = 0

    enum DragMode { case move, resize, rulerA, rulerB, floor }
    enum Mode { case circle, floor, ruler }

    private var session: Session? { store.session(sessionID) }

    private var mode: Mode {
        guard let s = session else { return .circle }
        switch s.assay {
        case .gait, .tailSuspension: return .ruler
        case .cylinder: return s.params.cylinder.view == .bottom ? .circle : .floor
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(instruction).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    canvas
                    if duration > 1 {
                        VStack(alignment: .leading, spacing: 2) {
                            Slider(value: $frameTime, in: 0...max(0.1, duration - 0.05))
                                .accessibilityLabel(L("Frame", "画面时刻"))
                            Text(L("Frame at ", "画面时刻 ") + Fmt.clockPrecise(frameTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    controls
                }
                .screenContent()
                .padding(.vertical, 12)
            }
            .background(Palette.canvas)
            .navigationTitle(L("Calibration", "标定"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done", "完成")) { dismissKeyboard() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button(L("Save for this video", "仅保存到本视频")) { save(all: false) }
                        Button(L("Save and use for all videos of this assay", "保存并用于该范式的所有视频")) { confirmAll = true }
                    } label: {
                        Text(L("Save", "保存")).fontWeight(.semibold)
                    } primaryAction: {
                        save(all: false)
                    }
                }
            }
            .confirmationDialog(L("Use this calibration for every video of this assay? Do this only if the camera did not move.",
                                  "将此标定用于该范式的所有视频？仅在相机位置未移动时这样做。"),
                                isPresented: $confirmAll, titleVisibility: .visible) {
                Button(L("Use for all", "全部使用")) { save(all: true) }
            }
            .task { await setup() }
            .onChange(of: frameTime) { _, t in loadImage(at: t, debounce: true) }
        }
    }

    private var instruction: String {
        switch mode {
        case .circle:
            return L("Drag inside the circle to move it, drag its edge to resize. Match the inner rim of the cylinder floor.",
                     "在圆内拖动可移动，拖动圆边可调整大小。使其与圆筒底面内缘重合。")
        case .floor:
            return L("Drag the dashed line onto the cylinder floor.", "将虚线拖到圆筒底面位置。")
        case .ruler:
            return L("Drag both ends onto marks of a known distance (e.g. a ruler or the walkway width), then enter that distance.",
                     "将两端拖到已知距离的标记上（如标尺或步道宽度），然后输入该距离。")
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let rect = aspectFitRect(videoSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    Image(uiImage: image).resizable().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Canvas { ctx, _ in drawOverlay(ctx, rect: rect) }
                    .allowsHitTesting(false)
                if let loupe, let image {
                    LoupeView(image: image, videoSize: videoSize, point: loupe)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(rect: rect))
        }
        .aspectRatio(videoSize.width / max(1, videoSize.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(L("Calibration frame", "标定画面"))
    }

    private func drawOverlay(_ ctx: GraphicsContext, rect: CGRect) {
        let s = rect.width / max(1, videoSize.width)
        func v(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }

        // Pose of this frame, to help placement.
        if let t = track, let i = t.frameIndex(atPlayerTime: shownTime) {
            for k in Kp.allCases {
                guard let p = t.point(k, i, threshold: 0.3) else { continue }
                let c = v(p.x, p.y)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(KeypointColors.color(k)))
            }
        }

        let accent = Color.yellow
        switch mode {
        case .circle:
            let c = v(circle.cx, circle.cy), r = circle.r * s
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(accent), lineWidth: 2.5)
            if let m = session?.params.cylinder.wallMargin {
                let ri = r * (1 - m)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ri, y: c.y - ri, width: 2 * ri, height: 2 * ri)), with: .color(accent.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(accent))
            let h = CGPoint(x: c.x + r, y: c.y)
            ctx.fill(Path(ellipseIn: CGRect(x: h.x - 11, y: h.y - 11, width: 22, height: 22)), with: .color(accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: h.x - 11, y: h.y - 11, width: 22, height: 22)), with: .color(.black.opacity(0.5)), lineWidth: 1)
        case .floor:
            let y = rect.minY + floorY * s
            var p = Path(); p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
            ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - 11, y: y - 11, width: 22, height: 22)), with: .color(accent))
        case .ruler:
            let a = v(ruler.x1, ruler.y1), b = v(ruler.x2, ruler.y2)
            var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(accent), lineWidth: 2.5)
            for q in [a, b] {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 11, y: q.y - 11, width: 22, height: 22)), with: .color(accent.opacity(0.35)))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 11, y: q.y - 11, width: 22, height: 22)), with: .color(accent), lineWidth: 2)
                var cross = Path()
                cross.move(to: CGPoint(x: q.x - 6, y: q.y)); cross.addLine(to: CGPoint(x: q.x + 6, y: q.y))
                cross.move(to: CGPoint(x: q.x, y: q.y - 6)); cross.addLine(to: CGPoint(x: q.x, y: q.y + 6))
                ctx.stroke(cross, with: .color(.black), lineWidth: 1)
            }
        }
    }

    private func drag(rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let s = rect.width / max(1, videoSize.width)
                func toVideo(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - rect.minX) / s, y: (p.y - rect.minY) / s) }
                let start = toVideo(g.startLocation), now = toVideo(g.location)
                if dragMode == nil {
                    dragStart = (circle, ruler, floorY)
                    let touchSlop = 30 / s
                    switch mode {
                    case .circle:
                        let d = hypot(start.x - circle.cx, start.y - circle.cy)
                        dragMode = abs(d - circle.r) < touchSlop ? .resize : .move
                    case .floor:
                        dragMode = .floor
                    case .ruler:
                        let da = hypot(start.x - ruler.x1, start.y - ruler.y1), db = hypot(start.x - ruler.x2, start.y - ruler.y2)
                        dragMode = da <= db ? .rulerA : .rulerB
                    }
                }
                guard let ds = dragStart else { return }
                let (c0, r0, f0) = ds
                let dx = now.x - start.x, dy = now.y - start.y
                switch dragMode {
                case .move:
                    circle.cx = c0.cx + dx; circle.cy = c0.cy + dy
                    loupe = nil
                case .resize:
                    circle.r = max(20, hypot(now.x - circle.cx, now.y - circle.cy))
                    loupe = now
                case .floor:
                    floorY = min(max(0, f0 + dy), videoSize.height)
                    loupe = CGPoint(x: now.x, y: floorY)
                case .rulerA:
                    ruler.x1 = r0.x1 + dx; ruler.y1 = r0.y1 + dy
                    loupe = CGPoint(x: ruler.x1, y: ruler.y1)
                case .rulerB:
                    ruler.x2 = r0.x2 + dx; ruler.y2 = r0.y2 + dy
                    loupe = CGPoint(x: ruler.x2, y: ruler.y2)
                case .none:
                    break
                }
                switch mode {
                case .circle: hasCircle = true
                case .floor: hasFloor = true
                case .ruler: hasRuler = true
                }
            }
            .onEnded { _ in
                dragMode = nil
                dragStart = nil
                withAnimation(Motion.gentle) { loupe = nil }
            }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch mode {
        case .circle:
            Card {
                InfoRow(key: L("Center", "圆心"), value: String(format: "%.0f, %.0f px", circle.cx, circle.cy))
                InfoRow(key: L("Radius", "半径"), value: String(format: "%.0f px", circle.r))
                if track != nil {
                    Button { autoCircle() } label: { Label(L("Auto-fit from tracking", "根据追踪自动拟合"), systemImage: "wand.and.stars") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        case .floor:
            Card {
                InfoRow(key: L("Floor line", "地面线"), value: String(format: "y = %.0f px", floorY))
                if track != nil {
                    Button { autoFloor() } label: { Label(L("Estimate from hind paws", "根据后爪位置估计"), systemImage: "wand.and.stars") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        case .ruler:
            Card {
                NumberField(title: L("Known distance", "已知距离"), value: $ruler.cm, unit: "cm")
                InfoRow(key: L("Length on screen", "画面长度"), value: String(format: "%.0f px", ruler.pixels))
                InfoRow(key: L("Scale", "比例"), value: ruler.pxPerCm.map { String(format: "%.2f px/cm", $0) } ?? "—")
                if hasRuler || session?.calibration.scale != nil {
                    Button(L("Remove scale (use body lengths)", "移除标尺（使用体长单位）"), role: .destructive) {
                        hasRuler = false
                        save(all: false, removeScale: true)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: Logic

    private func setup() async {
        guard let s = session else { return }
        let asset = AVURLAsset(url: store.videoURL(s))
        if let t = track {
            videoSize = CGSize(width: t.width, height: t.height)
            duration = t.duration
        } else if let vt = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await vt.load(.naturalSize), let tf = try? await vt.load(.preferredTransform) {
            let r = CGRect(origin: .zero, size: size).applying(tf)
            videoSize = CGSize(width: abs(r.width), height: abs(r.height))
            duration = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        }
        frameTime = min(1, duration / 2)
        let w = videoSize.width, h = videoSize.height
        circle = s.calibration.circle ?? CircleCal(cx: w / 2, cy: h / 2, r: min(w, h) * 0.42)
        floorY = s.calibration.floorY ?? h * 0.85
        ruler = s.calibration.scale ?? ScaleCal(x1: w * 0.3, y1: h * 0.85, x2: w * 0.7, y2: h * 0.85, cm: 10)
        hasCircle = s.calibration.circle != nil
        hasFloor = s.calibration.floorY != nil
        hasRuler = s.calibration.scale != nil
        if s.calibration.circle == nil, mode == .circle, track != nil { autoCircle() }
        if s.calibration.floorY == nil, mode == .floor, track != nil { autoFloor() }
        loadImage(at: frameTime, debounce: false)
    }

    private func loadImage(at t: Double, debounce: Bool) {
        guard let s = session else { return }
        imageTask?.cancel()
        let url = store.videoURL(s)
        // One generator for the whole sheet; cancel in-flight work when a newer frame is asked for.
        let gen: AVAssetImageGenerator
        if let g = generator { gen = g } else {
            gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            gen.maximumSize = CGSize(width: 1600, height: 1600)
            generator = gen
        }
        gen.cancelAllCGImageGeneration()
        imageTask = Task {
            if debounce { try? await Task.sleep(nanoseconds: 60_000_000) }
            guard !Task.isCancelled else { return }
            if let r = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)), !Task.isCancelled {
                image = UIImage(cgImage: r.image)
                let actual = r.actualTime.seconds
                shownTime = actual.isFinite ? actual : t
            }
        }
    }

    private func percentile(_ v: [Double], _ q: Double) -> Double? {
        let s = v.sorted()
        guard !s.isEmpty else { return nil }
        return s[min(s.count - 1, max(0, Int(Double(s.count - 1) * q)))]
    }

    private func autoCircle() {
        guard let t = track else { return }
        var xs: [Double] = [], ys: [Double] = []
        for k in Kp.allCases {
            for i in stride(from: 0, to: t.frameCount, by: 2) where t.c[k.rawValue][i] >= 0.5 && t.x[k.rawValue][i] >= 0 {
                xs.append(Double(t.x[k.rawValue][i])); ys.append(Double(t.y[k.rawValue][i]))
            }
        }
        guard let x0 = percentile(xs, 0.005), let x1 = percentile(xs, 0.995),
              let y0 = percentile(ys, 0.005), let y1 = percentile(ys, 0.995), x1 > x0, y1 > y0 else { return }
        withAnimation(Motion.gentle) {
            circle = CircleCal(cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, r: max(x1 - x0, y1 - y0) / 2 * 1.02)
        }
        hasCircle = true
    }

    private func autoFloor() {
        guard let t = track else { return }
        var ys: [Double] = []
        for k in [Kp.lh, .rh] {
            for i in 0..<t.frameCount where t.c[k.rawValue][i] >= 0.5 && t.y[k.rawValue][i] >= 0 { ys.append(Double(t.y[k.rawValue][i])) }
        }
        if let y = percentile(ys, 0.95) { withAnimation(Motion.gentle) { floorY = y }; hasFloor = true }
    }

    private func save(all: Bool, removeScale: Bool = false) {
        guard let s = session else { return }
        var cal = s.calibration
        cal.copiedFrom = nil
        switch mode {
        case .circle: cal.circle = circle
        case .floor: cal.floorY = floorY
        case .ruler: cal.scale = removeScale ? nil : (ruler.pxPerCm != nil ? ruler : nil)
        }
        store.update(sessionID) { $0.calibration = cal }
        if s.hasPose { store.analyze(sessionID) }
        if all {
            for other in store.sessions where other.assay == s.assay && other.id != s.id {
                var c = cal
                c.copiedFrom = s.displayName
                store.update(other.id) { $0.calibration = c }
                if other.hasPose { store.analyze(other.id) }
            }
        }
        if !removeScale { dismiss() }
    }
}

/// Circular magnifier (3×) showing the area under the finger, with a crosshair.
@MainActor
struct LoupeView: View {
    let image: UIImage
    let videoSize: CGSize
    let point: CGPoint
    private let size: CGFloat = 110
    private let zoom: CGFloat = 3

    var body: some View {
        let scale = size * zoom / max(videoSize.width, videoSize.height)
        let w = videoSize.width * scale, h = videoSize.height * scale
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: w, height: h)
                .offset(x: w / 2 - point.x * scale, y: h / 2 - point.y * scale)
                .frame(width: size, height: size)
                .clipped()
            Path { p in
                p.move(to: CGPoint(x: size / 2 - 10, y: size / 2)); p.addLine(to: CGPoint(x: size / 2 + 10, y: size / 2))
                p.move(to: CGPoint(x: size / 2, y: size / 2 - 10)); p.addLine(to: CGPoint(x: size / 2, y: size / 2 + 10))
            }
            .stroke(Color.yellow, lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
        .shadow(radius: 6)
    }
}
