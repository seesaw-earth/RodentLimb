// Tasks.swift — the task-first view of the library (TASK_FIRST_SPEC.md §1–§2).
//
// A task (任务) is one paradigm run as one experiment. It is stored as an `Experiment` whose
// `plannedAssays == [assay]`; no file format changes. A study of 1.0–1.3 with several paradigms
// (planned, or present in its analyses) shows as one task per paradigm, so a task is referred to by
// (experimentID, assay). Hierarchy everywhere: task → group → animal → session (timepoint · trial · date).
// A session is the `Session` of the task's assay made from one `Recording` (video); it is created when
// the video is added, so it appears in the task at once.
//
// Foundation only (no SwiftUI), so the logic compiles and can be tested without the iOS SDK.

import Foundation

struct TaskRef: Hashable, Codable, Identifiable {
    var experimentID: UUID
    var assay: Assay
    var id: String { experimentID.uuidString + "|" + assay.rawValue }
}

/// What moving videos into or out of a task did, so it can be undone (`SessionStore.undoMove`).
struct TaskMove {
    var ids: Set<UUID>
    /// Study of each video before (nil = none).
    var previousStudy: [UUID: UUID?] = [:]
    /// Sessions created in the target task.
    var createdSessions: Set<UUID> = []
    /// Sessions moved to Recently Deleted (one entry).
    var removedEntry: UUID?
    /// Videos that left their study (now "Not in a task").
    var left: Set<UUID> = []
}

/// What deleting a task did, so it can be undone (`SessionStore.undoDeleteTask`).
struct TaskDeletion {
    /// Recently Deleted entry of a deleted study.
    var entry: UUID?
    /// Sessions removed from a study that keeps other tasks.
    var move: TaskMove?
    /// The paradigm taken off the study's plan, and where it was in the plan.
    var unplanned: TaskRef?
    var unplannedIndex: Int?
}

/// What deleting a task will do (for its confirmation).
struct TaskDeletionPlan {
    /// The study holds only this task: deleting the task deletes the study.
    var wholeStudy: Bool
    var videos: Int
    var sessions: Int
}

/// Counts shown in task rows and headers ("12 sessions · 3 need review").
struct TaskCounts: Equatable {
    var sessions = 0
    var needsReview = 0
    /// Waiting for or running the pose model, or QC still being computed.
    var processing = 0
    var failed = 0
    var excluded = 0
    var needsCalibration = 0
    var ready = 0

    var summary: String {
        var parts = [String(format: L("%d sessions", "%d 个实验"), sessions)]
        if needsReview > 0 { parts.append(String(format: L("%d need review", "%d 个待审核"), needsReview)) }
        if processing > 0 { parts.append(String(format: L("%d processing", "%d 个处理中"), processing)) }
        if failed > 0 { parts.append(String(format: L("%d failed", "%d 个失败"), failed)) }
        return parts.joined(separator: " · ")
    }
}

/// State of one session in a task, as the user sees it (short coloured text in rows).
enum SessionState: Equatable {
    case queued, processing, checking, needsReview, excluded, failed, needsCalibration, ready

    var title: String {
        switch self {
        case .queued: return L("Queued", "排队中")
        case .processing: return L("Tracking", "识别中")
        case .checking: return L("Checking quality", "检查质量中")
        case .needsReview: return L("Needs review", "待审核")
        case .excluded: return L("Excluded", "已排除")
        case .failed: return L("Failed", "失败")
        case .needsCalibration: return L("Needs calibration", "需要标定")
        case .ready: return L("Done", "完成")
        }
    }
}

/// Paradigms offered for a new task, grouped by purpose (spec §2.1), with a one-line explanation.
enum TaskCatalog {
    struct Section: Identifiable {
        var id: String { title.en }
        let title: LText
        let assays: [Assay]
    }

    static let sections: [Section] = [
        Section(title: LText("Motor", "运动功能"), assays: [.gait, .cylinder]),
        Section(title: LText("Pain and itch", "疼痛与瘙痒"), assays: [.itch, .pain]),
        Section(title: LText("Affective and repetitive", "情绪与刻板行为"), assays: [.tailSuspension, .grooming]),
        Section(title: LText("Seizure", "癫痫"), assays: [.seizure]),
    ]

