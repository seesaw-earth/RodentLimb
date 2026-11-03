// TaskStats.swift — numbers behind the Results of a task: measures available, the group comparison
// (each animal one point, group mean ± SEM, n per group) and time courses (per bin, or across the
// task's timepoints). Included sessions only; the animal is the experimental unit (several trials of
// one animal at one timepoint are averaged first — StudyExport.groupStats).
//
// Foundation only.

import Foundation

struct MeasureOption: Identifiable, Hashable {
    var key: String
    var label: LText
    var unit: String
    var highlight: Bool
    var id: String { key }

    var axisTitle: String { unit.isEmpty ? label.text : label.text + " (" + unit + ")" }
}

/// A binned series of the paradigm (behaviour bins, or TST immobility per minute).
struct BinOption: Identifiable, Hashable {
    var key: String
    var label: LText
    var unit: String
    /// Bin width in seconds.
    var binSize: Double
    var id: String { key }

    var axisTitle: String { unit.isEmpty ? label.text : label.text + " (" + unit + ")" }
    static let tstPerMinute = "tst_immobility_per_minute"
}

struct AnimalPoint: Identifiable {
    var id: Int
    var value: Double
    /// −0.5…0.5, deterministic (golden-ratio sequence), so points do not jump between redraws.
    var jitter: Double
}

struct GroupSummary: Identifiable {
    var id: String { name }
    var name: String
    /// Position in the design's group order (colour).
    var index: Int
    var points: [AnimalPoint]
    var mean: Double
    var sd: Double?
    var sem: Double?
    var n: Int { points.count }
}

struct CoursePoint: Identifiable {
    var id: String { group + "|" + String(x) }
    var group: String
    var groupIndex: Int
    /// Bin centre in minutes (bins) or timepoint index (timepoints).
    var x: Double
    var label: String
    var mean: Double
    var sem: Double?
    var n: Int
}

@MainActor
extension SessionStore {
    /// Measures found in the results of a task (highlighted ones first, then in result order).
    func measureOptions(_ t: TaskRef, results: [UUID: AnalysisResult]) -> [MeasureOption] {
        var seen = Set<String>(), out: [MeasureOption] = []
        for s in sessions(in: t) {
            for m in results[s.id]?.metrics ?? [] where !seen.contains(m.key) {
                seen.insert(m.key)
                out.append(MeasureOption(key: m.key, label: m.label, unit: m.unit, highlight: m.highlight))
            }
        }
        return out.filter(\.highlight) + out.filter { !$0.highlight }
    }

    /// Binned series found in the results of a task.
    func binOptions(_ t: TaskRef, results: [UUID: AnalysisResult]) -> [BinOption] {
        var seen = Set<String>(), out: [BinOption] = []
        for s in sessions(in: t) {
            guard let r = results[s.id] else { continue }
            if let d = r.behavior {
                for b in d.bins where !seen.contains(b.key) {
                    seen.insert(b.key)
                    out.append(BinOption(key: b.key, label: b.label, unit: b.unit, binSize: d.binSize))
                }
            }
            if let d = r.tst, !d.perMinute.isEmpty, !seen.contains(BinOption.tstPerMinute) {
                seen.insert(BinOption.tstPerMinute)
                out.append(BinOption(key: BinOption.tstPerMinute, label: LText("Immobility per minute", "每分钟不动时间"), unit: "s", binSize: 60))
            }
        }
        return out
    }

    private func groupIndex(_ name: String, in e: Experiment) -> Int {
        groupChoices(e).firstIndex(of: name) ?? groupChoices(e).count
    }

    /// The shared statistics call an animal without a group "All animals"; in a task that has groups
    /// it is "Not allocated".
    private func shownGroup(_ name: String, in e: Experiment) -> String {
        !e.cells.isEmpty && name == L("All animals", "全部动物") ? L("Not allocated", "未分组") : name
    }

