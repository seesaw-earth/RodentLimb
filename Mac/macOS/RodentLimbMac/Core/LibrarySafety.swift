// LibrarySafety.swift — nothing made in RodentLimb is lost to one click, one crash or a second Mac.
//
//  • Recently Deleted: deleting videos, analyses or a study moves their folders into
//    "<library>/Recently Deleted/<entry>/" (same layout as the library) instead of erasing them.
//    Restore puts them back; an entry is erased for good after 30 days or with "Delete Now".
//    Referenced video files are never touched by a delete (they were never inside the library).
//  • Metadata backups: one compact JSON file with every study, video record and analysis setting
//    ("<library>/Backups/metadata-<date>-<reason>.json"), once a day and before risky changes.
//    Tracking (pose.bin) and results are not in it: edits never change the pose, and results are
//    recomputed from the settings. Restoring a backup never deletes anything.
//  • Library lock: "<library>/.rodentlimb-lock.json" names the Mac that has the library open and is
//    refreshed every minute, so opening the same library on two Macs (shared drive, iCloud Drive)
//    gives a warning instead of two apps silently overwriting each other's changes.
//
// Everything here is plain file work (no UI, no main actor): the store calls it from its serial
// I/O queue, and the core tests run it on Linux.

import Foundation

// MARK: - Recently Deleted

struct DeletedEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case videos, analyses, study }

    /// A video that only left the study (the study was deleted, its videos kept): restoring the
    /// study puts it back in, with the animal it had.
    struct Link: Codable, Hashable {
        var recordingID: UUID
        var animalID: UUID?
        var subject: String
        var group: String
    }

    var id = UUID()
    var deletedAt = Date()
    var kind: Kind
    var studyID: UUID?
    var studyName = ""
    var recordingIDs: [UUID] = []
    var sessionIDs: [UUID] = []
    /// Library-relative paths of what was moved ("Recordings/<id>", "Sessions/<id>", "Experiments/<id>.json").
    var items: [String] = []
    /// Display names of the first deleted videos / analyses (for the list).
    var names: [String] = []
    var detached: [Link] = []
    var bytes: Int64 = 0

    var expires: Date { deletedAt.addingTimeInterval(Double(RecentlyDeleted.keepDays) * 86_400) }

    var title: String {
        let v = recordingIDs.count, a = sessionIDs.count
        switch kind {
        case .study:
            let name = studyName.isEmpty ? L("Study", "研究") : "“\(studyName)”"
            if v > 0 { return String(format: L("%@ with %d video(s)", "%@ 及 %d 段视频"), name, v) }
            return name
        case .videos:
            if a > 0 { return String(format: L("%d video record(s) and %d analysis(es)", "%d 条视频记录及 %d 个分析"), v, a) }
            return String(format: L("%d video record(s)", "%d 条视频记录"), v)
        case .analyses:
            return String(format: L("%d analysis(es)", "%d 个分析"), a)
        }
    }
}

enum RecentlyDeleted {
    static let folderName = "Recently Deleted"
    static let entryFile = "entry.json"
    static let keepDays = 30

    static func root(_ base: URL) -> URL { base.appendingPathComponent(folderName, isDirectory: true) }
    static func folder(_ base: URL, _ id: UUID) -> URL { root(base).appendingPathComponent(id.uuidString, isDirectory: true) }