    static func blurb(_ a: Assay) -> LText {
        switch a {
        case .gait: return LText("Stride, stance and swing, coordination; bottom view of a walkway.", "步幅、支撑与摆动、协调性；步道仰视。")
        case .cylinder: return LText("Left, right and both forepaw wall contacts while rearing.", "竖立时左、右、双前爪触壁。")
        case .itch: return LText("Scratching bouts, time and latency after a pruritogen.", "致痒剂后的抓挠次数、时间与潜伏期。")
        case .pain: return LText("Licking and flinching of the injected paw; formalin phases.", "注射爪的舔咬与甩爪；福尔马林分相。")
        case .tailSuspension: return LText("Immobility, latency, clasping and tail climbing.", "不动时间、潜伏期、抱握与爬尾。")
        case .grooming: return LText("Grooming time, bouts and body regions; microstructure.", "理毛时间、次数与身体部位；微结构。")
        case .seizure: return LText("Racine-type stage, jerks, clonus and latencies.", "Racine 类分级、抽动、阵挛与潜伏期。")
        }
    }

    /// Paradigms that need a calibration before results are meaningful.
    static func needsCalibration(_ a: Assay) -> Bool { a == .cylinder || a == .gait }
}

/// Sessions of a task arranged for the Sessions list: group → animal → sessions.
struct TaskGroupNode: Identifiable {
    var id: String { name }
    var name: String
    var animals: [TaskAnimalNode]
    var sessionCount: Int { animals.reduce(0) { $0 + $1.sessions.count } }
}

struct TaskAnimalNode: Identifiable {
    var id: String
    var label: String
    var sessions: [Session]
}

@MainActor
extension SessionStore {
    // MARK: Listing

    /// Paradigms of a study: the planned ones (in order), then any present in its analyses.
    private func taskAssays(_ e: Experiment, present: Set<Assay>) -> [Assay] {
        var out = e.plannedAssays
        for a in Assay.allCases where present.contains(a) && !out.contains(a) { out.append(a) }
        return out
    }

    /// Paradigms present in the analyses of each study (one pass over the analyses).
    private func presentAssays() -> [UUID: Set<Assay>] {
        var map: [UUID: Set<Assay>] = [:]
        for s in sessions {
            guard let eid = recording(for: s)?.experimentID else { continue }
            map[eid, default: []].insert(s.assay)
        }
        return map
    }

    /// Every task, newest study first; a study with several paradigms gives one task per paradigm.
    var tasks: [TaskRef] {
        let present = presentAssays()
        return experiments.flatMap { e in taskAssays(e, present: present[e.id] ?? []).map { TaskRef(experimentID: e.id, assay: $0) } }
    }

    /// Studies of 1.0–1.3 without any paradigm yet (no planned task, no analysis).
    var studiesWithoutTask: [Experiment] {
        let present = presentAssays()
        return experiments.filter { taskAssays($0, present: present[$0.id] ?? []).isEmpty }
    }

    /// Tasks of a study.
    func tasks(of eid: UUID) -> [TaskRef] {
        guard let e = experiment(eid) else { return [] }
        let present = Set(sessions.filter { recording(for: $0)?.experimentID == eid }.map(\.assay))
        return taskAssays(e, present: present).map { TaskRef(experimentID: eid, assay: $0) }
    }

    func taskExists(_ t: TaskRef) -> Bool {
        guard let e = experiment(t.experimentID) else { return false }
        if e.plannedAssays.contains(t.assay) { return true }
        return sessions.contains { $0.assay == t.assay && recording(for: $0)?.experimentID == t.experimentID }
    }

    /// The task a session belongs to (nil when its video is in no study).
    func task(for s: Session) -> TaskRef? {
        guard let eid = recording(for: s)?.experimentID, experiment(eid) != nil else { return nil }
        return TaskRef(experimentID: eid, assay: s.assay)
    }

