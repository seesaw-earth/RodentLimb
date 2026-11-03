// AnalysisTabs.swift — the Summary and Measures tabs of an analysis, the "waiting for tracking"
// state, and the coarse playback clock shared by the Review tab's charts and event list.
//   Summary  — the 2–4 numbers that matter, notes, the one key chart
//   Measures — every measure, grouped, the detailed charts, how the result was made
// (Review is in AnalysisReviewTab.swift.)

import SwiftUI
import AppKit

/// The three tabs of an analysis page (same as the iPhone app).
enum AnalysisDetailTab: String, CaseIterable, Identifiable {
    case summary, review, measures
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return L("Summary", "概览")
        case .review: return L("Review", "回放")
        case .measures: return L("Measures", "全部指标")
        }
    }
}

/// Low-rate copy of the player's time (≈ 5 Hz) for views that only need to know roughly where
/// playback is (playheads, the event under the playhead, the gait window), so charts are never
/// redrawn at the player's rate. The analysis page holds it without observing it.
@MainActor
final class ResultsPlaybackClock: ObservableObject {
    @Published private(set) var time: Double = 0

    func set(_ t: Double) {
        guard t.isFinite, abs(t - time) > 0.004 else { return }
        time = t
    }
}

/// Re-renders only its content when the coarse clock ticks.
@MainActor
struct ResultsClockReader<Content: View>: View {
    @ObservedObject var clock: ResultsPlaybackClock
    @ViewBuilder var content: (Double) -> Content
    var body: some View { content(clock.time) }
}

// MARK: - Summary

@MainActor
struct AnalysisSummaryTab: View {
    let session: Session
    let result: AnalysisResult
    /// Go to the Review tab at a track time.
    let goReview: (Double) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let highlights = result.metrics.filter { $0.highlight }
                if !highlights.isEmpty {
                    HeroMetrics(metrics: highlights, tint: Palette.assay(session.assay))
                }
                NoteList(notes: result.notes)
                keyCharts
            }
            .padding(.vertical, 18)
            .pageContent()
        }
    }

    @ViewBuilder
    private var keyCharts: some View {
        if let d = result.tst {
            TSTMotionCard(detail: d, seek: goReview)
        }
        if let d = result.cylinder {
            CylinderUseCard(detail: d)
        }
        if let d = result.gait {
            FootfallCard(detail: d)
            if let p = d.patterns, !p.isEmpty { GaitPatternCard(patterns: p) }
        }
        if let d = result.behavior {
            BehaviorEthogramCard(detail: d, seek: goReview)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                BehaviorTimeCourseCard(detail: d, tint: Palette.assay(session.assay))
                if session.assay == .grooming {
                    BehaviorCompositionCard(detail: d, title: L("Grooming by body region", "各身体部位理毛时间"))
                }
            }
        }
    }
}

// MARK: - Measures

@MainActor
struct AnalysisMeasuresTab: View {
    let session: Session
    let result: AnalysisResult
    let goReview: (Double) -> Void

    @Environment(AppModel.self) private var app

    private var poseModel: PoseModelID { session.recordingID.map { app.store.poseModel($0) } ?? .visible }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(title: L("All measures", "全部指标"))
                    Button {
                        copyMeasures()
                    } label: {
                        Text(L("Copy", "拷贝"))
                    }
                    .controlSize(.small)
                    .help(L("Copy every measure as tab-separated text (paste into a spreadsheet)", "以制表符分隔文本拷贝全部指标（可粘贴到表格）"))
                }
                MeasureList(metrics: result.metrics)
                    .frame(maxWidth: 680, alignment: .leading)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    detailCards
                }
                footer
            }
            .padding(.vertical, 18)
            .pageContent()
        }
    }

    @ViewBuilder
    private var detailCards: some View {
        if let d = result.tst {
            TSTPerMinuteCard(detail: d)
        }
        if let d = result.cylinder {
            CylinderTimelineCard(detail: d, seek: goReview)
        }
        if let d = result.gait {
            PawTableCard(detail: d)
            PhaseCard(detail: d)
            FootprintCard(detail: d, videoSize: session.videoSize ?? CGSize(width: 1920, height: 1080))
        }
        if let d = result.behavior {
            BehaviorTimeCourseCard(detail: d, tint: Palette.assay(session.assay))
            if session.assay != .seizure {
                BehaviorCompositionCard(detail: d, title: L("Time per behavior (analysis window)", "各行为时间（分析窗口内）"))
            }
            BehaviorSignalCard(detail: d, seek: goReview)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(format: L("Model %@ (%@) · %@ · pose coverage %@ · analyzed %@", "模型 %@（%@）· %@ · 姿态覆盖率 %@ · 分析于 %@"),
                        poseModel.displayName + " · " + poseModel.shortTitle.text, session.modelVersion ?? "—", Fmt.fps(session.fps),
                        Fmt.percent(result.poseCoverage), Fmt.date(result.analyzedAt)))
            if let from = session.calibration.copiedFrom, !from.isEmpty {
                Text(String(format: L("Calibration copied from %@.", "标定沿用自 %@。"), from))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(.top, 4)
    }

    /// Tab-separated measures (English labels, like the exports).
    private func copyMeasures() {
        var lines = ["measure\tvalue\tunit"]
        for m in result.metrics { lines.append("\(m.label.en)\t\(m.exportValue)\t\(m.unit)") }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
        app.toast = L("Measures copied", "已拷贝指标")
    }
}

