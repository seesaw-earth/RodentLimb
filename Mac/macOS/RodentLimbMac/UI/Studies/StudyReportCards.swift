// StudyReportCards.swift — what a study reports: the exclusions (ARRIVE 2.0 item 3: every excluded
// video with its reason, plus the videos still waiting for a decision) and the methods text
// (`studyMethods`, English, read-only and selectable, with a Copy button). Rows open the video.
// Animals appear by blind code and without group while the study is blinded.

import SwiftUI

// MARK: - Exclusions

struct StudyExclusionsCard: View {
    let experiment: Experiment

    @Environment(AppModel.self) private var app
    @State private var showAllPending = false

    init(experiment: Experiment) { self.experiment = experiment }

    var body: some View {
        let store = app.store
        let recs = store.recordings(in: experiment.id)
        let excluded = recs.filter { $0.decision == .excluded }.sorted { title($0) < title($1) }
        let pending = recs.filter { $0.isProcessed && $0.decision == .pending }
        let noReason = excluded.filter { StudyText.trimmed($0.exclusionReason).isEmpty }.count
        Card {
            CardHeader(L("Exclusions", "排除记录"), symbol: "minus.circle",
                       subtitle: L("ARRIVE 2.0 item 3: report every excluded video and the reason. Exclusions are listed in the methods text.",
                                   "ARRIVE 2.0 第 3 项：报告每一个被排除的视频及其原因。排除记录会写入方法学描述。"))
            if excluded.isEmpty {
                Text(L("No video has been excluded.", "尚未排除任何视频。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if noReason > 0 {
                    Banner(text: String(format: L("%d excluded video(s) have no reason. Open them and add one.", "%d 段已排除的视频未填写原因，请打开并补充。"), noReason),
                           level: .warning)
                }
                VStack(spacing: 0) {
                    ForEach(Array(excluded.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 { Divider() }
                        excludedRow(item.element)
                    }
                }
            }
            if !pending.isEmpty {
                pendingList(pending)
            }
        }
    }

    private func title(_ r: Recording) -> String {
        let store = app.store
        var t = store.displayName(r)
        let g = store.groupLabel(r)   // group (unless blinded) · timepoint
        if !g.isEmpty { t += " · " + g }
        if r.trial > 1 { t += " · " + String(format: L("trial %d", "第 %d 次"), r.trial) }
        return t
    }

    private func excludedRow(_ r: Recording) -> some View {
        let reason = StudyText.trimmed(r.exclusionReason)
        return Button {
            app.open(.recording(r.id))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Palette.gray).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(r)).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(reason.isEmpty ? L("No reason given", "未填写原因") : reason)
                        .font(.callout)
                        .foregroundStyle(reason.isEmpty ? Palette.warning : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                QCBadge(report: r.qc)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Open the video", "打开视频"))
    }

    private func pendingList(_ pending: [Recording]) -> some View {
        let shown = showAllPending ? pending : Array(pending.prefix(6))
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(format: L("%d videos need an inclusion decision.", "%d 段视频待决定是否纳入。"), pending.count))
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.warning)
            ForEach(shown) { r in
                Button {
                    app.open(.recording(r.id))
                } label: {
                    HStack(spacing: 8) {
                        Text(title(r)).lineLimit(1)
                        Spacer(minLength: 8)
                        RecordingStatusTag(recording: r, missing: app.store.missingVideos.contains(r.id))
                    }
                    .font(.callout)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Open the video to include or exclude it", "打开视频以决定纳入或排除"))
            }
            if pending.count > 6 {
                Button(showAllPending ? L("Show Fewer", "收起") : String(format: L("Show All %d", "显示全部 %d 段"), pending.count)) {
                    withAnimation(Motion.snappy) { showAllPending.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Methods text

struct StudyMethodsCard: View {
    let experiment: Experiment

    @Environment(AppModel.self) private var app

    init(experiment: Experiment) { self.experiment = experiment }

    var body: some View {
        let text = app.store.studyMethods(experiment)
        Card {
            CardHeader(title: L("Methods text", "方法学描述"), symbol: "doc.plaintext",
                       subtitle: L("Task-design paragraph for the methods section (English; ARRIVE 2.0). It follows the task as it changes and is also part of the task export.",
                                   "用于方法部分的任务设计段落（英文；ARRIVE 2.0）。随任务变化自动更新，也包含在任务导出中。")) {
                Button {
                    StudyClipboard.copy(text)
                    app.toast = L("Methods text copied", "已拷贝方法学描述")
                } label: {
                    Text(L("Copy", "拷贝"))
                }
                .controlSize(.small)
                .help(L("Copy the methods text to the clipboard", "将方法学描述拷贝到剪贴板"))
            }
            ScrollView {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 240)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5)
            }
        }
    }
}
