// Experiment.swift — study design: groups (between-subject factors), repeated measurements
// (within-subject timepoints / conditions), the animals and their allocation, blinding, and the
// QC inclusion criteria set before scoring.
//
// Follows what ARRIVE 2.0 asks to be reported (study design and groups, experimental unit = the
// animal, exact n per group, inclusion / exclusion criteria set a priori, randomisation, blinding)
// and the NIH policy of treating sex as a biological variable (sex is recorded for every animal and
// can be used to split comparisons).

import Foundation

/// A between-subject factor, e.g. Genotype (WT, KO) or Treatment (Vehicle, Drug). The first level
/// is the reference (control) level.
struct DesignFactor: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var levels: [String]
}

enum AnimalSex: String, Codable, CaseIterable, Identifiable {
    case unknown, male, female
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: return L("Not recorded", "未记录")
        case .male: return L("Male", "雄")
        case .female: return L("Female", "雌")
        }
    }
    var short: String {
        switch self {
        case .unknown: return "?"
        case .male: return L("M", "雄")
        case .female: return L("F", "雌")
        }
    }
    var exportName: String { self == .unknown ? "" : rawValue }
}

/// The experimental unit.
struct Animal: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Animal ID as written on the cage card / ear tag.
    var code: String
    var sex: AnimalSex = .unknown
    /// Level of each between-subject factor, keyed by `DesignFactor.id.uuidString`.
    var levels: [String: String] = [:]
    /// Cohort / batch / testing day — a blocking variable.
    var cohort: String = ""
    var cage: String = ""
    var notes: String = ""
    /// Shown instead of the code while the study is blinded.
    var blindCode: String = ""

    init(code: String) { self.code = code }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        sex = (try? c.decodeIfPresent(AnimalSex.self, forKey: .sex)) ?? .unknown
        levels = (try? c.decodeIfPresent([String: String].self, forKey: .levels)) ?? [:]
        cohort = (try? c.decodeIfPresent(String.self, forKey: .cohort)) ?? ""
        cage = (try? c.decodeIfPresent(String.self, forKey: .cage)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        blindCode = (try? c.decodeIfPresent(String.self, forKey: .blindCode)) ?? ""
    }

    func level(_ f: DesignFactor) -> String? {
        guard let v = levels[f.id.uuidString], f.levels.contains(v) else { return nil }
        return v
    }
}

enum DesignKind: String, Codable {
    case single, between, within, mixed

    var label: String {
        switch self {
        case .single: return L("Single group", "单组")
        case .between: return L("Between-subject groups", "组间设计")
        case .within: return L("Repeated measures (within-subject)", "重复测量（组内设计）")
        case .mixed: return L("Mixed: groups × repeated measures", "混合设计：组间 × 重复测量")
        }
    }
    var methods: String {
        switch self {
        case .single: return "single-group"
        case .between: return "between-subject"
        case .within: return "within-subject (repeated-measures)"
        case .mixed: return "mixed (between-subject factors × repeated measures)"
        }
    }
}

struct Experiment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var notes: String = ""
    var createdAt: Date = Date()
    var factors: [DesignFactor] = []
    /// Within-subject levels in order (e.g. Baseline, Day 7, Day 28, or doses in a crossover).
    var timepoints: [String] = []
    var animals: [Animal] = []
    /// While blinded, group labels are hidden and animals are shown by their blind code.
    var blinded: Bool = false
    /// How allocation was done (filled in by the randomiser, editable).
    var randomization: String = ""
    var qc: QCCriteria = QCCriteria()
    /// Tasks of this study, pre-selected when videos are imported into it.
    var plannedAssays: [Assay] = []

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        factors = (try? c.decodeIfPresent([LossyElement<DesignFactor>].self, forKey: .factors))?.compactMap { $0.value } ?? []
        timepoints = (try? c.decodeIfPresent([String].self, forKey: .timepoints)) ?? []
        animals = (try? c.decodeIfPresent([LossyElement<Animal>].self, forKey: .animals))?.compactMap { $0.value } ?? []
        blinded = (try? c.decodeIfPresent(Bool.self, forKey: .blinded)) ?? false
        randomization = (try? c.decodeIfPresent(String.self, forKey: .randomization)) ?? ""
        qc = (try? c.decodeIfPresent(QCCriteria.self, forKey: .qc)) ?? QCCriteria()
        plannedAssays = (try? c.decodeIfPresent([LossyElement<Assay>].self, forKey: .plannedAssays))?.compactMap { $0.value } ?? []
    }

    var design: DesignKind {
        let between = factors.contains { $0.levels.count > 1 }
        let within = timepoints.count > 1
        switch (between, within) {
        case (true, true): return .mixed
        case (true, false): return .between
        case (false, true): return .within
        case (false, false): return .single
        }
    }

    func animal(_ id: UUID?) -> Animal? {
        guard let id else { return nil }
        return animals.first { $0.id == id }
    }

    func animal(code: String) -> Animal? {
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return nil }
        return animals.first { $0.code.compare(c, options: [.caseInsensitive]) == .orderedSame }
    }

    /// Group (cell) of an animal: its levels joined, e.g. "KO · Drug". Empty when no factor.
    func groupLabel(_ a: Animal) -> String {
        factors.compactMap { a.level($0) }.joined(separator: " · ")
    }

    /// Factors that have levels (the ones animals are allocated to).
    var activeFactors: [DesignFactor] { factors.filter { !$0.levels.isEmpty } }

    /// Every combination of factor levels (the design's cells), in factor order.
    var cells: [[String]] {
        let active = activeFactors
        guard !active.isEmpty else { return [] }
        var out: [[String]] = [[]]
        for f in active {
            out = out.flatMap { prefix in f.levels.map { prefix + [$0] } }
        }
        return out
    }

    /// Animal ID as it may be shown now.
    func displayCode(_ a: Animal) -> String {
        if blinded { return a.blindCode.isEmpty ? L("Animal ?", "动物 ?") : a.blindCode }
        return a.code
    }

    /// Animals whose levels are not set for every factor.
    var unallocated: [Animal] {
        let active = activeFactors
        return animals.filter { a in active.contains { a.level($0) == nil } }
    }

    /// Gives every animal a random code (A###) that does not reveal its group.
    mutating func ensureBlindCodes() {
        var used = Set(animals.map(\.blindCode).filter { !$0.isEmpty })
        let upper = animals.count > 400 ? 99_999 : 999
        for i in animals.indices where animals[i].blindCode.isEmpty {
            var code = ""
            var attempts = 0
            repeat {
                code = "A" + String(Int.random(in: 100...upper))
                attempts += 1
            } while used.contains(code) && attempts < 1000
            if used.contains(code) { code = "A" + String(100_000 + i) }
            used.insert(code)
            animals[i].blindCode = code
        }
    }
}

