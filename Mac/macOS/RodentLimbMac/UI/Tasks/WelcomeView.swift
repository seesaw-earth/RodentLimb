// WelcomeView.swift — the page shown while the library has no task: what the app does in three
// steps and one button, New Task…. Videos dropped here open New Task first and are added to the
// task it creates.

import SwiftUI

@MainActor
struct WelcomeView: View {
    @Environment(AppModel.self) private var app

    private var steps: [(String, String)] {
        [
            (L("Choose the task", "选择任务"),
             L("Pick the paradigm — gait, cylinder, itch, pain, tail suspension, grooming or seizure — and name the groups.",
               "选择范式——步态、圆筒、瘙痒、疼痛、悬尾、理毛或癫痫——并为各组命名。")),
            (L("Add the videos", "添加视频"),
             L("Drop videos or folders. Each video gets its animal, group and timepoint from its file name; you can correct them before adding.",
               "拖入视频或文件夹。每段视频会根据文件名填写动物、组别和时间点，添加前可以修改。")),
            (L("Review and compare", "复核与比较"),
             L("Videos are tracked in the background and checked for quality. Results appear by group, ready to export.",
               "视频在后台识别并做质量检查，结果按组显示，可直接导出。")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RodentLimb").font(.largeTitle.weight(.bold))
                    Text(L("Pose-based behaviour analysis for mouse experiments.", "基于姿态识别的小鼠行为分析。"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(i + 1)")
                                .font(.title2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.0).font(.headline)
                                Text(step.1).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button {
                        app.newTaskRequest = NewTaskRequest()
                    } label: {
                        Text(L("New Task…", "新建任务…")).frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text(L("or drop videos on the window", "或将视频拖入窗口"))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                if !PoseModelLoader.isInstalled {
                    Banner(text: PoseRunError.modelMissing.errorDescription ?? "", level: .error)
                }
                if !app.store.recordings.isEmpty {
                    let outside = app.store.recordingsNotInTask.count
                    if outside > 0 {
                        HStack {
                            Text(String(format: L("%d video(s) in this library are not in a task yet.", "资料库中有 %d 段视频尚未归入任务。"), outside))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button(L("Show", "查看")) { app.show(.unassigned) }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.canvas)
    }
}

/// Videos in no task, and studies from earlier versions without a paradigm (each can become a task).
@MainActor
struct UnassignedPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            let studies = app.store.studiesWithoutTask
            if !studies.isEmpty {
                CappedScroll(maxHeight: 220) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Studies without a paradigm", "尚无范式的研究"))
                        .font(.headline)
                    Text(L("Made with an earlier version. Choose the paradigm of each to turn it into a task (its videos get that task's sessions).",
                           "由早期版本创建。为每个研究选择范式即可变为任务（其视频会获得该任务的会话）。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(studies) { e in
                        HStack {
                            Text(e.name.isEmpty ? L("Untitled study", "未命名研究") : e.name).fontWeight(.medium)
                            Text(String(format: L("%d videos", "%d 段视频"), app.store.recordings(in: e.id).count))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Menu(L("Make Task", "设为任务")) {
                                ForEach(Assay.allCases) { a in
                                    Button(a.name.text) {
                                        app.store.setParadigm(a, for: e.id)
                                        app.show(.task(TaskRef(experimentID: e.id, assay: a)))
                                    }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Palette.inset)
                Divider()
            }
            RecordingsPage(filter: .unassigned)
        }
    }
}
