// StudyAnimalSheets.swift — adding animals and allocating them: the "Add Animal" popover (rapid
// entry: Return adds and keeps the form open), the "Paste List" sheet (one animal per line,
// optional sex and cohort columns, e.g. copied from a spreadsheet) and the randomisation sheet
// (port of the iPhone RandomizeSheet: all animals or only unallocated ones, stratified by sex and
// optionally cohort, seed shown and editable, with a preview of the group sizes).

import SwiftUI

// MARK: - Add one animal

struct StudyAddAnimalForm: View {
    let experimentID: UUID

    @Environment(AppModel.self) private var app
    @State private var code = ""
    @State private var sex = AnimalSex.unknown
    @State private var cohort = ""
    @State private var levels: [String: String] = [:]
    @State private var message: String?
    @State private var problem: String?
    @FocusState private var codeFocused: Bool

    init(experimentID: UUID) { self.experimentID = experimentID }

    var body: some View {
        let e = app.store.experiment(experimentID)
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Add Animal", "添加动物")).font(.headline)
            Form {
                TextField(L("Animal ID", "动物编号"), text: $code, prompt: Text(L("ear tag / cage card", "耳标 / 笼卡")))
                    .focused($codeFocused)
                    .onSubmit { add() }
                Picker(L("Sex", "性别"), selection: $sex) {
                    ForEach(AnimalSex.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                TextField(L("Cohort", "批次"), text: $cohort, prompt: Text(L("optional", "可选")))
                if let e, !e.blinded {
                    ForEach(e.activeFactors) { f in
                        Picker(f.name, selection: levelBinding(f)) {
                            Text(L("Not allocated", "未分组")).tag("")
                            ForEach(f.levels, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                    }
                }
            }
            .formStyle(.columns)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
            } else if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Palette.success)
            }
            if e?.blinded == true {
                Text(L("The task is blinded: allocate new animals with Randomise.", "任务处于盲法状态：请用“随机分组”为新动物分组。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(L("Return adds and keeps this open.", "按回车添加并保持打开。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Add", "添加")) { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(StudyText.trimmed(code).isEmpty || e == nil)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { codeFocused = true }
    }

    private func levelBinding(_ f: DesignFactor) -> Binding<String> {
        let key = f.id.uuidString
        return Binding(get: { levels[key] ?? "" },
                       set: { levels[key] = $0.isEmpty ? nil : $0 })
    }

    private func add() {
        let c = StudyText.trimmed(code)
        guard !c.isEmpty, let e = app.store.experiment(experimentID) else { return }
        if e.animal(code: c) != nil {
            problem = String(format: L("“%@” is already in this task.", "“%@”已在本任务中。"), c)
            return
        }
        var a = Animal(code: c)
        a.sex = sex
        a.cohort = StudyText.trimmed(cohort)
        if !e.blinded {
            // Only levels that exist in the design.
            for f in e.activeFactors {
                if let v = levels[f.id.uuidString], f.levels.contains(v) { a.levels[f.id.uuidString] = v }
            }
        }
        let animal = a
        app.store.updateExperiment(experimentID) { $0.animals.append(animal) }
        message = String(format: L("Added “%@”.", "已添加“%@”。"), c)
        problem = nil
        code = ""
        codeFocused = true
    }
}

// MARK: - Paste a list

struct StudyPasteAnimalsSheet: View {
    let experimentID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var defaultSex = AnimalSex.unknown
    @State private var defaultCohort = ""

    struct Entry: Identifiable {
        let id: Int
        let code: String
        let sex: AnimalSex?
        let cohort: String
        let exists: Bool
    }

    init(experimentID: UUID) { self.experimentID = experimentID }

    var body: some View {
        let e = app.store.experiment(experimentID)
        let entries = Self.parse(text, existing: e)
        let fresh = entries.filter { !$0.exists }
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Paste Animal IDs", "粘贴动物编号")).font(.title3.weight(.semibold))
            Text(L("One animal per line. Further columns, separated by tabs or commas (as copied from a spreadsheet), are read as sex (M / F) and cohort.",
                   "每行一只动物。其后的列（用制表符或逗号分隔，如从电子表格拷贝）依次读作性别（M / F）和批次。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 90, idealHeight: 170, maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1)
                }
            HStack(spacing: 16) {
                Picker(L("Sex when not given", "未给出时的性别"), selection: $defaultSex) {
                    ForEach(AnimalSex.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .fixedSize()
                TextField(L("Cohort when not given", "未给出时的批次"), text: $defaultCohort, prompt: Text(L("Cohort when not given", "未给出时的批次")))
                    .labelsHidden()
                    .frame(maxWidth: 220)
            }
            summary(entries, fresh: fresh)
            HStack {
                Button {
                    if let s = StudyClipboard.string() { text = s }
                } label: {
                    Text(L("Paste from Clipboard", "从剪贴板粘贴"))
                }
                Spacer()
                Button(L("Cancel", "取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fresh.isEmpty ? L("Add", "添加") : String(format: L("Add %d Animals", "添加 %d 只动物"), fresh.count)) {
                    add(fresh)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fresh.isEmpty || e == nil)
            }
        }
        .padding(18)
        .sheetFrame(minWidth: 440, idealWidth: 580, maxWidth: 760, minHeight: 320, idealHeight: 520, maxHeight: 800)
    }

    @ViewBuilder
    private func summary(_ entries: [Entry], fresh: [Entry]) -> some View {
        let existing = entries.count - fresh.count
        if entries.isEmpty {
            Text(L("Nothing to add yet.", "尚无可添加的内容。")).font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(existing > 0
                     ? String(format: L("%d new animal(s); %d already in the task (skipped).", "%d 只新动物；%d 只已在任务中（跳过）。"), fresh.count, existing)
                     : String(format: L("%d new animal(s).", "%d 只新动物。"), fresh.count))
                    .font(.caption.weight(.semibold))
                Text(fresh.prefix(8).map { entryLabel($0) }.joined(separator: " · ") + (fresh.count > 8 ? " …" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func entryLabel(_ x: Entry) -> String {
        var parts = [x.code]
        let s = x.sex ?? defaultSex
        if s != .unknown { parts.append(s.short) }
        let c = x.cohort.isEmpty ? StudyText.trimmed(defaultCohort) : x.cohort
        if !c.isEmpty { parts.append(c) }
        return parts.joined(separator: " ")
    }

    /// Lines → animals (first column ID; then sex or cohort; then cohort). A header line is skipped;
    /// IDs repeated in the list are taken once (case-insensitive, as IDs are matched in a study).
    static func parse(_ text: String, existing e: Experiment?) -> [Entry] {
        var out: [Entry] = []
        var seen = Set<String>()
        let headers: Set<String> = ["id", "animal", "animal id", "animal_id", "code", "subject", "动物", "编号", "动物编号"]
        let lines = text.split(whereSeparator: { $0.isNewline })
        for (n, raw) in lines.enumerated() {
            let cols = raw.split(omittingEmptySubsequences: false,
                                 whereSeparator: { $0 == "\t" || $0 == "," || $0 == ";" || $0 == "，" })
                .map { StudyText.trimmed(String($0)) }
            guard let code = cols.first, !code.isEmpty else { continue }
            if n == 0 && headers.contains(code.lowercased()) { continue }
            let key = code.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            var sex: AnimalSex?
            var cohort = ""
            if cols.count > 1, !cols[1].isEmpty {
                if let s = StudyText.sex(cols[1]) { sex = s } else { cohort = cols[1] }
            }
            if cols.count > 2, !cols[2].isEmpty { cohort = cols[2] }
            out.append(Entry(id: out.count, code: code, sex: sex, cohort: cohort, exists: e?.animal(code: code) != nil))
        }
        return out
    }

    private func add(_ entries: [Entry]) {
        let sexDefault = defaultSex
        let cohortDefault = StudyText.trimmed(defaultCohort)
        var added = 0
        app.store.updateExperiment(experimentID) { e in
            for x in entries where e.animal(code: x.code) == nil {
                var a = Animal(code: x.code)
                a.sex = x.sex ?? sexDefault
                a.cohort = x.cohort.isEmpty ? cohortDefault : x.cohort
                e.animals.append(a)
                added += 1
            }
        }
        app.toast = String(format: L("Added %d animal(s)", "已添加 %d 只动物"), added)
        dismiss()
    }
}

// MARK: - Randomisation

struct StudyRandomiseSheet: View {
    let experimentID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var reallocateAll = false
    @State private var byCohort = false
    @State private var seedText = String(Int.random(in: 1...999_999))

    init(experimentID: UUID) { self.experimentID = experimentID }

    /// The seed typed by the user (a positive whole number), nil when invalid.
    private var seed: UInt64? {
        guard let v = UInt64(StudyText.trimmed(seedText)), v > 0 else { return nil }
        return v
    }

    var body: some View {
        VStack(spacing: 0) {
            if let e = app.store.experiment(experimentID) {
                form(e)
            } else {
                EmptyState(title: L("Task deleted", "该任务已删除"), message: L("This task no longer exists.", "该任务已不存在。"),
                           symbol: "trash")
            }
            Divider()
            footer
        }
        .sheetFrame(minWidth: 440, idealWidth: 580, maxWidth: 760, minHeight: 340, idealHeight: 600, maxHeight: 860)
    }

    private func form(_ e: Experiment) -> some View {
        Form {
            Section {
                LabeledContent(L("Groups", "组数"), value: StudyText.groupCount(e))
                LabeledContent(L("Animals", "动物"), value: "\(e.animals.count)")
                LabeledContent(L("Not yet allocated", "尚未分组"), value: "\(e.unallocated.count)")
            } footer: {
                Text(L("Block randomisation stratified by sex: within each sex, animals are dealt to the groups in random blocks of one animal per group, so group sizes differ by at most one. The method and seed are written to the task's design text (ARRIVE 2.0 item 4).",
                       "按性别分层的区组随机：每种性别内，动物按“每组一只”的随机区组依次分配，各组样本量最多相差 1。方法和随机种子会写入任务设计说明（ARRIVE 2.0 第 4 项）。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("Also balance cohorts", "同时平衡批次"), isOn: $byCohort)
                Toggle(L("Re-allocate every animal", "重新分配全部动物"), isOn: $reallocateAll)
                LabeledContent(L("Seed", "随机种子")) {
                    HStack(spacing: 6) {
                        TextField(L("Seed", "随机种子"), text: $seedText)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 120)
                        Button(L("New Seed", "新种子")) {
                            seedText = String(Int.random(in: 1...999_999))
                        }
                        .buttonStyle(.borderless)
                        .help(L("New random seed", "新的随机种子"))
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if seed == nil {
                        Text(L("The seed must be a positive whole number.", "随机种子必须是正整数。"))
                            .foregroundStyle(Palette.danger)
                    }
                    if reallocateAll {
                        Text(L("Existing allocations will be replaced. Do this only before any treatment was given.", "现有分组将被替换。只应在给予任何处理之前这样做。"))
                            .foregroundStyle(Palette.warning)
                    } else if e.unallocated.isEmpty && !e.animals.isEmpty {
                        Text(L("Every animal already has a group. Turn on “Re-allocate every animal” to start over.", "所有动物都已分组。如需重新开始，请打开“重新分配全部动物”。"))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L("Animals that already have a group keep it and count towards the group sizes; only the others are allocated.",
                               "已分组的动物保持不变并计入各组样本量；只分配其余动物。"))
                            .foregroundStyle(.secondary)
                    }
                    Text(L("The same seed with the same animals always gives the same allocation.", "相同的动物和相同的种子总会得到相同的分组。"))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if e.blinded {
                Section {
                    Text(L("The task is blinded: the allocation is made but stays hidden.", "任务处于盲法状态：分组会完成但保持隐藏。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let s = seed, canAllocate(e) {
                preview(e, seed: s)
            }
        }
        .formStyle(.grouped)
    }

    /// Group sizes the allocation would give (computed on a copy; nothing is saved).
    private func preview(_ e: Experiment, seed s: UInt64) -> some View {
        let result = Randomizer.allocate(e, all: reallocateAll, byCohort: byCohort, seed: s)
        let sizes = app.store.groupSizes(result)
        return Section {
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    Text(L("Group", "组别")).gridColumnAlignment(.leading)
                    Text("n")
                    Text(L("Male", "雄"))
                    Text(L("Female", "雌"))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(Array(sizes.enumerated()), id: \.offset) { item in
                    GridRow {
                        Text(item.element.group).lineLimit(1)
                        Text("\(item.element.total)")
                        Text("\(item.element.male)")
                        Text("\(item.element.female)")
                    }
                    .font(.callout.monospacedDigit())
                }
            }
        } header: {
            Text(L("Preview", "预览"))
        }
    }

    private func canAllocate(_ e: Experiment) -> Bool {
        !e.animals.isEmpty && !e.cells.isEmpty && (reallocateAll || !e.unallocated.isEmpty)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("Cancel", "取消")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(L("Allocate", "分配")) { allocate() }
                .keyboardShortcut(.defaultAction)
                .disabled(seed == nil || !(app.store.experiment(experimentID).map { canAllocate($0) } ?? false))
        }
        .padding(14)
    }

    private func allocate() {
        guard let e = app.store.experiment(experimentID), let s = seed, canAllocate(e) else { return }
        let allocated = Randomizer.allocate(e, all: reallocateAll, byCohort: byCohort, seed: s)
        app.store.updateExperiment(experimentID) { $0 = allocated }
        app.toast = e.blinded ? L("Allocated (hidden while blinded)", "已分组（盲法期间隐藏）") : L("Animals allocated", "已完成分组")
        dismiss()
    }
}