// MARK: - Randomisation

/// Small seeded generator so an allocation can be reproduced from the seed in the methods text.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One element of a decoded array, or nil when that element is damaged, so a single bad entry
/// does not discard the whole list (which the next save would then write back empty).
struct LossyElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum Randomizer {
    /// Block randomisation of animals to the design's cells, stratified by sex (and cohort when
    /// requested). Within each stratum the animals are shuffled and each one goes to a random cell
    /// among the least-filled ones — with every animal allocated this is the classic permuted
    /// block (one animal per group per block, random order within blocks). Animals that already
    /// have a group count towards the sizes, so group sizes differ by at most one in every stratum
    /// also when only new animals are allocated (`all` off).
    static func allocate(_ e: Experiment, all: Bool, byCohort: Bool, seed: UInt64) -> Experiment {
        var e = e
        let cells = e.cells
        guard !cells.isEmpty else { return e }
        var rng = SplitMix64(seed: seed)
        let active = e.activeFactors
        let snapshot = e.animals
        let candidates = snapshot.indices.filter { i in all || active.contains { snapshot[i].level($0) == nil } }
        // Nothing to allocate: keep the record of the allocation that was actually made.
        guard !candidates.isEmpty else { return e }
        let incoming = Set(candidates)
        func stratum(_ a: Animal) -> String { a.sex.rawValue + (byCohort ? "|" + a.cohort : "") }
        var strata: [String: [Int]] = [:]
        var order: [String] = []
        for i in candidates {
            let key = stratum(snapshot[i])
            if strata[key] == nil { order.append(key) }
            strata[key, default: []].append(i)
        }
        for key in order {
            var members = strata[key] ?? []
            members.shuffle(using: &rng)
            var size: [[String]: Int] = [:]
            for (i, a) in snapshot.enumerated() where !incoming.contains(i) && stratum(a) == key {
                let cell = active.compactMap { a.level($0) }
                if cell.count == active.count { size[cell, default: 0] += 1 }
            }
            for i in members {
                let least = cells.map { size[$0, default: 0] }.min() ?? 0
                let options = cells.filter { size[$0, default: 0] == least }
                guard !options.isEmpty else { continue }
                let cell = options[Int.random(in: 0..<options.count, using: &rng)]
                size[cell, default: 0] += 1
                for (f, level) in zip(active, cell) {
                    e.animals[i].levels[f.id.uuidString] = level
                }
            }
        }
        let strataText = byCohort ? "sex and cohort" : "sex"
        let date = ISO8601DateFormatter().string(from: Date())
        if !all, !e.randomization.isEmpty, candidates.count < snapshot.count {
            // Animals added after the first allocation: keep the original record and append.
            e.randomization += " \(candidates.count) animal(s) added later were allocated the same way, each to a random group among the least-filled ones of its stratum (RodentLimb, \(date), seed \(seed))."
        } else {
            e.randomization = "Animals were allocated to \(cells.count) groups by block randomisation stratified by \(strataText) (blocks of one animal per group, random order within blocks; generated in RodentLimb on \(date), seed \(seed))."
        }
        return e
    }
}
