// AnalysisEventList.swift — the events behind the numbers, next to the review player: cylinder
// wall contacts, behavior events (both relabelable), tail-suspension bouts and gait strides
// (read only). One list for every assay, keyboard first:
//   click = go to the event · ⌘-click / ⇧-click = select several · ↑/↓ = previous / next event
//   1…9 = label as class · 0 = ignore · ←/→ = frame · Space = play / pause · Return = play event
//   J/K/L , . as in the player · right-click = play, relabel, restore the automatic label.
// The row under the playhead is highlighted by a tiny background view observing ResultsPlaybackClock,
// so the rows themselves are not rebuilt during playback.

import SwiftUI
import AppKit

/// One row of the list.
struct AnalysisEventItem: Identifiable, Equatable {
    /// Stable event id (onset frame) for editable events; the index for read-only lists.
    let id: Int
    let onset: Double
    let offset: Double
    let time: String
    let detail: String
    /// Current label key (PawLabel raw value, behavior class key, or a filter key).
    let label: String
    let labelText: String
    let color: Color
    /// Counted in the measures (dimmed otherwise).
    let counted: Bool
    let edited: Bool
}

/// A label the reviewer can assign (or filter by), with its number key.
struct AnalysisEventChoice: Identifiable, Equatable {
    let key: String
    let title: String
    let color: Color
    let digit: Int?
    var id: String { key }
}

/// What the list shows for one analysis.
struct AnalysisEventModel {
    var title: String
    var items: [AnalysisEventItem]
    /// Shown in the filter menu.
    var filters: [AnalysisEventChoice]
    /// Labels that can be assigned; empty = read-only list.
    var choices: [AnalysisEventChoice]
    /// Seconds of video shown before an event when going to it.
    var leadIn: Double
    var emptyText: String

    var editable: Bool { !choices.isEmpty }
    static let ignoreKey = "ignore"
}

@MainActor
struct AnalysisEventList: View {
    let model: AnalysisEventModel
    let clock: ResultsPlaybackClock
    /// Not observed here (the player view does): only used to seek and play.
    let controller: PlayerController?
    /// (events, new label key) — the page decides whether that is an override or the automatic label.
    let relabel: (Set<Int>, String) -> Void
    let restore: (Set<Int>) -> Void

    @State private var selection: Set<Int> = []
    @State private var anchor: Int?
    @State private var filter: String?
    @FocusState private var focused: Bool

    private var shown: [AnalysisEventItem] {
        guard let f = filter else { return model.items }
        return model.items.filter { $0.label == f }
    }

    var body: some View {
        let items = shown
        VStack(spacing: 0) {
            header(items)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            Divider()
            if items.isEmpty {
                Text(model.items.isEmpty ? model.emptyText : L("No events with this label.", "没有该标签的事件。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(items) { item in
                                row(item, in: items).id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: anchor) { _, a in
                        guard let a else { return }
                        proxy.scrollTo(a)
                    }
                }
            }
            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .background(Palette.card)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            move(press.key == .upArrow ? -1 : 1, in: shown, extend: press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard let c = controller else { return .ignored }
            let dir = press.key == .leftArrow ? -1 : 1
            if press.modifiers.contains(.shift) { c.jump(Double(dir)) } else { c.step(dir) }
            return .handled
        }
        .onKeyPress(.space) {
            guard let c = controller else { return .ignored }
            c.toggle()
            return .handled
        }
        .onKeyPress(.return) {
            guard let a = anchor, let item = model.items.first(where: { $0.id == a }) else { return .ignored }
            play(item)
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            digit(press.characters)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "jklJKL,.")) { press in
            // Same keys as the player, so playback can be driven from the list too.
            guard let c = controller else { return .ignored }
            switch press.characters.lowercased() {
            case "j": c.jump(-5)
            case "k": c.pause()
            case "l": c.play()
            case ",": c.step(-1)
            case ".": c.step(1)
            default: return .ignored
            }
            return .handled
        }
        .onAppear {
            // Keyboard review works at once (↑/↓, numbers, Space) without clicking the list first.
            Task { @MainActor in focused = true }
        }
        .onChange(of: filter) { _, _ in
            let visible = Set(shown.map(\.id))
            selection = selection.intersection(visible)
            if let a = anchor, !visible.contains(a) { anchor = nil }
        }
    }

