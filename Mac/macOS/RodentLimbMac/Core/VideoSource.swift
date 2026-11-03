// VideoSource.swift — where the video of a recording lives on the Mac.
//
// On the iPhone every video is copied into the app. Lab videos on a Mac are large and often sit
// on an external drive or a server, so by default the Mac app *references* them in place: the
// recording keeps a security-scoped bookmark (the App Sandbox's way of remembering a file the
// user chose), the last known path and a fingerprint (size, modification date, first and last
// MiB). Videos can also be copied into the library ("Copy videos into the library").
//
// The sidecar file Recordings/<id>/source.json holds this; the shared Recording struct (and the
// iPhone app, which ignores the file) stays unchanged.

import Foundation

struct VideoSource: Codable, Equatable {
    enum Mode: String, Codable {
        /// The file stays where it is (bookmark).
        case referenced
        /// The file was copied into the recording folder (Recording.videoFile).
        case copied
    }

    var mode: Mode
    var bookmark: Data?
    /// Last known absolute path (shown to the user, used to search for a moved file).
    var path: String
    var fileName: String
    var size: Int64
    var modified: Double
    var fingerprint: String
    /// Mac-only processing bookkeeping (kept here so the shared Recording is not changed).
    var attempts: Int = 0
    /// Times the app stopped unexpectedly while this video was being processed.
    var crashes: Int = 0
    /// Position in the processing queue (lower first); nil = import order.
    var queueRank: Double?
    /// Pose model that tracks / tracked this video; nil = CylinderMousePoseV2 (the default and the
    /// only model of libraries from the iPhone and from 1.3.0).
    var poseModel: PoseModelID?

    init(mode: Mode, bookmark: Data?, path: String, fileName: String, size: Int64, modified: Double, fingerprint: String) {
        self.mode = mode
        self.bookmark = bookmark
        self.path = path
        self.fileName = fileName
        self.size = size
        self.modified = modified
        self.fingerprint = fingerprint
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

    static func load(folder: URL) -> VideoSource? {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(VideoSource.self, from: d)
    }

    func save(folder: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// Size, modification date and a fast fingerprint (FNV-1a over the first and last MiB). Detects a
/// different or modified file before a checkpoint is continued; not a whole-file hash.
enum VideoFingerprint {
    struct Info: Equatable {
        var size: Int64
        var modified: Double
        var fingerprint: String
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

/// Holds access to a video for as long as it is needed (security scope is released on deinit).
/// Create one per use (a review player, a processing run); never share one across threads that
/// outlive it.
final class VideoAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool

    init(url: URL, scoped: Bool) {
        self.url = url
        self.scoped = scoped
    }

    deinit {
        #if canImport(Darwin)
        if scoped { url.stopAccessingSecurityScopedResource() }
        #endif
    }
}

enum VideoBookmarks {
    /// Bookmark for a file the user chose (open panel or drag and drop).
    static func make(_ url: URL) -> Data? {
        #if os(macOS)
        return try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                     includingResourceValuesForKeys: [.fileSizeKey, .contentModificationDateKey, .volumeNameKey],
                                     relativeTo: nil)
        #else
        return nil
        #endif
    }

    /// Resolves a bookmark. Returns the URL and a refreshed bookmark when the old one was stale.
    static func resolve(_ data: Data) -> (url: URL, refreshed: Data?)? {
        #if os(macOS)
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        var refreshed: Data?
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            refreshed = make(url)
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        return (url, refreshed)
        #else
        return nil
        #endif
    }

    /// Starts access to a resolved bookmark URL.
    static func access(_ url: URL, scoped: Bool) -> VideoAccess {
        #if os(macOS)
        let ok = scoped ? url.startAccessingSecurityScopedResource() : false
        return VideoAccess(url: url, scoped: ok)
        #else
        return VideoAccess(url: url, scoped: false)
        #endif
    }
}

enum VideoFiles {
    /// File types AVFoundation can usually read. Others (AVI, MKV, FLV …) are listed with advice to
    /// convert them to MP4 (H.264 / HEVC).
    static let readable: Set<String> = ["mp4", "mov", "m4v", "3gp", "3g2", "mts", "m2ts", "ts"]
    static let known: Set<String> = readable.union(["avi", "mkv", "wmv", "flv", "webm", "mpg", "mpeg", "ogv", "h264", "hevc"])

    static func isVideo(_ url: URL) -> Bool { known.contains(url.pathExtension.lowercased()) }
    static func isReadable(_ url: URL) -> Bool { readable.contains(url.pathExtension.lowercased()) }

    /// Video files in the given files and folders (folders searched recursively, hidden files and
    /// packages skipped), sorted by path. At most `limit` files.
    static func collect(_ urls: [URL], limit: Int = 5000) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey],
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let f as URL in e where isVideo(f) {
                    if seen.insert(f.standardizedFileURL.path).inserted { out.append(f) }
                    if out.count >= limit { break }
                }
            } else if isVideo(u), seen.insert(u.standardizedFileURL.path).inserted {
                out.append(u)
            }
            if out.count >= limit { break }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
