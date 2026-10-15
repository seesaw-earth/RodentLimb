// LibraryView.swift — all sessions in a native list: filter by assay, search, swipe to delete,
// Edit to multi-select for export, and group comparison per assay.

import SwiftUI
import Charts

@MainActor
struct LibraryView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue

    @State private var filter: Assay?
    @State private var search = ""
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var share: SharePayload?
    @State private var pendingDelete: Set<UUID> = []
    @State private var confirmDelete = false
    @State private var compareAssay: Assay?
    @State private var message: String?

    private var list: [Session] {
        store.sessions.filter { s in
            (filter == nil || s.assay == filter) &&
            (search.isEmpty || s.subject.localizedCaseInsensitiveContains(search) || s.group.localizedCaseInsensitiveContains(search)
             || s.originalName.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack(path: $app.libraryPath) {
            List(selection: $selection) {
                Section {
                    Picker(L("Assay", "范式"), selection: $filter) {
                        Text(L("All", "全部")).tag(Assay?.none)
                        ForEach(Assay.allCases) { Text($0.code).tag(Assay?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if let filter, list.contains(where: { $0.status == .done }) {
                    Section {
                        Button { compareAssay = filter } label: {
                            Label(L("Compare groups", "组间比较"), systemImage: "chart.bar.xaxis")
                        }
                    }
                }
                Section {
                    ForEach(list) { s in
                        NavigationLink(value: s.id) { SessionRow(session: s, card: false) }
                            .swipeActions {
                                Button(role: .destructive) { pendingDelete = [s.id]; confirmDelete = true } label: {
                                    Label(L("Delete", "删除"), systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) { pendingDelete = [s.id]; confirmDelete = true } label: {
                                    Label(L("Delete", "删除"), systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    if !list.isEmpty {
                        Text(String(format: L("%d sessions · stored on this iPhone", "%d 条记录 · 保存在本机"), list.count))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if list.isEmpty {
                    if search.isEmpty {
                        EmptyState(title: L("No sessions yet", "还没有记录"),
                                   message: L("Analyses you start appear here.", "开始的分析会显示在这里。"))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .navigationTitle(L("Data", "数据"))
            .searchable(text: $search, prompt: L("Subject, group or file", "动物编号、组别或文件名"))
            .environment(\.editMode, $editMode)
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { SessionDetailView(id: $0) }
            .sheet(item: $share) { ShareSheet(items: $0.items) }
            .sheet(item: $compareAssay) { a in GroupCompareView(assay: a).environmentObject(store).fontDesign(.rounded) }
            .confirmationDialog(String(format: L("Delete %d sessions and their files?", "删除 %d 条记录及其文件？"), pendingDelete.count),
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Delete", "删除"), role: .destructive) {
                    if let cur = queue.currentID, pendingDelete.contains(cur) { queue.cancelCurrent() }
                    store.delete(pendingDelete)
                    selection.subtract(pendingDelete)
                    pendingDelete = []
                }
            }
            .toast($message)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(editMode.isEditing ? L("Done", "完成") : L("Select", "选择")) {
                withAnimation(Motion.snappy) {
                    editMode = editMode.isEditing ? .inactive : .active
                    selection = []
                }
            }
            .disabled(store.sessions.isEmpty)
        }
        if editMode.isEditing {
            ToolbarItemGroup(placement: .bottomBar) {
                Button(selection.count == list.count ? L("Deselect all", "取消全选") : L("Select all", "全选")) {
                    selection = selection.count == list.count ? [] : Set(list.map(\.id))
                }
                Spacer()
                Button { exportSelection() } label: { Label(L("Export CSV", "导出 CSV"), systemImage: "square.and.arrow.up") }
                    .disabled(selection.isEmpty)
                Button(role: .destructive) { pendingDelete = selection; confirmDelete = true } label: {
                    Label(L("Delete", "删除"), systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private func exportSelection() {
        let chosen = store.sessions.filter { selection.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        let assays = Set(chosen.map(\.assay))
        var urls: [URL] = []
        for a in Assay.allCases where assays.contains(a) {
            let group = chosen.filter { $0.assay == a }
            let results = store.loadResults(group.map(\.id))
            if let u = Exporter.groupCSV(group, results: results) { urls.append(u) }
        }
        if urls.isEmpty { message = L("Nothing to export", "没有可导出的内容"); return }
        share = SharePayload(items: urls)
    }
}

// MARK: - Group comparison

@MainActor
struct GroupCompareView: View {
    let assay: Assay
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var metricKey = ""
    @State private var results: [UUID: AnalysisResult] = [:]
    @State private var share: SharePayload?

    private var sessions: [Session] { store.sessions.filter { $0.assay == assay && $0.status == .done } }

    private var metricOptions: [Metric] {
        var seen = Set<String>(), out: [Metric] = []
        for s in sessions {
            for m in results[s.id]?.metrics ?? [] where !seen.contains(m.key) { seen.insert(m.key); out.append(m) }
        }
        return out
    }

    private struct GroupStat: Identifiable {
        var id: String { name }
        var name: String
        var values: [Double]
        var mean: Double
        var sd: Double?
        var sem: Double? { sd.map { $0 / sqrt(Double(values.count)) } }
    }

    private var stats: [GroupStat] {
        var byGroup: [String: [Double]] = [:]
        var order: [String] = []
        for s in sessions {
            guard let v = results[s.id]?.metric(metricKey)?.value, v.isFinite else { continue }
            let g = s.group.isEmpty ? L("(no group)", "（未分组）") : s.group
            if byGroup[g] == nil { order.append(g) }
            byGroup[g, default: []].append(v)
        }
        return order.compactMap { g in
            guard let v = byGroup[g], let m = Signal.mean(v) else { return nil }
            return GroupStat(name: g, values: v, mean: m, sd: Signal.sd(v))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(L("Metric", "指标"), selection: $metricKey) {
                        ForEach(metricOptions) { m in
                            Text(m.label.text + (m.unit.isEmpty ? "" : " (\(m.unit))")).tag(m.key)
                        }
                    }
                    .pickerStyle(.menu)
                    Card {
                        let st = stats
                        let unit = metricOptions.first { $0.key == metricKey }?.unit ?? ""
                        Chart {
                            ForEach(st) { g in
                                BarMark(x: .value(L("Group", "组别"), g.name), y: .value("mean", g.mean))
                                    .foregroundStyle(Palette.assay(assay).opacity(0.35))
                                if let e = g.sem {
                                    RuleMark(x: .value(L("Group", "组别"), g.name), yStart: .value("lo", g.mean - e), yEnd: .value("hi", g.mean + e))
                                        .foregroundStyle(.primary)
                                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                                }
                                ForEach(Array(g.values.enumerated()), id: \.offset) { _, v in
                                    PointMark(x: .value(L("Group", "组别"), g.name), y: .value("v", v))
                                        .foregroundStyle(Palette.assay(assay))
                                        .symbolSize(30)
                                }
                            }
                        }
                        .chartYAxisLabel(unit)
                        .frame(height: 260)
                        Text(L("Bars = mean, whiskers = SEM, dots = individual animals.", "柱 = 均值，误差线 = 标准误，点 = 单只动物。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Card {
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text(L("Group", "组别")).gridColumnAlignment(.leading)
                                Text("n"); Text(L("Mean", "均值")); Text("SD"); Text("SEM")
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Divider()
                            ForEach(stats) { g in
                                GridRow {
                                    Text(g.name).lineLimit(1)
                                    Text("\(g.values.count)")
                                    Text(Fmt.num(g.mean, 2))
                                    Text(Fmt.num(g.sd, 2))
                                    Text(Fmt.num(g.sem, 2))
                                }
                                .font(.subheadline.monospacedDigit())
                            }
                        }
                        Text(L("Descriptive only. Run statistics in your usual software with the exported CSV.", "仅为描述性统计。请用导出的 CSV 在常用软件中做统计检验。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .screenContent()
                .padding(.vertical, 12)
            }
            .background(Palette.canvas)
            .navigationTitle(assay.name.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Close", "关闭")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { if let u = Exporter.groupCSV(sessions, results: results) { share = SharePayload(items: [u]) } } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L("Export CSV", "导出 CSV"))
                }
            }
            .sheet(item: $share) { ShareSheet(items: $0.items) }
            .task {
                results = store.loadResults(sessions.map(\.id))
                if metricKey.isEmpty { metricKey = metricOptions.first { $0.highlight }?.key ?? metricOptions.first?.key ?? "" }
            }
        }
    }
}
