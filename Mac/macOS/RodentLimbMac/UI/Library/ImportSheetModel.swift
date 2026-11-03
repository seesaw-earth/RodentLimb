// ImportSheetModel.swift — state of the Add Videos sheet of a task: the videos waiting to be added
// (probed with VideoProbe at most four at a time, results applied to the table in small batches so
// a long list stays smooth), each video's animal, group, timepoint and trial (suggested from the file
// name, from the animal's group in the task, or from the sheet's default group), the pose model and
// keep in place / copy, and the import itself (SessionStore.importVideos: every video joins the task
// and gets its session at once) with its outcome for the result page.
//
// Not actor-isolated as a whole (so a view can create it as a @State default); everything that
// touches the store is @MainActor.

import Foundation
import Observation

/// What the sheet knows about one pending file.
enum ImportRowStatus: Int {
    case reading = 0, ready, warning, unreadable
}

/// One video in the import table.
struct ImportPendingVideo: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var animal = ""
    var timepoint = ""
    var trial = 1
    /// Group in the task ("" = none yet).
    var group = ""
    var facts: VideoFacts?
    /// Typed or bulk-set by the user: suggestions no longer overwrite it.
    var animalEdited = false
    var timepointEdited = false
    var trialEdited = false
    var groupEdited = false
    /// The group is the one the animal already has in the task (it keeps it).
    var groupFromAnimal = false
    /// The timepoint came from the file or folder name (otherwise it is the sheet's default).
    var timepointFromName = false

    init(url: URL) {
        id = UUID()
        self.url = url
    }

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }

    // Sort keys of the table columns (−1 = not read yet).
    var duration: Double { facts?.duration ?? -1 }
    var fps: Double { facts?.fps ?? -1 }
    var pixels: Int {
        guard let f = facts else { return -1 }
        return min(max(0, f.width), 100_000) * min(max(0, f.height), 100_000)
    }
    var fileSize: Int64 { facts?.fileSize ?? -1 }
    var statusRank: Int { status.rawValue }

    var status: ImportRowStatus {
        guard let f = facts else { return .reading }
        if !f.playable { return .unreadable }
        return f.warnings.isEmpty ? .ready : .warning
    }

    var isImportable: Bool { status != .unreadable }

    /// What to check, or why the file cannot be used (tooltip of the status column).
    var advice: String {
        guard let f = facts else {
            return L("Reading duration, frame rate and size…", "正在读取时长、帧率和尺寸…")
        }
        if !f.playable { return f.problem ?? L("This file cannot be read.", "无法读取该文件。") }
        let w = f.warnings
        return w.isEmpty ? L("Ready to import.", "可以导入。") : w.joined(separator: "\n")
    }
}

/// How the bulk editor changes the animal IDs of the selected videos.
enum ImportAnimalEdit: String, CaseIterable, Identifiable {
    case replace, prefix, number
    var id: String { rawValue }
    var label: String {
        switch self {
        case .replace: return L("Set to", "设为")
        case .prefix: return L("Add prefix", "添加前缀")
        case .number: return L("Number", "编号")
        }
    }
}

/// Totals shown in the footer.
struct ImportSheetSummary {
    var total = 0
    var importable = 0
    var unreadable = 0
    var reading = 0
    var warnings = 0
    var noTimepoint = 0
    var noAnimal = 0
    var noGroup = 0
    /// Animal IDs given two different groups (an animal is in one group).
    var groupConflicts: [String] = []
    var seconds = 0.0
    var bytes: Int64 = 0
}

/// What happened, for the result page.
struct ImportSheetResult {
    var created = 0
    var duplicates: [String] = []
    var failures: [(name: String, reason: String)] = []
    var unreadable = 0
    /// Duplicates that can be imported anyway (identified unambiguously by name and path).
    var retryable: [SessionStore.ImportItem] = []
}

@Observable
final class ImportSheetModel {
    enum Phase { case editing, importing, finished }

