// CalibrationSheet.swift — mark the cylinder rim (bottom view), the floor line (side view) or a
// cm ruler (gait) on a frame of the video. Drag the handles with the mouse (a loupe magnifies the
// point under the cursor while dragging), nudge them with the arrow keys, type exact values, pick
// the frame with the time slider, or let "Auto" place them from the tracked keypoints (same fit
// as the iPhone app). Save writes the calibration and re-analyses; optionally the same calibration
// is used for the other analyses of this task in the study (same camera position).
// The video stays readable through a VideoAccess kept in @State while the sheet is open.

import SwiftUI
import AppKit

@MainActor
struct CalibrationSheet: View {
    let id: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var access: VideoAccess?
    @State private var track: PoseTrack?
    @State private var image: CGImage?
    @State private var videoSize = CGSize(width: 1920, height: 1080)
    @State private var sizeKnown = false
    @State private var duration: Double = 0
    /// Track time of the frame asked for / shown (player time − offset).
    @State private var frameTime: Double = 0
    @State private var shownTime: Double = 0
    @State private var requestedTime: Double?
    @State private var mode: CalibrationMode = .circle
    @State private var cameraView: CylinderViewMode = .bottom
    @State private var circle = CircleCal(cx: 960, cy: 540, r: 400)
    @State private var floorY: Double = 900
    @State private var ruler = ScaleCal(x1: 600, y1: 900, x2: 1300, y2: 900, cm: 10)
    /// Video coordinates magnified by the loupe, and the cursor (view coordinates) it follows.
    @State private var loupe: CGPoint?
    @State private var cursor: CGPoint?
    @State private var dragMode: CalibrationHandle?
    @State private var selectedHandle: CalibrationHandle?
    @State private var dragStart: (CircleCal, ScaleCal, Double)?
    @State private var imageTask: Task<Void, Never>?
    /// Counts manual edits, so a background auto-fit never overwrites a drag made meanwhile.
    @State private var editCount = 0
    @State private var ready = false
    @State private var videoMissing = false
    @State private var fitting = false
    @State private var fitMessage: String?
    @State private var showPose = true
    @State private var applyToOthers = false
    @State private var confirmApply = false
    /// Other analyses of this task with the same camera set-up (computed once, at setup).
    @State private var otherTargets: [UUID] = []
    @State private var otherTitle = ""
    @FocusState private var canvasFocused: Bool

