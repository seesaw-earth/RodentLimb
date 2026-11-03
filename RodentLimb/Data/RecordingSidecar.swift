// RecordingSidecar.swift — per-video processing facts the shared Recording does not hold:
// which pose model tracks / tracked the video, and the file's fingerprint (duplicate detection).
//
// Stored as Recordings/<id>/source.json, the same file and format as the Mac app's VideoSource, so a
// library copied between the iPhone and the Mac keeps the model of every video. On the iPhone the video
// is always inside the recording folder (mode "copied"). Fields only the Mac uses (bookmark, queue
// rank, attempts, crashes) are read and written back unchanged.
//
// A video without this file (iPhone 1.0–1.3) was tracked with CylinderMousePoseV2; tracking it again
// uses PoseModelID.runnable (CylinderPose7 FP16, the same network).
//
// Foundation only.

import Foundation

struct RecordingSidecar: Codable, Equatable {
    enum Mode: String, Codable {
        case referenced
        case copied
    }

    var mode: Mode = .copied
    var bookmark: Data?
    var path: String = ""
    var fileName: String = ""
    var size: Int64 = 0
    var modified: Double = 0
    var fingerprint: String = ""
    var attempts: Int = 0
    var crashes: Int = 0
    var queueRank: Double?
    /// Pose model that tracks / tracked this video; nil = CylinderMousePoseV2.
    var poseModel: PoseModelID?

    init(fileName: String, poseModel: PoseModelID?) {
        self.fileName = fileName
        self.poseModel = poseModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .copied
        bookmark = try? c.decodeIfPresent(Data.self, forKey: .bookmark)
        path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
        fileName = (try? c.decodeIfPresent(String.self, forKey: .fileName)) ?? ""
        size = (try? c.decodeIfPresent(Int64.self, forKey: .size)) ?? 0
        modified = (try? c.decodeIfPresent(Double.self, forKey: .modified)) ?? 0
        fingerprint = (try? c.decodeIfPresent(String.self, forKey: .fingerprint)) ?? ""
        attempts = (try? c.decodeIfPresent(Int.self, forKey: .attempts)) ?? 0
        crashes = (try? c.decodeIfPresent(Int.self, forKey: .crashes)) ?? 0
        queueRank = try? c.decodeIfPresent(Double.self, forKey: .queueRank)
        poseModel = (try? c.decodeIfPresent(PoseModelID.self, forKey: .poseModel)) ?? nil
    }

    static let fileName = "source.json"

    /// "size|fingerprint", or nil when the fingerprint is unknown.
    var duplicateKey: String? { fingerprint.isEmpty ? nil : "\(size)|\(fingerprint)" }

    static func load(folder: URL) -> RecordingSidecar? {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(RecordingSidecar.self, from: d)
    }

    func save(folder: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// Size, modification date and a fast fingerprint (FNV-1a over the first and last MiB) — the same
/// algorithm as the Mac app, so duplicates are recognised across both. Not a whole-file hash.
enum VideoFingerprint {
    struct Info: Equatable {
        var size: Int64
        var modified: Double
        var fingerprint: String

        var duplicateKey: String { "\(size)|\(fingerprint)" }
    }

    static func make(_ url: URL) throws -> Info {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = Int64((attrs[.size] as? NSNumber)?.int64Value ?? 0)
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var h = FNV1a()
        h.add(Data("\(size)".utf8))
        let n = Int(min(size, 1_048_576))
        h.add(try file.read(upToCount: n) ?? Data())
        if size > Int64(n) {
            try file.seek(toOffset: UInt64(size - Int64(n)))
            h.add(try file.read(upToCount: n) ?? Data())
        }
        return Info(size: size, modified: modified, fingerprint: h.hex)
    }

    struct FNV1a {
        private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func add(_ d: Data) {
            for b in d {
                value ^= UInt64(b)
                value = value &* 0x0000_0100_0000_01B3
            }
        }
        var hex: String { String(format: "%016llx", value) }
    }
}
