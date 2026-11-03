// TaskSupport.swift — tasks, the unit the user works in ("task first", as in RodentFlow):
// choose the paradigm when the task is created, add videos into it, results by group.
//
// A task is stored as a study (`Experiment`) whose planned assays are exactly the task's paradigm, so
// the files stay those of the iPhone app and of earlier versions. A study with several paradigms
// (planned, or analysed in its videos) shows up as one task per paradigm, sharing its groups and
// animals — a task is therefore identified by (study, paradigm).
//
// Groups are the levels of the study's factor (one factor "Group" for tasks made here); an older
// study with a factorial design keeps it and its cells are the groups ("KO · Drug").

import Foundation

struct TaskRef: Hashable, Codable, Sendable {
    var experimentID: UUID
    var assay: Assay
}

/// Counts of one task, for the sidebar and the task page.
struct TaskCounts: Equatable {
    var sessions = 0
    var tracking = 0
    var review = 0
    var failed = 0
    var excluded = 0
    var done = 0
}

/// What moving videos into or out of a task did, so it can be undone.
struct TaskMove {
    var ids: Set<UUID>
    /// Study of each video before (nil = none).
    var previousStudy: [UUID: UUID?] = [:]
    /// Sessions created in the target task.
    var createdSessions: Set<UUID> = []
    /// Sessions moved to Recently Deleted.
    var removedEntry: UUID?
    /// Videos that left their study (now "Not in a task").
    var left: Set<UUID> = []
}

/// What deleting a task did, so it can be undone.
struct TaskDeletion {
    /// Recently Deleted entry of a deleted study.
    var entry: UUID?
    /// Sessions removed from a study that keeps other tasks.
    var move: TaskMove?
    /// The paradigm taken off the study's plan.
    var unplanned: TaskRef?
}

/// Name of the factor of a task made in RodentLimb 1.4 (its levels are the groups).
let kTaskGroupFactor = "Group"

/// The paradigms as offered by New Task, grouped by purpose.
enum TaskParadigms {
    struct Section: Identifiable {
        let id: String
        let title: String
        let assays: [Assay]
    }

    static var sections: [Section] {
        [
            Section(id: "motor", title: L("Motor", "运动"), assays: [.gait, .cylinder]),
            Section(id: "pain", title: L("Pain and itch", "疼痛与瘙痒"), assays: [.itch, .pain]),
            Section(id: "affect", title: L("Affective and repetitive behaviour", "情绪与刻板行为"), assays: [.tailSuspension, .grooming]),
            Section(id: "seizure", title: L("Seizure", "癫痫"), assays: [.seizure]),
        ]
    }
}

extension SessionStore {
    // MARK: Listing

    /// Paradigms analysed in the videos of each study (one pass over the sessions).
    func analysedAssaysByStudy() -> [UUID: Set<Assay>] {
        var out: [UUID: Set<Assay>] = [:]
        for s in sessions {
            if let eid = recording(for: s)?.experimentID { out[eid, default: []].insert(s.assay) }
        }
        return out
    }

    /// The paradigms of a study as tasks: planned ones first (in their order), then any other
    /// paradigm analysed in its videos.
    func taskAssays(of e: Experiment, analysed: Set<Assay>? = nil) -> [Assay] {
        var out: [Assay] = []
        for a in e.plannedAssays where !out.contains(a) { out.append(a) }
        let found: Set<Assay>
        if let analysed {
            found = analysed
        } else {
            var set = Set<Assay>()
            for s in sessions where !out.contains(s.assay) && !set.contains(s.assay) {
                if recording(for: s)?.experimentID == e.id { set.insert(s.assay) }
            }
            found = set
        }
        for a in Assay.allCases where found.contains(a) && !out.contains(a) { out.append(a) }
        return out
    }

    /// Every task, newest study first.
    var tasks: [TaskRef] {
        let analysed = analysedAssaysByStudy()
        return experiments.sorted { $0.createdAt > $1.createdAt }.flatMap { e in
            taskAssays(of: e, analysed: analysed[e.id] ?? []).map { TaskRef(experimentID: e.id, assay: $0) }
        }
    }

