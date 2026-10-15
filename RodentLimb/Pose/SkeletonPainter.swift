import Foundation
import UIKit
import CoreVideo
import CoreGraphics

// Draws onto a fresh BGRA pixel buffer, leaving the AVAssetReader source untouched.
enum SkeletonPainter {
    static func render(source: CVPixelBuffer, pose: DecodedPose?,
                       keypointThreshold: Double) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var result: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, attributes as CFDictionary, &result)
        guard status == kCVReturnSuccess, let target = result else {
            throw PoseError.writerFailed("pixel buffer \(status)")
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
