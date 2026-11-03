// PoseCheckpoint.swift — pose keypoints written to disk while the model runs, so a batch can be
// paused, the Mac can sleep, the app can be quit — or crash — and the video continues from the
// last saved frame instead of starting again.
//
// A recording's checkpoint folder (Recordings/<id>/checkpoint/) holds
//   checkpoint.json              the manifest: video fingerprint, model, threshold, frame size,
//                                fps, the closed segments
//   segment_000000.csv …         closed segments, `segmentRows` analysed frames each
//   segment_00000N.csv.partial   the segment being written. Rows are appended and flushed at least
//                                every ~2 s, so a crash or power cut loses only the last seconds;
//                                a half-written last line is dropped when the run continues.
//
// Each row: frame, pts (the frame's presentation time in the video timeline), box confidence and
// x, y, confidence of the 7 keypoints (display frame, pixels; a missing keypoint is −1, −1, 0).
// Numbers are written with the shortest text that reads back as the same Float / Double, so the
// pose track rebuilt from the rows is bit-identical to the one the run computed.
//
// When the video is finished the store writes pose.bin (the iPhone app's format) and removes the
// checkpoint folder.
//
// Foundation only (compiled and tested on Linux: tools/run_core_tests.sh).

import Foundation

struct PoseCheckpointManifest: Codable, Equatable {
    static let fileName = "checkpoint.json"
    static let currentFormat = 1

    struct Segment: Codable, Equatable {
        var index: Int
        var file: String
        var rows: Int
        var firstPTS: Double
        var lastPTS: Double
    }

    var format = PoseCheckpointManifest.currentFormat
    /// Identity of the video file (a different or edited file must not be continued).
    var videoSize: Int64
    var videoModified: Double
    var videoFingerprint: String
    /// Model and the setting that changes its output.
    var modelName: String
    var modelVersion: String
    var boxThreshold: Double
    /// Displayed (orientation-corrected) frame size and nominal frame rate.
    var width: Int
    var height: Int
    var fps: Double
    var duration: Double
    /// Presentation time of the first decoded frame (the pose track's time zero).
    var firstPTS: Double?
    var segments: [Segment] = []
    var startedAt = Date()
    var updatedAt = Date()

    var closedRows: Int { segments.reduce(0) { $0 + $1.rows } }

    static func segmentName(_ index: Int) -> String { String(format: "segment_%06d.csv", index) }
    static func partialName(_ index: Int) -> String { segmentName(index) + ".partial" }

    /// The same video, model and model setting — the only case in which rows can be continued.
    func continues(_ o: PoseCheckpointManifest) -> Bool {
        format == o.format && videoSize == o.videoSize && abs(videoModified - o.videoModified) < 0.001
            && videoFingerprint == o.videoFingerprint && modelName == o.modelName && modelVersion == o.modelVersion
            && abs(boxThreshold - o.boxThreshold) < 1e-9 && width == o.width && height == o.height
    }

    static func load(_ folder: URL) throws -> PoseCheckpointManifest {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(PoseCheckpointManifest.self, from: Data(contentsOf: folder.appendingPathComponent(fileName)))
    }

    func save(to folder: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        try e.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// One analysed frame.
struct PoseRow: Equatable {
    var frame: Int
    var pts: Double
    var box: Float
    /// Kp order; −1 / −1 / 0 when missing.
    var x: [Float]
    var y: [Float]
    var c: [Float]

    static let keypoints = Kp.allCases.count
    static let columns = 3 + 3 * keypoints

    static func missing(frame: Int, pts: Double) -> PoseRow {
        PoseRow(frame: frame, pts: pts, box: 0,
                x: Array(repeating: -1, count: keypoints), y: Array(repeating: -1, count: keypoints),
                c: Array(repeating: 0, count: keypoints))
    }

    static var header: String {
        var cols = ["frame", "pts_s", "box_confidence"]
        for k in Kp.allCases { cols += [k.exportName + "_x", k.exportName + "_y", k.exportName + "_confidence"] }
        return cols.joined(separator: ",") + "\n"
    }

    @inline(__always) private static func text(_ v: Float) -> String { v.isFinite ? "\(v)" : "0.0" }

    var line: String {
        var s = String(frame) + "," + (pts.isFinite ? "\(pts)" : "0.0") + "," + Self.text(box)
        for k in 0..<Self.keypoints {
            let xv = k < x.count ? x[k] : -1, yv = k < y.count ? y[k] : -1, cv = k < c.count ? c[k] : 0
            s += "," + Self.text(xv) + "," + Self.text(yv) + "," + Self.text(cv)
        }
        return s + "\n"
    }

    static func parse(_ line: Substring) -> PoseRow? {
        let f = line.split(separator: ",", omittingEmptySubsequences: false)
        guard f.count == columns, let frame = Int(f[0]), let pts = Double(f[1]), let box = Float(f[2]) else { return nil }
        var x = [Float](), y = [Float](), c = [Float]()
        x.reserveCapacity(keypoints); y.reserveCapacity(keypoints); c.reserveCapacity(keypoints)
        for k in 0..<keypoints {
            guard let xv = Float(f[3 + 3 * k]), let yv = Float(f[4 + 3 * k]), let cv = Float(f[5 + 3 * k]) else { return nil }
            x.append(xv); y.append(yv); c.append(cv)
        }
        return PoseRow(frame: frame, pts: pts, box: box, x: x, y: y, c: c)
    }
}

enum PoseCheckpointError: LocalizedError {
    case badHeader(String)
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .badHeader(let f): return L("Unexpected columns in the checkpoint file ", "检查点文件列不正确：") + f
        case .cannotWrite(let f): return L("Cannot write the checkpoint file ", "无法写入检查点文件：") + f
        }
    }
}

