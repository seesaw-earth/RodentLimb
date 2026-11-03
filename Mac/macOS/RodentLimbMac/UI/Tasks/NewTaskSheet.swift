// NewTaskSheet.swift — New Task (⇧⌘N, the sidebar, the welcome page, or videos dropped while no task
// is selected). Step 1: choose the paradigm (grouped by purpose, one line each). Step 2: name, groups,
// timepoints, notes and blinding. Create opens the task; videos that were dropped before are added to
// it right away (the Add Videos sheet opens with them). With dropped videos and existing tasks, step 1
// also offers to add them to one of those tasks instead.

import SwiftUI

struct NewTaskSheet: View {
    let request: NewTaskRequest

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var assay: Assay?
    @State private var name = ""
    @State private var nameEdited = false
    @State private var groups: [String] = ["", ""]
    @State private var timepointPreset = "none"
    @State private var customTimepoints = ""
    @State private var notes = ""
    @State private var blind = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let assay {
                details(assay)
            } else {
                paradigms
            }
            Divider()
            footer
        }
        .sheetFrame(minWidth: 460, idealWidth: 620, maxWidth: 760, minHeight: 360, idealHeight: 640, maxHeight: 860)
    }

    // MARK: Step 1 — paradigm

    private var paradigms: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("New Task", "新建任务")).font(.title2.weight(.semibold))
                    Text(L("Choose the paradigm. Every video added to the task is analysed with it.",
                           "选择实验范式。加入该任务的每段视频都会按此范式分析。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(TaskParadigms.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)
                        VStack(spacing: 0) {
                            ForEach(Array(section.assays.enumerated()), id: \.element) { i, a in
                                if i > 0 { Divider().padding(.leading, 14) }
                                paradigmRow(a)
                            }
                        }
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
                    }
                }
                if !request.pendingURLs.isEmpty && !app.store.tasks.isEmpty {
                    existingTasks
                }
            }
            .padding(24)
        }
    }

    private func paradigmRow(_ a: Assay) -> some View {
        Button {
            choose(a)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name.text).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(a.summary.text).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 12)
                Text(a.code).font(.caption.weight(.semibold).monospaced()).foregroundStyle(Palette.assay(a))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var existingTasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: L("OR ADD THE %d VIDEO(S) TO AN EXISTING TASK", "或将这 %d 个项目加入已有任务"), request.pendingURLs.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            VStack(spacing: 0) {
                ForEach(Array(app.store.tasks.prefix(12).enumerated()), id: \.element) { i, t in
                    if i > 0 { Divider().padding(.leading, 14) }
                    Button {
                        let urls = request.pendingURLs
                        dismiss()
                        app.show(.task(t))
                        app.importAfterSheetCloses(ImportRequest(task: t, urls: urls))
                    } label: {
                        HStack {
                            Text(app.store.taskTitle(t)).foregroundStyle(.primary)
                            Spacer()
                            Text(t.assay.name.text).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
        }
    }

    // MARK: Step 2 — details

    private func details(_ a: Assay) -> some View {
        Form {
            Section {
                LabeledContent(L("Paradigm", "范式")) {
                    HStack {
                        Text(a.name.text).fontWeight(.medium)
                        Spacer()
                        Button(L("Change", "更改")) { assay = nil }
                            .buttonStyle(.link)
                    }
                }
                TextField(L("Name", "名称"), text: nameBinding, prompt: Text(defaultName(a)))
                    .focused($nameFocused)
            } header: {
                Text(L("New task", "新建任务"))
            }

            Section {
                ForEach(groups.indices, id: \.self) { i in
                    HStack {
                        TextField(String(format: L("Group %d", "组 %d"), i + 1), text: groupBinding(i),
                                  prompt: Text(i == 0 ? L("e.g. Control", "如 Control") : i == 1 ? L("e.g. Treatment", "如 Treatment") : L("Group name", "组名")))
                        if groups.count > 1 {
                            Button(L("Remove", "移除")) { groups.remove(at: i) }
                                .buttonStyle(.link)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button(L("Add Group", "添加组")) { groups.append("") }
                    Spacer()
                    Menu(L("Presets", "预设")) {
                        ForEach(StudyPresets.factors) { p in
                            Button(p.levels.joined(separator: ", ")) { groups = p.levels }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text(L("Groups", "组别"))
            } footer: {
                Text(L("Optional. The first group is the reference (control). Videos are put in a group when they are added; groups can be changed later on the Design tab.",
                       "可选。第一组为参照（对照）组。添加视频时为其选择组别；之后可在“设计”页修改。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L("Timepoints", "时间点"), selection: $timepointPreset) {
                    Text(L("None — one session per animal", "无——每只动物一次")).tag("none")
                    ForEach(StudyPresets.timepoints) { p in
                        Text(p.title).tag(p.id)
                    }
                    Text(L("Custom…", "自定义…")).tag("custom")
                }
                if timepointPreset == "custom" {
                    TextField(L("Timepoints", "时间点"), text: $customTimepoints,
                              prompt: Text(L("In order, comma-separated, e.g. Baseline, Day 7, Day 28", "按顺序，用逗号分隔，如 Baseline, Day 7, Day 28")))
                }
            } header: {
                Text(L("Repeated measurements", "重复测量"))
            }

            Section {
                TextField(L("Notes", "备注"), text: $notes,
                          prompt: Text(L("Aim, hypothesis, primary outcome (optional)", "目的、假设、主要结局指标（可选）")),
                          axis: .vertical)
                    .lineLimit(2...4)
                Toggle(L("Blind the scoring", "盲法评分"), isOn: $blind)
            } footer: {
                Text(L("While blinded, groups are hidden and animals are shown by random codes, so videos are reviewed without knowing the group. Unblind on the task page when scoring is done.",
                       "盲法期间隐藏组别，动物以随机编码显示，从而在不知道分组的情况下复核视频。评分完成后在任务页面揭盲。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { nameFocused = true }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if !request.pendingURLs.isEmpty {
                Text(String(format: L("%d dropped item(s) will be added to the new task.", "拖入的 %d 个项目将加入新任务。"), request.pendingURLs.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Cancel", "取消")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            if assay == nil {
                Button(L("Continue", "继续")) {}
                    .disabled(true)
            } else {
                Button(request.pendingURLs.isEmpty ? L("Create Task", "创建任务") : L("Create and Add Videos", "创建并添加视频")) { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    // MARK: Logic

    private func choose(_ a: Assay) {
        assay = a
        if !nameEdited { name = "" }
    }

    private func defaultName(_ a: Assay) -> String {
        a.name.text + " " + SessionStore.dayStamp()
    }

    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { name = $0; nameEdited = true })
    }

    private func groupBinding(_ i: Int) -> Binding<String> {
        Binding(get: { i < groups.count ? groups[i] : "" },
                set: { if i < groups.count { groups[i] = $0 } })
    }

    private var chosenTimepoints: [String] {
        switch timepointPreset {
        case "none": return []
        case "custom": return StudyText.list(customTimepoints)
        default: return StudyPresets.timepoints.first { $0.id == timepointPreset }?.timepoints ?? []
        }
    }

    private func create() {
        guard let a = assay else { return }
        let typed = name.trimmingCharacters(in: .whitespaces)
        let t = app.store.createTask(assay: a, name: typed.isEmpty ? defaultName(a) : typed, groups: groups,
                                     timepoints: chosenTimepoints, notes: notes, blinded: blind)
        let urls = request.pendingURLs
        dismiss()
        app.taskCreated(t, pendingURLs: urls)
    }
}