    private var store: SessionStore { app.store }
    private var session: Session? { store.session(id) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 10) {
                    canvasArea
                    frameSlider
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                sidePanel
                    .frame(width: 290)
            }
            Divider()
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .sheetFrame(minWidth: 640, idealWidth: 1080, maxWidth: 1500, minHeight: 440, idealHeight: 780, maxHeight: 1100)
        .task { await setup() }
        .onChange(of: frameTime) { _, t in loadImage(at: t, debounce: true) }
        .onChange(of: cameraView) { _, v in
            guard session?.assay == .cylinder else { return }
            mode = v == .bottom ? .circle : .floor
            selectedHandle = nil
        }
        .onDisappear {
            imageTask?.cancel()
            NSCursor.arrow.set()
        }
        .confirmationDialog(String(format: L("Use this calibration for %d other analyses?", "将此标定用于另外 %d 个分析？"), otherTargets.count),
                            isPresented: $confirmApply, titleVisibility: .visible) {
            Button(L("Save and Use for All", "保存并全部使用")) { save(all: true) }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("Do this only if the camera did not move between the videos. Their current calibration is replaced and they are re-analysed.",
                   "仅在各视频之间相机位置未移动时这样做。它们现有的标定将被替换并重新分析。"))
        }
    }

    // MARK: Header & footer

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let s = session { AssayBadge(assay: s.assay, size: 30) }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Calibration", "标定")).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if session?.assay == .cylinder {
                Picker(L("Camera", "拍摄视角"), selection: $cameraView) {
                    ForEach(CylinderViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help(L("Bottom view: mark the rim of the cylinder. Side view: mark the floor line.", "仰视：标定圆筒边缘；侧视：标定地面线。"))
            }
        }
    }

    private var subtitle: String {
        guard let s = session else { return "" }
        let name = store.recording(for: s).map { store.displayName($0) } ?? s.displayName
        return [s.assay.name.text, name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if mode == .ruler && session?.calibration.scale != nil {
                Button(L("Remove Scale", "移除标尺"), role: .destructive) { removeScale() }
                    .help(L("Report lengths in body lengths instead of cm", "长度改用体长单位而非厘米"))
            }
            Spacer()
            Button(L("Cancel", "取消"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(L("Save", "保存")) {
                if applyToOthers && !otherTargets.isEmpty { confirmApply = true } else { save(all: false) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        guard ready, session != nil else { return false }
        switch mode {
        case .circle: return circle.r.isFinite && circle.r > 1 && circle.cx.isFinite && circle.cy.isFinite
        case .floor: return floorY.isFinite
        case .ruler: return ruler.pxPerCm != nil
        }
    }

    // MARK: Frame

    private var canvasArea: some View {
        GeometryReader { geo in
            let rect = aspectFitRect(videoSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                } else if videoMissing {
                    VStack(spacing: 8) {
                        Text(L("The video file cannot be found. You can still type the values, or locate the video from its page.",
                               "找不到视频文件。仍可直接输入数值，或在视频页面重新定位视频。"))
                            .multilineTextAlignment(.center)
                    }
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                let ov = overlay
                Canvas { ctx, _ in ov.draw(ctx, rect: rect) }
                    .allowsHitTesting(false)
                if let loupe, let image, let cursor {
                    CalibrationLoupe(image: image, videoSize: videoSize, displayScale: rect.width / max(1, videoSize.width),
                                     point: loupe, shape: loupeShape)
                        .position(loupePosition(cursor, in: geo.size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in dragChanged(g, rect: rect) }
                .onEnded { _ in dragEnded() })
            .onContinuousHover { phase in hover(phase, rect: rect) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .focusable()
        .focused($canvasFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in nudge(press) }
        .accessibilityLabel(L("Calibration frame", "标定画面"))
    }

    private var frameSlider: some View {
        HStack(spacing: 8) {
            Text(L("Frame", "画面")).font(.callout).foregroundStyle(.secondary)
            Button { frameTime = max(0, frameTime - 1) } label: { Image(systemName: "gobackward") }
                .buttonStyle(.borderless)
                .help(L("Back 1 s", "后退 1 秒"))
            Slider(value: $frameTime, in: 0...max(0.1, duration - 0.05))
                .controlSize(.small)
                .disabled(duration <= 0.1 || access == nil)
                .accessibilityLabel(L("Frame time", "画面时刻"))
            Button { frameTime = min(max(0, duration - 0.05), frameTime + 1) } label: { Image(systemName: "goforward") }
                .buttonStyle(.borderless)
                .help(L("Forward 1 s", "前进 1 秒"))
            Text(Fmt.clockPrecise(frameTime))
                .font(.callout.monospacedDigit())
                .frame(width: 70, alignment: .trailing)
        }
        .disabled(access == nil)
    }

    private func loupePosition(_ c: CGPoint, in size: CGSize) -> CGPoint {
        let d: CGFloat = 95, half: CGFloat = 68
        var x = c.x - d, y = c.y - d
        if x < half { x = c.x + d }
        if y < half { y = c.y + d }
        x = min(max(half, x), max(half, size.width - half))
        y = min(max(half, y), max(half, size.height - half))
        return CGPoint(x: x, y: y)
    }

    private var overlay: CalibrationOverlay {
        CalibrationOverlay(mode: mode, circle: circle, floorY: floorY, ruler: ruler,
                           wallMargin: session?.params.cylinder.wallMargin, selected: selectedHandle,
                           track: showPose ? track : nil, time: shownTime, videoSize: videoSize)
    }

    private var loupeShape: CalibrationLoupe.Outline {
        switch mode {
        case .circle: return .circle(circle)
        case .floor: return .floor(floorY)
        case .ruler: return .ruler(ruler)
        }
    }

    // MARK: Mouse & keys

    private func toVideo(_ p: CGPoint, rect: CGRect) -> CGPoint? {
        let s = rect.width / max(1, videoSize.width)
        guard s.isFinite, s > 0 else { return nil }
        return CGPoint(x: (p.x - rect.minX) / s, y: (p.y - rect.minY) / s)
    }

    /// Which handle a click at video point `p` grabs (`slop` in video pixels).
    private func handle(at p: CGPoint, slop: Double) -> CalibrationHandle {
        let x = Double(p.x), y = Double(p.y)
        switch mode {
        case .circle:
            let d = hypot(x - circle.cx, y - circle.cy)
            return abs(d - circle.r) < max(4, slop) ? .resize : .move
        case .floor:
            return .floor
        case .ruler:
            let da = hypot(x - ruler.x1, y - ruler.y1), db = hypot(x - ruler.x2, y - ruler.y2)
            return da <= db ? .rulerA : .rulerB
        }
    }

    private func dragChanged(_ g: DragGesture.Value, rect: CGRect) {
        guard ready, let start = toVideo(g.startLocation, rect: rect), let now = toVideo(g.location, rect: rect) else { return }
        let s = Double(rect.width / max(1, videoSize.width))
        if dragMode == nil {
            editCount += 1
            canvasFocused = true
            dragStart = (circle, ruler, floorY)
            let h = handle(at: start, slop: 10 / max(0.01, s))
            dragMode = h
            selectedHandle = h
            NSCursor.closedHand.set()
        }
        guard let ds = dragStart else { return }
        let (c0, r0, f0) = ds
        let dx = Double(now.x - start.x), dy = Double(now.y - start.y)
        let w = Double(videoSize.width), hgt = Double(videoSize.height)
        let nx = Self.clamp(Double(now.x), 0, w), ny = Self.clamp(Double(now.y), 0, hgt)
        switch dragMode {
        case .move:
            circle.cx = Self.clamp(c0.cx + dx, 0, w)
            circle.cy = Self.clamp(c0.cy + dy, 0, hgt)
            loupe = CGPoint(x: circle.cx, y: circle.cy)
        case .resize:
            circle.r = max(20, hypot(nx - circle.cx, ny - circle.cy))
            loupe = CGPoint(x: nx, y: ny)
        case .floor:
            floorY = Self.clamp(f0 + dy, 0, hgt)
            loupe = CGPoint(x: nx, y: floorY)
        case .rulerA:
            ruler.x1 = Self.clamp(r0.x1 + dx, 0, w)
            ruler.y1 = Self.clamp(r0.y1 + dy, 0, hgt)
            loupe = CGPoint(x: ruler.x1, y: ruler.y1)
        case .rulerB:
            ruler.x2 = Self.clamp(r0.x2 + dx, 0, w)
            ruler.y2 = Self.clamp(r0.y2 + dy, 0, hgt)
            loupe = CGPoint(x: ruler.x2, y: ruler.y2)
        case .none:
            break
        }
        cursor = g.location
    }

    private func dragEnded() {
        dragMode = nil
        dragStart = nil
        cursor = nil
        withAnimation(Motion.gentle) { loupe = nil }
        NSCursor.arrow.set()
    }

    private func hover(_ phase: HoverPhase, rect: CGRect) {
        guard dragMode == nil else { return }
        switch phase {
        case .active(let loc):
            guard ready, rect.contains(loc), let p = toVideo(loc, rect: rect) else { NSCursor.arrow.set(); return }
            let s = Double(rect.width / max(1, videoSize.width))
            switch handle(at: p, slop: 10 / max(0.01, s)) {
            case .move: NSCursor.openHand.set()
            case .resize, .rulerA, .rulerB: NSCursor.crosshair.set()
            case .floor: NSCursor.resizeUpDown.set()
            }
        case .ended:
            NSCursor.arrow.set()
        }
    }

    /// Arrow keys move the selected handle by 1 px (⇧ 10 px); ⌥ arrows change the radius.
    private func nudge(_ press: KeyPress) -> KeyPress.Result {
        guard ready else { return .ignored }
        let step: Double = press.modifiers.contains(.shift) ? 10 : 1
        var dx = 0.0, dy = 0.0
        if press.key == .leftArrow { dx = -step }
        else if press.key == .rightArrow { dx = step }
        else if press.key == .upArrow { dy = -step }
        else if press.key == .downArrow { dy = step }
        else { return .ignored }
        editCount += 1
        let w = Double(videoSize.width), h = Double(videoSize.height)
        switch mode {
        case .circle:
            if selectedHandle == .resize || press.modifiers.contains(.option) {
                circle.r = max(20, circle.r + (dx != 0 ? dx : -dy))
            } else {
                circle.cx = Self.clamp(circle.cx + dx, 0, w)
                circle.cy = Self.clamp(circle.cy + dy, 0, h)
            }
        case .floor:
            floorY = Self.clamp(floorY + dy, 0, h)
        case .ruler:
            if selectedHandle == .rulerA {
                ruler.x1 = Self.clamp(ruler.x1 + dx, 0, w)
                ruler.y1 = Self.clamp(ruler.y1 + dy, 0, h)
            } else {
                ruler.x2 = Self.clamp(ruler.x2 + dx, 0, w)
                ruler.y2 = Self.clamp(ruler.y2 + dy, 0, h)
            }
        }
        return .handled
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        guard v.isFinite else { return lo }
        return min(max(lo, v), max(lo, hi))
    }

    // MARK: Side panel

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(instruction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) { fields }
                        .padding(4)
                } label: {
                    Text(L("Values (video pixels)", "数值（视频像素）"))
                }
                if mode != .ruler {
                    HStack(spacing: 8) {
                        Button {
                            if mode == .circle { autoCircle() } else { autoFloor() }
                        } label: {
                            Text(mode == .circle ? L("Auto-fit from Tracking", "根据追踪自动拟合") : L("Estimate from Hind Paws", "根据后爪位置估计"))
                        }
                        .disabled(track == nil || fitting || !ready)
                        .help(track == nil ? L("Available once the video has been tracked", "视频识别完成后可用")
                                           : L("Place it from where the keypoints were found in the whole video", "根据整段视频中关键点的位置自动放置"))
                        if fitting { ProgressView().controlSize(.small) }
                    }
                    if let fitMessage {
                        Text(fitMessage).font(.caption).foregroundStyle(Palette.warning).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(L("Show keypoints of this frame", "显示该帧的关键点"), isOn: $showPose)
                    .disabled(track == nil)
                if let from = session?.calibration.copiedFrom, !from.isEmpty {
                    Banner(text: String(format: L("The current calibration was copied from %@.", "当前标定沿用自 %@。"), from))
                }
                applyOption
                Text(L("Arrow keys move the selected handle by 1 px (⇧: 10 px); ⌥ + arrows change the radius.",
                       "方向键将所选控制点移动 1 像素（⇧：10 像素）；⌥ + 方向键调整半径。"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch mode {
        case .circle:
            NumberField(title: L("Center x", "圆心 x"), value: $circle.cx, unit: "px")
            NumberField(title: L("Center y", "圆心 y"), value: $circle.cy, unit: "px")
            NumberField(title: L("Radius", "半径"), value: $circle.r, unit: "px")
        case .floor:
            NumberField(title: L("Floor line y", "地面线 y"), value: $floorY, unit: "px")
        case .ruler:
            NumberField(title: L("Known distance", "已知距离"), value: $ruler.cm, unit: "cm")
            Divider()
            NumberField(title: L("Start x", "起点 x"), value: $ruler.x1, unit: "px")
            NumberField(title: L("Start y", "起点 y"), value: $ruler.y1, unit: "px")
            NumberField(title: L("End x", "终点 x"), value: $ruler.x2, unit: "px")
            NumberField(title: L("End y", "终点 y"), value: $ruler.y2, unit: "px")
            Divider()
            InfoRow(key: L("Length on screen", "画面长度"), value: String(format: "%.0f px", ruler.pixels.finiteOr(0)))
            InfoRow(key: L("Scale", "比例"), value: ruler.pxPerCm.map { String(format: "%.2f px/cm", $0) } ?? "—")
        }
    }

    private var instruction: String {
        switch mode {
        case .circle:
            return L("Drag inside the circle to move it, drag its edge (or the handle) to resize. Match the inner rim of the cylinder floor.",
                     "在圆内拖动可移动，拖动圆边（或控制点）可调整大小。使其与圆筒底面内缘重合。")
        case .floor:
            return L("Drag the dashed line onto the cylinder floor.", "将虚线拖到圆筒底面位置。")
        case .ruler:
            return L("Drag both ends onto marks of a known distance (e.g. a ruler or the walkway width), then enter that distance.",
                     "将两端拖到已知距离的标记上（如标尺或步道宽度），然后输入该距离。")
        }
    }

    private var applyOption: some View {
        Toggle(isOn: $applyToOthers) {
            VStack(alignment: .leading, spacing: 2) {
                Text(otherTitle)
                Text(L("Same camera position only.", "仅限相机位置相同时。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(otherTargets.isEmpty)
        .help(L("Copy this calibration to the other analyses of this task (they are re-analysed)", "将此标定复制到该任务的其他分析（并重新分析）"))
    }

    private func applyTitle(_ n: Int) -> String {
        guard let s = session, let eid = store.recording(for: s)?.experimentID else {
            return String(format: L("Use this calibration for all analyses of this task outside tasks (%d)", "将此标定用于任务之外该任务的所有分析（%d 个）"), n)
        }
        let name = store.experiment(eid)?.name ?? L("this task", "本任务")
        return String(format: L("Use this calibration for all analyses of this task in “%@” (%d)", "将此标定用于任务“%@”中该任务的所有分析（%d 个）"), name, n)
    }

    /// Other analyses of the same task whose video is in the same study (or, outside studies, also outside).
    private func findOtherTargets(_ s: Session) -> [UUID] {
        let eid = store.recording(for: s)?.experimentID
        let studyOf = Dictionary(store.recordings.map { ($0.id, $0.experimentID) }, uniquingKeysWith: { a, _ in a })
        return store.sessions.filter { o in
            guard o.assay == s.assay, o.id != s.id, let rid = o.recordingID, let entry = studyOf[rid] else { return false }
            return entry == eid
        }.map(\.id)
    }

    // MARK: Loading

    private func setup() async {
        guard let s = session else { return }
        cameraView = s.params.cylinder.view
        switch s.assay {
        case .cylinder: mode = cameraView == .bottom ? .circle : .floor
        default: mode = .ruler
        }
        if let r = store.recording(for: s) { access = store.videoAccess(r) }
        videoMissing = access == nil
        let t = await store.pose(id)
        track = t
        if let t {
            videoSize = CGSize(width: max(1, t.width), height: max(1, t.height))
            duration = t.duration.finiteOr(0)
            sizeKnown = true
        } else if let size = s.videoSize {
            videoSize = size
            duration = (s.duration ?? 0).finiteOr(0)
            sizeKnown = true
        }
        resetGeometry(s)
        otherTargets = findOtherTargets(s)
        otherTitle = applyTitle(otherTargets.count)
        ready = true
        if s.calibration.circle == nil, mode == .circle, track != nil { autoCircle() }
        if s.calibration.floorY == nil, mode == .floor, track != nil { autoFloor() }
        frameTime = min(1, max(0, duration / 2))
        loadImage(at: frameTime, debounce: false)
    }

    /// The saved calibration, or a sensible start for this frame size.
    private func resetGeometry(_ s: Session) {
        let w = Double(videoSize.width), h = Double(videoSize.height)
        circle = s.calibration.circle ?? CircleCal(cx: w / 2, cy: h / 2, r: min(w, h) * 0.42)
        floorY = s.calibration.floorY ?? h * 0.85
        ruler = s.calibration.scale ?? ScaleCal(x1: w * 0.3, y1: h * 0.85, x2: w * 0.7, y2: h * 0.85, cm: 10)
    }

    private func loadImage(at t: Double, debounce: Bool) {
        guard let url = access?.url, t.isFinite, requestedTime != t else { return }
        requestedTime = t
        imageTask?.cancel()
        let offset = (track?.timeOffset ?? 0).finiteOr(0)
        let maxSize: CGFloat = sizeKnown ? 2048 : 0
        imageTask = Task { @MainActor in
            if debounce { try? await Task.sleep(nanoseconds: 80_000_000) }
            guard !Task.isCancelled else { return }
            let img = await FrameGrabber.image(url, scoped: false, at: max(0, t) + offset, maxSize: maxSize)
            guard !Task.isCancelled else { return }
            guard let img else {
                if requestedTime == t { requestedTime = nil }
                return
            }
            image = img
            shownTime = t
            if !sizeKnown {
                // Neither the pose nor the import gave the frame size: use the full-size frame.
                sizeKnown = true
                videoSize = CGSize(width: max(1, img.width), height: max(1, img.height))
                if let s = session, editCount == 0 { resetGeometry(s) }
            }
        }
    }

    // MARK: Auto-fit

    /// The fits sort every tracked keypoint of the video, so they run in the background; a drag
    /// made meanwhile wins over the result.
    private func autoCircle() {
        guard let t = track else { return }
        let edits = editCount
        fitting = true
        fitMessage = nil
        Task { @MainActor in
            let computed = await Task.detached(priority: .userInitiated) { CalibrationFit.circle(t) }.value
            fitting = false
            guard let fit = computed else {
                fitMessage = L("Not enough tracked keypoints to place the rim. Drag the circle instead.", "追踪到的关键点不足，无法放置圆筒边缘，请手动拖动圆圈。")
                return
            }
            guard edits == editCount else { return }
            withAnimation(Motion.gentle) { circle = fit }
        }
    }

    private func autoFloor() {
        guard let t = track else { return }
        let edits = editCount
        fitting = true
        fitMessage = nil
        Task { @MainActor in
            let computed = await Task.detached(priority: .userInitiated) { CalibrationFit.floor(t) }.value
            fitting = false
            guard let y = computed else {
                fitMessage = L("Not enough tracked hind paws to place the floor. Drag the line instead.", "追踪到的后爪不足，无法放置地面线，请手动拖动横线。")
                return
            }
            guard edits == editCount else { return }
            withAnimation(Motion.gentle) { floorY = y }
        }
    }

    // MARK: Saving

    private func save(all: Bool) {
        guard let s = session else { dismiss(); return }
        var cal = s.calibration
        cal.copiedFrom = nil
        switch mode {
        case .circle:
            cal.circle = CircleCal(cx: circle.cx.finiteOr(0), cy: circle.cy.finiteOr(0), r: max(1, circle.r.finiteOr(1)))
        case .floor:
            cal.floorY = floorY.finiteOr(0)
        case .ruler:
            cal.scale = ruler.pxPerCm != nil ? ruler : nil
        }
        let view = cameraView
        let saved = cal
        store.update(id) { x in
            x.calibration = saved
            if x.assay == .cylinder { x.params.cylinder.view = view }
        }
        if s.hasPose { store.analyze(id) }
        if all {
            var n = 0
            for oid in otherTargets {
                guard let o = store.session(oid) else { continue }
                var c = saved
                c.copiedFrom = s.displayName
                store.update(oid) { $0.calibration = c }
                if o.hasPose { store.analyze(oid, background: true) }
                n += 1
            }
            app.toast = String(format: L("Calibration used for %d more analyses", "标定已用于另外 %d 个分析"), n)
        }
        dismiss()
    }

    private func removeScale() {
        store.update(id) { $0.calibration.scale = nil }
        if session?.hasPose == true { store.analyze(id) }
        app.toast = L("Scale removed — lengths are in body lengths", "已移除标尺——长度以体长为单位")
        dismiss()
    }
}
