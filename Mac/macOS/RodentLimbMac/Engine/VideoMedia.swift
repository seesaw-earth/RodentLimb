// VideoMedia.swift — facts about a video file (for the import sheet and lists) and still frames
// (thumbnails, calibration). Everything here is async and runs off the main thread.

import Foundation
import AVFoundation
import AppKit
import CoreImage

struct VideoFacts: Equatable, Sendable {
    var duration: Double
    var fps: Double
    /// Displayed (orientation-corrected) size.
    var width: Int
    var height: Int
    var codec: String
    var fileSize: Int64
    var creationDate: Date?
    /// The file opens and has a decodable video track.
    var playable: Bool
    var problem: String?
    /// macOS reports the track as decodable, but a test frame could not be decoded.
    var testFrameFailed = false

    var sizeLabel: String { width > 0 ? "\(width)×\(height)" : "—" }

    /// Advice shown in the import sheet before anything is processed.
    var warnings: [String] {
        var w: [String] = []
        if let problem { w.append(problem) }
        if playable && fps > 0 && fps < 25 {
            w.append(L("Below 25 fps: fast behaviours (scratching, flinches, gait) need ≥ 60 fps.",
                       "低于 25 fps：快速行为（抓挠、甩爪、步态）需要 ≥ 60 fps。"))
        }
        if playable && duration > 0 && duration < 5 { w.append(L("Very short video.", "视频很短。")) }
        if playable && testFrameFailed {
            w.append(L("A test frame could not be decoded: tracking will probably fail. Check that the file plays in QuickTime Player, or convert it to H.264 MP4.",
                       "无法解码测试画面：识别很可能会失败。请确认文件能在 QuickTime Player 中播放，或先转换为 H.264 MP4。"))
        }
        return w
    }
}

enum VideoProbe {
    /// Reads duration, frame rate, size and codec. Never throws: problems are reported in `problem`.
    static func facts(_ url: URL, scoped: Bool) async -> VideoFacts {
        let access = VideoBookmarks.access(url, scoped: scoped)
        defer { _ = access }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        var out = VideoFacts(duration: 0, fps: 0, width: 0, height: 0, codec: "", fileSize: size, creationDate: nil,
                             playable: false, problem: nil)
        guard FileManager.default.fileExists(atPath: url.path) else {
            out.problem = PoseRunError.videoMissing.errorDescription
            return out
        }
        if !VideoFiles.isReadable(url) {
            out.problem = L("This format usually cannot be read on a Mac. Convert it to MP4 (H.264 or HEVC), e.g. with HandBrake or ffmpeg.",
                            "Mac 通常无法读取这种格式。请先转换为 MP4（H.264 或 HEVC），例如使用 HandBrake 或 ffmpeg。")
        }
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                out.problem = PoseRunError.noVideoTrack.errorDescription
                return out
            }
            async let d = asset.load(.duration)
            async let f = track.load(.nominalFrameRate)
            async let t = track.load(.preferredTransform)
            async let n = track.load(.naturalSize)
            async let formats = track.load(.formatDescriptions)
            async let created = asset.load(.creationDate)
            async let decodable = track.load(.isDecodable)
            let (dur, fr, tf, nat) = try await (d, f, t, n)
            let r = CGRect(origin: .zero, size: nat).applying(tf)
            out.duration = CMTimeGetSeconds(dur).finiteOr(0)
            out.fps = Double(fr).finiteOr(0)
            out.width = Int(safe: Double(abs(r.width)).rounded())
            out.height = Int(safe: Double(abs(r.height)).rounded())
            if let desc = (try? await formats)?.first {
                out.codec = fourCC(CMFormatDescriptionGetMediaSubType(desc))
            }
            if let item = try? await created {
                out.creationDate = try? await item.load(.dateValue)
            }
            out.playable = out.duration > 0 && out.width > 0
            if !out.playable && out.problem == nil {
                out.problem = L("The video has no duration or frame size.", "视频没有时长或画面尺寸信息。")
            }
            // Can this Mac decode it at all? (A codec without a decoder — e.g. AV1 on M1 / M2 Macs —
            // still has a duration and a size, then fails during tracking: VideoToolbox err -12906.)
            if out.playable, (try? await decodable) == false {
                out.playable = false
                out.problem = undecodableMessage(codec: out.codec)
            } else if out.playable {
                let probeTime = min(1, out.duration / 2)
                let frame = await FrameGrabber.image(url, scoped: false, at: probeTime, maxSize: 64, exact: false)
                out.testFrameFailed = frame == nil
            }
        } catch {
            out.problem = PoseRunError.badVideo(error.localizedDescription).errorDescription
        }
        return out
    }

    /// Why a video whose codec has no decoder on this Mac cannot be used, and how to fix it.
    static func undecodableMessage(codec: String) -> String {
        let c = codec.isEmpty ? L("unknown", "未知") : codec
        return String(format: L("This Mac has no decoder for the video's codec (%@): it cannot be tracked or played here. AV1, for example, is decoded only by Macs with an M3 chip or newer. Convert the video to H.264 MP4 (HandBrake, or ffmpeg -i input -c:v libx264 -crf 18 -pix_fmt yuv420p output.mp4) and import the converted file.",
                                "这台 Mac 没有该视频编码（%@）的解码器，因此无法在本机识别或播放。例如 AV1 只有 M3 及更新芯片的 Mac 才能解码。请先转换为 H.264 MP4（HandBrake，或 ffmpeg -i input -c:v libx264 -crf 18 -pix_fmt yuv420p output.mp4）后再导入转换后的文件。"), c)
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        let s = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        switch s {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "ap4h", "apch", "apcn", "apcs", "apco": return "ProRes"
        case "mp4v": return "MPEG-4"
        case "av01": return "AV1"
        case "vp08": return "VP8"
        case "vp09": return "VP9"
        case "jpeg", "mjpa", "mjpb": return "Motion JPEG"
        default: return s
        }
    }
}