    // MARK: Header & footer

    private func header(_ items: [AnalysisEventItem]) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.headline)
                Text(countText(items)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 6)
            if model.editable {
                Menu {
                    labelButtons(validSelection, current: currentLabel(validSelection))
                } label: {
                    Text(L("Label", "标签"))
                }
                .controlSize(.small)
                .fixedSize()
                .disabled(validSelection.isEmpty)
                .help(L("Relabel the selected events (or press 1–9, 0 = ignore)", "修改所选事件的标签（或按 1–9，0 = 忽略）"))
            }
            if !model.filters.isEmpty {
                Picker(L("Show", "显示"), selection: $filter) {
                    Text(String(format: L("All (%d)", "全部（%d）"), model.items.count)).tag(String?.none)
                    ForEach(model.filters) { f in
                        Text("\(f.title) (\(count(f.key)))").tag(String?.some(f.key))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help(L("Show only events with this label", "只显示该标签的事件"))
            }
        }
    }

    private var footer: some View {
        Text(hint)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String {
        guard model.editable else {
            return L("Click a row to go to it · ↑/↓ previous / next · Space play / pause",
                     "点击行跳到该处 · ↑/↓ 上一个 / 下一个 · 空格 播放 / 暂停")
        }
        let keys = model.choices.compactMap { c in c.digit.map { "\($0) \(c.title)" } }.joined(separator: " · ")
        return L("Click = go to event · ↑/↓ = previous / next · Space = play. Relabel with right-click or the keys: ",
                 "点击 = 跳到事件 · ↑/↓ = 上一个 / 下一个 · 空格 = 播放。右键或按键修改标签：") + keys
    }

    private func countText(_ items: [AnalysisEventItem]) -> String {
        let counted = model.items.filter { $0.counted }.count
        var text = String(format: L("%d shown · %d counted", "显示 %d 个 · 计入 %d 个"), items.count, counted)
        let edited = model.items.filter { $0.edited }.count
        if edited > 0 { text += String(format: L(" · %d edited", " · 已修改 %d 个"), edited) }
        if validSelection.count > 1 { text += String(format: L(" · %d selected", " · 已选 %d 个"), validSelection.count) }
        return text
    }

    private func count(_ key: String) -> Int { model.items.filter { $0.label == key }.count }

    // MARK: Rows

    private func row(_ item: AnalysisEventItem, in items: [AnalysisEventItem]) -> some View {
        let selected = selection.contains(item.id)
        let ignored = item.label == AnalysisEventModel.ignoreKey
        return HStack(spacing: 8) {
            Button {
                play(item)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ignored ? Color.secondary : item.color)
            }
            .buttonStyle(.plain)
            .help(L("Play from here (Return)", "从这里播放（回车）"))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.time).font(.callout.monospacedDigit().weight(.medium))
                if !item.detail.isEmpty {
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Text(item.labelText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(ignored ? Color.secondary : Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ignored ? Palette.inset : item.color, in: Capsule())
                .frame(maxWidth: 160, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            ZStack {
                ReviewActiveRowMarker(clock: clock, start: item.onset - 0.05, end: max(item.offset, item.onset + 0.3))
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(focused ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.16))
                }
            }
        }
        .opacity(item.counted ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { click(item, in: items) }
        .contextMenu { menu(for: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func menu(for item: AnalysisEventItem) -> some View {
        let targets: Set<Int> = selection.contains(item.id) && selection.count > 1 ? validSelection : [item.id]
        Button(L("Play from Here", "从这里播放")) { play(item) }
        if model.editable {
            Divider()
            labelButtons(targets, current: currentLabel(targets))
            if model.items.contains(where: { targets.contains($0.id) && $0.edited }) {
                Divider()
                Button(targets.count > 1 ? L("Restore Automatic Labels", "恢复自动标签") : L("Restore Automatic Label", "恢复自动标签")) {
                    restore(targets)
                }
            }
        }
    }

    /// One checkable item per label (checkmark on the current label when all targets share it).
    @ViewBuilder
    private func labelButtons(_ targets: Set<Int>, current: String?) -> some View {
        ForEach(model.choices) { c in
            Toggle(isOn: Binding(get: { c.key == current }, set: { _ in relabel(targets, c.key) })) {
                Text(c.digit.map { "\(c.title)    \($0)" } ?? c.title)
            }
        }
    }

    // MARK: Selection & keys

    /// Selected ids that are still in the list (events can disappear after re-analysis).
    private var validSelection: Set<Int> {
        guard !selection.isEmpty else { return [] }
        let ids = Set(model.items.map(\.id))
        return selection.intersection(ids)
    }

    private func currentLabel(_ targets: Set<Int>) -> String? {
        let labels = Set(model.items.filter { targets.contains($0.id) }.map(\.label))
        return labels.count == 1 ? labels.first : nil
    }

    private func click(_ item: AnalysisEventItem, in items: [AnalysisEventItem]) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchor = item.id
        } else if flags.contains(.shift), let a = anchor,
                  let i = items.firstIndex(where: { $0.id == a }), let j = items.firstIndex(where: { $0.id == item.id }) {
            let lo = min(i, j), hi = max(i, j)
            selection = Set(items[lo...hi].map(\.id))
        } else {
            selection = [item.id]
            anchor = item.id
            seek(item)
        }
    }

    private func move(_ delta: Int, in items: [AnalysisEventItem], extend: Bool) {
        guard !items.isEmpty else { return }
        let next: Int
        if let a = anchor, let current = items.firstIndex(where: { $0.id == a }) {
            next = min(max(0, current + delta), items.count - 1)
        } else {
            // Nothing selected yet: start from the playhead.
            let t = clock.time
            if delta > 0 {
                next = items.firstIndex { $0.onset >= t - 0.05 } ?? (items.count - 1)
            } else {
                next = items.lastIndex { $0.onset <= t + 0.05 } ?? 0
            }
        }
        guard items.indices.contains(next) else { return }
        let item = items[next]
        if extend { selection.insert(item.id) } else { selection = [item.id] }
        anchor = item.id
        seek(item)
    }

    private func digit(_ chars: String) -> KeyPress.Result {
        guard model.editable, let n = Int(chars), let c = model.choices.first(where: { $0.digit == n }) else { return .ignored }
        let targets = validSelection
        guard !targets.isEmpty else { return .ignored }
        relabel(targets, c.key)
        return .handled
    }

    private func seek(_ item: AnalysisEventItem) {
        controller?.seek(max(0, item.onset - model.leadIn))
    }

    private func play(_ item: AnalysisEventItem) {
        focused = true
        selection = [item.id]
        anchor = item.id
        guard let c = controller else { return }
        c.seek(max(0, item.onset - model.leadIn))
        c.play()
    }
}

/// Highlights a row while the playhead is inside its event (observes only the coarse clock).
@MainActor
private struct ReviewActiveRowMarker: View {
    @ObservedObject var clock: ResultsPlaybackClock
    let start: Double
    let end: Double

    var body: some View {
        let on = clock.time >= start && clock.time <= end
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(on ? Color.accentColor.opacity(0.10) : Color.clear)
            .overlay(alignment: .leading) {
                if on {
                    Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 3)
                }
            }
            .allowsHitTesting(false)
    }
}
