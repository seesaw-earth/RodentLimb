// ImportSheetParts.swift — the smaller pieces of the Import Videos sheet:
//  • ImportPatternEditor (popover): automatic naming, or separators + "part N is the animal /
//    timepoint / trial", with a live preview of how a file name is split and read;
//  • ImportBulkEditor (popover): set animal IDs (same ID, a prefix, or prefix + numbers), the
//    timepoint and the trial of many selected videos at once;
//  • ImportResultPanel: what the import did (added, duplicates skipped, failures) and how to go on.

import SwiftUI

// MARK: - File-name pattern

private struct ImportSeparatorChoice: Identifiable {
    let char: Character
    let label: String
    var id: String { String(char) }

    static var common: [ImportSeparatorChoice] {
        [ImportSeparatorChoice(char: "_", label: "_"),
         ImportSeparatorChoice(char: "-", label: "-"),
         ImportSeparatorChoice(char: " ", label: L("space", "空格")),
         ImportSeparatorChoice(char: ".", label: ".")]
    }
}

@MainActor
struct ImportPatternEditor: View {
    let model: ImportSheetModel
    let sample: URL?

    var body: some View {
        let p = model.pattern
        let parts = sample.map { ImportNaming.parts(ImportNaming.stem($0), separators: p.separators) } ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Animal, timepoint and trial from file names", "从文件名读取动物、时间点和试次"))
                .font(.headline)
            Picker(L("Mode", "方式"), selection: modeBinding) {
                Text(L("Automatic", "自动")).tag(false)
                Text(L("By position in the name", "按名称中的位置")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if p.isAutomatic {
                Text(L("A registered animal ID or timepoint of the task found in the name (or in a parent folder's name) is used; otherwise the whole name becomes the animal ID. Trials written as T2, trial2 or rep2 are recognised.",
                       "文件名（或上级文件夹名）中包含任务已登记的动物编号或时间点时直接采用；否则整个文件名作为动物编号。可识别 T2、trial2、rep2 形式的试次。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                separatorsRow(p)
                partsPreview(parts, p)
                let count = min(20, max(1, parts.count, p.animalPart ?? 0, p.timepointPart ?? 0, p.trialPart ?? 0))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text(L("Animal ID", "动物编号")).gridColumnAlignment(.trailing)
                        partPicker(\.animalPart, count: count)
                    }
                    GridRow {
                        Text(L("Timepoint", "时间点"))
                        partPicker(\.timepointPart, count: count)
                    }
                    GridRow {
                        Text(L("Trial", "试次"))
                        partPicker(\.trialPart, count: count)
                    }
                }
            }
            Divider()
            resultPreview(p)
        }
        .padding(16)
        .frame(width: 460)
    }

    private var modeBinding: Binding<Bool> {
        Binding(get: { !model.pattern.isAutomatic }, set: { byPosition in
            var q = model.pattern
            if byPosition {
                if q.isAutomatic { q.animalPart = 1 }
            } else {
                q.animalPart = nil
                q.timepointPart = nil
                q.trialPart = nil
            }
            model.setPattern(q)
        })
    }

    private func separatorsRow(_ p: NamePattern) -> some View {
        HStack(spacing: 6) {
            Text(L("Split at", "分隔符"))
            ForEach(ImportSeparatorChoice.common) { c in
                Toggle(isOn: separatorBinding(c.char)) {
                    Text(c.label).monospaced().frame(minWidth: 14)
                }
                .toggleStyle(.button)
                .help(String(format: L("Split the name at “%@”", "在“%@”处分隔名称"), c.label))
            }
            TextField(L("Other", "其他"), text: otherBinding, prompt: Text(L("other", "其他")))
                .labelsHidden()
                .frame(width: 64)
                .help(L("Other characters that separate the parts of a name", "其他用于分隔名称各部分的字符"))
            if p.separators.isEmpty {
                Text(L("(none: “_” is used)", "（未选：使用“_”）")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func separatorBinding(_ c: Character) -> Binding<Bool> {
        Binding(get: { model.pattern.separators.contains(c) }, set: { on in
            var q = model.pattern
            if on {
                if !q.separators.contains(c) { q.separators.append(c) }
            } else {
                q.separators.removeAll { $0 == c }
            }
            model.setPattern(q)
        })
    }

    private var otherBinding: Binding<String> {
        let standard = Set(ImportSeparatorChoice.common.map(\.char))
        return Binding(get: { String(model.pattern.separators.filter { !standard.contains($0) }) }, set: { typed in
            var q = model.pattern
            var seen = Set<Character>()
            let kept = q.separators.filter { standard.contains($0) }
            let extra = typed.filter { !standard.contains($0) && seen.insert($0).inserted }
            q.separators = String(kept) + String(extra)
            model.setPattern(q)
        })
    }

    private func partsPreview(_ parts: [String], _ p: NamePattern) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sample {
                Text(sample.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if parts.isEmpty {
                Text(L("Add videos to see how their names are split.", "添加视频后可查看名称如何分段。"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                            partChip(i + 1, part, Self.role(i + 1, p))
                        }
                    }
                }
            }
        }
    }

    private func partChip(_ n: Int, _ text: String, _ color: Color?) -> some View {
        HStack(spacing: 4) {
            Text("\(n)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(text).font(.callout.monospaced()).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((color ?? Palette.gray).opacity(color == nil ? 0.10 : 0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            if let color {
                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(color, lineWidth: 1)
            }
        }
    }

    private static func role(_ n: Int, _ p: NamePattern) -> Color? {
        if p.animalPart == n { return Palette.blue }
        if p.timepointPart == n { return Palette.purple }
        if p.trialPart == n { return Palette.orange }
        return nil
    }

    private func partPicker(_ key: WritableKeyPath<NamePattern, Int?>, count: Int) -> some View {
        Picker("", selection: Binding<Int?>(get: { model.pattern[keyPath: key] }, set: { v in
            var q = model.pattern
            q[keyPath: key] = v
            model.setPattern(q)
        })) {
            Text(L("Not in the name", "名称中没有")).tag(Int?.none)
            ForEach(Array(1...max(1, count)), id: \.self) { i in
                Text(String(format: L("Part %d", "第 %d 段"), i)).tag(Int?.some(i))
            }
        }
        .labelsHidden()
        .frame(width: 190)
    }

    @ViewBuilder
    private func resultPreview(_ p: NamePattern) -> some View {
        if let sample {
            let s = model.preview(sample, pattern: p)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    Text(L("Animal ID", "动物编号")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(s.animal.isEmpty ? "—" : s.animal).fontWeight(.semibold).foregroundStyle(Palette.blue)
                }
                GridRow {
                    Text(L("Timepoint", "时间点")).foregroundStyle(.secondary)
                    Text(s.timepoint.isEmpty ? L("(the sheet's timepoint)", "（使用上方的时间点）") : s.timepoint)
                        .fontWeight(.semibold).foregroundStyle(s.timepoint.isEmpty ? Color.secondary : Palette.purple)
                }
                GridRow {
                    Text(L("Trial", "试次")).foregroundStyle(.secondary)
                    Text("\(max(1, s.trial ?? 1))").fontWeight(.semibold).foregroundStyle(Palette.orange)
                }
            }
            .font(.callout)
            Text(L("Values you typed in the table are kept.", "你在表格中输入的值会保留。"))
                .font(.caption).foregroundStyle(.tertiary)
        } else {
            Text(L("Add videos to preview how their names are read.", "添加视频后可预览名称的读取结果。"))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bulk editing

@MainActor
struct ImportBulkEditor: View {
    let model: ImportSheetModel
    let ids: Set<UUID>
    let close: () -> Void

    @State private var editAnimal = false
    @State private var mode: ImportAnimalEdit = .replace
    @State private var animalText = ""
    @State private var start = 1
    @State private var digits = 2
    @State private var editTimepoint = false
    @State private var timepoint = ""
    @State private var editTrial = false
    @State private var trial = 1
    @State private var editGroup = false
    @State private var group = ""

    var body: some View {
        let timepoints = model.experiment?.timepoints ?? []
        let groups = model.groupsEditable ? model.taskGroups : []
        VStack(alignment: .leading, spacing: 14) {
            Text(ids.count == 1 ? L("Edit 1 Video", "编辑 1 个视频") : String(format: L("Edit %d Videos", "编辑 %d 个视频"), ids.count))
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Toggle(L("Animal ID", "动物编号"), isOn: $editAnimal).toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker(L("Change", "方式"), selection: $mode) {
                            ForEach(ImportAnimalEdit.allCases) { m in Text(m.label).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 270)
                        HStack(spacing: 6) {
                            TextField(L("Animal ID", "动物编号"), text: $animalText, prompt: Text(animalPrompt))
                                .labelsHidden()
                                .frame(width: 150)
                            if mode == .number {
                                Text(L("from", "起始"))
                                TextField(L("from", "起始"), value: $start, format: .number)
                                    .labelsHidden()
                                    .frame(width: 50)
                                Stepper(value: $digits, in: 1...4) {
                                    Text(String(format: L("%d digits", "%d 位"), digits)).monospacedDigit()
                                }
                            }
                        }
                        Text(example).font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!editAnimal)
                }
                GridRow {
                    Toggle(L("Timepoint", "时间点"), isOn: $editTimepoint).toggleStyle(.checkbox)
                    HStack(spacing: 4) {
                        TextField(L("Timepoint", "时间点"), text: $timepoint, prompt: Text(L("None", "无")))
                            .labelsHidden()
                            .frame(width: 150)
                        if !timepoints.isEmpty {
                            Menu(L("Choose", "选择")) {
                                ForEach(timepoints, id: \.self) { t in Button(t) { timepoint = t } }
                            }
                            .fixedSize()
                        }
                    }
                    .disabled(!editTimepoint)
                }
                if !groups.isEmpty {
                    GridRow {
                        Toggle(L("Group", "组别"), isOn: $editGroup).toggleStyle(.checkbox)
                        Picker(L("Group", "组别"), selection: $group) {
                            Text(L("None", "无")).tag("")
                            ForEach(groups, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .disabled(!editGroup)
                    }
                }
                GridRow {
                    Toggle(L("Trial", "试次"), isOn: $editTrial).toggleStyle(.checkbox)
                    Stepper(value: $trial, in: 1...99) {
                        Text("\(trial)").monospacedDigit().frame(minWidth: 24, alignment: .leading)
                    }
                    .disabled(!editTrial)
                }
            }
            HStack {
                Spacer()
                Button(L("Cancel", "取消"), role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Apply", "应用")) { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(editAnimal || editTimepoint || editTrial || editGroup))
            }
        }
        .padding(16)
        .frame(width: 480)
        .onChange(of: animalText) { _, _ in editAnimal = true }
        .onChange(of: timepoint) { _, _ in editTimepoint = true }
        .onChange(of: trial) { _, _ in editTrial = true }
        .onChange(of: mode) { _, _ in editAnimal = true }
        .onChange(of: group) { _, _ in editGroup = true }
    }

    private var animalPrompt: String {
        switch mode {
        case .replace: return L("Animal ID", "动物编号")
        case .prefix: return L("Prefix, e.g. WT-", "前缀，如 WT-")
        case .number: return L("Prefix, e.g. M", "前缀，如 M")
        }
    }

    private var example: String {
        let text = animalText.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .replace:
            return text.isEmpty ? L("Every selected video gets the same animal ID.", "所选视频使用相同的动物编号。")
                : String(format: L("All selected videos: %@", "所选视频均为：%@"), text)
        case .prefix:
            return String(format: L("Added in front of each ID: 07 → %@07", "加在每个编号前：07 → %@07"), text)
        case .number:
            let a = min(max(0, start), 1_000_000_000)
            let list = (0..<min(3, max(1, ids.count))).map { text + ImportSheetModel.padded(a + $0, digits) }
            return list.joined(separator: ", ") + (ids.count > 3 ? " …" : "") + L(" (in table order)", "（按表格顺序）")
        }
    }

    private func apply() {
        let animal: (mode: ImportAnimalEdit, text: String, start: Int, digits: Int)? =
            editAnimal ? (mode: mode, text: animalText, start: start, digits: digits) : nil
        model.bulkEdit(ids, animal: animal,
                       timepoint: editTimepoint ? timepoint : nil,
                       trial: editTrial ? trial : nil,
                       group: editGroup ? group : nil)
        close()
    }
}

// MARK: - Result

@MainActor
struct ImportResultPanel: View {
    let result: ImportSheetResult
    let busy: Bool
    let done: Int
    let total: Int
    let autoStart: Bool
    let importAnyway: () -> Void
    let finish: (_ start: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !result.duplicates.isEmpty { duplicatesBox }
                    if !result.failures.isEmpty { failuresBox }
                    if result.unreadable > 0 {
                        Banner(text: String(format: L("%d unreadable file(s) were skipped. Convert them to MP4 (H.264 or HEVC), e.g. with HandBrake or ffmpeg, and import them again.",
                                                      "跳过了 %d 个无法读取的文件。请先转换为 MP4（H.264 或 HEVC，例如使用 HandBrake 或 ffmpeg）后重新导入。"), result.unreadable),
                               level: .warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                if busy {
                    ProgressView(value: Double(min(done, total)), total: Double(max(1, total))).frame(width: 200)
                    Text(String(format: L("Importing %d of %d…", "正在导入第 %d / %d 个…"), min(done + 1, max(1, total)), total))
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var buttons: some View {
        if result.created == 0 {
            Button(L("Close", "关闭")) { finish(false) }
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
        } else if autoStart {
            Button(L("Done", "完成")) { finish(false) }
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
        } else {
            Button(L("Not Now", "稍后")) { finish(false) }
                .keyboardShortcut(.cancelAction)
                .disabled(busy)
            Button(L("Start Tracking", "开始识别")) { finish(true) }
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
        }
    }

    private var title: String {
        switch result.created {
        case 0: return L("No videos were added", "没有添加任何视频")
        case 1: return L("1 video added to the task", "已将 1 段视频加入任务")
        default: return String(format: L("%d videos added to the task", "已将 %d 段视频加入任务"), result.created)
        }
    }

    private var subtitle: String {
        if result.created == 0 { return L("See below why.", "原因见下方。") }
        if autoStart {
            return L("Tracking starts by itself and continues in the background; the task's sessions show its progress.",
                     "识别会自动开始并在后台继续；任务的会话列表会显示进度。")
        }
        return L("Automatic start is off (Settings › Processing). Start tracking now?",
                 "自动开始已关闭（设置 › 处理）。现在开始识别吗？")
    }

    private var duplicatesBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("These files are already in the library (same size and content), so they were skipped.",
                       "这些文件已在资料库中（大小和内容相同），因此已跳过。"))
                    .font(.callout).foregroundStyle(.secondary)
                nameList(result.duplicates)
                if !result.retryable.isEmpty {
                    Button(String(format: L("Import %d Anyway", "仍然导入 %d 个"), result.retryable.count)) { importAnyway() }
                        .disabled(busy)
                        .help(L("Adds a second record of the same video (e.g. for another task or timepoint).",
                                "为同一视频再添加一条记录（例如用于另一个任务或时间点）。"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(String(format: L("%d already in the library", "%d 个已在资料库中"), result.duplicates.count))
        }
    }

    private var failuresBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(result.failures.prefix(200).enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name).font(.callout.weight(.semibold))
                        Text(f.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if result.failures.count > 200 {
                    Text(String(format: L("and %d more", "以及另外 %d 个"), result.failures.count - 200)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(String(format: L("%d could not be added", "%d 个无法添加"), result.failures.count))
                .foregroundStyle(Palette.danger)
        }
    }

    private func nameList(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(names.prefix(200).enumerated()), id: \.offset) { _, n in
                Text(n).font(.callout).textSelection(.enabled)
            }
            if names.count > 200 {
                Text(String(format: L("and %d more", "以及另外 %d 个"), names.count - 200)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
