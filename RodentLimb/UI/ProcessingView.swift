// ProcessingView.swift — the Processing tab: the video being tracked (progress, time left, model),
// the videos waiting, failed videos (try again), and — when everything is tracked — what to do next
// instead of an empty page. Pausing, leaving the app or a crash loses nothing: a video continues
// from where it stopped, or is tracked again from the start.

import SwiftUI

@MainActor
struct ProcessingView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @EnvironmentObject private var engine: PoseEngine

    var body: some View {
        NavigationStack(path: $app.processingPath) {
            let queued = store.queuedRecordings.filter { $0.id != queue.currentID }
            let failed = store.recordings.filter { $0.status == .failed }
            let names = store.taskNames(store.tasks)
            List {
                if let id = queue.currentID, let r = store.recording(id) {
                    Section { CurrentJobRow(recording: r, names: names) } header: { Text(L("Tracking now", "正在识别")) }
                } else if queue.pausedForBackground {
                    Section {
                        Text(L("Tracking paused while RodentLimb was in the background. It resumes by itself.",
                               "RodentLimb 在后台时暂停了识别，回到前台后会自动继续。"))
                            .font(.subheadline)
                    }
                }
                if !queued.isEmpty {
                    Section {
                        ForEach(queued.prefix(200)) { r in
                            NavigationLink(value: Route.recording(r.id)) { QueueRow(recording: r, names: names) }
                        }
                    } header: {
                        Text(String(format: L("Waiting (%d)", "等待中（%d）"), queued.count))
                    } footer: {
                        Text(L("Videos are tracked one after another in the order they were added. Keep the app open; if you leave it, tracking pauses and continues from the same frame.",
                               "视频按添加顺序依次识别。请保持 App 在前台；离开时会暂停，回来后从中断的那一帧继续。"))
                    }
                }
                if !failed.isEmpty {
                    Section {
                        ForEach(failed) { r in
                            NavigationLink(value: Route.recording(r.id)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.displayName(r)).font(.body.weight(.semibold))
                                    Text(r.failure ?? L("Tracking failed.", "识别失败。"))
                                        .font(.footnote).foregroundStyle(Palette.danger).lineLimit(3)
                                }
                            }
                            .swipeActions {
                                Button(L("Try again", "重试")) { queue.retry(recording: r.id) }.tint(.accentColor)
                            }
                        }
                        Button(L("Try all again", "全部重试")) {
                            for r in failed { queue.retry(recording: r.id) }
                        }
                    } header: {
                        Text(String(format: L("Failed (%d)", "失败（%d）"), failed.count))
                    }
                }
                if queue.currentID == nil && queued.isEmpty {
                    FinishedSections()
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("Processing", "处理"))
            .routeDestinations()
        }
    }
}

/// The video being tracked.
@MainActor
private struct CurrentJobRow: View {
    let recording: Recording
    let names: [TaskRef: String]
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { app.openRecording(recording.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.displayName(recording)).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            LiveProgress(progress: queue.progress) { p in
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: p.fraction)
                    HStack {
                        Text(String(format: "%.0f%%", p.fraction * 100)).monospacedDigit()
                        Spacer()
                        if p.framesPerSecond > 0 {
                            Text(String(format: L("%.0f frames/s", "%.0f 帧/秒"), p.framesPerSecond)).monospacedDigit()
                        }
                        Text(Fmt.remaining(p.secondsLeft)).monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            Button(L("Cancel", "取消"), role: .destructive) { queue.cancelCurrent() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let t = store.currentTask(of: recording.id) { parts.append(names[t] ?? t.assay.name.text) }
        parts.append(store.poseModel(recording.id).runnable.displayName)
        return parts.joined(separator: " · ")
    }
}

@MainActor
private struct QueueRow: View {
    let recording: Recording
    let names: [TaskRef: String]
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.displayName(recording)).font(.body.weight(.medium)).lineLimit(1)
            Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let t = store.currentTask(of: recording.id) {
            parts.append(names[t] ?? t.assay.name.text)
        } else {
            parts.append(L("Not in a task", "未归入任务"))
        }
        parts.append(store.poseModel(recording.id).runnable.displayName)
        return parts.joined(separator: " · ")
    }
}

/// Everything is tracked: what is left to do, instead of an empty page.
@MainActor
private struct FinishedSections: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        let tracked = store.recordings.filter(\.isProcessed).count
        let review = store.recordings.filter { store.needsReview($0) }.count
        let unassigned = store.unassignedRecordings.count
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.recordings.isEmpty ? L("Nothing to track", "没有待识别的视频") : L("All videos are tracked", "全部视频已识别"))
                    .font(.headline)
                Text(store.recordings.isEmpty
                     ? L("Add videos inside a task. They are tracked here one after another, in the background, and progress is kept if you leave the app.",
                         "请在任务中添加视频。视频会在这里依次识别，离开 App 时进度会保留。")
                     : String(format: L("%d videos tracked. Results update in their tasks as soon as each video is checked.",
                                        "已识别 %d 段视频。每段视频检查完成后，结果会立即在其任务中更新。"), tracked))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            if review > 0 {
                NavigationLink(value: Route.needsReview) {
                    CountRow(title: L("Review tracking quality", "检查追踪质量"), count: review, color: Palette.warning)
                }
            }
            if unassigned > 0 {
                NavigationLink(value: Route.unassigned) {
                    CountRow(title: L("Videos not in a task", "未归入任务的视频"), count: unassigned)
                }
            }
            if store.recordings.isEmpty || store.tasks.isEmpty {
                Button(L("New Task", "新建任务")) { app.showNewTask = true }
            } else {
                Button(L("Open Tasks", "打开任务")) { app.tab = .tasks }
            }
        } header: {
            Text(L("Next steps", "下一步"))
        }
    }
}
