// ImportNaming.swift — animal ID, timepoint and trial suggested from a video's file and folder names.
//
// Lab videos are usually named after the animal and the day ("M12_Day7_T2.mp4",
// "WT-03 baseline.mov", "Day 28/KO_05.mp4"). Two ways to read them:
//   • Automatic: a registered animal ID contained in the name wins (longest match), else the whole
//     file name; a registered timepoint found in the name or in a parent folder's name; a trial
//     written as T2 / trial2 / rep2.
//   • Pattern: the name is split at the chosen separators and the user says which part is the
//     animal, the timepoint and the trial (e.g. part 1 = animal, part 2 = timepoint).
//
// Foundation only (tested on Linux).

import Foundation

struct NamePattern: Codable, Equatable {
    /// Characters that split a file name into parts.
    var separators: String = "_- ."
    /// 1-based part numbers; nil = automatic.
    var animalPart: Int?
    var timepointPart: Int?
    var trialPart: Int?

    var isAutomatic: Bool { animalPart == nil && timepointPart == nil && trialPart == nil }
}

struct NameSuggestion: Equatable {
    var animal: String
    var timepoint: String
    var trial: Int?
}

enum ImportNaming {
    static func stem(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    static func parts(_ stem: String, separators: String) -> [String] {
        let set = CharacterSet(charactersIn: separators.isEmpty ? "_" : separators)
        return stem.components(separatedBy: set).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Lower-cased letters and digits only ("Day 7" → "day7"), to compare names written differently.
    static func squash(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// A trial number written as T2, trial2, trial_2, rep2, run2 (whole part only).
    static func trial(in part: String) -> Int? {
        let p = part.lowercased()
        for prefix in ["trial", "rep", "run", "t"] where p.hasPrefix(prefix) {
            let rest = p.dropFirst(prefix.count)
            if !rest.isEmpty, rest.count <= 3, let n = Int(rest), n > 0 { return n }
        }
        return nil
    }

    static func suggest(url: URL, pattern: NamePattern, animals: [String], timepoints: [String]) -> NameSuggestion {
        let s = stem(url)
        let folders = url.deletingLastPathComponent().pathComponents.suffix(3).reversed().map { String($0) }
        return suggest(stem: s, folders: Array(folders), pattern: pattern, animals: animals, timepoints: timepoints)
    }

    /// `folders`: names of the enclosing folders, nearest first.
    static func suggest(stem: String, folders: [String] = [], pattern: NamePattern, animals: [String], timepoints: [String]) -> NameSuggestion {
        let p = parts(stem, separators: pattern.separators)
        func part(_ i: Int?) -> String? {
            guard let i, i >= 1, i <= p.count else { return nil }
            return p[i - 1]
        }

        // Animal
        var animal: String
        if let a = part(pattern.animalPart) {
            animal = registered(a, in: animals) ?? a
        } else {
            let lower = squash(stem)
            let hit = animals.filter { !$0.isEmpty && lower.contains(squash($0)) && !squash($0).isEmpty }
                .max { squash($0).count < squash($1).count }
            animal = hit ?? stem
        }

        // Timepoint
        var timepoint = ""
        if let t = part(pattern.timepointPart) {
            timepoint = registered(t, in: timepoints) ?? t
        } else if !timepoints.isEmpty {
            let candidates = [stem] + folders
            outer: for c in candidates {
                let lc = squash(c)
                // Longest registered timepoint first ("Day 28" before "Day 2").
                for t in timepoints.sorted(by: { squash($0).count > squash($1).count }) where !squash(t).isEmpty {
                    if lc.contains(squash(t)) { timepoint = t; break outer }
                }
            }
        }

        // Trial
        var trial: Int?
        if let t = part(pattern.trialPart) {
            trial = Int(t) ?? Self.trial(in: t)
        } else {
            trial = p.compactMap { Self.trial(in: $0) }.last
        }
        if animal.isEmpty { animal = stem }
        return NameSuggestion(animal: animal, timepoint: timepoint, trial: trial)
    }

    /// The registered spelling of a name written differently ("day7" → "Day 7").
    static func registered(_ s: String, in list: [String]) -> String? {
        let k = squash(s)
        guard !k.isEmpty else { return nil }
        return list.first { squash($0) == k }
    }
}
