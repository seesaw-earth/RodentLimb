// TempFiles.swift — the app's temporary copies of picked videos: removed as soon as they are added
// or discarded, and anything left by an interrupted session is cleared at launch.
//
// Layouts in the temporary folder: "<UUID>-<file name>" (copies from Files) and "<UUID>/<file name>"
// (videos from Photos or dropped, PickedVideo). Exports ("RodentLimbExport-…") older than a day are
// cleared too. Foundation only; file work runs off the main thread.

import Foundation

enum TempFiles {
    /// Removes a temporary copy (and its own folder for the "<UUID>/<name>" layout).
    static func remove(_ url: URL) {
        DispatchQueue.global(qos: .utility).async { removeNow(url) }
    }

    static func removeNow(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        if isOwnFolder(parent) { try? fm.removeItem(at: parent) }
    }

    /// A "<UUID>" folder directly inside the temporary folder.
    static func isOwnFolder(_ dir: URL) -> Bool {
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return dir.deletingLastPathComponent().standardizedFileURL.path == tmp && UUID(uuidString: dir.lastPathComponent) != nil
    }

    /// Clears temporary copies left behind by an earlier run (called at launch, before any import).
    static func clearStale(now: Date = Date()) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        for u in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let name = u.lastPathComponent
            let prefix = String(name.prefix(36))
            let ownCopy = UUID(uuidString: prefix) != nil && (name.count == 36 || name.dropFirst(36).hasPrefix("-"))
            var oldExport = false
            if name.hasPrefix("RodentLimbExport-"),
               let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                oldExport = now.timeIntervalSince(d) > 86_400
            }
            if ownCopy || oldExport { try? fm.removeItem(at: u) }
        }
    }
}
