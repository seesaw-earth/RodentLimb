// PoseStorage.swift — compact on-disk format for the pose track (pose.bin).
//
// Up to 1.2 the track was stored as a binary property list through PropertyListEncoder. Every
// value then becomes its own NSNumber object (≈ 1.2 million objects for a 30-min, 30-fps video),
// so saving and loading took seconds, briefly needed hundreds of MB and — for saving — ran on the
// main thread at the end of each video, which froze the app and could get it terminated.
//
// pose.bin is a small JSON header followed by the raw arrays:
//   "RLPS" · UInt32 version · UInt32 header length · header JSON ·
//   times (Float64 × n) · boxConfidence (Float32 × n) · for each keypoint: x, y, c (Float32 × n)
// All numbers little-endian (every Apple platform). Reading and writing are plain memory copies.
// Old pose.plist files are still read and converted to pose.bin once; the old file is removed the
// next time the pose is saved (e.g. when tracking is re-run).

import Foundation

enum PoseStorage {
    static let fileName = "pose.bin"
    static let legacyFileName = "pose.plist"

    private static let magic: [UInt8] = Array("RLPS".utf8)
    private static let version: UInt32 = 1

    private struct Header: Codable {
        var width: Int
        var height: Int
        var fps: Double
        var duration: Double
        var modelName: String
        var modelVersion: String
        var timeOffset: Double?
        var frames: Int
        var keypoints: Int
    }

    enum StorageError: LocalizedError {
        case malformed(String)
        var errorDescription: String? {
            switch self {
            case .malformed(let d): return "Pose file is damaged (\(d))."
            }
        }
    }

    // MARK: Files

    /// Reads the pose of a session folder: pose.bin, else the legacy pose.plist (which is then
    /// converted to pose.bin once). Call off the main thread.
    static func load(folder: URL) -> PoseTrack? {
        let bin = folder.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: bin, options: .mappedIfSafe), var t = try? decode(data) {
            t.sanitize()
            return t
        }
        let legacy = folder.appendingPathComponent(legacyFileName)
        guard let data = try? Data(contentsOf: legacy),
              var t = try? PropertyListDecoder().decode(PoseTrack.self, from: data) else { return nil }
        t.sanitize()
        if let out = try? encode(t) { try? out.write(to: bin, options: .atomic) }
        return t
    }

    /// Writes pose.bin (and removes an outdated pose.plist). Call off the main thread.
    static func save(_ track: PoseTrack, folder: URL) throws {
        let data = try encode(track)
        try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(legacyFileName))
    }

    static func exists(folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent(fileName).path)
            || fm.fileExists(atPath: folder.appendingPathComponent(legacyFileName).path)
    }

    // MARK: Encoding

    static func encode(_ track: PoseTrack) throws -> Data {
        var t = track
        t.sanitize()
        let n = t.frameCount, k = t.x.count
        let header = Header(width: t.width, height: t.height, fps: t.fps, duration: t.duration,
                            modelName: t.modelName, modelVersion: t.modelVersion, timeOffset: t.timeOffset,
                            frames: n, keypoints: k)
        let headerData = try JSONEncoder().encode(header)
        var data = Data()
        data.reserveCapacity(12 + headerData.count + n * (8 + 4 + k * 12))
        data.append(contentsOf: magic)
        appendUInt32(&data, version)
        appendUInt32(&data, UInt32(headerData.count))
        data.append(headerData)
        appendDoubles(&data, t.times)
        appendFloats(&data, t.boxConfidence)
        for i in 0..<k {
            appendFloats(&data, t.x[i])
            appendFloats(&data, t.y[i])
            appendFloats(&data, t.c[i])
        }
        return data
    }

    private static func appendUInt32(_ data: inout Data, _ v: UInt32) {
        let le = v.littleEndian
        data.append(UInt8(truncatingIfNeeded: le))
        data.append(UInt8(truncatingIfNeeded: le >> 8))
        data.append(UInt8(truncatingIfNeeded: le >> 16))
        data.append(UInt8(truncatingIfNeeded: le >> 24))
    }

    private static func appendDoubles(_ data: inout Data, _ a: [Double]) {
        a.withUnsafeBufferPointer { data.append($0) }
    }

    private static func appendFloats(_ data: inout Data, _ a: [Float]) {
        a.withUnsafeBufferPointer { data.append($0) }
    }

    // MARK: Decoding

    static func decode(_ data: Data) throws -> PoseTrack {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> PoseTrack in
            var offset = 0
            func take(_ count: Int) throws -> UnsafeRawBufferPointer {
                guard count >= 0, count <= raw.count - offset else { throw StorageError.malformed("truncated") }
                let slice = UnsafeRawBufferPointer(rebasing: raw[offset ..< offset + count])
                offset += count
                return slice
            }
            func readUInt32() throws -> UInt32 {
                let b = try take(4)
                return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
            }
            func readDoubles(_ count: Int) throws -> [Double] {
                let bytes = try take(count * MemoryLayout<Double>.stride)
                return [Double](unsafeUninitializedCapacity: count) { buffer, initialized in
                    if count > 0, let dst = buffer.baseAddress, let src = bytes.baseAddress {
                        UnsafeMutableRawPointer(dst).copyMemory(from: src, byteCount: bytes.count)
                    }
                    initialized = count
                }
            }
            func readFloats(_ count: Int) throws -> [Float] {
                let bytes = try take(count * MemoryLayout<Float>.stride)
                return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
                    if count > 0, let dst = buffer.baseAddress, let src = bytes.baseAddress {
                        UnsafeMutableRawPointer(dst).copyMemory(from: src, byteCount: bytes.count)
                    }
                    initialized = count
                }
            }

            let head = try take(4)
            guard Array(head) == magic else { throw StorageError.malformed("not a pose file") }
            guard try readUInt32() == version else { throw StorageError.malformed("unknown version") }
            let headerLength = Int(try readUInt32())
            let headerBytes = try take(headerLength)
            guard let headerBase = headerBytes.baseAddress else { throw StorageError.malformed("header") }
            let header = try JSONDecoder().decode(Header.self, from: Data(bytes: headerBase, count: headerBytes.count))
            let n = header.frames, k = header.keypoints
            // Validate before multiplying, so a damaged header can neither overflow nor over-allocate.
            guard n >= 0, k == Kp.allCases.count,
                  n <= (raw.count - offset) / (8 + 4 + k * 12) else { throw StorageError.malformed("size") }

            var t = PoseTrack(width: header.width, height: header.height, fps: header.fps, duration: header.duration,
                              modelName: header.modelName, modelVersion: header.modelVersion)
            t.timeOffset = header.timeOffset
            t.times = try readDoubles(n)
            t.boxConfidence = try readFloats(n)
            for i in 0..<k {
                t.x[i] = try readFloats(n)
                t.y[i] = try readFloats(n)
                t.c[i] = try readFloats(n)
            }
            return t
        }
    }
}