    /// Group comparison of one measure (one timepoint, or all pooled when the task has none).
    func groupSummaries(_ t: TaskRef, metric: String, timepoint: String?, results: [UUID: AnalysisResult]) -> [GroupSummary] {
        guard let e = experiment(t.experimentID), !metric.isEmpty else { return [] }
        let tp: String? = e.timepoints.isEmpty ? nil : (timepoint ?? e.timepoints.first)
        var stats = groupStats(e, assay: t.assay, metric: metric, grouping: .cells, timepoint: tp, results: results)
        if tp == nil {
            // No timepoints in the design: groupStats splits by the recordings' (normally empty)
            // timepoint; keep one entry per group.
            let blank = stats.filter { $0.timepoint.isEmpty }
            if !blank.isEmpty { stats = blank } else if let first = stats.first?.timepoint { stats = stats.filter { $0.timepoint == first } }
        }
        return stats.map { g in
            GroupSummary(name: shownGroup(g.name, in: e), index: groupIndex(g.name, in: e),
                         points: g.values.enumerated().map { i, v in AnimalPoint(id: i, value: v, jitter: Self.jitter(i)) },
                         mean: g.mean, sd: g.sd, sem: g.sem)
        }
        .sorted { ($0.index, $0.name) < ($1.index, $1.name) }
    }

    /// Mean ± SEM of one measure per group across the task's timepoints.
    func timepointCourse(_ t: TaskRef, metric: String, results: [UUID: AnalysisResult]) -> [CoursePoint] {
        guard let e = experiment(t.experimentID), e.timepoints.count > 1, !metric.isEmpty else { return [] }
        let stats = groupStats(e, assay: t.assay, metric: metric, grouping: .cells, timepoint: nil, results: results)
        return stats.compactMap { g in
            guard let x = e.timepoints.firstIndex(of: g.timepoint) else { return nil }
            return CoursePoint(group: shownGroup(g.name, in: e), groupIndex: groupIndex(g.name, in: e), x: Double(x), label: g.timepoint,
                               mean: g.mean, sem: g.sem, n: g.values.count)
        }
    }

    /// Mean ± SEM per group per bin of a binned series (included sessions, one timepoint).
    func binnedCourse(_ t: TaskRef, series: BinOption, timepoint: String?, results: [UUID: AnalysisResult]) -> [CoursePoint] {
        guard let e = experiment(t.experimentID) else { return [] }
        let tp: String? = e.timepoints.isEmpty ? nil : (timepoint ?? e.timepoints.first)
        // group → animal → per-bin values (trials of one animal averaged).
        var perAnimal: [String: [String: [[Double]]]] = [:]
        for s in sessions(in: t) {
            guard let r = recording(for: s), r.decision == .included, let res = results[s.id] else { continue }
            if let tp, r.timepoint != tp { continue }
            let values: [Double]
            if series.key == BinOption.tstPerMinute {
                values = res.tst?.perMinute ?? []
            } else {
                values = res.behavior?.bins.first { $0.key == series.key }?.values ?? []
            }
            guard !values.isEmpty else { continue }
            let g = shownGroup(groupName(s, in: e, by: .cells), in: e)
            let unit = r.animalID?.uuidString ?? r.id.uuidString
            perAnimal[g, default: [:]][unit, default: []].append(values)
        }
        var out: [CoursePoint] = []
        for (g, animals) in perAnimal {
            // Per animal: mean over its trials, bin by bin.
            let curves: [[Double]] = animals.values.map { trials in
                let n = trials.map(\.count).max() ?? 0
                return (0..<n).map { i in
                    let v = trials.compactMap { i < $0.count && $0[i].isFinite ? $0[i] : nil }
                    return v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count)
                }
            }
            let bins = curves.map(\.count).max() ?? 0
            for i in 0..<bins {
                let v = curves.compactMap { i < $0.count && $0[i].isFinite ? $0[i] : nil }
                guard let m = Signal.mean(v) else { continue }
                let sem = Signal.sd(v).map { $0 / Double(v.count).squareRoot() }
                let centre = (Double(i) + 0.5) * series.binSize / 60
                out.append(CoursePoint(group: g, groupIndex: groupIndex(g, in: e), x: centre,
                                       label: String(format: "%.0f", centre), mean: m, sem: sem, n: v.count))
            }
        }
        return out.sorted { ($0.groupIndex, $0.group, $0.x) < ($1.groupIndex, $1.group, $1.x) }
    }

    /// Included / left-out sessions of a task (for the footnote under the charts).
    func inclusionCounts(_ t: TaskRef) -> (included: Int, leftOut: Int) {
        var inc = 0, out = 0
        for s in sessions(in: t) {
            if recording(for: s)?.decision == .included { inc += 1 } else { out += 1 }
        }
        return (inc, out)
    }

    /// −0.5…0.5 from the golden-ratio sequence.
    nonisolated static func jitter(_ i: Int) -> Double {
        let g = 0.618_033_988_749_895
        let f = (Double(i) * g).truncatingRemainder(dividingBy: 1)
        return f - 0.5
    }
}
