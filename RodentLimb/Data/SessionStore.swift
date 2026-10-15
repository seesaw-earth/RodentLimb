// SessionStore.swift — sessions on disk (Documents/RodentLimb/Sessions/<id>/) and analysis.
//
// Each session folder holds: session.json, the copied video, pose.plist (inference result),
// result.json (latest analysis) and optionally skeleton.mp4. The folder is visible in the
// Files app.

import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var results: [UUID: AnalysisResult] = [:]

    private var poseCache: [UUID: PoseTrack] = [:]
    private var poseOrder: [UUID] = []
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    let root: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("RodentLimb/Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    // MARK: Paths

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func videoURL(_ s: Session) -> URL { folder(s.id).appendingPathComponent(s.videoFile) }
    func poseURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("pose.plist") }
    func resultURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("result.json") }
    func skeletonURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("skeleton.mp4") }

    func session(_ id: UUID) -> Session? { sessions.first { $0.id == id } }

    // MARK: Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var list: [Session] = []
        for d in dirs {
            guard let data = try? Data(contentsOf: d.appendingPathComponent("session.json")),
                  var s = try? decoder.decode(Session.self, from: data) else { continue }
            // A session that was mid-inference when the app quit goes back to the queue.
            if s.status == .processing { s.status = .queued }
            list.append(s)
        }
        sessions = list.sorted { $0.createdAt > $1.createdAt }
    }

    /// Updates memory immediately (the UI reacts at once) and writes to disk shortly after, off
    /// the main thread, coalescing bursts such as slider drags or label edits.
    func save(_ s: Session) {
        var s = s
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            var old = sessions[i]
            old.updatedAt = s.updatedAt
            if old == s { return }          // nothing changed: no redraw, no write
            s.updatedAt = Date()
            sessions[i] = s
        } else {
            s.updatedAt = Date()
            sessions.insert(s, at: 0)
            sessions.sort { $0.createdAt > $1.createdAt }
        }
        dirty.insert(s.id)
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private var dirty = Set<UUID>()
    private var flushTask: Task<Void, Never>?

    /// Writes pending sessions now (also called when the app goes to the background).
    func flush() {
        let items = dirty.compactMap { id in session(id).map { ($0, folder(id)) } }
        dirty.removeAll()
        guard !items.isEmpty else { return }
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            for (session, dir) in items {
                // Never recreate the folder of a session deleted in the meantime.
                guard FileManager.default.fileExists(atPath: dir.path), let data = try? encoder.encode(session) else { continue }
                try? data.write(to: dir.appendingPathComponent("session.json"), options: .atomic)
            }
        }
    }

    func update(_ id: UUID, _ change: (inout Session) -> Void) {
        guard var s = session(id) else { return }
        change(&s)
        save(s)
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids {
            dirty.remove(id)
            analysisTasks[id]?.cancel()
            try? FileManager.default.removeItem(at: folder(id))
            results[id] = nil
            poseCache[id] = nil
        }
        sessions.removeAll { ids.contains($0.id) }
    }

    // MARK: Import

    /// Copies a picked video into a new session folder.
    func importVideo(from url: URL, assay: Assay, subject: String, group: String, notes: String) throws -> Session {
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        var s = Session(assay: assay, subject: subject, group: group, notes: notes,
                        videoFile: "video." + ext, originalName: url.lastPathComponent)
        // Start from the parameters and calibration used last time for this assay (fixed rigs).
        if let prev = sessions.first(where: { $0.assay == assay }) {
            s.params = prev.params
            s.params.cylinder.lesion = prev.params.cylinder.lesion
            if prev.calibration.circle != nil || prev.calibration.floorY != nil || prev.calibration.scale != nil {
                s.calibration = prev.calibration
                s.calibration.copiedFrom = prev.displayName
            }
        }
        try FileManager.default.createDirectory(at: folder(s.id), withIntermediateDirectories: true)
        let dest = videoURL(s)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: url, to: dest)
        save(s)
        return s
    }

    var knownGroups: [String] {
        var seen = Set<String>(), out: [String] = []
        for s in sessions where !s.group.isEmpty && !seen.contains(s.group) {
            seen.insert(s.group); out.append(s.group)
        }
        return out
    }

    // MARK: Pose

    func storePose(_ track: PoseTrack, for id: UUID) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(track).write(to: poseURL(id), options: .atomic)
        cachePose(track, id)
    }

    private func cachePose(_ t: PoseTrack, _ id: UUID) {
        poseCache[id] = t
        poseOrder.removeAll { $0 == id }
        poseOrder.append(id)
        while poseOrder.count > 3 { poseCache[poseOrder.removeFirst()] = nil }
    }

    func pose(_ id: UUID) async -> PoseTrack? {
        if let t = poseCache[id] { return t }
        let url = poseURL(id)
        let loaded: PoseTrack? = await Task.detached(priority: .userInitiated) { () -> PoseTrack? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? PropertyListDecoder().decode(PoseTrack.self, from: data)
        }.value
        guard var t = loaded else { return nil }
        if t.timeOffset == nil, let s = session(id) {
            t.timeOffset = await PoseVideoProcessor.firstFrameTime(url: videoURL(s)) ?? 0
            try? storePose(t, for: id)
        }
        cachePose(t, id)
        return t
    }

    // MARK: Results

    /// Returns the cached result, loading it from disk into the cache if needed. Call from
    /// actions or tasks, not while a view is computing its body (use `results[id]` there).
    @discardableResult
    func loadResult(_ id: UUID) -> AnalysisResult? {
        if let r = results[id] { return r }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: resultURL(id)),
              let r = try? decoder.decode(AnalysisResult.self, from: data) else { return nil }
        results[id] = r
        return r
    }

    /// Re-runs the analysis for a session (pose must exist). Debounce-safe: a newer request
    /// cancels the older one.
    func analyze(_ id: UUID, debounce: Double = 0) {
        analysisTasks[id]?.cancel()
        analysisTasks[id] = Task { [weak self] in
            if debounce > 0 { try? await Task.sleep(nanoseconds: UInt64(debounce * 1e9)) }
            guard !Task.isCancelled, let self, let s = self.session(id), s.hasPose,
                  let track = await self.pose(id) else { return }
            let result = await Task.detached(priority: .userInitiated) { Analyzer.run(session: s, track: track) }.value
            guard !Task.isCancelled, var current = self.session(id) else { return }
            self.results[id] = result
            self.writeResult(result, id)
            current.summary = Array(result.metrics.filter { $0.highlight }.prefix(3))
            current.worstNote = result.notes.map(\.level).max { self.rank($0) < self.rank($1) }
            current.status = current.isCalibrated ? .done : .needsSetup
            self.save(current)
        }
    }

    private func rank(_ l: NoteLevel) -> Int { l == .error ? 2 : l == .warning ? 1 : 0 }

    private func writeResult(_ r: AnalysisResult, _ id: UUID) {
        let url = resultURL(id), dir = folder(id)
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard FileManager.default.fileExists(atPath: dir.path), let data = try? encoder.encode(r) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Loads results for many sessions (for group export / comparison).
    func loadResults(_ ids: [UUID]) -> [UUID: AnalysisResult] {
        var out: [UUID: AnalysisResult] = [:]
        for id in ids { if let r = loadResult(id) { out[id] = r } }
        return out
    }

    // MARK: Storage

    func storageBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
