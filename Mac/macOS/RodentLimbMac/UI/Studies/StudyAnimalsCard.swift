// StudyAnimalsCard.swift — the animals of a study in an editable, sortable table (ID, sex, one level
// picker per factor, cohort, cage, notes, number of videos), with multi-selection, a context
// menu (sex, levels, open a video, remove), adding one animal or a pasted list, removing animals
// (keeping or deleting their videos) and the group sizes by sex.
// Blinding (as on the iPhone): animals show their blind code; their group, real ID, cage and notes
// are hidden and cannot be edited, only sex and cohort can; animals cannot be removed.

import SwiftUI

/// One table row: the values used for sorting (the cells edit the animal itself).
struct StudyAnimalRow: Identifiable {
    let id: UUID
    let code: String
    let sex: String
    let group: String
    let cohort: String
    let cage: String
    let notes: String
    let videos: Int
}

struct StudyAnimalsCard: View {
    let experiment: Experiment
    let onRandomise: () -> Void

    @Environment(AppModel.self) private var app
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\StudyAnimalRow.code)]
    @State private var showAdd = false
    @State private var showPaste = false
    @State private var pendingRemoval = Set<UUID>()
    @State private var confirmRemove = false

    init(experiment: Experiment, onRandomise: @escaping () -> Void) {
        self.experiment = experiment
        self.onRandomise = onRandomise
    }

    var body: some View {
        let e = experiment
        Card {
            CardHeader(title: L("Animals", "动物"), symbol: "pawprint",
                       subtitle: L("The experimental unit is the animal. Sex is recorded for every animal (NIH: sex as a biological variable). Click a cell to edit it.",
                                   "实验单位为动物。每只动物都记录性别（NIH：性别作为生物学变量）。点击单元格即可编辑。")) {
                actions(e)
            }
            if e.animals.isEmpty {
                Text(L("Animals are added here (one by one or as a pasted list), or automatically when a video is imported with a new animal ID.",
                       "可在此逐一添加或粘贴列表添加动物，也可在导入视频时输入新编号自动添加。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                table(e, rows: rows(e))
                if !selection.isEmpty {
                    Text(String(format: L("%d selected — right-click for sex, group and removal.", "已选 %d 只——右键可设置性别、分组或移除。"), selection.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            groupSizes(e)
        }
        .sheet(isPresented: $showPaste) {
            StudyPasteAnimalsSheet(experimentID: e.id).environment(app)
        }
        .confirmationDialog(removalTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
            let videos = removalVideos(e)
            if videos.isEmpty {
                Button(L("Remove", "移除"), role: .destructive) { remove(e, deleteVideos: false) }
            } else {
                Button(L("Remove, Keep Their Videos", "移除，保留其视频")) { remove(e, deleteVideos: false) }
                Button(String(format: L("Remove and Delete %d Videos", "移除并删除 %d 段视频"), videos.count), role: .destructive) {
                    remove(e, deleteVideos: true)
                }
            }
            Button(L("Cancel", "取消"), role: .cancel) { pendingRemoval = [] }
        } message: {
            Text(removalMessage(e))
        }
    }

    // MARK: Header actions

    private func actions(_ e: Experiment) -> some View {
        HStack(spacing: 6) {
            Button {
                showAdd = true
            } label: {
                Text(L("Add Animal", "添加动物"))
            }
            .help(L("Add one animal (ID, sex, cohort, group)", "添加一只动物（编号、性别、批次、分组）"))
            .popover(isPresented: $showAdd, arrowEdge: .bottom) {
                StudyAddAnimalForm(experimentID: e.id).environment(app)
            }
            Button {
                showPaste = true
            } label: {
                Text(L("Paste List…", "粘贴列表…"))
            }
            .help(L("Add many animals from a list of IDs (e.g. copied from a spreadsheet)", "从编号列表批量添加动物（如从电子表格拷贝）"))
            Button(action: onRandomise) {
                Text(L("Randomise…", "随机分组…"))
            }
            .disabled(e.cells.isEmpty || e.animals.isEmpty)
            .help(e.cells.isEmpty
                  ? L("Add a between-subject factor with levels in the design first", "请先在设计中添加带水平的组间因素")
                  : L("Allocate animals to groups at random", "将动物随机分配到各组"))
        }
        .controlSize(.small)
    }

    // MARK: Table

    private func rows(_ e: Experiment) -> [StudyAnimalRow] {
        var counts: [UUID: Int] = [:]
        for r in app.store.recordings(in: e.id) {
            if let a = r.animalID { counts[a, default: 0] += 1 }
        }
        let list = e.animals.map { a in
            StudyAnimalRow(id: a.id,
                           code: e.displayCode(a),
                           sex: a.sex.label,
                           group: e.blinded ? "" : e.groupLabel(a),
                           cohort: a.cohort,
                           cage: e.blinded ? "" : a.cage,
                           notes: e.blinded ? "" : a.notes,
                           videos: counts[a.id] ?? 0)
        }
        return list.sorted(using: sortOrder)
    }

    private func tableHeight(_ count: Int) -> CGFloat {
        min(440, max(150, 34 + CGFloat(count) * 30))
    }

    private func groupColumnTitle(_ e: Experiment) -> String {
        let names = e.activeFactors.map(\.name)
        if e.blinded || names.isEmpty { return L("Group", "组别") }
        return L("Group", "组别") + " — " + names.joined(separator: " × ")
    }

    private func table(_ e: Experiment, rows: [StudyAnimalRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L("Animal", "动物"), value: \StudyAnimalRow.code) { row in
                codeCell(row, e)
            }
            .width(min: 80, ideal: 110)
            TableColumn(L("Sex", "性别"), value: \StudyAnimalRow.sex) { row in
                sexCell(row, e)
            }
            .width(min: 90, ideal: 110)
            TableColumn(groupColumnTitle(e), value: \StudyAnimalRow.group) { row in
                groupCell(row, e)
            }
            .width(min: 140, ideal: 240)
            TableColumn(L("Cohort", "批次"), value: \StudyAnimalRow.cohort) { row in
                StudyCommitField(value: row.cohort, prompt: "—") { setCohort(row.id, $0, e) }
            }
            .width(min: 70, ideal: 100)
            TableColumn(L("Cage", "笼号"), value: \StudyAnimalRow.cage) { row in
                hiddenOrField(row.cage, blinded: e.blinded) { setCage(row.id, $0, e) }
            }
            .width(min: 60, ideal: 80)
            TableColumn(L("Notes", "备注"), value: \StudyAnimalRow.notes) { row in
                hiddenOrField(row.notes, blinded: e.blinded) { setNotes(row.id, $0, e) }
            }
            .width(min: 100, ideal: 200)
            TableColumn(L("Videos", "视频"), value: \StudyAnimalRow.videos) { row in
                Text("\(row.videos)")
                    .monospacedDigit()
                    .foregroundStyle(row.videos == 0 ? Color.secondary : Color.primary)
            }
            .width(min: 44, ideal: 56)
        }
        .frame(height: tableHeight(rows.count))
        .contextMenu(forSelectionType: UUID.self) { ids in
            rowMenu(ids, e)
        } primaryAction: { ids in
            openFirstVideo(ids, e)
        }
        .onDeleteCommand { askRemove(selection, e) }
    }

    @ViewBuilder
    private func codeCell(_ row: StudyAnimalRow, _ e: Experiment) -> some View {
        if e.blinded {
            Text(row.code).fontWeight(.semibold)
            .help(L("Blind code. The real ID is hidden until the task is unblinded.", "盲码。揭盲前隐藏真实编号。"))
        } else {
            StudyCommitField(value: row.code, prompt: L("Animal ID", "动物编号")) { rename(row.id, to: $0, e) }
                .fontWeight(.semibold)
        }
    }

    private func sexCell(_ row: StudyAnimalRow, _ e: Experiment) -> some View {
        Picker(L("Sex", "性别"), selection: sexBinding(row.id, e)) {
            ForEach(AnimalSex.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    @ViewBuilder
    private func groupCell(_ row: StudyAnimalRow, _ e: Experiment) -> some View {
        if e.blinded {
            Text(L("Hidden while blinded", "盲法期间隐藏")).foregroundStyle(.tertiary)
        } else if e.activeFactors.isEmpty {
            Text(L("No groups", "无分组")).foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                ForEach(e.activeFactors) { f in
                    Picker(f.name, selection: levelBinding(row.id, f, e)) {
                        Text(L("Not allocated", "未分组")).tag("")
                        ForEach(f.levels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .help(f.name)
                }
            }
        }
    }

    @ViewBuilder
    private func hiddenOrField(_ value: String, blinded: Bool, commit: @escaping (String) -> Bool) -> some View {
        if blinded {
            Text(L("Hidden", "已隐藏"))
                .foregroundStyle(.tertiary)
                .help(L("Hidden while blinded: it could reveal the group.", "盲法期间隐藏：可能泄露分组。"))
        } else {
            StudyCommitField(value: value, prompt: "—", commit: commit)
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UUID>, _ e: Experiment) -> some View {
        if !ids.isEmpty {
            Button(L("Open First Video", "打开第一段视频")) { openFirstVideo(ids, e) }
                .disabled(firstVideo(ids, e) == nil)
            Divider()
            Menu(L("Sex", "性别")) {
                ForEach(AnimalSex.allCases) { s in
                    Button(s.label) { setSex(ids, s, e) }
                }
            }
            if !e.blinded {
                ForEach(e.activeFactors) { f in
                    Menu(f.name) {
                        Button(L("Not allocated", "未分组")) { setLevel(ids, f, nil, e) }
                        ForEach(f.levels, id: \.self) { level in
                            Button(level) { setLevel(ids, f, level, e) }
                        }
                    }
                }
            }
            Divider()
            Button(String(format: L("Remove %d Animal(s)…", "移除 %d 只动物…"), ids.count), role: .destructive) {
                askRemove(ids, e)
            }
            .disabled(e.blinded)
        }
    }

    // MARK: Group sizes

    @ViewBuilder
    private func groupSizes(_ e: Experiment) -> some View {
        if e.blinded {
            Text(String(format: L("%d animals. Group sizes are hidden while the task is blinded.", "共 %d 只动物。盲法期间隐藏各组样本量。"),
                        e.animals.count))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !e.animals.isEmpty {
            let sizes = app.store.groupSizes(e)
            let notAllocated = L("Not allocated", "未分组")
            let counts = sizes.filter { $0.group != notAllocated }.map(\.total)
            let unknownSex = e.animals.filter { $0.sex == .unknown }.count
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Group sizes (n animals)", "各组样本量（动物数）")).font(.callout.weight(.semibold))
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow {
                        Text(L("Group", "组别")).gridColumnAlignment(.leading)
                        Text("n")
                        Text(L("Male", "雄"))
                        Text(L("Female", "雌"))
                        Text(L("Not recorded", "未记录"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(Array(sizes.enumerated()), id: \.offset) { item in
                        GridRow {
                            Text(item.element.group).lineLimit(1)
                            Text("\(item.element.total)")
                            Text("\(item.element.male)")
                            Text("\(item.element.female)")
                            Text("\(max(0, item.element.total - item.element.male - item.element.female))")
                        }
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(item.element.group == notAllocated ? Palette.warning : Color.primary)
                    }
                }
                .textSelection(.enabled)
                if let lo = counts.min(), let hi = counts.max(), hi - lo > 1 {
                    Text(L("Group sizes differ by more than one animal.", "各组样本量相差超过 1 只。"))
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                }
                if unknownSex > 0 {
                    Text(String(format: L("Sex is not recorded for %d animal(s).", "%d 只动物未记录性别。"), unknownSex))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: Bindings and edits

    private func update(_ e: Experiment, _ ids: Set<UUID>, _ change: @escaping (inout Animal) -> Void) {
        app.store.updateExperiment(e.id) { x in
            for i in x.animals.indices where ids.contains(x.animals[i].id) { change(&x.animals[i]) }
        }
    }

    private func sexBinding(_ id: UUID, _ e: Experiment) -> Binding<AnimalSex> {
        Binding(get: { app.store.experiment(e.id)?.animal(id)?.sex ?? .unknown },
                set: { s in update(e, [id]) { $0.sex = s } })
    }

    private func levelBinding(_ id: UUID, _ f: DesignFactor, _ e: Experiment) -> Binding<String> {
        Binding(get: { app.store.experiment(e.id)?.animal(id)?.level(f) ?? "" },
                set: { v in setLevel([id], f, v.isEmpty ? nil : v, e) })
    }

    private func setSex(_ ids: Set<UUID>, _ s: AnimalSex, _ e: Experiment) {
        update(e, ids) { $0.sex = s }
    }

    private func setLevel(_ ids: Set<UUID>, _ f: DesignFactor, _ level: String?, _ e: Experiment) {
        // Groups are never changed while blinded (nobody could see what was changed).
        guard app.store.experiment(e.id)?.blinded == false else { return }
        let key = f.id.uuidString
        update(e, ids) { $0.levels[key] = level }
    }

    private func rename(_ id: UUID, to text: String, _ e: Experiment) -> Bool {
        let c = StudyText.trimmed(text)
        guard !c.isEmpty, let current = app.store.experiment(e.id), !current.blinded else { return false }
        if StudyText.codeTaken(c, in: current, except: id) {
            app.alert = AppAlert(title: L("Duplicate animal ID", "动物编号重复"),
                                 message: String(format: L("Another animal in this task already has the ID “%@”.", "本任务中已有编号为“%@”的动物。"), c))
            return false
        }
        update(e, [id]) { $0.code = c }
        return true
    }

    private func setCohort(_ id: UUID, _ text: String, _ e: Experiment) -> Bool {
        let c = StudyText.trimmed(text)
        update(e, [id]) { $0.cohort = c }
        return true
    }

    private func setCage(_ id: UUID, _ text: String, _ e: Experiment) -> Bool {
        guard app.store.experiment(e.id)?.blinded == false else { return false }
        let c = StudyText.trimmed(text)
        update(e, [id]) { $0.cage = c }
        return true
    }

    private func setNotes(_ id: UUID, _ text: String, _ e: Experiment) -> Bool {
        guard app.store.experiment(e.id)?.blinded == false else { return false }
        update(e, [id]) { $0.notes = text }
        return true
    }

    // MARK: Videos of animals

    private func videos(of ids: Set<UUID>, _ e: Experiment) -> [Recording] {
        app.store.recordings(in: e.id).filter { r in r.animalID.map { ids.contains($0) } ?? false }
    }

    private func firstVideo(_ ids: Set<UUID>, _ e: Experiment) -> Recording? {
        videos(of: ids, e).min { a, b in
            let ta = e.timepoints.firstIndex(of: a.timepoint) ?? Int.max
            let tb = e.timepoints.firstIndex(of: b.timepoint) ?? Int.max
            if ta != tb { return ta < tb }
            if a.trial != b.trial { return a.trial < b.trial }
            return a.createdAt < b.createdAt
        }
    }

    private func openFirstVideo(_ ids: Set<UUID>, _ e: Experiment) {
        if let r = firstVideo(ids, e) {
            app.open(.recording(r.id))
        } else if !ids.isEmpty {
            app.toast = L("No video of this animal yet", "该动物还没有视频")
        }
    }

    // MARK: Removing

    private var removalTitle: String {
        String(format: L("Remove %d animal(s) from the task?", "从任务中移除 %d 只动物？"), pendingRemoval.count)
    }

    private func removalVideos(_ e: Experiment) -> [Recording] {
        videos(of: pendingRemoval, e)
    }

    private func removalMessage(_ e: Experiment) -> String {
        let n = removalVideos(e).count
        guard n > 0 else { return L("They have no videos.", "这些动物没有视频。") }
        return String(format: L("They have %d video(s). Kept videos stay in the task, not linked to an animal, with the animal ID as text.",
                                "这些动物共有 %d 段视频。保留的视频仍在本任务中，不再关联动物，动物编号以文字形式保留。"), n)
    }

    private func askRemove(_ ids: Set<UUID>, _ e: Experiment) {
        guard !ids.isEmpty else { return }
        guard !e.blinded else {
            app.alert = AppAlert(title: L("The task is blinded", "任务处于盲法状态"),
                                 message: L("Animals cannot be removed while the task is blinded: their IDs and videos could reveal the allocation. Unblind first.",
                                            "盲法期间不能移除动物：其编号和视频可能泄露分组。请先揭盲。"))
            return
        }
        pendingRemoval = ids
        confirmRemove = true
    }

    private func remove(_ e: Experiment, deleteVideos: Bool) {
        let ids = pendingRemoval
        pendingRemoval = []
        let store = app.store
        guard !ids.isEmpty, let current = store.experiment(e.id), !current.blinded else { return }
        let recs = videos(of: ids, current)
        if deleteVideos {
            for r in recs where app.batch.jobs[r.id] != nil { app.batch.cancel(r.id) }
            let recIDs = Set(recs.map(\.id))
            app.selectedRecordings.subtract(recIDs)
            store.deleteRecordings(recIDs)
        } else {
            for r in recs {
                let code = current.animal(r.animalID)?.code ?? r.subject
                store.updateRecording(r.id) { rec in
                    rec.animalID = nil
                    rec.subject = code
                }
            }
        }
        store.updateExperiment(e.id) { x in x.animals.removeAll { ids.contains($0.id) } }
        selection.subtract(ids)
        app.toast = String(format: L("Removed %d animal(s)", "已移除 %d 只动物"), ids.count)
    }
}