    /// "Gait — SNI cohort 2"; a study with several paradigms: "Study · Gait analysis".
    func taskName(_ t: TaskRef) -> String {
        guard let e = experiment(t.experimentID) else { return t.assay.name.text }
        let name = e.name.isEmpty ? t.assay.name.text : e.name
        return tasks(of: t.experimentID).count > 1 ? name + " · " + t.assay.name.text : name
    }

    /// Names of many tasks in one pass (for lists: no scan of the library per row).
    func taskNames(_ list: [TaskRef]) -> [TaskRef: String] {
        var perStudy: [UUID: Int] = [:]
        for t in list { perStudy[t.experimentID, default: 0] += 1 }
        var out: [TaskRef: String] = [:]
        for t in list {
            let e = experiment(t.experimentID)
            let name = (e?.name.isEmpty ?? true) ? t.assay.name.text : e!.name
            out[t] = (perStudy[t.experimentID] ?? 0) > 1 ? name + " · " + t.assay.name.text : name
        }
        return out
    }

    /// Sessions of a task in animal / timepoint / trial / date order. Sort keys are computed once per
    /// session, and the list is cached until the library changes (`revision`), so screens can ask for
    /// it freely while they redraw.
    func sessions(in t: TaskRef) -> [Session] {
        if let c = taskSessionCache[t], c.revision == revision { return c.list }
        guard let e = experiment(t.experimentID) else { return [] }
        let timepoints = e.timepoints
        var keyed: [(s: Session, label: String, tp: Int, trial: Int, created: Date)] = []
        for s in sessions where s.assay == t.assay {
            guard let r = recording(for: s), r.experimentID == t.experimentID else { continue }
            keyed.append((s, subjectLabel(r), timepoints.firstIndex(of: r.timepoint) ?? timepoints.count, r.trial, r.recordedOn ?? r.createdAt))
        }
        let list = keyed.sorted { a, b in
            if a.label != b.label { return a.label.localizedStandardCompare(b.label) == .orderedAscending }
            if a.tp != b.tp { return a.tp < b.tp }
            if a.trial != b.trial { return a.trial < b.trial }
            return a.created < b.created
        }.map(\.s)
        if taskSessionCache.count > 64 { taskSessionCache.removeAll() }
        taskSessionCache[t] = (revision, list)
        return list
    }

    // MARK: States and counts

    /// A tracked video whose QC needs a decision (QC computed, not passed automatically).
    func needsReview(_ r: Recording) -> Bool { r.isProcessed && r.decision == .pending && r.qc != nil }

    func state(of s: Session) -> SessionState {
        guard let r = recording(for: s) else { return s.status == .failed ? .failed : .ready }
        switch r.status {
        case .queued: return .queued
        case .processing: return .processing
        case .failed: return .failed
        case .ready:
            switch r.decision {
            case .excluded: return .excluded
            case .pending: return r.qc == nil ? .checking : .needsReview
            case .included: return s.status == .needsSetup ? .needsCalibration : .ready
            }
        }
    }

    private func add(_ st: SessionState, to c: inout TaskCounts) {
        c.sessions += 1
        switch st {
        case .queued, .processing, .checking: c.processing += 1
        case .needsReview: c.needsReview += 1
        case .excluded: c.excluded += 1
        case .failed: c.failed += 1
        case .needsCalibration: c.needsCalibration += 1
        case .ready: c.ready += 1
        }
    }

    /// Counts of every task in one pass over the analyses (for the Tasks list).
    func taskCounts() -> [TaskRef: TaskCounts] {
        var out: [TaskRef: TaskCounts] = [:]
        for s in sessions {
            guard let eid = recording(for: s)?.experimentID else { continue }
            add(state(of: s), to: &out[TaskRef(experimentID: eid, assay: s.assay), default: TaskCounts()])
        }
        return out
    }

    func counts(_ t: TaskRef) -> TaskCounts { counts(of: sessions(in: t)) }

    func counts(of list: [Session]) -> TaskCounts {
        var c = TaskCounts()
        for s in list { add(state(of: s), to: &c) }
        return c
    }

    // MARK: Groups

