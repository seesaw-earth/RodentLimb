// DesignSheets.swift — the design sheets of a task: full design (factors, timepoints, blinding, QC
// inclusion criteria), one animal (ID, sex, group, cohort), and block randomisation.

import SwiftUI

// MARK: - Design editor

@MainActor
struct StudyEditorSheet: View {
    let experimentID: UUID
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    private struct FactorRow: Identifiable {
        var id: UUID
        var name: String
        var levels: String
    }

    @State private var name = ""
    @State private var notes = ""
    @State private var factors: [FactorRow] = []
    @State private var timepoints = ""
    @State private var blinded = false
    @State private var qc = QCCriteria()
    @State private var loaded = false
    /// Blinded when the editor opened: the groups cannot be changed (that would silently drop
    /// allocations nobody can see) and unblinding goes through the study screen's confirmation.
    @State private var wasBlinded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Task name", "任务名称"), text: $name)
                    TextField(L("Aim, hypothesis, primary outcome…", "目的、假设、主要结局指标…"), text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    ForEach($factors) { $f in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(L("Factor, e.g. Genotype", "因素，如 Genotype"), text: $f.name).font(.body.weight(.semibold))
                            TextField(L("Levels, comma-separated (control first)", "水平，用逗号分隔（对照放第一个）"), text: $f.levels)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    }
                    .onDelete { factors.remove(atOffsets: $0) }
                    Menu(L("Add factor", "添加因素")) {
                        Button(L("Group: Control, Treatment", "分组：Control, Treatment")) { addFactor("Group", "Control, Treatment") }
                        Button(L("Genotype: WT, KO", "基因型：WT, KO")) { addFactor("Genotype", "WT, KO") }
                        Button(L("Treatment: Vehicle, Drug", "处理：Vehicle, Drug")) { addFactor("Treatment", "Vehicle, Drug") }
                        Button(L("Dose: 0, 1, 3, 10 mg/kg", "剂量：0, 1, 3, 10 mg/kg")) { addFactor("Dose", "0 mg/kg, 1 mg/kg, 3 mg/kg, 10 mg/kg") }
                        Button(L("Surgery: Sham, Lesion", "手术：Sham, Lesion")) { addFactor("Surgery", "Sham, Lesion") }
                        Button(L("Empty factor", "空白因素")) { addFactor("", "") }
                    }
                } header: {
                    Text(L("Groups (between-subject factors)", "分组（组间因素）"))
                } footer: {
                    if wasBlinded {
                        Text(L("Groups are hidden and locked while the task is blinded.", "盲法期间分组被隐藏并锁定。"))
                    } else {
                        Text(L("One factor named Group is the usual design. With several factors, every combination of levels is a group (2 × 2 = 4 groups). Renaming a level here unassigns animals that had the old name (rename groups in the task's Design to keep them).",
                               "通常只需一个名为 Group 的因素。有多个因素时，各水平的每种组合即一个组（2 × 2 = 4 组）。在此重命名水平会使原水平下的动物变为未分组（在任务的“设计”中重命名分组可保留分组）。"))
                    }
                }
                .disabled(wasBlinded)
                Section {
                    TextField(L("e.g. Baseline, Day 7, Day 28", "如 Baseline, Day 7, Day 28"), text: $timepoints)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Menu {
                        Button("Pre, Post") { timepoints = "Pre, Post" }
                        Button("Baseline, Day 7, Day 14, Day 28") { timepoints = "Baseline, Day 7, Day 14, Day 28" }
                        Button("Vehicle, Low, High (crossover)") { timepoints = "Vehicle, Low dose, High dose" }
                    } label: { Text(L("Presets", "预设")) }
                } header: {
                    Text(L("Repeated measurements (within-subject)", "重复测量（组内）"))
                } footer: {
                    Text(L("Each animal is recorded at every timepoint or condition. For crossover designs, counterbalance the order of conditions between animals.",
                           "每只动物在每个时间点或条件下各录一次。交叉设计中，请在动物间平衡条件顺序。"))
                }
                Section {
                    Toggle(L("Blind the scoring", "评分时设盲"), isOn: $blinded)
                        .disabled(wasBlinded)
                } footer: {
                    Text(L("While blinded, group labels and group comparisons are hidden and animals are shown by random codes, so videos are reviewed, relabelled and included / excluded without knowing the group.",
                           "设盲期间隐藏组别和组间比较，动物以随机编码显示，从而在不知道分组的情况下复核视频、修改标签、决定纳入/排除。"))
                }
                Section {
                    ParamSlider(title: L("Pass: mouse tracked ≥", "通过：小鼠可用帧 ≥"), value: $qc.passCoverage, range: 0.5...1, step: 0.01, unit: "", decimals: 2,
                                help: L("Share of frames with nose and tail base usable after short-gap filling.", "填补短缺口后，鼻尖和尾根都可用的帧占比。"))
                    ParamSlider(title: L("Fail: mouse tracked <", "不通过：小鼠可用帧 <"), value: $qc.failCoverage, range: 0.3...0.95, step: 0.01, unit: "", decimals: 2)
                    ParamSlider(title: L("Longest loss allowed", "允许的最长丢失"), value: $qc.maxLostSeconds, range: 1...60, step: 1, unit: "s", decimals: 0)
                    ParamSlider(title: L("Minimum frame rate", "最低帧率"), value: $qc.minFPS, range: 10...120, step: 5, unit: "fps", decimals: 0)
                    ParamSlider(title: L("Implausible jumps allowed", "允许的不合理跳点"), value: $qc.maxJumpRate, range: 0...0.1, step: 0.005, unit: "", decimals: 3)
                } header: {
                    Text(L("Inclusion criteria (set before scoring)", "纳入标准（评分前设定）"))
                } footer: {
                    Text(L("Videos meeting every criterion are included automatically; the others wait for a decision with a reason. Changing the criteria recomputes QC for this task's videos.",
                           "满足所有标准的视频自动纳入；其余的需填写原因后决定。修改标准会重新计算本任务视频的 QC。"))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L("Design", "设计"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("Save", "保存")) { save(); dismiss() } }
            }
            .onAppear {
                guard !loaded, let e = store.experiment(experimentID) else { return }
                loaded = true
                wasBlinded = e.blinded
                name = e.name
                notes = e.notes
                factors = e.factors.map { FactorRow(id: $0.id, name: $0.name, levels: $0.levels.joined(separator: ", ")) }
                timepoints = e.timepoints.joined(separator: ", ")
                blinded = e.blinded
                qc = e.qc
            }
        }
        .interactiveDismissDisabled(loaded)
    }

    private func addFactor(_ n: String, _ levels: String) {
        factors.append(FactorRow(id: UUID(), name: n, levels: levels))
    }

    private static func split(_ text: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" }) {
            let v = part.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty && !seen.contains(v) { seen.insert(v); out.append(v) }
        }
        return out
    }

    private func save() {
        let newFactors = factors.compactMap { row -> DesignFactor? in
            let n = row.name.trimmingCharacters(in: .whitespaces)
            let levels = Self.split(row.levels)
            guard !n.isEmpty || !levels.isEmpty else { return nil }
            return DesignFactor(id: row.id, name: n.isEmpty ? L("Factor", "因素") : n, levels: levels)
        }
        let tps = Self.split(timepoints)
        let n = name.trimmingCharacters(in: .whitespaces)
        let note = notes, blind = blinded, criteria = qc
        let locked = wasBlinded
        store.editTask(experimentID) { e in
            if !n.isEmpty { e.name = n }
            e.notes = note
            e.timepoints = tps
            var c = criteria
            if c.failCoverage > c.passCoverage { c.failCoverage = c.passCoverage }
            e.qc = c
            // While blinded the groups and the blinding itself are left as they are.
            guard !locked else { return }
            e.factors = newFactors
            e.blinded = blind
            // Allocations to levels that no longer exist are dropped.
            let valid = Dictionary(uniqueKeysWithValues: newFactors.map { ($0.id.uuidString, Set($0.levels)) })
            for i in e.animals.indices {
                e.animals[i].levels = e.animals[i].levels.filter { valid[$0.key]?.contains($0.value) == true }
            }
        }
    }
}

