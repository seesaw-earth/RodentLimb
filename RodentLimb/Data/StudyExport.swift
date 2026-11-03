// StudyExport.swift — design information for exports, group statistics, and the study-design
// paragraph (ARRIVE 2.0: design, experimental unit, n per group, inclusion / exclusion criteria
// and exclusions, randomisation, blinding, sex).

import Foundation

/// One analysis with everything needed for a long-format row.
struct ExportRow {
    var session: Session
    var result: AnalysisResult?
    var study: String
    var animal: String
    var blindCode: String
    var sex: String
    var cohort: String
    var cage: String
    /// (factor name, level) in factor order.
    var factors: [(String, String)]
    var group: String
    var timepoint: String
    var trial: Int
    var recorded: Date
    var qcVerdict: String
    var qcCoverage: Double?
    var qcLongestLost: Double?
    /// "1", "0" or "pending".
    var included: String
    var exclusionReason: String
    var blinded: Bool

    /// Extra summary fields for the single-session export.
    var designFields: [(String, String)] {
        var out: [(String, String)] = [("study", study), ("blind_code", blindCode), ("sex", sex), ("cohort", cohort)]
        if !blinded { out += factors.map { ($0.0, $0.1) } }
        out += [("timepoint", timepoint), ("trial", "\(trial)"), ("qc_verdict", qcVerdict),
                ("qc_mouse_tracked_pct", Exporter.f(qcCoverage.map { $0 * 100 }, 1)), ("included", included),
                ("exclusion_reason", exclusionReason)]
        return out
    }
}

/// Descriptive statistics of one group (or group × timepoint).
struct GroupStat: Identifiable {
    var id: String { name + "|" + timepoint }
    var name: String
    var timepoint: String
    var values: [Double]
    var mean: Double
    var sd: Double?
    var sem: Double? { sd.map { $0 / Double(values.count).squareRoot() } }
}

/// How a study's analyses are grouped for a comparison.
enum Grouping: Hashable {
    /// All factors combined (the design's cells, e.g. "KO · Drug").
    case cells
    /// One factor (index into `Experiment.factors`).
    case factor(UUID)
    /// Sex.
    case sex
    /// Cells split by sex.
    case cellsBySex
}

@MainActor
extension SessionStore {
    func exportRow(_ s: Session, result: AnalysisResult?) -> ExportRow {
        let r = recording(for: s)
        let e = r.flatMap { experiment(for: $0) }
        let a = e?.animal(r?.animalID)
        var factors: [(String, String)] = []
        if let e, let a { factors = e.activeFactors.map { ($0.name, a.level($0) ?? "") } }
        let decision = r?.decision ?? .included
        return ExportRow(session: s, result: result,
                         study: e?.name ?? "",
                         animal: a?.code ?? r?.subject ?? s.subject,
                         blindCode: a?.blindCode ?? "",
                         sex: a?.sex.exportName ?? "",
                         cohort: a?.cohort ?? "",
                         cage: a?.cage ?? "",
                         factors: factors,
                         group: (e != nil && a != nil) ? e!.groupLabel(a!) : (r?.group ?? s.group),
                         timepoint: r?.timepoint ?? "",
                         trial: r?.trial ?? 1,
                         recorded: r?.recordedOn ?? r?.createdAt ?? s.createdAt,
                         qcVerdict: r?.qc?.verdict.rawValue ?? "",
                         qcCoverage: r?.qc?.coreCoverage,
                         qcLongestLost: r?.qc?.longestLost,
                         included: decision == .included ? "1" : decision == .excluded ? "0" : "pending",
                         exclusionReason: r?.exclusionReason ?? "",
                         blinded: e?.blinded ?? false)
    }

    func exportRows(_ sessions: [Session], results: [UUID: AnalysisResult]) -> [ExportRow] {
        sessions.map { exportRow($0, result: results[$0.id]) }
    }