// MARK: - Waiting for tracking

/// Shown while the video of the analysis is queued or being tracked. Only this view observes the
/// batch progress, so the rest of the page does not redraw several times a second.
@MainActor
struct AnalysisTrackingStatus: View {
    let recordingID: UUID?
    @Environment(AppModel.self) private var app

    var body: some View {
        let batch = app.batch
        let job = recordingID.flatMap { batch.jobs[$0] }
        let queuedCount = app.store.queuedCount
        let position = recordingID.flatMap { app.store.queuePosition(of: $0) }
        let offline = recordingID.map { app.store.missingVideos.contains($0) } ?? false
        VStack(spacing: 14) {
            ZStack {
                ProgressRing(fraction: job?.fraction ?? 0, lineWidth: 6)
                if let job {
                    Text(Fmt.percent(job.fraction)).font(.title3.weight(.semibold).monospacedDigit())
                } else {
                    Text(offline ? L("Offline", "离线") : L("Waiting", "等待"))
                        .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            Text(title(job)).font(.title3.weight(.semibold))
            // Changes several times a second (position, time left): a fixed three-line height, so the
            // page does not change height on every update.
            Text(detail(job, position: position, count: queuedCount, offline: offline))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3, reservesSpace: true)
            HStack(spacing: 10) {
                Button {
                    app.show(.queue)
                } label: {
                    Text(L("Show Processing Queue", "显示处理队列"))
                }
                if job == nil && !batch.isActive && !offline {
                    Button {
                        batch.start()
                    } label: {
                        Text(L("Start Tracking", "开始识别"))
                    }
                    .keyboardShortcut(.defaultAction)
                }
                if offline, let rid = recordingID {
                    Button(L("Locate Video…", "定位视频…")) { app.locateVideo(rid) }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 480)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func title(_ job: BatchEngine.Job?) -> String {
        guard let job else { return L("Waiting for tracking", "等待识别") }
        switch job.phase {
        case .opening: return L("Opening the video…", "正在打开视频…")
        case .tracking: return L("Tracking every frame", "正在逐帧识别")
        case .finishing: return L("Saving the pose and checking quality…", "正在保存姿态并检查质量…")
        }
    }

    private func detail(_ job: BatchEngine.Job?, position: Int?, count: Int, offline: Bool) -> String {
        if let job {
            var parts: [String] = []
            if job.framesTotal > 0 {
                parts.append(String(format: L("Frame %d of about %d", "第 %d 帧，共约 %d 帧"), job.framesDone, job.framesTotal))
            }
            parts.append(Fmt.remaining(job.secondsLeft))
            return parts.joined(separator: " · ") + "\n" +
                L("The results appear here as soon as the pose is ready.", "姿态就绪后，结果会立即显示在这里。")
        }
        if offline {
            return L("The video is offline (the drive is not connected or the file moved). It waits in the queue until the file is back.",
                     "视频离线（磁盘未连接或文件已移动），将在队列中等待，直到文件可用。")
        }
        var text: String
        if let position {
            text = String(format: L("Position %d of %d in the queue.", "队列中第 %d 个，共 %d 个。"), position + 1, max(count, position + 1))
        } else {
            text = L("The pose model has not run on this video yet.", "该视频尚未运行姿态模型。")
        }
        switch app.batch.state {
        case .paused: text += " " + L("Tracking is paused.", "识别已暂停。")
        case .lowDisk: text += " " + L("Tracking is paused: the library's disk is almost full.", "识别已暂停：资料库所在磁盘空间不足。")
        case .waitingForModel(let message): text += " " + message
        case .idle, .running: break
        }
        return text
    }
}
