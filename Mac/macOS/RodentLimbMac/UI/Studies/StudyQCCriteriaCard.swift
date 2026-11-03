// StudyQCCriteriaCard.swift — the study's inclusion criteria (QCCriteria), set before scoring
// (ARRIVE 2.0 item 3). The sliders edit a draft; Apply saves it, and the store then re-runs QC for
// every tracked video of the study (decisions already made are kept; videos still waiting for a
// decision are rated again and included automatically when they now pass).

import SwiftUI

struct StudyQCCriteriaCard: View {
    let experiment: Experiment

    @Environment(AppModel.self) private var app
    @State private var draft: QCCriteria

    init(experiment: Experiment) {
        self.experiment = experiment
        _draft = State(initialValue: experiment.qc)
    }

    var body: some View {
        let e = experiment
        let changed = draft != e.qc
        Card {
            CardHeader(L("Inclusion criteria (QC)", "纳入标准（QC）"), symbol: "checkmark.shield",
                       subtitle: L("Set before scoring (ARRIVE 2.0 item 3). Videos meeting every criterion are included automatically; the others wait for a decision with a reason.",
                                   "评分前设定（ARRIVE 2.0 第 3 项）。满足所有标准的视频自动纳入；其余视频需填写原因后决定。"))
            VStack(spacing: 10) {
                StudyCriterionRow(title: L("Pass: mouse tracked ≥", "通过：小鼠可用帧 ≥"),
                                  help: L("Share of frames with nose and tail base usable after short-gap filling.", "填补短缺口后，鼻尖和尾根都可用的帧占比。"),
                                  value: $draft.passCoverage, range: 0.5...1, step: 0.01) { Fmt.percent($0) }
                StudyCriterionRow(title: L("Fail: mouse tracked <", "不通过：小鼠可用帧 <"),
                                  help: L("Below this the video is rated a QC failure; between the two thresholds it needs a decision.", "低于此值判为 QC 不通过；介于两个阈值之间需人工决定。"),
                                  value: $draft.failCoverage, range: 0.3...0.95, step: 0.01) { Fmt.percent($0) }
                StudyCriterionRow(title: L("Longest loss allowed", "允许的最长丢失"),
                                  help: L("Longest stretch without the mouse that still passes.", "仍可通过的最长连续丢失时长。"),
                                  value: $draft.maxLostSeconds, range: 1...60, step: 1) { String(format: L("%.0f s", "%.0f 秒"), $0) }
                StudyCriterionRow(title: L("Minimum frame rate", "最低帧率"),
                                  help: L("Fast behaviours (steps, scratching, flinches) need ≥ 60 fps.", "快速动作（步态、抓挠、甩爪）需要 ≥ 60 fps。"),
                                  value: $draft.minFPS, range: 10...120, step: 5) { String(format: "%.0f fps", $0) }
                StudyCriterionRow(title: L("Implausible jumps allowed", "允许的不合理跳点"),
                                  help: L("Share of frames in which a keypoint jumps away and back (wrong detections, left/right swaps).", "关键点跳开又跳回的帧占比（误检、左右互换）。"),
                                  value: $draft.maxJumpRate, range: 0...0.1, step: 0.005) { Fmt.percent($0, 1) }
            }
            if draft.failCoverage > draft.passCoverage {
                Banner(text: L("The failure threshold is above the pass threshold; it will be lowered to the pass threshold.",
                               "不通过阈值高于通过阈值，应用时将降至通过阈值。"), level: .warning)
            }
            Text(verdictLine(e))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(L("Defaults", "默认值")) { draft = QCCriteria() }
                    .disabled(draft == QCCriteria())
                    .help(L("Restore the default criteria (not saved until you apply)", "恢复默认标准（应用后才保存）"))
                Spacer()
                if changed {
                    Text(L("Not applied yet", "尚未应用"))
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                }
                Button(L("Revert", "还原")) { draft = e.qc }
                    .disabled(!changed)
                Button(L("Apply Criteria", "应用标准")) { apply(e) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!changed)
                    .help(L("Save the criteria and re-check this task's tracked videos", "保存标准并重新检查本任务已识别的视频"))
            }
            .controlSize(.small)
        }
        .onChange(of: e.qc) { old, new in
            // Saved elsewhere (another window, the iPhone file): follow unless the user is editing.
            if draft == old { draft = new }
        }
    }

    private func verdictLine(_ e: Experiment) -> String {
        var pass = 0, warn = 0, fail = 0, unchecked = 0
        for r in app.store.recordings(in: e.id) where r.hasPose {
            switch r.qc?.verdict {
            case .pass?: pass += 1
            case .warn?: warn += 1
            case .fail?: fail += 1
            case nil: unchecked += 1
            }
        }
        var parts = [String(format: L("Current QC: %d passed", "当前 QC：%d 段通过"), pass),
                     String(format: L("%d warning", "%d 段警告"), warn),
                     String(format: L("%d failed", "%d 段不通过"), fail)]
        if unchecked > 0 { parts.append(String(format: L("%d being checked", "%d 段检查中"), unchecked)) }
        return parts.joined(separator: " · ")
    }

    private func apply(_ e: Experiment) {
        var c = draft
        if c.failCoverage > c.passCoverage { c.failCoverage = c.passCoverage }
        let criteria = c
        let tracked = app.store.recordings(in: e.id).filter { $0.hasPose }.count
        app.store.updateExperiment(e.id) { $0.qc = criteria }
        draft = criteria
        app.toast = tracked > 0
            ? String(format: L("Criteria applied — re-checking %d videos", "已应用标准——正在重新检查 %d 段视频"), tracked)
            : L("Criteria applied", "已应用标准")
    }
}

/// One criterion: title and explanation, slider, value.
private struct StudyCriterionRow: View {
    let title: String
    let help: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300, alignment: .leading)
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
            Text(format(value))
                .font(.callout.monospacedDigit())
                .frame(width: 70, alignment: .trailing)
                .textSelection(.enabled)
        }
        .help(help)
    }
}