    /// Analyses of a study for one task, in a stable order (group, animal, timepoint).
    func analyses(in e: Experiment, assay: Assay) -> [Session] {
        let recs = Dictionary(recordings(in: e.id).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func key(_ s: Session) -> (String, String, Int) {
            guard let r = s.recordingID.flatMap({ recs[$0] }) else { return ("", "", 0) }
            let a = e.animal(r.animalID)
            let tp = e.timepoints.firstIndex(of: r.timepoint) ?? e.timepoints.count
            // While blinded, rows are not ordered by group (that would reveal the allocation).
            let group = e.blinded ? "" : (a.map { e.groupLabel($0) } ?? "")
            let who = a.map { e.displayCode($0) } ?? r.subject
            return (group + "|" + who, r.timepoint, tp)
        }
        return sessions.filter { s in s.assay == assay && s.recordingID.map { recs[$0] != nil } == true }
            .sorted { key($0).0 != key($1).0 ? key($0).0 < key($1).0 : key($0).2 < key($1).2 }
    }

    /// Group label of an analysis for a grouping ("(no animal)" / "(not allocated)" when it cannot be placed).
    func groupName(_ s: Session, in e: Experiment, by grouping: Grouping) -> String {
        guard let r = recording(for: s), let a = e.animal(r.animalID) else { return L("(no animal)", "（未关联动物）") }
        switch grouping {
        case .cells: return e.groupLabel(a).isEmpty ? L("All animals", "全部动物") : e.groupLabel(a)
        case .factor(let fid):
            guard let f = e.factors.first(where: { $0.id == fid }) else { return "" }
            return a.level(f) ?? L("(not allocated)", "（未分组）")
        case .sex: return a.sex.label
        case .cellsBySex:
            let g = e.groupLabel(a)
            return (g.isEmpty ? "" : g + " · ") + a.sex.label
        }
    }

    /// Mean, SD and SEM per group, using included videos only. With `timepoint` nil the groups are
    /// also split by timepoint (time course); otherwise only that timepoint is used. The animal is
    /// the experimental unit: several trials of one animal in the same group and timepoint are
    /// averaged first, so n counts animals, not videos.
    func groupStats(_ e: Experiment, assay: Assay, metric: String, grouping: Grouping, timepoint: String?,
                    results: [UUID: AnalysisResult]) -> [GroupStat] {
        var perAnimal: [String: [String: [Double]]] = [:]
        var unitOrder: [String: [String]] = [:]
        var order: [String] = []
        for s in analyses(in: e, assay: assay) {
            guard let r = recording(for: s), r.decision == .included else { continue }
            if let tp = timepoint, r.timepoint != tp { continue }
            guard let v = results[s.id]?.metric(metric)?.value, v.isFinite else { continue }
            let key = groupName(s, in: e, by: grouping) + "\u{1F}" + (timepoint == nil ? r.timepoint : "")
            let unit = r.animalID?.uuidString ?? r.id.uuidString
            if perAnimal[key] == nil { order.append(key) }
            if perAnimal[key]?[unit] == nil { unitOrder[key, default: []].append(unit) }
            perAnimal[key, default: [:]][unit, default: []].append(v)
        }
        var values: [String: [Double]] = [:]
        for key in order {
            let units = perAnimal[key] ?? [:]
            values[key] = (unitOrder[key] ?? []).compactMap { units[$0].flatMap { Signal.mean($0) } }
        }
        let cellOrder = e.cells.map { $0.joined(separator: " · ") }
        let tpOrder = e.timepoints
        let stats: [GroupStat] = order.compactMap { key in
            let parts = key.components(separatedBy: "\u{1F}")
            guard let v = values[key], let m = Signal.mean(v) else { return nil }
            return GroupStat(name: parts.first ?? "", timepoint: parts.count > 1 ? parts[1] : "", values: v, mean: m, sd: Signal.sd(v))
        }
        func rank(_ g: GroupStat) -> (Int, Int, String) {
            let c = cellOrder.firstIndex { g.name.hasPrefix($0) } ?? cellOrder.count
            let t = tpOrder.firstIndex(of: g.timepoint) ?? tpOrder.count
            return (t, c, g.name)
        }
        return stats.sorted { rank($0) < rank($1) }
    }

    /// Animals per group (cell) and sex, for the design summary.
    func groupSizes(_ e: Experiment) -> [(group: String, total: Int, male: Int, female: Int)] {
        var out: [(group: String, total: Int, male: Int, female: Int)] = []
        let labels = e.cells.isEmpty ? [""] : e.cells.map { $0.joined(separator: " · ") }
        for label in labels {
            let members = e.animals.filter { e.cells.isEmpty || e.groupLabel($0) == label }
            out.append((label.isEmpty ? L("All animals", "全部动物") : label, members.count,
                        members.filter { $0.sex == .male }.count, members.filter { $0.sex == .female }.count))
        }
        let unallocated = e.unallocated.count
        if !e.cells.isEmpty && unallocated > 0 {
            let u = e.unallocated
            out.append((L("Not allocated", "未分组"), unallocated, u.filter { $0.sex == .male }.count, u.filter { $0.sex == .female }.count))
        }
        return out
    }

    /// Study-design paragraph for the methods section (English).
    func studyMethods(_ e: Experiment) -> String {
        var t = "Study design — \(e.name)\n\n"
        let recs = recordings(in: e.id)
        t += "Design: \(e.design.methods)"
        if !e.activeFactors.isEmpty {
            t += "; between-subject factor(s): " + e.activeFactors.map { "\($0.name) (\($0.levels.joined(separator: ", ")); reference \($0.levels.first ?? ""))" }.joined(separator: "; ")
        }
        if e.timepoints.count > 1 { t += "; repeated measurements: " + e.timepoints.joined(separator: ", ") }
        t += ". The experimental unit was the individual animal.\n"
        if e.blinded {
            t += "Animals: n = \(e.animals.count); group sizes withheld while the study is blinded (export again after unblinding).\n"
        } else {
            let sizes = groupSizes(e)
            t += "Animals: n = \(e.animals.count) (" + sizes.map { "\($0.group): n = \($0.total) [\($0.male) male, \($0.female) female]" }.joined(separator: "; ") + ").\n"
        }
        let unknownSex = e.animals.filter { $0.sex == .unknown }.count
        if unknownSex > 0 { t += "Sex was not recorded for \(unknownSex) animal(s).\n" }
        t += e.randomization.isEmpty ? "Randomisation: not recorded in RodentLimb.\n" : "Randomisation: \(e.randomization)\n"
        t += e.blinded
            ? "Blinding: videos were scored with group allocation concealed (animals shown by random codes).\n"
            : "Blinding: group allocation was visible during scoring in RodentLimb (study not set to blinded).\n"
        t += "Inclusion / exclusion criteria (set before analysis): " + e.qc.methods + "\n"
        let excluded = recs.filter { $0.decision == .excluded }
        let pending = recs.filter { $0.decision == .pending }
        t += "Videos: \(recs.count) recorded, \(recs.filter { $0.decision == .included }.count) included, \(excluded.count) excluded"
        t += pending.isEmpty ? ".\n" : ", \(pending.count) not yet reviewed.\n"
        for r in excluded {
            let a = e.animal(r.animalID)
            let who = (a.map { e.displayCode($0) } ?? r.subject) + (r.timepoint.isEmpty ? "" : " (\(r.timepoint))")
            let group = e.blinded ? "" : (a.map { e.groupLabel($0) } ?? "")
            t += "  Excluded: \(who)\(group.isEmpty ? "" : ", " + group) — \(r.exclusionReason.isEmpty ? "no reason given" : r.exclusionReason)\n"
        }
        t += "\nReferences\n"
        t += "Percie du Sert N. et al. (2020) The ARRIVE guidelines 2.0: updated guidelines for reporting animal research. PLoS Biol 18:e3000410.\n"
        t += "Clayton J.A., Collins F.S. (2014) Policy: NIH to balance sex in cell and animal studies. Nature 509:282–283.\n"
        return t
    }

    /// Files for a study: one long-format CSV per task, plus the design paragraph.
    func exportStudy(_ e: Experiment) async -> [URL] {
        let assays = Assay.allCases.filter { a in sessions.contains { $0.assay == a && recording(for: $0)?.experimentID == e.id } }
        var urls: [URL] = []
        for a in assays {
            let list = analyses(in: e, assay: a)
            let res = await loadResults(list.map(\.id))
            if let u = Exporter.groupCSV(exportRows(list, results: res), name: e.name) { urls.append(u) }
        }
        let text = studyMethods(e)
        let dir = urls.first?.deletingLastPathComponent() ?? Exporter.exportDir()
        if let u = Exporter.write(text, dir.appendingPathComponent(Exporter.safeName(e.name) + "_design.txt")) { urls.append(u) }
        return urls
    }
}