/// Still frames of a video (upright), e.g. for calibration and thumbnails.
enum FrameGrabber {
    /// The frame at `time` (seconds of the video's own timeline). `maxSize` limits the longest side.
    static func image(_ url: URL, scoped: Bool, at time: Double, maxSize: CGFloat = 0, exact: Bool = true) async -> CGImage? {
        let access = VideoBookmarks.access(url, scoped: scoped)
        defer { _ = access }
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        if exact {
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
        }
        if maxSize > 0 { gen.maximumSize = CGSize(width: maxSize, height: maxSize) }
        let t = CMTime(seconds: max(0, time.finiteOr(0)), preferredTimescale: 600_000)
        do {
            let (img, _) = try await gen.image(at: t)
            return img
        } catch {
            // Exact frames can fail near the end of some files: fall back to the nearest frame.
            if exact {
                gen.requestedTimeToleranceBefore = .positiveInfinity
                gen.requestedTimeToleranceAfter = .positiveInfinity
                return try? await gen.image(at: t).image
            }
            return nil
        }
    }
}

/// Thumbnails for lists, cached in memory and in the recording folder (thumbnail.jpg).
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var images: [UUID: NSImage] = [:]
    private var order: [UUID] = []
    private var loading = Set<UUID>()
    private let limit = 300

    func cached(_ id: UUID) -> NSImage? { images[id] }

    func load(_ id: UUID, folder: URL, video: URL?, scoped: Bool, at time: Double = 1) async -> NSImage? {
        if let i = images[id] { return i }
        if loading.contains(id) { return nil }
        loading.insert(id)
        defer { loading.remove(id) }
        let file = folder.appendingPathComponent("thumbnail.jpg")
        let fromDisk = await Task.detached(priority: .utility) { NSImage(contentsOf: file) }.value
        if let img = fromDisk { insert(img, id); return img }
        guard let video, let cg = await FrameGrabber.image(video, scoped: scoped, at: time, maxSize: 320, exact: false) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        insert(img, id)
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            Task.detached(priority: .background) { try? data.write(to: file, options: .atomic) }
        }
        return img
    }

    private func insert(_ img: NSImage, _ id: UUID) {
        images[id] = img
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > limit { images[order.removeFirst()] = nil }
    }

    func trim() {
        images.removeAll()
        order.removeAll()
    }
}