// MARK: - Animal editor

@MainActor
struct AnimalEditorSheet: View {
    let experimentID: UUID
    let animalID: UUID?
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var sex = AnimalSex.unknown
    @State private var levels: [String: String] = [:]
    @State private var cohort = ""
    @State private var cage = ""
    @State private var notes = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    private var experiment: Experiment? { store.experiment(experimentID) }

    /// An existing animal of a blinded study: its real ID, cage and notes can reveal the group, so
    /// it is shown by its blind code and only sex and cohort can be edited.
    private var masked: Bool { animalID != nil && experiment?.blinded == true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if masked, let e = experiment, let a = e.animal(animalID) {
                        InfoRow(key: L("Animal (blind code)", "动物（盲码）"), value: e.displayCode(a))
                    } else {
                        TextField(L("Animal ID (ear tag, cage card)", "动物编号（耳标、笼卡）"), text: $code)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Picker(L("Sex", "性别"), selection: $sex) {
                        ForEach(AnimalSex.allCases) { Text($0.label).tag($0) }
                    }
                }
                if let e = experiment, !e.activeFactors.isEmpty {
                    Section {
                        if e.blinded {
                            Text(L("Group allocation is hidden while the task is blinded.", "盲法期间隐藏分组。")).font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(e.activeFactors) { f in
                                Picker(f.name, selection: Binding(get: { levels[f.id.uuidString] ?? "" },
                                                                  set: { levels[f.id.uuidString] = $0.isEmpty ? nil : $0 })) {
                                    Text(L("Not allocated", "未分组")).tag("")
                                    ForEach(f.levels, id: \.self) { Text($0).tag($0) }
                                }
                            }
                        }
                    } header: { Text(L("Group", "分组")) }
                }
                Section {
                    TextField(L("Cohort / batch / test day", "批次 / 测试日"), text: $cohort)
                    if !masked {
                        TextField(L("Cage", "笼号"), text: $cage)
                        TextField(L("Notes (strain, age, weight…)", "备注（品系、周龄、体重…）"), text: $notes, axis: .vertical).lineLimit(1...4)
                    }
                } footer: {
                    Text(L("Cohort is a blocking variable: animals tested on different days or in different batches can be balanced across groups when randomising.",
                           "批次是区组变量：随机分组时可让不同测试日或批次的动物在各组间平衡。"))
                }
                if animalID != nil && !masked {
                    Section {
                        Button(L("Remove animal", "移除动物"), role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(animalID == nil ? L("New animal", "新动物") : L("Animal", "动物"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "保存")) { save(); dismiss() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(L("Remove this animal from the task? Its videos stay, with the ID as text.", "从任务中移除该动物？其视频保留，编号以文字形式保存。"),
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Remove", "移除"), role: .destructive) { remove(); dismiss() }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let a = experiment?.animal(animalID) {
                    code = a.code; sex = a.sex; levels = a.levels; cohort = a.cohort; cage = a.cage; notes = a.notes
                }
            }
        }
        // Save or Cancel, never lost by a swipe.
        .interactiveDismissDisabled(loaded)
    }

    private func save() {
        let c = code.trimmingCharacters(in: .whitespaces)
        let s = sex, lv = levels, co = cohort.trimmingCharacters(in: .whitespaces), cg = cage, n = notes
        let target = animalID
        store.editTask(experimentID) { e in
            if let target, let i = e.animals.firstIndex(where: { $0.id == target }) {
                e.animals[i].sex = s
                e.animals[i].cohort = co
                // While blinded only sex and cohort are editable (the rest was not shown).
                guard !e.blinded else { return }
                e.animals[i].code = c
                e.animals[i].levels = lv
                e.animals[i].cage = cg
                e.animals[i].notes = n
            } else {
                var a = Animal(code: c)
                a.sex = s
                a.levels = lv
                a.cohort = co
                a.cage = cg
                a.notes = n
                e.animals.append(a)
            }
        }
    }

    private func remove() {
        guard let target = animalID, let e = experiment, let a = e.animal(target) else { return }
        for r in store.recordings(in: experimentID) where r.animalID == target {
            store.updateRecording(r.id) { $0.animalID = nil; $0.subject = a.code }
        }
        store.backupBeforeChange(MetadataBackup.Reason.beforeBulk)
        store.editTask(experimentID) { $0.animals.removeAll { $0.id == target } }
    }
}

// MARK: - Randomisation

@MainActor
struct RandomizeSheet: View {
    let experimentID: UUID
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var reallocateAll = false
    @State private var byCohort = false
    @State private var seed = UInt64.random(in: 1...999_999)

    private var experiment: Experiment? { store.experiment(experimentID) }

    var body: some View {
        NavigationStack {
            Form {
                if let e = experiment {
                    Section {
                        InfoRow(key: L("Groups", "组数"), value: "\(e.cells.count)")
                        InfoRow(key: L("Animals", "动物"), value: "\(e.animals.count)")
                        InfoRow(key: L("Not yet allocated", "尚未分组"), value: "\(e.unallocated.count)")
                    } footer: {
                        Text(L("Block randomisation stratified by sex: within each sex, animals are dealt to the groups in random blocks of one animal per group, so group sizes differ by at most one. The method and seed are written to the task's design text (ARRIVE 2.0 item 4).",
                               "按性别分层的区组随机：每种性别内，动物按“每组一只”的随机区组依次分配，各组样本量最多相差 1。方法和随机种子会写入研究设计说明（ARRIVE 2.0 第 4 项）。"))
                    }
                    Section {
                        Toggle(L("Also balance cohorts", "同时平衡批次"), isOn: $byCohort)
                        Toggle(L("Re-allocate every animal", "重新分配全部动物"), isOn: $reallocateAll)
                        HStack {
                            Text(L("Seed", "随机种子"))
                            Spacer()
                            Text("\(seed)").monospacedDigit().foregroundStyle(.secondary)
                            Button(L("New", "换一个")) { seed = UInt64.random(in: 1...999_999) }
                                .accessibilityLabel(L("New seed", "新种子"))
                        }
                    } footer: {
                        if reallocateAll {
                            Text(L("Existing allocations will be replaced. Do this only before any treatment was given.", "现有分组将被替换。只应在给予任何处理之前这样做。"))
                                .foregroundStyle(Palette.warning)
                        }
                    }
                    if e.blinded {
                        Section {
                            Text(L("The task is blinded: the allocation is made but stays hidden.", "任务处于盲法状态：分组会完成但保持隐藏。"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L("Randomise", "随机分组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Allocate", "分配")) {
                        let all = reallocateAll, cohort = byCohort, s = seed
                        if all { store.backupBeforeChange(MetadataBackup.Reason.beforeBulk) }
                        store.editTask(experimentID) { e in
                            e = Randomizer.allocate(e, all: all, byCohort: cohort, seed: s)
                        }
                        dismiss()
                    }
                    .disabled((experiment?.animals.isEmpty ?? true) || (experiment?.cells.isEmpty ?? true))
                }
            }
        }
    }
}