enum PoseCheckpoint {
    /// Frames per segment file (≈ 1 min of 30-fps video). A closed segment is never rewritten.
    static let segmentRows = 1800

    /// Complete rows of a segment file (a half-written last line is ignored) and the byte length of
    /// those complete lines, header included.
    static func readRows(_ url: URL) throws -> (rows: [PoseRow], validBytes: Int) {
        let data = try Data(contentsOf: url)
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], 0) }
        let valid = data.prefix(through: lastNewline)
        let text = String(decoding: valid, as: UTF8.self)
        var rows: [PoseRow] = []
        var first = true
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if first {
                first = false
                guard line + "\n" == PoseRow.header else { throw PoseCheckpointError.badHeader(url.lastPathComponent) }
                continue
            }
            // A damaged line in the middle (disk error) is skipped rather than ending the run.
            if let r = PoseRow.parse(line) { rows.append(r) }
        }
        return (rows, valid.count)
    }

    /// What a run continues from.
    struct Resume {
        var manifest: PoseCheckpointManifest
        /// Every complete row saved so far, in order.
        var rows: [PoseRow] = []
        var partialIndex: Int?
        var partialRows = 0
        var partialFirstPTS: Double?
        var partialValidBytes = 0

        var lastPTS: Double? { rows.last?.pts }
        var isFresh: Bool { rows.isEmpty }
    }

    /// Opens (or starts) the checkpoint in `folder` for the run described by `fresh`. A checkpoint of
    /// another video file, model or threshold is discarded. Never throws for a damaged checkpoint:
    /// the run then starts from the beginning.
    static func prepare(folder: URL, fresh: PoseCheckpointManifest) throws -> Resume {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent(PoseCheckpointManifest.fileName).path),
           let saved = try? PoseCheckpointManifest.load(folder), saved.continues(fresh),
           let resume = try? load(folder: folder, manifest: saved) {
            return resume
        }
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fresh.save(to: folder)
        return Resume(manifest: fresh)
    }

    /// Reads a checkpoint without changing it (also used to finish a video with the frames done).
    static func load(folder: URL, manifest m: PoseCheckpointManifest) throws -> Resume {
        var out = Resume(manifest: m)
        var last = -Double.infinity
        for seg in m.segments.sorted(by: { $0.index < $1.index }) {
            for r in try readRows(folder.appendingPathComponent(seg.file)).rows where r.pts > last {
                out.rows.append(r)
                last = r.pts
            }
        }
        let closed = Set(m.segments.map(\.index))
        let maxClosed = m.segments.map(\.index).max() ?? -1
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let partials = names.compactMap { name -> Int? in
            guard name.hasPrefix("segment_"), name.hasSuffix(".csv.partial") else { return nil }
            return Int(name.dropFirst("segment_".count).prefix(6))
        }.filter { !closed.contains($0) && $0 > maxClosed }.sorted()
        if let index = partials.last {
            let r = try readRows(folder.appendingPathComponent(PoseCheckpointManifest.partialName(index)))
            let fresh = r.rows.filter { $0.pts > last }
            out.partialIndex = index
            out.partialRows = r.rows.count
            out.partialFirstPTS = r.rows.first?.pts
            out.partialValidBytes = r.validBytes
            out.rows += fresh
        }
        return out
    }

    /// Rebuilds the pose track from saved rows (times start at the first frame).
    static func track(rows: [PoseRow], manifest m: PoseCheckpointManifest) -> PoseTrack {
        var t = PoseTrack(width: m.width, height: m.height, fps: m.fps > 0 ? m.fps : 30, duration: m.duration,
                          modelName: m.modelName, modelVersion: m.modelVersion)
        t.reserve(rows.count)
        let start = m.firstPTS ?? rows.first?.pts ?? 0
        for r in rows {
            t.times.append(max(0, r.pts - start))
            t.boxConfidence.append(r.box)
            for k in 0..<PoseRow.keypoints {
                t.x[k].append(k < r.x.count ? r.x[k] : -1)
                t.y[k].append(k < r.y.count ? r.y[k] : -1)
                t.c[k].append(k < r.c.count ? r.c[k] : 0)
            }
        }
        t.timeOffset = start.isFinite ? start : 0
        if let last = t.times.last { t.duration = max(t.duration.finiteOr(0), last) }
        t.sanitize()
        return t
    }

    /// Number of saved frames, read quickly from the manifest and the partial segment (for lists).
    static func savedFrames(folder: URL) -> Int {
        guard let m = try? PoseCheckpointManifest.load(folder) else { return 0 }
        var n = m.closedRows
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        if let partial = names.filter({ $0.hasSuffix(".csv.partial") }).sorted().last,
           let data = try? Data(contentsOf: folder.appendingPathComponent(partial)) {
            n += max(0, data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 } - 1)
        }
        return n
    }
}