    /// Group labels of a study in design order ("Control", "Treatment"; factorial: "WT · Vehicle").
    func groupChoices(_ e: Experiment) -> [String] { e.cells.map { $0.joined(separator: " · ") } }

    /// Group of a video's animal as it may be shown now ("" while blinded).
    func groupName(_ r: Recording, in e: Experiment) -> String {
        if e.blinded { return "" }
        guard let a = e.animal(r.animalID) else { return L("No animal ID", "无动物编号") }
        let g = e.groupLabel(a)
        if g.isEmpty { return e.cells.isEmpty ? L("All animals", "全部动物") : L("Not allocated", "未分组") }
        return g
    }

    /// The sessions of a task as group → animal → session. While blinded, one group with animals by code.
    func taskTree(_ t: TaskRef, sessions list: [Session]? = nil) -> [TaskGroupNode] {
        guard let e = experiment(t.experimentID) else { return [] }
        var groups: [String: [String: TaskAnimalNode]] = [:]
        for s in list ?? sessions(in: t) {
            guard let r = recording(for: s) else { continue }
            let g = e.blinded ? L("All animals (blinded)", "全部动物（盲法）") : groupName(r, in: e)
            let a = e.animal(r.animalID)
            let key = a?.id.uuidString ?? "free:" + r.subject
            let label = a.map { e.displayCode($0) } ?? (r.subject.isEmpty ? L("No animal ID", "无动物编号") : r.subject)
            var node = groups[g]?[key] ?? TaskAnimalNode(id: g + "|" + key, label: label, sessions: [])
            node.sessions.append(s)
            groups[g, default: [:]][key] = node
        }
        let order = groupChoices(e)
        func rank(_ name: String) -> (Int, String) { (order.firstIndex(of: name) ?? order.count, name) }
        let tpOrder = e.timepoints
        return groups.keys.sorted { rank($0) < rank($1) }.map { g in
            let animals = (groups[g] ?? [:]).values.map { node -> TaskAnimalNode in
                var n = node
                n.sessions.sort { a, b in
                    let ra = recording(for: a), rb = recording(for: b)
                    let ta = tpOrder.firstIndex(of: ra?.timepoint ?? "") ?? tpOrder.count
                    let tb = tpOrder.firstIndex(of: rb?.timepoint ?? "") ?? tpOrder.count
                    if ta != tb { return ta < tb }
                    if (ra?.trial ?? 1) != (rb?.trial ?? 1) { return (ra?.trial ?? 1) < (rb?.trial ?? 1) }
                    return (ra?.recordedOn ?? a.createdAt) < (rb?.recordedOn ?? b.createdAt)
                }
                return n
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            return TaskGroupNode(name: g, animals: animals)
        }
    }

    /// "Day 7 · trial 2 · 3 Nov 2026" for a session row.
    func sessionLine(_ r: Recording) -> String {
        var parts: [String] = []
        if !r.timepoint.isEmpty { parts.append(r.timepoint) }
        if r.trial > 1 { parts.append(String(format: L("trial %d", "第 %d 次"), r.trial)) }
        let locale = Locale(identifier: Lang.isChinese ? "zh-Hans" : "en")
        parts.append((r.recordedOn ?? r.createdAt).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
        return parts.joined(separator: " · ")
    }

    // MARK: Videos outside tasks

    /// Videos in no task: outside any study, in a study that no longer exists, or in a study but
    /// without any analysis yet (1.3 videos never assigned to a task).
    var unassignedRecordings: [Recording] {
        recordings.filter { r in
            guard let eid = r.experimentID, experiment(eid) != nil else { return true }
            return sessions(of: r.id).isEmpty && r.plannedAssays.isEmpty
        }
    }

    // MARK: Peers

    /// The other sessions of the same task as this one (same paradigm, same study; sessions outside
    /// any study only share with each other). Parameters and calibration are only ever copied
    /// between these — never from another task.
    func taskPeers(of sessionID: UUID) -> [Session] {
        guard let s = session(sessionID) else { return [] }
        let eid = recording(for: s)?.experimentID
        return sessions.filter { $0.id != sessionID && $0.assay == s.assay && recording(for: $0)?.experimentID == eid }
    }
}
