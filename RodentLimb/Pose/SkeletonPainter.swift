import Foundation
import UIKit
import CoreVideo
import CoreGraphics

// Draws onto a fresh BGRA pixel buffer, leaving the AVAssetReader source untouched.
enum SkeletonPainter {
    /// `pool` is the asset writer adaptor's pool: recycling its buffers avoids allocating a new
    /// full-size frame for every video frame (Apple: "for maximum efficiency" use the pool).
    static func render(source: CVPixelBuffer, pose: DecodedPose?,
                       keypointThreshold: Double, pool: CVPixelBufferPool? = nil) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var result: CVPixelBuffer?
        if let pool {
            var pooled: CVPixelBuffer?
            // A pool buffer of another size or format cannot be filled row by row below.
            if CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pooled) == kCVReturnSuccess,
               let p = pooled,
               CVPixelBufferGetWidth(p) == width, CVPixelBufferGetHeight(p) == height,
               CVPixelBufferGetPixelFormatType(p) == kCVPixelFormatType_32BGRA {
                result = p
            }
        }
        if result == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
            ]
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                             kCVPixelFormatType_32BGRA, attributes as CFDictionary, &result)
            guard status == kCVReturnSuccess else { throw PoseError.writerFailed("pixel buffer \(status)") }
        }
        guard let target = result else { throw PoseError.writerFailed("pixel buffer") }
        // The source must be BGRA (the reader is configured for it); anything else would be
        // copied with the wrong row length.
        guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else {
            throw PoseError.writerFailed("source pixel format")
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(target, [])
        defer {
            CVPixelBufferUnlockBaseAddress(target, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        guard let src = CVPixelBufferGetBaseAddress(source),
              let dst = CVPixelBufferGetBaseAddress(target) else {
            throw PoseError.writerFailed("pixel memory")
        }
        let srcStride = CVPixelBufferGetBytesPerRow(source)
        let dstStride = CVPixelBufferGetBytesPerRow(target)
        for row in 0..<height {
            memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), width * 4)
        }

        guard let ctx = CGContext(data: dst, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: dstStride,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                                              CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw PoseError.writerFailed("bitmap context")
        }

        // All detection coordinates are in raw pixel coordinates, top-left origin.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        let scale = max(0.8, CGFloat(min(width, height)) / 640)

        guard let pose else { return target }
        ctx.setLineWidth(2 * scale)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        for (a, b) in Kp.bones {
            let p = pose.keypoints[a.rawValue], q = pose.keypoints[b.rawValue]
            guard p.confidence >= keypointThreshold, q.confidence >= keypointThreshold, p.x >= 0, q.x >= 0 else { continue }
            ctx.move(to: CGPoint(x: p.x, y: p.y))
            ctx.addLine(to: CGPoint(x: q.x, y: q.y))
            ctx.strokePath()
        }
        for k in Kp.allCases {
            let p = pose.keypoints[k.rawValue]
            guard p.confidence >= keypointThreshold, p.x >= 0 else { continue }
            let r = 4.2 * scale
            let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            ctx.setFillColor(KeypointColors.ui(k).cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.2 * scale)
            ctx.strokeEllipse(in: rect)
        }
        return target
    }
}