/// Appends rows to the checkpoint while a run is in progress. Not thread-safe: owned by one run.
final class PoseCheckpointWriter {
    static let flushSeconds: Double = 2
    static let flushBytes = 64 * 1024

    let folder: URL
    private(set) var manifest: PoseCheckpointManifest
    private var handle: FileHandle?
    private var segIndex: Int?
    private var segRows = 0
    private var segFirst: Double?
    private var segLast: Double?
    private var buffer = Data()
    private var lastFlush = Date()

    init(folder: URL, resume: PoseCheckpoint.Resume) throws {
        self.folder = folder
        manifest = resume.manifest
        buffer.reserveCapacity(Self.flushBytes + 4096)
        // The interrupted segment continues after its last complete row.
        if let index = resume.partialIndex {
            let url = folder.appendingPathComponent(PoseCheckpointManifest.partialName(index))
            let h = try FileHandle(forWritingTo: url)
            if resume.partialValidBytes == 0 {
                try h.truncate(atOffset: 0)
                try h.write(contentsOf: Data(PoseRow.header.utf8))
            } else {
                try h.truncate(atOffset: UInt64(resume.partialValidBytes))
            }
            try h.seekToEnd()
            handle = h
            segIndex = index
            segRows = resume.partialRows
            segFirst = resume.partialFirstPTS
            segLast = resume.partialRows > 0 ? resume.lastPTS : nil
        }
    }

    deinit { try? handle?.close() }

    /// Records the presentation time of the first decoded frame (once).
    func setFirstPTS(_ t: Double) throws {
        guard manifest.firstPTS == nil else { return }
        manifest.firstPTS = t
        manifest.updatedAt = Date()
        try manifest.save(to: folder)
    }

    func append(_ row: PoseRow) throws {
        if segIndex == nil || segRows >= PoseCheckpoint.segmentRows {
            try closeSegment()
            try openSegment((manifest.segments.map(\.index).max() ?? -1) + 1)
        }
        buffer.append(contentsOf: row.line.utf8)
        segRows += 1
        if segFirst == nil { segFirst = row.pts }
        segLast = row.pts
        if buffer.count >= Self.flushBytes || Date().timeIntervalSince(lastFlush) >= Self.flushSeconds {
            try flush()
        }
    }

    func flush(sync: Bool = false) throws {
        guard let h = handle else { return }
        if !buffer.isEmpty {
            try h.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
        if sync { try h.synchronize() }
        lastFlush = Date()
    }

    /// Flushes and closes the open file, keeping the partial segment for a later continuation.
    func suspend() {
        try? flush(sync: true)
        try? handle?.close()
        handle = nil
    }

    private func openSegment(_ index: Int) throws {
        let url = folder.appendingPathComponent(PoseCheckpointManifest.partialName(index))
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        guard fm.createFile(atPath: url.path, contents: Data(PoseRow.header.utf8)) else {
            throw PoseCheckpointError.cannotWrite(url.lastPathComponent)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        handle = h
        segIndex = index
        segRows = 0
        segFirst = nil
        segLast = nil
    }

    /// Closes the open segment (renamed from .partial and recorded in the manifest).
    func closeSegment() throws {
        guard let index = segIndex, let h = handle else { return }
        try flush(sync: true)
        try h.close()
        handle = nil
        segIndex = nil
        let fm = FileManager.default
        let partial = folder.appendingPathComponent(PoseCheckpointManifest.partialName(index))
        guard segRows > 0, let first = segFirst, let last = segLast else {
            try? fm.removeItem(at: partial)
            return
        }
        let name = PoseCheckpointManifest.segmentName(index)
        let final = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
        try fm.moveItem(at: partial, to: final)
        manifest.segments.removeAll { $0.index == index }
        manifest.segments.append(.init(index: index, file: name, rows: segRows, firstPTS: first, lastPTS: last))
        manifest.segments.sort { $0.index < $1.index }
        manifest.updatedAt = Date()
        try manifest.save(to: folder)
    }
}