    /// Moves the entry's items out of the library into a new entry folder. The entry file is written
    /// first, so even an interruption half-way leaves everything findable. Returns the entry with its
    /// size filled in. Items that do not exist (never saved) are left out.
    @discardableResult
    static func move(_ entry: DeletedEntry, base: URL) -> DeletedEntry {
        let fm = FileManager.default
        var e = entry
        e.items = entry.items.filter { fm.fileExists(atPath: base.appendingPathComponent($0).path) }
        guard !e.items.isEmpty else { return e }
        let dir = folder(base, e.id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        write(e, to: dir)
        var moved: [String] = []
        for rel in e.items {
            let src = base.appendingPathComponent(rel), dst = dir.appendingPathComponent(rel)
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: src, to: dst)) != nil { moved.append(rel) }
        }
        e.items = moved
        e.bytes = size(of: dir)
        if moved.isEmpty { try? fm.removeItem(at: dir) } else { write(e, to: dir) }
        return e
    }

    /// Entries, newest first.
    static func list(_ base: URL) -> [DeletedEntry] {
        let fm = FileManager.default
        let decoder = Coders.decoder()
        var out: [DeletedEntry] = []
        for d in (try? fm.contentsOfDirectory(at: root(base), includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: d.appendingPathComponent(entryFile)),
                  let e = try? decoder.decode(DeletedEntry.self, from: data) else { continue }
            out.append(e)
        }
        return out.sorted { $0.deletedAt > $1.deletedAt }
    }

    struct RestoreOutcome {
        var entry: DeletedEntry
        var restored: [String] = []
        /// Items left in Recently Deleted because something with the same name is back in the library.
        var conflicts: [String] = []
    }

    /// Moves an entry's items back into the library. The entry disappears when everything is back.
    static func restore(_ id: UUID, base: URL) -> RestoreOutcome? {
        let fm = FileManager.default
        let dir = folder(base, id)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(entryFile)),
              let e = try? Coders.decoder().decode(DeletedEntry.self, from: data) else { return nil }
        var out = RestoreOutcome(entry: e)
        for rel in e.items {
            let src = dir.appendingPathComponent(rel), dst = base.appendingPathComponent(rel)
            guard fm.fileExists(atPath: src.path) else { continue }
            if fm.fileExists(atPath: dst.path) { out.conflicts.append(rel); continue }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: src, to: dst)) != nil { out.restored.append(rel) } else { out.conflicts.append(rel) }
        }
        if out.conflicts.isEmpty {
            try? fm.removeItem(at: dir)
        } else {
            var left = e
            left.items = out.conflicts
            left.bytes = size(of: dir)
            write(left, to: dir)
        }
        return out
    }

    static func erase(_ id: UUID, base: URL) {
        try? FileManager.default.removeItem(at: folder(base, id))
    }

    static func eraseAll(_ base: URL) {
        let fm = FileManager.default
        for d in (try? fm.contentsOfDirectory(at: root(base), includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: d)
        }
    }

    /// Erases entries older than `keepDays`. Returns how many were erased.
    @discardableResult
    static func purge(_ base: URL, now: Date = Date()) -> Int {
        let fm = FileManager.default
        var n = 0
        let decoder = Coders.decoder()
        for d in (try? fm.contentsOfDirectory(at: root(base), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let date: Date?
            if let data = try? Data(contentsOf: d.appendingPathComponent(entryFile)),
               let e = try? decoder.decode(DeletedEntry.self, from: data) {
                date = e.deletedAt
            } else {
                date = (try? d.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
            guard let date, now.timeIntervalSince(date) > Double(keepDays) * 86_400 else { continue }
            if (try? fm.removeItem(at: d)) != nil { n += 1 }
        }
        return n
    }

    private static func write(_ e: DeletedEntry, to dir: URL) {
        let enc = Coders.encoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(e) { try? data.write(to: dir.appendingPathComponent(entryFile), options: .atomic) }
    }

    static func size(of dir: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        while let u = en.nextObject() as? URL {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

// MARK: - Metadata backups

struct MetadataSnapshot: Codable {
    var format = 1
    var createdAt = Date()
    var reason: String
    var appVersion: String
    var experiments: [Experiment]
    var recordings: [Recording]
    var sessions: [Session]
}

struct BackupInfo: Identifiable, Hashable {
    var url: URL
    var createdAt: Date
    var reason: String
    var bytes: Int64
    var id: String { url.lastPathComponent }

    var reasonLabel: String {
        switch reason {
        case MetadataBackup.Reason.daily: return L("Daily", "每日")
        case MetadataBackup.Reason.beforeDelete: return L("Before deleting", "删除前")
        case MetadataBackup.Reason.beforeRestore: return L("Before restoring a backup", "恢复备份前")
        case MetadataBackup.Reason.beforeBulk: return L("Before a bulk change", "批量修改前")
        case MetadataBackup.Reason.manual: return L("Made by you", "手动创建")
        default: return reason
        }
    }
}

enum MetadataBackup {
    static let folderName = "Backups"
    static let keepDaily = 14
    static let keepOther = 10

    enum Reason {
        static let daily = "daily"
        static let beforeDelete = "before-delete"
        static let beforeRestore = "before-restore"
        static let beforeBulk = "before-bulk-change"
        static let manual = "manual"
    }

    static func root(_ base: URL) -> URL { base.appendingPathComponent(folderName, isDirectory: true) }

    private static func stamp() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }

    /// Writes a snapshot ("metadata-20261102-153000-daily.json", UTC). Compact JSON: readable with
    /// any JSON viewer, small enough to keep many.
    @discardableResult
    static func write(_ snap: MetadataSnapshot, base: URL) throws -> URL {
        let fm = FileManager.default
        let dir = root(base)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir.appendingPathComponent("metadata-\(stamp().string(from: snap.createdAt))-\(snap.reason).json")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("metadata-\(stamp().string(from: snap.createdAt))-\(snap.reason)-\(n).json")
            n += 1
        }
        let enc = Coders.encoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(snap).write(to: url, options: .atomic)
        prune(base)
        return url
    }

    /// Backups, newest first (read from the file names — the files are not opened).
    static func list(_ base: URL) -> [BackupInfo] {
        let fm = FileManager.default
        let f = stamp()
        var out: [BackupInfo] = []
        for u in (try? fm.contentsOfDirectory(at: root(base), includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
            let name = u.deletingPathExtension().lastPathComponent
            guard u.pathExtension == "json", name.hasPrefix("metadata-") else { continue }
            let parts = name.dropFirst("metadata-".count).split(separator: "-", maxSplits: 2).map(String.init)
            guard parts.count >= 2, let date = f.date(from: parts[0] + "-" + parts[1]) else { continue }
            var reason = parts.count > 2 ? parts[2] : ""
            // A counter added to keep names unique ("…-daily-2") is not part of the reason.
            if let dash = reason.lastIndex(of: "-"), Int(reason[reason.index(after: dash)...]) != nil {
                reason = String(reason[..<dash])
            }
            let bytes = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            out.append(BackupInfo(url: u, createdAt: date, reason: reason, bytes: bytes))
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    static func load(_ url: URL) throws -> MetadataSnapshot {
        try Coders.decoder().decode(MetadataSnapshot.self, from: Data(contentsOf: url))
    }

    static func latest(_ base: URL, reason: String? = nil) -> BackupInfo? {
        list(base).first { reason == nil || $0.reason == reason }
    }

    /// Keeps the newest `keepDaily` daily backups and the newest `keepOther` of the others.
    static func prune(_ base: URL) {
        let all = list(base)
        let daily = all.filter { $0.reason == Reason.daily }
        let other = all.filter { $0.reason != Reason.daily }
        for b in daily.dropFirst(keepDaily) + other.dropFirst(keepOther) {
            try? FileManager.default.removeItem(at: b.url)
        }
    }
}

// MARK: - Library lock

struct LibraryLockInfo: Codable, Equatable {
    var token: String
    var host: String
    var user: String
    var pid: Int32
    var app: String
    var updated: Date
}

enum LibraryLock {
    static let fileName = ".rodentlimb-lock.json"
    /// A lock not refreshed for this long belongs to an app that quit unexpectedly (or a Mac that sleeps).
    static let staleAfter: TimeInterval = 180

    static func url(_ base: URL) -> URL { base.appendingPathComponent(fileName) }

    static func read(_ base: URL) -> LibraryLockInfo? {
        guard let d = try? Data(contentsOf: url(base)) else { return nil }
        return try? Coders.decoder().decode(LibraryLockInfo.self, from: d)
    }

    /// The live lock of another app instance (another Mac, or a second copy on this Mac), if any.
    static func otherHolder(_ base: URL, token: String, now: Date = Date()) -> LibraryLockInfo? {
        guard let l = read(base), l.token != token, now.timeIntervalSince(l.updated) < staleAfter else { return nil }
        return l
    }

    static func write(_ base: URL, token: String, host: String, app: String, now: Date = Date()) {
        let info = LibraryLockInfo(token: token, host: host, user: NSUserName(),
                                   pid: ProcessInfo.processInfo.processIdentifier, app: app, updated: now)
        let enc = Coders.encoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(info) { try? d.write(to: url(base), options: .atomic) }
    }

    /// Removes the lock if it is ours (never another Mac's).
    static func release(_ base: URL, token: String) {
        guard let l = read(base), l.token == token else { return }
        try? FileManager.default.removeItem(at: url(base))
    }
}