    func taskExists(_ t: TaskRef) -> Bool {
        guard let e = experiment(t.experimentID) else { return false }
        if e.plannedAssays.contains(t.assay) { return true }
        return taskAssays(of: e).contains(t.assay)
    }

    /// "SNI cohort 2"; "SNI cohort 2 · Gait" when the study holds several tasks (`shared`: known
    /// already, e.g. for a whole list).
    func taskTitle(_ t: TaskRef, shared: Bool? = nil) -> String {
        guard let e = experiment(t.experimentID) else { return t.assay.name.text }
        let name = e.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("Untitled task", "未命名任务") : e.name
        let several = shared ?? (taskAssays(of: e).count > 1)
        return several ? name + " · " + t.assay.name.text : name
    }

    /// Sessions, items needing review and sessions per group of every task (one pass, for the sidebar).
    struct TaskOverview {
        var tasks: [TaskRef] = []
        var sessions: [TaskRef: Int] = [:]
        var review: [TaskRef: Int] = [:]
        var groups: [TaskRef: [(name: String, count: Int)]] = [:]
        /// Studies holding several tasks (their tasks are titled "Study · Paradigm").
        var shared: Set<UUID> = []
        /// Videos in no task, and studies without a paradigm.
        var notInTask = 0
        var studiesWithoutTask = 0
    }

    func taskOverview() -> TaskOverview {
        var o = TaskOverview()
        o.tasks = tasks
        var perStudy: [UUID: Int] = [:]
        for t in o.tasks { perStudy[t.experimentID, default: 0] += 1 }
        o.shared = Set(perStudy.filter { $0.value > 1 }.map(\.key))
        o.studiesWithoutTask = experiments.filter { perStudy[$0.id] == nil }.count
        o.notInTask = recordings.filter { r in
            guard let eid = r.experimentID, experiment(eid) != nil else { return true }
            return perStudy[eid] == nil
        }.count
        // Group of each animal, once per study (not a scan of the animals for every session).
        var groupOf: [UUID: [UUID: String]] = [:]
        for e in experiments where !e.blinded && perStudy[e.id] != nil {
            var map: [UUID: String] = [:]
            for a in e.animals { map[a.id] = e.groupLabel(a) }
            groupOf[e.id] = map
        }
        var groupCounts: [TaskRef: [String: Int]] = [:]
        for s in sessions {
            guard let r = recording(for: s), let eid = r.experimentID else { continue }
            let t = TaskRef(experimentID: eid, assay: s.assay)
            o.sessions[t, default: 0] += 1
            if r.status == .ready && r.decision == .pending && r.qc != nil { o.review[t, default: 0] += 1 }
            if let aid = r.animalID, let g = groupOf[eid]?[aid], !g.isEmpty { groupCounts[t, default: [:]][g, default: 0] += 1 }
        }
        for t in o.tasks {
            guard let e = experiment(t.experimentID), !e.blinded else { continue }
            var names = e.cells.map { $0.joined(separator: " · ") }
            for g in (groupCounts[t] ?? [:]).keys.sorted() where !names.contains(g) { names.append(g) }
            o.groups[t] = names.map { ($0, groupCounts[t]?[$0] ?? 0) }
        }
        return o
    }

    // MARK: Sessions and groups

    /// Group of a video in its task ("" = no group; hidden while the task is blinded).
    func taskGroup(_ r: Recording) -> String {
        guard let e = experiment(for: r), !e.blinded, let a = e.animal(r.animalID) else { return "" }
        return e.groupLabel(a)
    }

    /// The sessions of a task, optionally of one group, in animal / timepoint / trial order.
    func sessions(in t: TaskRef, group: String? = nil) -> [Session] {
        let e = experiment(t.experimentID)
        let timepoints = e?.timepoints ?? []
        // Sort keys computed once per session (not in the comparator).
        var out: [(s: Session, label: String, tp: Int, trial: Int, created: Date)] = []
        for s in sessions where s.assay == t.assay {
            guard let r = recording(for: s), r.experimentID == t.experimentID else { continue }
            if let group, taskGroup(r) != group { continue }
            out.append((s, subjectLabel(r), timepoints.firstIndex(of: r.timepoint) ?? timepoints.count, r.trial, r.createdAt))
        }
        return out.sorted { a, b in
            if a.label != b.label { return a.label.localizedStandardCompare(b.label) == .orderedAscending }
            if a.tp != b.tp { return a.tp < b.tp }
            if a.trial != b.trial { return a.trial < b.trial }
            return a.created < b.created
        }.map(\.s)
    }

