// StudySupport.swift — small helpers shared by the study pages: design presets (factors and
// timepoints, as on the iPhone), list parsing, a text field that saves only when editing ends,
// the state shown for an animal × timepoint cell, and the pasteboard.
//
// Preset factor names, levels and timepoints are data (they go into exports), so they stay English.

import SwiftUI
import AppKit

// MARK: - Presets

/// A between-subject factor offered as a preset.
struct StudyFactorPreset: Identifiable {
    let id: String
    let title: String
    let name: String
    let levels: [String]
}

/// A sequence of within-subject timepoints / conditions offered as a preset.
struct StudyTimepointPreset: Identifiable {
    let id: String
    let title: String
    let timepoints: [String]
}

enum StudyPresets {
    /// The iPhone app's factor presets (control level first).
    static var factors: [StudyFactorPreset] {
        [
            StudyFactorPreset(id: "genotype", title: L("Genotype: WT, KO", "基因型：WT, KO"),
                              name: "Genotype", levels: ["WT", "KO"]),
            StudyFactorPreset(id: "treatment", title: L("Treatment: Vehicle, Drug", "处理：Vehicle, Drug"),
                              name: "Treatment", levels: ["Vehicle", "Drug"]),
            StudyFactorPreset(id: "dose", title: L("Dose: 0, 1, 3, 10 mg/kg", "剂量：0, 1, 3, 10 mg/kg"),
                              name: "Dose", levels: ["0 mg/kg", "1 mg/kg", "3 mg/kg", "10 mg/kg"]),
            StudyFactorPreset(id: "surgery", title: L("Surgery: Sham, Lesion", "手术：Sham, Lesion"),
                              name: "Surgery", levels: ["Sham", "Lesion"]),
        ]
    }

    /// The iPhone app's timepoint presets.
    static var timepoints: [StudyTimepointPreset] {
        [
            StudyTimepointPreset(id: "prepost", title: "Pre, Post", timepoints: ["Pre", "Post"]),
            StudyTimepointPreset(id: "days", title: "Baseline, Day 7, Day 14, Day 28",
                                 timepoints: ["Baseline", "Day 7", "Day 14", "Day 28"]),
            StudyTimepointPreset(id: "crossover",
                                 title: L("Crossover: Vehicle, Low dose, High dose", "交叉设计：Vehicle, Low dose, High dose"),
                                 timepoints: ["Vehicle", "Low dose", "High dose"]),
        ]
    }
}

// MARK: - Text

enum StudyText {
    static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "a, b; c" (also full-width separators and new lines) → trimmed, non-empty, unique, in order.
    static func list(_ text: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        let parts = text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" || $0.isNewline })
        for part in parts {
            let v = part.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty && !seen.contains(v) { seen.insert(v); out.append(v) }
        }
        return out
    }

    /// Unique values, first occurrence kept, order preserved.
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for v in values where !seen.contains(v) { seen.insert(v); out.append(v) }
        return out
    }

    /// Sex written in a pasted list (English or Chinese, short or long); nil when not a sex.
    static func sex(_ text: String) -> AnimalSex? {
        switch trimmed(text).lowercased() {
        case "m", "male", "♂", "雄", "雄性", "公": return .male
        case "f", "female", "♀", "雌", "雌性", "母": return .female
        case "?", "u", "unknown", "na", "n/a": return .unknown
        default: return nil
        }
    }

    /// Whether another animal of the study already uses this ID (case-insensitive).
    static func codeTaken(_ code: String, in e: Experiment, except id: UUID?) -> Bool {
        guard let other = e.animal(code: code) else { return false }
        return other.id != id
    }

    /// Number of groups as "4 (2 × 2)".
    static func groupCount(_ e: Experiment) -> String {
        let active = e.activeFactors
        guard !active.isEmpty else { return "1" }
        let n = e.cells.count
        if active.count == 1 { return "\(n)" }
        return "\(n) (" + active.map { "\($0.levels.count)" }.joined(separator: " × ") + ")"
    }
}

// MARK: - Video state of a grid cell

enum StudyVideoState {
    /// Order used to pick the state shown for a cell with several trials: usable data first, then
    /// what still needs the user, then what is on its way, then what failed or was excluded.
    static func rank(_ r: Recording) -> Int {
        switch r.status {
        case .ready:
            switch r.decision {
            case .included: return 0
            case .pending: return 1
            case .excluded: return 5
            }
        case .processing: return 2
        case .queued: return 3
        case .failed: return 4
        }
    }

    static func best(_ recs: [Recording]) -> Recording? {
        recs.min { rank($0) < rank($1) }
    }

    /// Trials of one cell in order (trial number, then import time).
    static func sortedTrials(_ recs: [Recording]) -> [Recording] {
        recs.sorted { $0.trial != $1.trial ? $0.trial < $1.trial : $0.createdAt < $1.createdAt }
    }

    /// Whether the best state of a cell needs the user (review or failure).
    static func needsAttention(_ r: Recording) -> Bool {
        (r.status == .ready && r.decision == .pending) || r.status == .failed
    }
}

// MARK: - Pasteboard

enum StudyClipboard {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

// MARK: - Commit-on-end text field

/// A plain text field that writes back only when editing ends (Return or focus leaves), so typing
/// does not rewrite the study on every keystroke. `commit` returns false to reject the value
/// (the field then shows the stored value again).
struct StudyCommitField: View {
    let value: String
    let prompt: String
    let axis: Axis
    let commit: (String) -> Bool

    @State private var draft: String
    @FocusState private var focused: Bool

    init(value: String, prompt: String = "", axis: Axis = .horizontal, commit: @escaping (String) -> Bool) {
        self.value = value
        self.prompt = prompt
        self.axis = axis
        self.commit = commit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(prompt, text: $draft, prompt: Text(prompt), axis: axis)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { finish() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { finish() }
            }
            .onChange(of: value) { _, newValue in
                if !focused { draft = newValue }
            }
            .onExitCommand {
                draft = value
                focused = false
            }
            // Closing the sheet or leaving the page while typing keeps what was typed.
            .onDisappear { finish() }
    }

    private func finish() {
        guard draft != value else { return }
        if !commit(draft) { draft = value }
    }
}
