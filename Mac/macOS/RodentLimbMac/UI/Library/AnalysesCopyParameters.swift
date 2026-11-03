// AnalysesCopyParameters.swift — copies the parameters (and optionally the calibration) of one
// session to the other selected sessions of the same task (Sessions tab › Copy Parameters to
// Selected…). Each video keeps its own injection time and injected paw.

import SwiftUI

// MARK: - Copy parameters

struct AnalysesCopyRequest: Identifiable {
    let id = UUID()
    var ids: [UUID]
    var source: UUID?
}

/// Copies the parameters (and optionally the calibration) of one analysis to the others of the
/// same task. Each video keeps its own injection time and injected paw.
@MainActor
struct AnalysesCopyParametersSheet: View {
    let request: AnalysesCopyRequest
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var source: UUID?
    @State private var calibration = false
    @State private var loaded = false

    var body: some View {
        let store = app.store
        let sessions = request.ids.compactMap { store.session($0) }
        let src = source.flatMap { store.session($0) }
        let targets = sessions.filter { $0.id != src?.id && $0.assay == src?.assay }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Copy Parameters", "复制参数")).font(.headline)
                Text(L("The chosen session's parameters replace those of the other selected sessions of the same task, which are then analysed again. Each video keeps its own injection time and injected paw.",
                       "所选会话的参数将替换同一任务中其他所选会话的参数，随后重新分析。每段视频保留各自的注射时刻和注射爪。"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker(L("Copy from", "复制自"), selection: $source) {
                ForEach(sessions) { s in
                    Text(label(s)).tag(UUID?.some(s.id))
                }
            }
            Toggle(L("Also copy the calibration (cylinder rim, floor line, scale)", "同时复制标定（圆筒边缘、地面线、比例尺）"), isOn: $calibration)
                .help(L("Only when every video was filmed with the same camera position", "仅当所有视频的相机位置相同时使用"))
            Text(String(format: L("%d sessions will be changed and re-analysed.", "将修改并重新分析 %d 个会话。"), targets.count))
                .font(.callout.weight(.semibold))
            HStack {
                Spacer()
                Button(L("Cancel", "取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Copy Parameters", "复制参数")) {
                    guard let sid = src?.id else { return }
                    store.applySettings(from: sid, to: targets.map(\.id), calibration: calibration)
                    app.toast = String(format: L("Parameters copied to %d sessions", "已将参数复制到 %d 个会话"), targets.count)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(src == nil || targets.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            source = request.source ?? request.ids.first
        }
    }

    private func label(_ s: Session) -> String {
        let store = app.store
        let r = store.recording(for: s)
        let animal = r.map { RecordingsQuery.animalLabel($0, store: store) } ?? s.displayName
        let group = r.map { store.groupLabel($0) } ?? s.group
        return [animal, group, s.status.title].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