    /// The groups of a task: the design's groups in order, then any other group its videos use.
    func taskGroups(_ t: TaskRef) -> [String] {
        guard let e = experiment(t.experimentID), !e.blinded else { return [] }
        var out = e.cells.map { $0.joined(separator: " · ") }
        var extra = Set<String>()
        for s in sessions where s.assay == t.assay {
            guard let r = recording(for: s), r.experimentID == t.experimentID else { continue }
            let g = taskGroup(r)
            if !g.isEmpty && !out.contains(g) { extra.insert(g) }
        }
        out.append(contentsOf: extra.sorted())
        return out
    }

    func taskCounts(_ t: TaskRef, group: String? = nil) -> TaskCounts {
        var c = TaskCounts()
        for s in sessions where s.assay == t.assay {
            guard let r = recording(for: s), r.experimentID == t.experimentID else { continue }
            if let group, taskGroup(r) != group { continue }
            c.sessions += 1
            switch r.status {
            case .queued, .processing: c.tracking += 1
            case .failed: c.failed += 1
            case .ready:
                switch r.decision {
                case .pending: if r.qc != nil { c.review += 1 }
                case .excluded: c.excluded += 1
                case .included: if s.status == .done { c.done += 1 }
                }
            }
        }
        return c
    }

    // MARK: Creating and changing tasks

    /// Creates a task: a study planned for exactly this paradigm, with its groups (one factor
    /// "Group") and timepoints.
    @discardableResult
    func createTask(assay: Assay, name: String, groups: [String], timepoints: [String] = [],
                    notes: String = "", blinded: Bool = false) -> TaskRef {
        let clean = Self.uniqueTrimmed(groups)
        let points = Self.uniqueTrimmed(timepoints)
        let e = createExperiment(name.trimmingCharacters(in: .whitespaces).isEmpty
                                 ? assay.name.text + " " + Self.dayStamp() : name)
        updateExperiment(e.id) { x in
            x.plannedAssays = [assay]
            x.factors = clean.isEmpty ? [] : [DesignFactor(name: kTaskGroupFactor, levels: clean)]
            x.timepoints = points
            x.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            x.blinded = blinded
        }
        flush()
        log.write("New task \(assay.code): \(experiment(e.id)?.name ?? "")")
        return TaskRef(experimentID: e.id, assay: assay)
    }

    /// Adds a group to a task (to its single factor; a factorial design is edited in the design sheet).
    func addGroup(_ name: String, to t: TaskRef) {
        let g = name.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, let e = experiment(t.experimentID), e.factors.count <= 1 else { return }
        updateExperiment(t.experimentID) { x in
            if x.factors.isEmpty { x.factors = [DesignFactor(name: kTaskGroupFactor, levels: [])] }
            if !x.factors[0].levels.contains(where: { $0.compare(g, options: .caseInsensitive) == .orderedSame }) {
                x.factors[0].levels.append(g)
            }
        }
    }

    /// Puts an animal in a group of a single-factor task (adding the group when it is new). An animal
    /// that already has a group keeps it unless `replace`.
    func setGroup(_ group: String, animal id: UUID, in experimentID: UUID, replace: Bool = false) {
        let g = group.trimmingCharacters(in: .whitespaces)
        guard !g.isEmpty, let e = experiment(experimentID), e.factors.count <= 1,
              let a = e.animal(id) else { return }
        if !replace, let f = e.factors.first, a.level(f) != nil { return }
        updateExperiment(experimentID) { x in
            if x.factors.isEmpty { x.factors = [DesignFactor(name: kTaskGroupFactor, levels: [])] }
            let level = x.factors[0].levels.first { $0.compare(g, options: .caseInsensitive) == .orderedSame } ?? g
            if !x.factors[0].levels.contains(level) { x.factors[0].levels.append(level) }
            if let i = x.animals.firstIndex(where: { $0.id == id }) {
                x.animals[i].levels[x.factors[0].id.uuidString] = level
            }
        }
    }

