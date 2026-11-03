// RecordingDetailQC.swift — the tracking-quality part of the video page, ported from the iPhone app:
// the QC summary (verdict, key numbers, coverage along the video, issues), per-keypoint coverage
// with the "frames to label" export, the QC player (raw keypoints with the lost stretches on the
// timeline and buttons to jump between them) and the guide to untracked frames.

import SwiftUI

// MARK: - Summary

@MainActor
struct RecordingDetailQCSummaryCard: View {
    let qc: QCReport

    var body: some View {
        Card {
            CardHeader(title: L("Tracking quality (QC)", "追踪质量（QC）"), symbol: "checkmark.seal",
                       subtitle: String(format: L("%@ · %@ · %d frames", "%@ · %@ · %d 帧"),
                                        Fmt.fps(qc.fps), Fmt.clock(qc.duration), qc.frames)) {
                QCBadge(report: qc)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                stat(L("Mouse tracked", "小鼠可用帧"), Fmt.percent(qc.coreCoverage),
                     L("Nose and tail base usable after filling short gaps", "填补短缺口后鼻尖与尾根均可用"))
                stat(L("Mouse detected", "检测到小鼠"), Fmt.percent(qc.detection),
                     L("Frames in which the model found the mouse at all", "模型检测到小鼠的帧"))
                stat(L("Longest loss", "最长丢失"), String(format: L("%.1f s", "%.1f 秒"), qc.longestLost.finiteOr(0)),
                     L("Longest stretch without the mouse", "连续丢失小鼠的最长时段"))
                stat(L("Gaps filled", "可填补缺失"), Fmt.percent(qc.recoverable),
                     L("Share of missing keypoints recovered by short-gap filling", "短缺口填补可恢复的缺失关键点比例"))
                stat(L("Implausible jumps", "不合理跳点"), Fmt.percent(qc.jumpRate, 1),
                     L("Frames with a keypoint leaping away and back (wrong detection or left/right swap)", "关键点跳开又跳回的帧（误检或左右互换）"))
                stat(L("Body length", "体长"), qc.bodyLength.map { String(format: "%.0f px", $0.finiteOr(0)) } ?? "—",
                     L("Median nose–tail-base distance", "鼻尖到尾根距离的中位数"))
            }
            RecordingsQCTimeline(timeline: qc.timeline, height: 18)
            Text(L("Tracking along the video: green = mouse tracked, red = lost.", "沿视频的追踪情况：绿 = 已追踪，红 = 丢失。"))
                .font(.caption).foregroundStyle(.secondary)
            NoteList(notes: qc.issues)
            Text(String(format: L("Computed %@", "计算于 %@"), Fmt.date(qc.computedAt)))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func stat(_ title: String, _ value: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .textSelection(.enabled)
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Per-keypoint coverage

@MainActor
struct RecordingDetailQCDetailCard: View {
    let qc: QCReport
    var exporting = false
    let exportFrames: () -> Void

    var body: some View {
        Card {
            CardHeader(L("Keypoint coverage", "各关键点覆盖率"), symbol: "chart.bar.xaxis",
                       subtitle: L("Dark bar: tracked by the model. Light bar: after filling short gaps.",
                                   "深色：模型识别到的帧；浅色：填补短缺口之后。"))
            ForEach(Kp.allCases) { k in
                let raw = k.rawValue < qc.rawCoverage.count ? qc.rawCoverage[k.rawValue].finiteOr(0) : 0
                let filled = k.rawValue < qc.filledCoverage.count ? qc.filledCoverage[k.rawValue].finiteOr(0) : 0
                HStack(spacing: 8) {
                    Circle().fill(KeypointColors.color(k)).frame(width: 8, height: 8)
                    Text(k.label.text).font(.callout).frame(width: 110, alignment: .leading).lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.inset)
                            Capsule().fill(KeypointColors.color(k).opacity(0.35))
                                .frame(width: geo.size.width * CGFloat(max(0, min(1, filled))))
                            Capsule().fill(KeypointColors.color(k))
                                .frame(width: geo.size.width * CGFloat(max(0, min(1, raw))))
                        }
                    }
                    .frame(height: 10)
                    Text(Fmt.percent(filled)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .help(String(format: L("%@: tracked in %@ of frames, %@ after filling short gaps", "%@：模型识别 %@ 的帧，填补短缺口后 %@"),
                             k.label.text, Fmt.percent(raw), Fmt.percent(filled)))
                .accessibilityElement(children: .combine)
            }
            Divider()
            InfoRow(key: L("Untracked stretches (longer than the gap limit)", "未追踪片段（超过可填补长度）"), value: "\(qc.longGaps)")
            InfoRow(key: L("Lost stretches ≥ 0.5 s", "≥ 0.5 秒的丢失片段"), value: "\(qc.lostSegments.count)")
            InfoRow(key: L("Body length variability (CV)", "体长变异系数"), value: qc.bodyLengthCV.map { Fmt.percent($0) } ?? "—")
            InfoRow(key: L("Frame timing irregularity", "帧间隔不规则度"), value: Fmt.percent(qc.timingCV))
            HStack(spacing: 8) {
                Button(action: exportFrames) {
                    Text(L("Export Frames to Label…", "导出待标注帧…"))
                }
                .disabled(exporting)
                if exporting { ProgressView().controlSize(.small) }
            }
            Text(L("Lists untracked stretches and low-confidence frames (CSV: frame, time, reason), for labelling them and refining the model — as with DeepLabCut's outlier frames.",
                   "列出未追踪片段和低置信度帧（CSV：帧号、时间、原因），可用于补充标注、重新训练模型——同 DeepLabCut 的 outlier frames。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - QC player

/// The video with every keypoint the model found (no gap filling, faint below the threshold) and
/// the stretches where the mouse was lost on the timeline.
///
/// The card does not follow the playhead: only the player and the previous / next buttons do (the
/// controller publishes the time ten times a second; the header, the menu of up to 100 stretches and
/// the timeline marks are not rebuilt for that).
@MainActor
struct RecordingDetailQCPlayer: View {
    let controller: PlayerController
    let track: PoseTrack
    let lost: [Interval]
    var threshold: Double = CommonParams().keypointThreshold

    private var decorations: PlayerDecorations {
        var d = PlayerDecorations()
        d.marks = lost.map { TimelineMark(start: $0.start, end: $0.end, color: Palette.danger) }
        d.markRows = 1
        let segments = lost
        d.chips = { t in
            segments.contains { t >= $0.start && t < $0.end }
                ? [OverlayChip(text: L("Mouse lost", "小鼠丢失"), color: Palette.danger)] : []
        }
        return d
    }

    var body: some View {
        Card {
            CardHeader(L("Video with the raw keypoints", "视频与原始关键点"), symbol: "play.rectangle",
                       subtitle: L("Everything the model found, also below the confidence threshold (faint). Red on the bar: the mouse was lost — click to jump. Space plays, ← → step one frame.",
                                   "显示模型识别到的全部关键点，低于置信度阈值的以浅色显示。进度条上的红色：小鼠丢失，点击可跳转。空格播放，← → 逐帧。"))
            ReviewPlayer(controller: controller, track: track, threshold: threshold, decorations: decorations,
                         showRaw: true, maxHeight: 480)
            HStack(spacing: 8) {
                LostStretchButtons(controller: controller, lost: lost)
                Spacer()
                if lost.isEmpty {
                    Text(L("No lost stretch ≥ 0.5 s", "没有 ≥ 0.5 秒的丢失片段"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(Array(lost.prefix(100).enumerated()), id: \.offset) { item in
                            Button(Fmt.clockPrecise(item.element.start) + "  ("
                                   + String(format: L("%.1f s", "%.1f 秒"), item.element.duration.finiteOr(0)) + ")") {
                                controller.seek(item.element.start)
                            }
                        }
                    } label: {
                        Text(String(format: L("%d lost", "%d 段丢失"), lost.count))
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .help(L("Jump to an untracked stretch", "跳到丢失片段"))
                }
            }
            .controlSize(.small)
        }
    }
}

/// Previous / Next Lost Stretch: the only part of the QC card that follows the playhead.
@MainActor
private struct LostStretchButtons: View {
    @ObservedObject var controller: PlayerController
    let lost: [Interval]

    var body: some View {
        let t = controller.time
        let previous = lost.last { $0.start < t - 0.05 }
        let next = lost.first { $0.start > t + 0.05 }
        Button {
            if let p = previous { controller.seek(p.start) }
        } label: {
            Text(L("Previous Lost Stretch", "上一个丢失片段"))
        }
        .disabled(previous == nil)
        .help(L("Jump to the previous stretch where the mouse was lost", "跳到上一个小鼠丢失的片段"))
        Button {
            if let n = next { controller.seek(n.start) }
        } label: {
            Text(L("Next Lost Stretch", "下一个丢失片段"))
        }
        .disabled(next == nil)
        .help(L("Jump to the next stretch where the mouse was lost", "跳到下一个小鼠丢失的片段"))
    }
}

// MARK: - Guide

/// What the app does with untracked frames, and what the user can do.
@MainActor
struct RecordingDetailMissingFramesGuide: View {
    @State private var expanded = false

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    item("1", L("Low-confidence keypoints are treated as missing (confidence threshold, Parameters › Pose cleaning).",
                                "低置信度关键点视为缺失（置信度阈值，见 参数 › 姿态预处理）。"))
                    item("2", L("Implausible jumps — a keypoint leaping away from where the neighbouring frames put it, often a wrong detection or a left/right swap — can be removed as well (off by default).",
                                "不合理跳点——关键点偏离相邻帧给出的位置，通常是误检或左右互换——也可以剔除（默认关闭）。"))
                    item("3", L("Only short gaps are filled (default ≤ 0.25 s): linear, shape-preserving cubic, body-relative (moves the hidden paw with the body) or a Kalman smoother. Longer gaps are left missing and excluded from every measure — reconstructing them would invent behaviour.",
                                "只填补短缺口（默认 ≤ 0.25 秒）：线性、三次保形、身体相对坐标（被遮挡的爪随身体移动）或 Kalman 平滑。更长的缺口保持缺失、不参与任何指标——重建它们等于凭空制造行为。"))
                    item("4", L("Each task reports how much of its window was tracked; behaviour in untracked frames is not counted.",
                                "每个任务都会报告分析窗口内的追踪比例；未追踪帧中的行为不计入。"))
                    item("5", L("If too much is missing, fix the cause: camera view, light, a clean transparent floor, ≥ 30–60 fps; lower the detection threshold in Settings and re-run tracking.",
                                "缺失过多时应从源头解决：拍摄视角、光照、干净的透明底面、≥ 30–60 fps；也可在“设置”中降低检测阈值后重新识别。"))
                    item("6", L("Label the exported frames and retrain the model so it learns these situations (active learning).",
                                "标注导出的帧并重新训练模型，让模型学会这些情况（主动学习）。"))
                    item("7", L("Exclude the video when it fails the task's criteria set in advance, and report the reason.",
                                "若视频未达到任务事先设定的标准，予以排除并报告原因。"))
                }
                .padding(.top, 8)
            } label: {
                Text(L("What can be done about untracked frames?", "追踪不到的帧怎么办？"))
                    .font(.callout.weight(.semibold))
            }
        }
    }

    private func item(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
