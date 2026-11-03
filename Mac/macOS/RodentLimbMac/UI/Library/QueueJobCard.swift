// QueueJobCard.swift — the videos being tracked right now, one card each: live frame with the
// detected keypoints, phase, progress, frames, speed, time left, "resumed from checkpoint", Cancel.
//
// Redraw budget: BatchEngine updates `jobs` several times per second and `previews` about once per
// second. Only the views in this file read them (QueueRunningSection for the list of cards, one
// QueueJobCard per job, QueueJobPreview for the picture), so the queue table and the header around
// them are not rebuilt on every progress tick.

import SwiftUI

/// Grid of running videos (nothing when none runs).
@MainActor
struct QueueRunningSection: View {
    /// The cards scroll beyond this height (several videos on a small window).
    var maxHeight: CGFloat = .infinity
    @Environment(AppModel.self) private var app

    var body: some View {
        let ids = app.batch.jobs.values
            .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
            .map(\.id)
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(ids.count == 1 ? L("Tracking now", "正在识别") : String(format: L("Tracking %d videos now", "正在识别 %d 个视频"), ids.count))
                    .font(.headline)
                CappedScroll(maxHeight: maxHeight) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 600), spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(ids, id: \.self) { id in
                            QueueJobCard(id: id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
        }
    }
}

/// One running video.
@MainActor
struct QueueJobCard: View {
    let id: UUID
    @Environment(AppModel.self) private var app

    var body: some View {
        if let job = app.batch.jobs[id] {
            HStack(alignment: .top, spacing: 12) {
                QueueJobPreview(id: id)
                    .frame(width: 176, height: 118)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(job.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button(L("Cancel", "取消")) {
                            app.batch.cancel(id)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help(L("Cancel this video. Its progress is kept: Retry continues from where it stopped.",
                                "取消该视频。进度会保留：“重试”将从中断处继续。"))
                        .accessibilityLabel(L("Cancel", "取消"))
                    }
                    Text(Self.phaseText(job.phase) + " · " + app.store.poseModel(id).shortTitle.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: min(1, max(0, job.fraction)))
                    HStack {
                        Text(Self.framesText(job)).monospacedDigit()
                        Spacer(minLength: 8)
                        Text(Fmt.fps(job.fps)).monospacedDigit()
                            .help(L("Frames analysed per second", "每秒分析的帧数"))
                    }
                    .font(.caption)
                    Text(job.phase == .opening ? " " : Fmt.remaining(job.secondsLeft))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if job.resumedFrames > 0 {
                        Text(String(format: L("Resumed from checkpoint at %@ frames", "已从检查点第 %@ 帧继续"), job.resumedFrames.formatted()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(L("This video was tracked before (pause, quit or an unexpected stop); the frames already done were kept.",
                                    "该视频之前已识别过一部分（暂停、退出或意外中断），已完成的帧已保留。"))
                    }
                }
            }
            .padding(12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { app.open(.recording(id)) }
            .contextMenu {
                Button(L("Open Video Page", "打开视频页面")) { app.open(.recording(id)) }
                Divider()
                Button(L("Cancel This Video", "取消该视频")) { app.batch.cancel(id) }
            }
        }
    }

    static func phaseText(_ p: RunProgress.Phase) -> String {
        switch p {
        case .opening: return L("Opening the video…", "正在打开视频…")
        case .tracking: return L("Detecting pose", "姿态识别中")
        case .finishing: return L("Saving the pose and checking quality…", "正在保存姿态并检查质量…")
        }
    }

    static func framesText(_ j: BatchEngine.Job) -> String {
        guard j.framesTotal > 0 else { return L("Counting frames…", "正在统计帧数…") }
        return String(format: L("%@ / %@ frames", "%@ / %@ 帧"), j.framesDone.formatted(), j.framesTotal.formatted())
    }
}

/// The frame being analysed (about once per second) with the keypoints found in it.
@MainActor
struct QueueJobPreview: View {
    let id: UUID
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.showSkeleton) private var showSkeleton = true

    var body: some View {
        let snap = app.batch.previews[id]
        ZStack {
            Color.black
            if let snap {
                Canvas { ctx, size in
                    QueueJobPreview.draw(snap, in: ctx, size: size, skeleton: showSkeleton)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .environment(\.colorScheme, .dark)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(L("Live preview with the detected keypoints", "实时预览及检测到的关键点"))
    }

    /// Picture aspect-fit in the box; keypoints (display-frame pixels) scaled from the frame size.
    static func draw(_ s: PreviewSnapshot, in ctx: GraphicsContext, size: CGSize, skeleton: Bool) {
        let frame = CGSize(width: max(1, s.frameWidth), height: max(1, s.frameHeight))
        let rect = aspectFitRect(frame, in: size)
        if let img = s.image {
            ctx.draw(Image(decorative: img, scale: 1), in: rect)
        }
        guard skeleton, rect.width > 0, rect.height > 0 else { return }
        let sx = rect.width / frame.width
        let sy = rect.height / frame.height
        func point(_ k: Kp) -> CGPoint? {
            let i = k.rawValue
            guard s.keypoints.indices.contains(i), let p = s.keypoints[i],
                  p.x.isFinite, p.y.isFinite, p.x >= 0, p.y >= 0 else { return nil }
            return CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy)
        }
        for (a, b) in Kp.bones {
            guard let p = point(a), let q = point(b) else { continue }
            var path = Path()
            path.move(to: p)
            path.addLine(to: q)
            ctx.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.5)
        }
        for k in Kp.allCases {
            guard let c = point(k) else { continue }
            let r: CGFloat = 3.5
            let dot = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: dot), with: .color(KeypointColors.color(k)))
            ctx.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 1)
        }
    }
}