    /// Videos that are in no task (no study, or a study without a paradigm).
    var recordingsNotInTask: [Recording] {
        let withTask = Set(tasks.map(\.experimentID))
        return recordings.filter { r in
            guard let eid = r.experimentID, experiment(eid) != nil else { return true }
            return !withTask.contains(eid)
        }
    }

    /// Studies without a paradigm (made on the iPhone before 1.4 without planned tasks).
    var studiesWithoutTask: [Experiment] {
        let withTask = Set(tasks.map(\.experimentID))
        return experiments.filter { !withTask.contains($0.id) }
    }

    /// Gives a study without a paradigm its paradigm (it becomes a task).
    func setParadigm(_ assay: Assay, for experimentID: UUID) {
        updateExperiment(experimentID) { x in if !x.plannedAssays.contains(assay) { x.plannedAssays.append(assay) } }
        for r in recordings(in: experimentID) { assign([assay], to: r.id) }
        flush()
    }

    /// Puts videos into a task. A video joins the task's study (its animal matched by ID; a group
    /// kept as text becomes the animal's group when the animal has none) and gets the task's session.
    /// A video belongs to one study: its sessions of other paradigms belonged to tasks of its old study
    /// and go to Recently Deleted. Within one study, `source` names the task the videos leave (its
    /// sessions go to Recently Deleted). The result undoes it all (`undoMove`).
    @discardableResult
    func moveToTask(_ ids: Set<UUID>, task t: TaskRef, from source: TaskRef? = nil) -> TaskMove {
        var m = TaskMove(ids: ids)
        guard let target = experiment(t.experimentID) else { return m }
        var remove = Set<UUID>()
        var joining = Set<UUID>()
        for id in ids {
            guard let r = recording(id) else { continue }
            m.previousStudy[id] = r.experimentID
            if r.experimentID == t.experimentID {
                if let source, source.experimentID == t.experimentID, source.assay != t.assay {
                    for s in sessions(of: id) where s.assay == source.assay { remove.insert(s.id) }
                }
            } else {
                for s in sessions(of: id) where s.assay != t.assay { remove.insert(s.id) }
                joining.insert(id)
            }
        }
        // The group each joining video carries: its animal's group in its old task (not while that task
        // is blinded), or the group kept as text by a video outside any task.
        var carried: [UUID: String] = [:]
        for id in joining {
            guard let r = recording(id) else { continue }
            let g = r.experimentID == nil ? r.group : taskGroup(r)
            if !g.trimmingCharacters(in: .whitespaces).isEmpty { carried[id] = g }
        }
        if !remove.isEmpty { m.removedEntry = delete(remove) }
        if !joining.isEmpty {
            move(joining, toStudy: t.experimentID)
            if !target.blinded && target.factors.count <= 1 {
                for (id, g) in carried {
                    if let aid = recording(id)?.animalID { setGroup(g, animal: aid, in: t.experimentID) }
                }
            }
        }
        for id in ids where recording(id) != nil {
            m.createdSessions.formUnion(assign([t.assay], to: id).map(\.id))
        }
        flush()
        log.write("Moved \(ids.count) video(s) to task \(taskTitle(t))")
        return m
    }

    /// Takes videos out of a task (or, with nil, out of every task of their study): those sessions go
    /// to Recently Deleted, and a video left with no session in its study leaves the study (it is then
    /// listed under "Not in a task", its animal ID and group kept as text). The result undoes it.
    @discardableResult
    func removeFromTask(_ recordingIDs: Set<UUID>, task t: TaskRef?) -> TaskMove {
        var m = TaskMove(ids: [])
        var remove = Set<UUID>()
        var leaving = Set<UUID>()
        for id in recordingIDs {
            guard let r = recording(id), let eid = r.experimentID else { continue }
            if let t, eid != t.experimentID { continue }
            m.ids.insert(id)
            m.previousStudy[id] = eid
            let mine = sessions(of: id)
            let gone = mine.filter { s in t.map { s.assay == $0.assay } ?? true }
            remove.formUnion(gone.map(\.id))
            if gone.count == mine.count { leaving.insert(id) }
        }
        if !remove.isEmpty { m.removedEntry = delete(remove) }
        if !leaving.isEmpty { move(leaving, toStudy: nil) }
        m.left = leaving
        flush()
        log.write("Removed \(m.ids.count) video(s) from \(t.map { taskTitle($0) } ?? "their tasks")")
        return m
    }

