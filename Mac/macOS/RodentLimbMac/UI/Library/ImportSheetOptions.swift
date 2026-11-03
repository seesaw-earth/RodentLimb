// ImportSheetOptions.swift — the upper half of the Add Videos sheet: what applies to every video
// being added to the task. Left: the task (fixed: videos are always added from a task), the group
// for videos that do not get one from their animal or file name, the timepoint for videos whose name
// has none, notes. Right: the pose model and whether the videos stay where they are or are copied
// into the library (with the space it needs).

import SwiftUI

@MainActor
struct ImportOptionsPanel: View {
    @Bindable var model: ImportSheetModel
    @Environment(AppModel.self) private var app
    @State private var newGroup = ""

    var body: some View {
        // Two columns on a wide sheet, one above the other on a narrow one; the options scroll so the
        // video table and the Add button below always keep their room.
        ScrollView {
            AdaptiveColumns(side: .half, threshold: 760, spacing: 28) {
                designForm.frame(maxWidth: .infinity, alignment: .leading)
                filesForm.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minHeight: 120, idealHeight: 230, maxHeight: 300)
        .disabled(model.phase != .editing)
    }

    // MARK: Task, group, timepoint

    private var designForm: some View {
        let e = model.experiment
        return Form {
            LabeledContent(L("Task", "任务")) {
                if let t = model.task {
                    Text(app.store.taskTitle(t) + "  ·  " + t.assay.name.text)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else {
                    Text(L("This task no longer exists", "该任务已不存在")).foregroundStyle(Palette.danger)
                }
            }
            if model.groupsEditable {
                LabeledContent(L("Group", "组别")) {
                    groupPicker
                }
            }
            LabeledContent(L("Timepoint", "时间点")) {
                HStack(spacing: 6) {
                    TextField(L("Timepoint", "时间点"), text: timepointBinding,
                              prompt: Text(L("e.g. Baseline, Day 7", "如 Baseline、Day 7")))
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    if let e, !e.timepoints.isEmpty {
                        Picker(L("Timepoint", "时间点"), selection: timepointBinding) {
                            if !e.timepoints.contains(model.defaultTimepoint) {
                                Text(L("Choose…", "选择…")).tag(model.defaultTimepoint)
                            }
                            ForEach(e.timepoints, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help(L("One of the task's timepoints", "任务中的时间点"))
                    }
                }
            }
            LabeledContent(L("Notes", "备注")) {
                TextField(L("Notes", "备注"), text: $model.notes, prompt: Text(L("Optional, for every video", "可选，适用于所有视频")))
                    .labelsHidden()
            }
            Text(footnote(e))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.columns)
    }

    private var groupPicker: some View {
        let groups = model.taskGroups
        return HStack(spacing: 6) {
            Picker(L("Group", "组别"), selection: defaultGroupBinding) {
                Text(L("From file name or animal", "按文件名或动物")).tag("")
                if !groups.isEmpty { Divider() }
                ForEach(groups, id: \.self) { Text($0).tag($0) }
                if !model.defaultGroup.isEmpty && !groups.contains(model.defaultGroup) {
                    Text(model.defaultGroup).tag(model.defaultGroup)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            TextField(L("New group", "新组别"), text: $newGroup, prompt: Text(L("New group", "新组别")))
                .labelsHidden()
                .frame(maxWidth: 120)
                .onSubmit { addGroup() }
            Button(L("Add", "添加")) { addGroup() }
                .disabled(newGroup.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addGroup() {
        let g = newGroup.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, let t = model.task else { return }
        app.store.addGroup(g, to: t)
        model.setDefaultGroup(model.taskGroups.first { $0.compare(g, options: .caseInsensitive) == .orderedSame } ?? g)
        model.refreshSuggestions()
        newGroup = ""
    }

    private func footnote(_ e: Experiment?) -> String {
        var s = L("Each video joins this task and is analysed with it after tracking and QC. Animal IDs are matched to the task's animals (new IDs are added); an animal keeps its group.",
                  "每段视频都会加入此任务，识别和质控后按该任务分析。动物编号会与任务中的动物对应（新编号会自动加入），已分组的动物保持原组别。")
        if let e, e.blinded {
            s += " " + L("The task is blinded: groups stay hidden and are allocated on the Design tab.",
                         "该任务处于盲法中：组别保持隐藏，请在“设计”页分配。")
        } else if let e, e.factors.count > 1 {
            s += " " + L("This task has a factorial design: set each animal's group on the Design tab.",
                         "该任务为多因素设计：请在“设计”页设置每只动物的组别。")
        }
        return s
    }

    // MARK: Pose model and files

    private var filesForm: some View {
        Form {
            LabeledContent(L("Pose model", "姿态模型")) {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L("Pose model", "姿态模型"), selection: $model.poseModel) {
                        ForEach(PoseModelID.choices) { m in
                            Text(m.title.text).tag(m)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(model.poseModel.detail.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !PoseModelLoader.isInstalled(model.poseModel) {
                        Text(String(format: L("%@ is not in this build — add it to Models/ (see README).", "此版本中没有 %@——请将其加入 Models/（见 README）。"),
                                    model.poseModel.displayName))
                            .font(.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            LabeledContent(L("Video files", "视频文件")) {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L("Video files", "视频文件"), selection: $model.copyVideos) {
                        Text(L("Keep videos where they are (recommended)", "保留在原位置（推荐）")).tag(false)
                        Text(L("Copy videos into the library", "将视频复制到资料库")).tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    copyFootnote
                }
            }
        }
        .formStyle(.columns)
    }

    @ViewBuilder
    private var copyFootnote: some View {
        if model.copyVideos {
            let need = model.summary.bytes
            let free = app.store.freeSpace()
            let short = free.map { $0 < need } ?? false
            let text = free.map {
                String(format: L("Needs %@; %@ free on the library's disk.", "需要 %@；资料库所在磁盘剩余 %@。"), Fmt.bytes(need), Fmt.bytes($0))
            } ?? String(format: L("Needs %@.", "需要 %@。"), Fmt.bytes(need))
            Text(text)
                .font(.caption)
                .foregroundStyle(short ? Palette.danger : Color.secondary)
        } else {
            Text(L("The library remembers where each video is. Keep the drive connected while videos are tracked; a moved file can be located again.",
                   "资料库会记住每个视频的位置。识别期间请保持磁盘连接；移动过的文件可以重新定位。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Bindings

    private var timepointBinding: Binding<String> {
        Binding(get: { model.defaultTimepoint }, set: { model.setDefaultTimepoint($0) })
    }

    private var defaultGroupBinding: Binding<String> {
        Binding(get: { model.defaultGroup }, set: { model.setDefaultGroup($0) })
    }
}
