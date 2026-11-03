// ActivityLog.swift — a plain-text log of what the batch did (imports, runs, failures, recoveries),
// one file per day in the library's Logs folder. Written off the main thread, in order. Useful when a
// long unattended batch is checked the next morning, and for bug reports.

import Foundation

final class ActivityLog: @unchecked Sendable {
    private let folder: URL
    private let queue = DispatchQueue(label: "RodentLimb.ActivityLog", qos: .utility)
    private let stamp: DateFormatter
    private let day: DateFormatter

    init(folder: URL) {
        self.folder = folder
        stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ message: String) {
        let now = Date()
        queue.async { [folder, stamp, day] in
            let url = folder.appendingPathComponent("activity-\(day.string(from: now)).log")
            let line = "\(stamp.string(from: now))  \(message)\n"
            let data = Data(line.utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Blocks until queued lines are written (on quit).
    func drain() { queue.sync {} }

    var currentFile: URL {
        folder.appendingPathComponent("activity-\(day.string(from: Date())).log")
    }
}