    var rows: [ImportPendingVideo] = []
    /// The task the videos are added to.
    private(set) var task: TaskRef?
    private(set) var defaultTimepoint = ""
    /// Group for videos whose animal has none yet and whose name names none.
    private(set) var defaultGroup = ""
    var notes = ""
    var copyVideos = false
    /// Pose model for these videos (first option: visible light FP16; second: near-infrared dark box).
    var poseModel: PoseModelID = .standard
    private(set) var pattern = NamePattern()
    /// Folder searches in progress.
    private(set) var searching = 0
    private(set) var phase: Phase = .editing
    private(set) var importDone = 0
    private(set) var importTotal = 0
    /// Short message under the table (nothing found, already listed).
    var notice: String?
    private(set) var result: ImportSheetResult?

    static let maxProbes = 4

    @ObservationIgnored private weak var store: SessionStore?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var probeQueue: [(UUID, URL)] = []
    @ObservationIgnored private var probeHead = 0
    @ObservationIgnored private var probes: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var arrived: [UUID: VideoFacts] = [:]
    @ObservationIgnored private var applyScheduled = false

    init() {}

    // MARK: Lifecycle

    /// Called once when the sheet appears.
    @MainActor
    func start(request: ImportRequest, store: SessionStore) {
        guard !started else { return }
        started = true
        self.store = store
        pattern = Self.loadPattern()
        copyVideos = UserDefaults.standard.object(forKey: SettingsKey.copyVideos) as? Bool ?? false
        poseModel = PoseModelID.defaultChoice
        task = store.taskExists(request.task) ? request.task : nil
        let g = request.group.trimmingCharacters(in: .whitespaces)
        if !g.isEmpty, !groupsHidden { defaultGroup = g }
        add(request.urls)
    }

    /// Stops reading videos (the sheet closed).
    func close() {
        closed = true
        for (_, t) in probes { t.cancel() }
        probes.removeAll()
        probeQueue.removeAll()
        probeHead = 0
        arrived.removeAll()
    }

    // MARK: Adding and removing

