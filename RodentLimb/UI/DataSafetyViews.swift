// DataSafetyViews.swift — Recently Deleted (restore, or erase for good) and the metadata backups
// (restore; nothing is ever deleted by a restore, and the current state is backed up first).

import SwiftUI

@MainActor
struct RecentlyDeletedView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var queue: ProcessingQueue
    @State private var entries: [DeletedEntry] = []
    @State private var loaded = false
    @State private var erasing: DeletedEntry?
    @State private var confirmEmpty = false
    @State private var working = false

    var body: some View {
        List {
            if loaded && entries.isEmpty {
                Text(L("Nothing was deleted in the last 30 days.", "最近 30 天没有删除任何内容。")).foregroundStyle(.secondary)
            }
            Section {
                ForEach(entries) { e in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(e.title).font(.body.weight(.semibold))
                        if !e.names.isEmpty {
                            Text(e.names.prefix(4).joined(separator: ", ") + (e.names.count > 4 ? " …" : ""))
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(String(format: L("Deleted %@ · %@ · erased after %@", "删除于 %@ · %@ · %@ 后彻底删除"),
                                    Fmt.date(e.deletedAt), Fmt.bytes(e.bytes),
                                    e.expires.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)
                                        .locale(Locale(identifier: Lang.isChinese ? "zh-Hans" : "en")))))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button(L("Restore", "恢复")) { restore(e) }.buttonStyle(SecondaryButtonStyle())
                            Button(L("Delete Now", "立即删除")) { erasing = e }.buttonStyle(SecondaryButtonStyle())
                        }
                        .disabled(working)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                if !entries.isEmpty {
                    Text(L("Deleted tasks, videos and sessions are kept here for 30 days, then erased.", "删除的任务、视频和实验会在这里保留 30 天，然后彻底删除。"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Recently Deleted", "最近删除"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Empty", "清空")) { confirmEmpty = true }.disabled(entries.isEmpty || working)
            }
        }
        .confirmationDialog(L("Erase this for good?", "彻底删除？"),
                            isPresented: Binding(get: { erasing != nil }, set: { if !$0 { erasing = nil } }),
                            titleVisibility: .visible, presenting: erasing) { e in
            Button(L("Delete Now", "立即删除"), role: .destructive) {
                Task { await store.eraseDeleted(e.id); await reload() }
            }
        } message: { _ in
            Text(L("This cannot be undone.", "此操作无法撤销。"))
        }
        .confirmationDialog(L("Erase everything in Recently Deleted?", "清空“最近删除”？"), isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button(L("Erase All", "全部删除"), role: .destructive) {
                Task { await store.emptyRecentlyDeleted(); await reload() }
            }
        } message: {
            Text(L("This cannot be undone.", "此操作无法撤销。"))
        }
        .task(id: store.recentlyDeletedVersion) { await reload() }
    }

    private func reload() async {
        entries = await store.recentlyDeleted()
        loaded = true
    }

    private func restore(_ e: DeletedEntry) {
        working = true
        Task { @MainActor in
            app.notice = await store.restoreDeleted(e.id)
            queue.kick()
            working = false
            await reload()
        }
    }
}

@MainActor
struct BackupsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @State private var backups: [BackupInfo] = []
    @State private var loaded = false
    @State private var restoring: BackupInfo?
    @State private var working = false

    var body: some View {
        List {
            Section {
                Button(L("Back Up Now", "立即备份")) {
                    store.backup(MetadataBackup.Reason.manual)
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        await reload()
                    }
                }
                .disabled(working)
            } footer: {
                Text(L("A backup holds every task, the design and decisions of every video, and the settings of every session (not the videos or tracking, which are never changed by edits). One is made every day and before deleting or bulk changes; the last 14 daily and 10 other backups are kept.",
                       "备份包含所有任务、每段视频的设计信息和纳入决定，以及每个实验的设置（不含视频和识别结果，编辑不会改变它们）。每天以及删除或批量修改前都会自动备份；保留最近 14 个每日备份和 10 个其他备份。"))
            }
            if loaded && backups.isEmpty {
                Text(L("No backups yet.", "还没有备份。")).foregroundStyle(.secondary)
            }
            Section {
                ForEach(backups) { b in
                    Button { restoring = b } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.date(b.createdAt)).foregroundStyle(.primary)
                                Text(b.reasonLabel + " · " + Fmt.bytes(b.bytes)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(L("Restore", "恢复")).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("Backups", "备份"))
        .confirmationDialog(L("Restore this backup?", "恢复该备份？"),
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible, presenting: restoring) { b in
            Button(L("Restore", "恢复")) { restore(b) }
        } message: { _ in
            Text(L("Tasks, video information, decisions and session settings return to this backup. Nothing is deleted, tracking is not touched, and the current state is backed up first.",
                   "任务、视频信息、纳入决定和实验设置将恢复到该备份。不会删除任何内容，也不会改动识别结果；恢复前会先备份当前状态。"))
        }
        .task { await reload() }
    }

    private func reload() async {
        backups = await store.backups()
        loaded = true
    }

    private func restore(_ b: BackupInfo) {
        working = true
        Task { @MainActor in
            app.notice = await store.restoreBackup(b.url)
            working = false
            await reload()
        }
    }
}