    /// Undoes a move or a removal: new sessions are erased, the videos go back to their studies and
    /// the removed sessions come back from Recently Deleted.
    func undoMove(_ m: TaskMove) async {
        if !m.createdSessions.isEmpty, let e = delete(m.createdSessions) { await eraseDeleted(e) }
        var byStudy: [UUID?: Set<UUID>] = [:]
        for id in m.ids where recording(id) != nil {
            let before = m.previousStudy[id] ?? nil
            if recording(id)?.experimentID != before { byStudy[before, default: []].insert(id) }
        }
        for (study, ids) in byStudy { move(ids, toStudy: study.flatMap { experiment($0) != nil ? $0 : nil }) }
        if let entry = m.removedEntry { _ = await restoreDeleted(entry) }
        flush()
    }

    /// What deleting a task will do (for its confirmation).
    struct TaskDeletionPlan {
        /// The study holds only this task: deleting it deletes the study.
        var wholeStudy: Bool
        /// Videos deleted with "delete videos too" (whole study), or sessions removed otherwise.
        var videos: Int
        var sessions: Int
    }

    func deletionPlan(_ t: TaskRef) -> TaskDeletionPlan {
        guard let e = experiment(t.experimentID) else { return TaskDeletionPlan(wholeStudy: true, videos: 0, sessions: 0) }
        let whole = taskAssays(of: e).allSatisfy { $0 == t.assay }
        return TaskDeletionPlan(wholeStudy: whole, videos: recordings(in: e.id).count, sessions: sessions(in: t).count)
    }

    /// Deletes a task. A study holding only this task is deleted (its videos too, unless
    /// `keepVideos`); a study with other tasks loses this paradigm (its sessions go to Recently
    /// Deleted; videos left without a session move to "Not in a task").
    @discardableResult
    func deleteTask(_ t: TaskRef, keepVideos: Bool) -> TaskDeletion {
        guard let e = experiment(t.experimentID) else { return TaskDeletion() }
        let others = taskAssays(of: e).filter { $0 != t.assay }
        if others.isEmpty {
            return TaskDeletion(entry: deleteExperiment(t.experimentID, deleteVideos: !keepVideos))
        }
        let ids = Set(sessions(in: t).compactMap(\.recordingID))
        let wasPlanned = e.plannedAssays.contains(t.assay)
        updateExperiment(t.experimentID) { $0.plannedAssays.removeAll { $0 == t.assay } }
        let move = removeFromTask(ids, task: t)
        return TaskDeletion(move: move, unplanned: wasPlanned ? t : nil)
    }

    /// Undoes `deleteTask`.
    func undoDeleteTask(_ d: TaskDeletion) async {
        if let entry = d.entry { _ = await restoreDeleted(entry) }
        if let t = d.unplanned {
            updateExperiment(t.experimentID) { x in if !x.plannedAssays.contains(t.assay) { x.plannedAssays.append(t.assay) } }
        }
        if let m = d.move { await undoMove(m) }
        flush()
    }

    // MARK: Helpers

    nonisolated static func uniqueTrimmed(_ list: [String]) -> [String] {
        var out: [String] = []
        for s in list {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !out.contains(where: { $0.compare(t, options: .caseInsensitive) == .orderedSame }) { out.append(t) }
        }
        return out
    }

    nonisolated static func dayStamp(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// The group a file seems to belong to: a group name found in the file or folder name.
    nonisolated static func guessGroup(_ url: URL, groups: [String]) -> String? {
        guard !groups.isEmpty else { return nil }
        let haystack = (url.deletingPathExtension().lastPathComponent + " " + url.deletingLastPathComponent().lastPathComponent)
            .lowercased()
        let tokens = Set(haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        // Whole-word matches first ("sham" in "M3_sham_d7"), then substrings of longer names.
        if let g = groups.first(where: { tokens.contains($0.lowercased()) }) { return g }
        return groups.filter { $0.count >= 3 }.sorted { $0.count > $1.count }.first { haystack.contains($0.lowercased()) }
    }
}