    /// Adds files and folders (folders searched recursively, off the main thread).
    @MainActor
    func add(_ urls: [URL]) {
        let input = urls.filter { $0.isFileURL }
        guard !input.isEmpty, !closed, phase == .editing else { return }
        searching += 1
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { VideoFiles.collect(input) }.value
            guard let self else { return }
            self.searching = max(0, self.searching - 1)
            guard !self.closed else { return }
            self.append(found)
        }
    }

    @MainActor
    private func append(_ found: [URL]) {
        var seen = Set(rows.map { $0.url.standardizedFileURL.path })
        var fresh: [ImportPendingVideo] = []
        for u in found where seen.insert(u.standardizedFileURL.path).inserted {
            fresh.append(ImportPendingVideo(url: u))
        }
        if found.isEmpty {
            notice = L("No videos were found in what you added.", "所添加的内容中没有找到视频。")
        } else if fresh.isEmpty {
            notice = L("These videos are already in the list.", "这些视频已在列表中。")
        } else {
            notice = nil
        }
        guard !fresh.isEmpty else { return }
        let ctx = namingContext
        for i in fresh.indices { suggest(&fresh[i], ctx) }
        rows.append(contentsOf: fresh)
        probeQueue.append(contentsOf: fresh.map { ($0.id, $0.url) })
        pumpProbes()
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty, phase == .editing else { return }
        rows.removeAll { ids.contains($0.id) }
        for id in ids {
            probes[id]?.cancel()
            probes[id] = nil
        }
    }

    func sort(using order: [KeyPathComparator<ImportPendingVideo>]) {
        guard !order.isEmpty else { return }
        rows.sort(using: order)
    }

    // MARK: Probing (≤ 4 at once)

    @MainActor
    private func pumpProbes() {
        while !closed, probes.count < Self.maxProbes, probeHead < probeQueue.count {
            let (id, url) = probeQueue[probeHead]
            probeHead += 1
            probes[id] = Task { [weak self] in
                let facts = await VideoProbe.facts(url, scoped: false)
                self?.probeFinished(id, facts)
            }
        }
        if probeHead >= probeQueue.count, !probeQueue.isEmpty {
            probeQueue.removeAll()
            probeHead = 0
        }
    }

    @MainActor
    private func probeFinished(_ id: UUID, _ facts: VideoFacts) {
        probes[id] = nil
        guard !closed else { return }
        arrived[id] = facts
        scheduleApply()
        pumpProbes()
    }

    /// Results are applied together at most ~7 times per second (one table update for many rows).
    @MainActor
    private func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.applyArrived()
        }
    }

    @MainActor
    private func applyArrived() {
        applyScheduled = false
        guard !closed, !arrived.isEmpty else { return }
        var copy = rows
        for i in copy.indices {
            if let f = arrived[copy[i].id] { copy[i].facts = f }
        }
        arrived.removeAll()
        rows = copy
    }

    // MARK: Naming

    struct NamingContext {
        var animals: [String] = []
        var timepoints: [String] = []
        /// The task's groups (empty while it is blinded).
        var groups: [String] = []
        /// Group of each registered animal (lower-cased code → group).
        var animalGroups: [String: String] = [:]
        var defaultGroup = ""
    }

    var studyID: UUID? { task?.experimentID }

    @MainActor
    var namingContext: NamingContext {
        guard let e = experiment else { return NamingContext() }
        var ctx = NamingContext(animals: e.animals.map(\.code).filter { !$0.isEmpty }, timepoints: e.timepoints)
        guard !e.blinded else { return ctx }
        ctx.groups = taskGroups
        for a in e.animals {
            let g = e.groupLabel(a)
            let code = a.code.trimmingCharacters(in: .whitespaces).lowercased()
            if !g.isEmpty && !code.isEmpty { ctx.animalGroups[code] = g }
        }
        ctx.defaultGroup = defaultGroup
        return ctx
    }

    @MainActor
    var experiment: Experiment? { store?.experiment(studyID) }

    /// While the task is blinded its groups are not shown (allocation is done on the Design tab).
    @MainActor
    var groupsHidden: Bool { experiment?.blinded ?? true }

    /// A design with several factors: groups are its cells, set on the Design tab, not here.
    @MainActor
    var groupsEditable: Bool { !groupsHidden && (experiment?.factors.count ?? 0) <= 1 }

    @MainActor
    var taskGroups: [String] {
        guard let t = task, let store else { return [] }
        return store.taskGroups(t)
    }

    private func suggest(_ row: inout ImportPendingVideo, _ ctx: NamingContext) {
        if !(row.animalEdited && row.timepointEdited && row.trialEdited) {
            let s = ImportNaming.suggest(url: row.url, pattern: pattern, animals: ctx.animals, timepoints: ctx.timepoints)
            if !row.animalEdited { row.animal = s.animal }
            if !row.timepointEdited {
                row.timepointFromName = !s.timepoint.isEmpty
                row.timepoint = s.timepoint.isEmpty ? defaultTimepoint : s.timepoint
            }
            if !row.trialEdited { row.trial = max(1, s.trial ?? 1) }
        }
        suggestGroup(&row, ctx)
    }

    /// The animal's group in the task (it keeps it), else a group named in the file or folder name,
    /// else the sheet's default group.
    private func suggestGroup(_ row: inout ImportPendingVideo, _ ctx: NamingContext) {
        let code = row.animal.trimmingCharacters(in: .whitespaces).lowercased()
        if let g = ctx.animalGroups[code], !code.isEmpty {
            row.group = g
            row.groupFromAnimal = true
            return
        }
        row.groupFromAnimal = false
        guard !row.groupEdited else { return }
        row.group = SessionStore.guessGroup(row.url, groups: ctx.groups) ?? ctx.defaultGroup
    }

    @MainActor
    func refreshSuggestions() {
        let ctx = namingContext
        var copy = rows
        for i in copy.indices { suggest(&copy[i], ctx) }
        if copy != rows { rows = copy }
    }

    /// What the pattern makes of one file (pattern editor preview).
    @MainActor
    func preview(_ url: URL, pattern p: NamePattern) -> NameSuggestion {
        let ctx = namingContext
        return ImportNaming.suggest(url: url, pattern: p, animals: ctx.animals, timepoints: ctx.timepoints)
    }

    /// The group for videos without one (rows the user did not set and whose name names no group).
    @MainActor
    func setDefaultGroup(_ g: String) {
        let value = g.trimmingCharacters(in: .whitespaces)
        guard value != defaultGroup else { return }
        let old = defaultGroup
        defaultGroup = value
        var copy = rows
        var changed = false
        for i in copy.indices where !copy[i].groupEdited && !copy[i].groupFromAnimal && copy[i].group == old {
            copy[i].group = value
            changed = true
        }
        if changed { rows = copy }
    }

    /// The timepoint for videos whose name does not contain one.
    func setDefaultTimepoint(_ t: String) {
        guard t != defaultTimepoint else { return }
        defaultTimepoint = t
        var copy = rows
        var changed = false
        for i in copy.indices where !copy[i].timepointEdited && !copy[i].timepointFromName && copy[i].timepoint != t {
            copy[i].timepoint = t
            changed = true
        }
        if changed { rows = copy }
    }

    @MainActor
    func setPattern(_ p: NamePattern) {
        guard p != pattern else { return }
        pattern = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: SettingsKey.namePattern)
        }
        refreshSuggestions()
    }

    static func loadPattern() -> NamePattern {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.namePattern),
              let p = try? JSONDecoder().decode(NamePattern.self, from: data) else { return NamePattern() }
        return p
    }

    // MARK: Editing

    private func index(_ id: UUID) -> Int? { rows.firstIndex { $0.id == id } }

    @MainActor
    func setAnimal(_ id: UUID, _ value: String) {
        guard let i = index(id), rows[i].animal != value else { return }
        var row = rows[i]
        row.animal = value
        row.animalEdited = true
        suggestGroup(&row, namingContext)
        rows[i] = row
    }

    /// Group of one video (an animal already in a group keeps it: change it on the Design tab).
    func setGroup(_ id: UUID, _ value: String) {
        guard let i = index(id), !rows[i].groupFromAnimal else { return }
        let v = value.trimmingCharacters(in: .whitespaces)
        guard rows[i].group != v else { return }
        rows[i].group = v
        rows[i].groupEdited = true
    }

    func setTimepoint(_ id: UUID, _ value: String) {
        guard let i = index(id), rows[i].timepoint != value else { return }
        rows[i].timepoint = value
        rows[i].timepointEdited = true
    }

    func setTrial(_ id: UUID, _ value: Int) {
        let v = min(max(1, value), 9_999)
        guard let i = index(id), rows[i].trial != v else { return }
        rows[i].trial = v
        rows[i].trialEdited = true
    }

    /// Changes many rows at once, in table order. `animal`: how, the text, first number, digits.
    @MainActor
    func bulkEdit(_ ids: Set<UUID>, animal: (mode: ImportAnimalEdit, text: String, start: Int, digits: Int)?,
                  timepoint: String?, trial: Int?, group: String? = nil) {
        guard !ids.isEmpty else { return }
        let ctx = namingContext
        var copy = rows
        // Clamped: the first number is typed freely, and `n += 1` must not overflow.
        var n = min(max(0, animal?.start ?? 1), 1_000_000_000)
        let digits = min(max(1, animal?.digits ?? 1), 6)
        for i in copy.indices where ids.contains(copy[i].id) {
            if let a = animal {
                let text = a.text.trimmingCharacters(in: .whitespaces)
                switch a.mode {
                case .replace:
                    copy[i].animal = text
                case .prefix:
                    if !copy[i].animal.hasPrefix(text) { copy[i].animal = text + copy[i].animal }
                case .number:
                    copy[i].animal = text + Self.padded(n, digits)
                    n += 1
                }
                copy[i].animalEdited = true
            }
            if let t = timepoint {
                copy[i].timepoint = t.trimmingCharacters(in: .whitespaces)
                copy[i].timepointEdited = true
            }
            if let t = trial {
                copy[i].trial = min(max(1, t), 9_999)
                copy[i].trialEdited = true
            }
            if animal != nil { suggestGroup(&copy[i], ctx) }
            if let g = group, !copy[i].groupFromAnimal {
                copy[i].group = g.trimmingCharacters(in: .whitespaces)
                copy[i].groupEdited = true
            }
        }
        rows = copy
    }

    static func padded(_ n: Int, _ digits: Int) -> String {
        let s = String(max(0, n))
        return s.count >= digits ? s : String(repeating: "0", count: digits - s.count) + s
    }

    /// Back to what the file name suggests.
    @MainActor
    func resetToSuggestions(_ ids: Set<UUID>) {
        let ctx = namingContext
        var copy = rows
        for i in copy.indices where ids.contains(copy[i].id) {
            copy[i].animalEdited = false
            copy[i].timepointEdited = false
            copy[i].trialEdited = false
            copy[i].groupEdited = false
            suggest(&copy[i], ctx)
        }
        rows = copy
    }

    // MARK: Summary

    var summary: ImportSheetSummary {
        var s = ImportSheetSummary()
        var groupsOf: [String: Set<String>] = [:]
        var firstSpelling: [String: String] = [:]
        for r in rows where r.isImportable && !r.groupFromAnimal {
            let code = r.animal.trimmingCharacters(in: .whitespaces)
            let g = r.group.trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty, !g.isEmpty else { continue }
            groupsOf[code.lowercased(), default: []].insert(g.lowercased())
            if firstSpelling[code.lowercased()] == nil { firstSpelling[code.lowercased()] = code }
        }
        s.groupConflicts = groupsOf.filter { $0.value.count > 1 }.keys.sorted().compactMap { firstSpelling[$0] }
        for r in rows {
            s.total += 1
            switch r.status {
            case .reading: s.reading += 1
            case .unreadable: s.unreadable += 1
            case .warning: s.warnings += 1
            case .ready: break
            }
            guard r.isImportable else { continue }
            s.importable += 1
            if let f = r.facts {
                if f.duration.isFinite && f.duration > 0 { s.seconds += f.duration }
                s.bytes = s.bytes &+ max(0, f.fileSize)
            }
            if r.timepoint.trimmingCharacters(in: .whitespaces).isEmpty { s.noTimepoint += 1 }
            if r.animal.trimmingCharacters(in: .whitespaces).isEmpty { s.noAnimal += 1 }
            if r.group.trimmingCharacters(in: .whitespaces).isEmpty { s.noGroup += 1 }
        }
        return s
    }

    // MARK: Import

    @MainActor
    func runImport(app: AppModel) async {
        guard phase == .editing, !closed else { return }
        let store = app.store
        guard let t = task, store.taskExists(t) else {
            notice = L("This task no longer exists. Close the sheet and choose a task.", "该任务已不存在。请关闭此窗口并选择一个任务。")
            return
        }
        let eid: UUID? = t.experimentID
        let usable = rows.filter { $0.isImportable }
        guard !usable.isEmpty else { return }
        let setGroups = groupsEditable
        // A timepoint typed differently from the study's spelling ("day7") is stored as registered ("Day 7").
        let registered = store.experiment(eid)?.timepoints ?? []
        func spelled(_ t: String) -> String {
            let typed = t.trimmingCharacters(in: .whitespaces)
            return ImportNaming.registered(typed, in: registered) ?? typed
        }
        let noteText = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let items: [SessionStore.ImportItem] = usable.map { r in
            let f = r.facts
            let duration: Double? = f.flatMap { $0.duration.isFinite && $0.duration > 0 ? $0.duration : nil }
            let fps: Double? = f.flatMap { $0.fps.isFinite && $0.fps > 0 ? $0.fps : nil }
            let width: Int? = f.flatMap { $0.width > 0 ? $0.width : nil }
            let height: Int? = f.flatMap { $0.height > 0 ? $0.height : nil }
            return SessionStore.ImportItem(url: r.url,
                                           animal: r.animal.trimmingCharacters(in: .whitespaces),
                                           timepoint: spelled(r.timepoint),
                                           trial: max(1, r.trial),
                                           group: setGroups ? r.group.trimmingCharacters(in: .whitespaces) : "",
                                           notes: noteText,
                                           experimentID: eid,
                                           planned: [t.assay],
                                           duration: duration,
                                           fps: fps,
                                           width: width,
                                           height: height,
                                           recordedOn: f?.creationDate,
                                           model: poseModel,
                                           createSessions: true)
        }
        phase = .importing
        importDone = 0
        importTotal = items.count
        let outcome = await store.importVideos(items, copy: copyVideos, allowDuplicates: false, progress: { [weak self] done, total in
            self?.importDone = done
            self?.importTotal = total
        })
        let createdPaths = Set(outcome.created.compactMap { store.source($0.id)?.path })
        var r = ImportSheetResult()
        r.created = outcome.created.count
        r.duplicates = outcome.duplicates
        r.failures = outcome.failures.map { (name: $0.0, reason: $0.1) }
        r.unreadable = rows.count - usable.count
        r.retryable = Self.unambiguous(outcome.duplicates, failures: outcome.failures.map { $0.0 },
                                       items: items, createdPaths: createdPaths)
        result = r
        phase = .finished
    }

    /// Imports the duplicates after all (the user confirmed on the result page).
    @MainActor
    func importDuplicatesAnyway(app: AppModel) async {
        guard phase == .finished, var r = result, !r.retryable.isEmpty else { return }
        let items = r.retryable
        phase = .importing
        importDone = 0
        importTotal = items.count
        let outcome = await app.store.importVideos(items, copy: copyVideos, allowDuplicates: true, progress: { [weak self] done, total in
            self?.importDone = done
            self?.importTotal = total
        })
        r.created += outcome.created.count
        var retried = items.map { $0.url.lastPathComponent }
        r.duplicates = r.duplicates.filter { name in
            guard let i = retried.firstIndex(of: name) else { return true }
            retried.remove(at: i)
            return false
        }
        r.failures += outcome.failures.map { (name: $0.0, reason: $0.1) }
        r.retryable = []
        result = r
        phase = .finished
    }

    /// Duplicates that can be told apart by name: a name skipped `n` times whose items (not created,
    /// not failed) are exactly `n`.
    @MainActor
    static func unambiguous(_ duplicates: [String], failures: [String], items: [SessionStore.ImportItem],
                            createdPaths: Set<String>) -> [SessionStore.ImportItem] {
        guard !duplicates.isEmpty else { return [] }
        var count: [String: Int] = [:]
        for n in duplicates { count[n, default: 0] += 1 }
        let failed = Set(failures)
        var names = Set<String>()
        for (name, n) in count where !failed.contains(name) {
            let same = items.filter { $0.url.lastPathComponent == name && !createdPaths.contains($0.url.path) }.count
            if same == n { names.insert(name) }
        }
        return items.filter { names.contains($0.url.lastPathComponent) && !createdPaths.contains($0.url.path) }
    }

    // MARK: Formatting

    /// "3 h 12 min", "12 min", "45 s".
    static func span(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let minutes = Int(safe: (seconds / 60).rounded())
        if minutes >= 60 { return String(format: L("%d h %d min", "%d 小时 %d 分钟"), minutes / 60, minutes % 60) }
        if minutes >= 1 { return String(format: L("%d min", "%d 分钟"), minutes) }
        return String(format: L("%d s", "%d 秒"), max(1, Int(safe: seconds.rounded())))
    }
}
