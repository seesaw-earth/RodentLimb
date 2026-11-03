// RecordingDetailInfo.swift — the editable design information of one video on its page: study,
// animal, group (outside a study), timepoint, trial, recording date and notes, plus read-only video
// facts. Every change is saved at once through the store, which mirrors it into the video's
// analyses. Text fields commit on Return or when they lose focus.

import SwiftUI

@MainActor
struct RecordingDetailInfoCard: View {
    let recordingID: UUID
    @Environment(AppModel.self) private var app

    var body: some View {
        let store = app.store
        if let r = store.recording(recordingID) {
            let e = store.experiment(for: r)
            Card {
                CardHeader(L("Video info", "视频信息"), symbol: "info.circle",
                           subtitle: L("Changes are saved at once and copied into every analysis of this video.",
                                       "修改会立即保存，并同步到该视频的所有分析。"))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        label(L("Task", "任务"))
                        HStack(spacing: 8) {
                            let titles = store.tasks.filter { $0.experimentID == r.experimentID }.map { store.taskTitle($0) }
                            Text(titles.isEmpty ? L("Not in a task", "未归入任务") : titles.joined(separator: ", "))
                                .foregroundStyle(titles.isEmpty ? .secondary : .primary)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Button(L("Move…", "移动…")) { app.assignRequest = AssignRequest(recordings: [recordingID]) }
                                .controlSize(.small)
                                .disabled(e?.blinded == true)
                        }
                    }
                    GridRow {
                        label(L("Animal", "动物"))
                        if e?.blinded == true {
                            HStack(spacing: 4) {
                                Text(store.subjectLabel(r)).textSelection(.enabled)
                                Text(L("blinded", "盲法")).font(.caption).foregroundStyle(.secondary)
                                    .help(L("The task is blinded: the animal is shown by its blind code.", "任务处于盲态：动物以盲码显示。"))
                            }
                        } else {
                            RecordingDetailCommitField(prompt: L("Animal ID", "动物编号"),
                                                       value: e.flatMap { $0.animal(r.animalID)?.code } ?? r.subject) { code in
                                store.setAnimal(recordingID, code: code)
                            }
                        }
                    }
                    if e == nil {
                        GridRow {
                            label(L("Group", "组别"))
                            RecordingDetailCommitField(prompt: L("Group", "组别"), value: r.group) { g in
                                store.updateRecording(recordingID) { $0.group = g }
                            }
                        }
                    } else if e?.blinded != true, let e, let a = e.animal(r.animalID) {
                        GridRow {
                            label(L("Group", "组别"))
                            Text(e.groupLabel(a).isEmpty ? L("Not allocated", "未分组") : e.groupLabel(a))
                                .foregroundStyle(.secondary)
                                .help(L("Groups are set in the task's animal list.", "组别在任务的动物列表中设置。"))
                        }
                    }
                    GridRow {
                        label(L("Timepoint", "时间点"))
                        timepointControl(r, e)
                    }
                    GridRow {
                        label(L("Trial", "试次"))
                        Stepper(value: Binding(get: { r.trial },
                                               set: { v in store.updateRecording(recordingID) { $0.trial = max(1, min(999, v)) } }),
                                in: 1...999) {
                            Text("\(r.trial)").monospacedDigit()
                        }
                    }
                    GridRow {
                        label(L("Recorded", "录制于"))
                        HStack(spacing: 6) {
                            Toggle(L("Known", "已知"), isOn: Binding(
                                get: { r.recordedOn != nil },
                                set: { on in store.updateRecording(recordingID) { $0.recordedOn = on ? ($0.recordedOn ?? $0.createdAt) : nil } }))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .help(L("Whether the recording date is known", "是否已知录制日期"))
                            if let d = r.recordedOn {
                                DatePicker(L("Recorded on", "录制于"), selection: Binding(
                                    get: { d },
                                    set: { new in store.updateRecording(recordingID) { $0.recordedOn = new } }),
                                           displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                            } else {
                                Text(L("Not set", "未设置")).foregroundStyle(.secondary)
                            }
                        }
                    }
                    GridRow(alignment: .top) {
                        label(L("Notes", "备注"))
                        RecordingDetailCommitField(prompt: L("Notes", "备注"), value: r.notes, multiline: true) { n in
                            store.updateRecording(recordingID) { $0.notes = n }
                        }
                    }
                }
                .controlSize(.small)
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    InfoRow(key: L("Duration", "时长"), value: r.duration.map { Fmt.clock($0) } ?? "—")
                    InfoRow(key: L("Frame rate", "帧率"), value: Fmt.fps(r.fps))
                    if let w = r.videoWidth, let h = r.videoHeight, w > 0, h > 0 {
                        InfoRow(key: L("Frame size", "画面尺寸"), value: "\(w)×\(h)")
                    }
                    InfoRow(key: L("Pose model", "姿态模型"),
                            value: store.poseModel(r.id).displayName + " · " + store.poseModel(r.id).shortTitle.text
                                + (r.modelVersion.map { $0.isEmpty ? "" : " (v\($0))" } ?? ""))
                    InfoRow(key: L("Imported", "导入于"), value: Fmt.date(r.createdAt))
                    InfoRow(key: L("Storage", "存储方式"),
                            value: store.source(r.id)?.mode == .copied ? L("Copied into the library", "已复制到资料库")
                            : L("Referenced in place", "原位引用"))
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    private func timepointControl(_ r: Recording, _ e: Experiment?) -> some View {
        let store = app.store
        if let e, !e.timepoints.isEmpty {
            let options = e.timepoints.contains(r.timepoint) || r.timepoint.isEmpty ? e.timepoints : e.timepoints + [r.timepoint]
            Picker(L("Timepoint", "时间点"), selection: Binding(
                get: { r.timepoint },
                set: { new in store.updateRecording(recordingID) { $0.timepoint = new } })) {
                Text(L("Not set", "未设置")).tag("")
                ForEach(options, id: \.self) { t in Text(t).tag(t) }
            }
            .labelsHidden()
        } else {
            RecordingDetailCommitField(prompt: L("e.g. Baseline, Day 7", "例如 基线、第 7 天"), value: r.timepoint) { t in
                store.updateRecording(recordingID) { $0.timepoint = t }
            }
        }
    }
}

/// Text field that edits a stored value: shows the stored value, commits on Return or focus loss.
@MainActor
struct RecordingDetailCommitField: View {
    let prompt: String
    let value: String
    var multiline = false
    let commit: (String) -> Void

    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if multiline {
                TextField(prompt, text: $text, axis: .vertical)
                    .lineLimit(2...6)
            } else {
                TextField(prompt, text: $text)
            }
        }
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onAppear {
            if !loaded { text = value; loaded = true }
        }
        .onChange(of: value) { _, new in
            if !focused { text = new }
        }
        .onChange(of: focused) { _, now in
            if !now { save() }
        }
        .onSubmit { save() }
        .onDisappear { save() }
    }

    private func save() {
        let t = multiline ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text.trimmingCharacters(in: .whitespaces)
        if t != value { commit(t) }
    }
}
