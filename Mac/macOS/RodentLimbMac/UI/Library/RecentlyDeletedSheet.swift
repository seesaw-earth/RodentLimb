// RecentlyDeletedSheet.swift — File › Recently Deleted… (⌥⌘⌫): videos, analyses and studies deleted
// in the last 30 days, with Restore and Delete Now. Deleting never erases anything at once; the
// folders wait in "<library>/Recently Deleted/" (Core/LibrarySafety.swift).

import SwiftUI
import AppKit

@MainActor
struct RecentlyDeletedSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DeletedEntry] = []
    @State private var loaded = false
    @State private var busy: UUID?
    @State private var confirmEmpty = false
    @State private var confirmErase: DeletedEntry?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Recently Deleted", "最近删除")).font(.title2.weight(.bold))
                    Text(String(format: L("Deleted videos, analyses and tasks are kept for %d days, then erased. Video files kept in their own folders are never deleted.",
                                          "删除的视频、分析和任务会保留 %d 天后再清除。保留在原位置的视频文件从不会被删除。"), RecentlyDeleted.keepDays))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            Group {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    EmptyState(title: L("Nothing deleted", "没有已删除的项目"),
                               message: L("Items you delete appear here for 30 days.", "删除的项目会在这里保留 30 天。"),
                               symbol: "trash")
                } else {
                    List {
                        ForEach(entries) { e in row(e) }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 160)
            Divider()
            HStack {
                Button(L("Show in Finder", "在访达中显示")) {
                    let url = RecentlyDeleted.root(app.store.base)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button(L("Empty…", "清空…"), role: .destructive) { confirmEmpty = true }
                    .disabled(entries.isEmpty)
                Spacer()
                Button(L("Done", "完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .sheetFrame(minWidth: 460, idealWidth: 620, maxWidth: 900, minHeight: 320, idealHeight: 480, maxHeight: 800)
        .task(id: app.store.recentlyDeletedVersion) { await reload() }
        .confirmationDialog(L("Erase everything in Recently Deleted?", "清空“最近删除”中的所有项目？"), isPresented: $confirmEmpty,
                            titleVisibility: .visible) {
            Button(L("Erase", "清除"), role: .destructive) { Task { await app.store.emptyRecentlyDeleted() } }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("This cannot be undone.", "此操作无法撤销。"))
        }
        .confirmationDialog(L("Erase this item now?", "立即清除该项目？"),
                            isPresented: Binding(get: { confirmErase != nil }, set: { if !$0 { confirmErase = nil } }),
                            titleVisibility: .visible, presenting: confirmErase) { e in
            Button(L("Erase", "清除"), role: .destructive) { Task { await app.store.eraseDeleted(e.id) } }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: { _ in
            Text(L("This cannot be undone.", "此操作无法撤销。"))
        }
    }

    private func row(_ e: DeletedEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.headline)
                if !e.names.isEmpty {
                    Text(names(e)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(details(e)).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if busy == e.id {
                ProgressView().controlSize(.small)
            } else {
                Button(L("Restore", "恢复")) { restore(e) }
                    .buttonStyle(.borderedProminent)
                Button(L("Erase…", "清除…")) {
                    confirmErase = e
                }
                .help(L("Erase now", "立即清除"))
            }
        }
        .padding(.vertical, 4)
    }

    private func names(_ e: DeletedEntry) -> String {
        let shown = e.names.prefix(4).joined(separator: ", ")
        let total = e.kind == .analyses ? e.sessionIDs.count : e.recordingIDs.count
        let more = max(0, total - min(4, e.names.count))
        return more > 0 ? shown + String(format: L(" and %d more", " 等另外 %d 项"), more) : shown
    }

    private func details(_ e: DeletedEntry) -> String {
        let days = max(0, Int(ceil(e.expires.timeIntervalSinceNow / 86_400)))
        var parts = [String(format: L("Deleted %@", "删除于 %@"), Fmt.date(e.deletedAt)),
                     String(format: L("erased in %d day(s)", "%d 天后清除"), days)]
        if e.bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: e.bytes, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        entries = await app.store.recentlyDeleted()
        loaded = true
    }

    private func restore(_ e: DeletedEntry) {
        busy = e.id
        Task { @MainActor in
            let text = await app.store.restoreDeleted(e.id)
            app.batch.kick()
            busy = nil
            app.toast = text
        }
    }
}
