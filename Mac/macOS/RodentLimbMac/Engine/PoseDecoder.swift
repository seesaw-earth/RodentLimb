// PoseDecoder.swift — decodes the raw Ultralytics pose head, exactly as the iPhone app does for
// CylinderMousePoseV2 (same candidate selection, letterbox mapping and clamping), so a video gives the
// same keypoints on both.
//
//   [1,5+3K,8400] = cx, cy, w, h, 1 class score, K × (x, y, confidence)   (raw one-to-many head)
//   also [1,8400,5+3K] and YOLO26 nms=False [1,300,6+3K] (end-to-end: x1 y1 x2 y2, conf, class, K × 3)
// K = 7 for CylinderMousePoseV2 (26 / 27 channels), 8 for PalmReaderPose8 (29 / 30). The model's
// keypoints are mapped onto the stored 7 (PoseModelID.keypointMap); a stored keypoint the model does
// not have is returned as missing.
// Coordinates are in model pixels and mapped back with Vision's .scaleFit letterbox.
//
// Mac difference: Swift's Float16 type is not available on Intel Macs, so half-precision outputs are
// converted bit by bit (same values).

import Foundation
import CoreML
import CoreGraphics

struct RawKeypoint { var x: Double; var y: Double; var confidence: Double }

struct DecodedPose {
    var score: Double
    var box: CGRect
    var keypoints: [RawKeypoint]
}

final class PoseDecoder {
    private let threshold: Double
    private let imageWidth: Double
    private let imageHeight: Double
    private let inputSize: Double
    private let keypointCount: Int
    /// Stored keypoint (Kp order) → model keypoint index.
    private let map: [Int?]

    init(threshold: Double, imageWidth: Int, imageHeight: Int, inputSize: Int = 640, model: PoseModelID = .visible) {
        self.threshold = threshold
        self.imageWidth = Double(imageWidth)
        self.imageHeight = Double(imageHeight)
        self.inputSize = Double(inputSize)
        self.keypointCount = model.keypointCount
        self.map = model.keypointMap
    }

    func decode(_ array: MLMultiArray) throws -> DecodedPose? {
        let t = try PoseTensor(array, keypointCount: keypointCount)
        guard let layout = PoseOutputLayout.detect(channels: t.channels, keypointCount: keypointCount) else {
            throw PoseRunError.modelFailed("tensor \(array.shape)")
        }
        let isEndToEnd = layout.endToEnd
        var best = -1
        var bestScore = threshold
        for i in 0..<t.candidates {
            let confidence = Double(t.value(4, i))
            if confidence > bestScore && confidence.isFinite {
                bestScore = confidence
                best = i
            }
        }
        guard best >= 0 else { return nil }

        let x1: Double, y1: Double, x2: Double, y2: Double
        if isEndToEnd {
            x1 = Double(t.value(0, best)); y1 = Double(t.value(1, best))
            x2 = Double(t.value(2, best)); y2 = Double(t.value(3, best))
        } else {
            let cx = Double(t.value(0, best)), cy = Double(t.value(1, best))
            let w = Double(t.value(2, best)), h = Double(t.value(3, best))
            x1 = cx - w / 2; y1 = cy - h / 2
            x2 = cx + w / 2; y2 = cy + h / 2
        }

        let scale = min(inputSize / imageWidth, inputSize / imageHeight)
        let padX = (inputSize - imageWidth * scale) / 2
        let padY = (inputSize - imageHeight * scale) / 2
        func restore(_ x: Double, _ y: Double) -> (Double, Double) { ((x - padX) / scale, (y - padY) / scale) }
        func clamp(_ v: Double, _ m: Double) -> Double { min(max(0, v), m) }

        let (rx1, ry1) = restore(x1, y1)
        let (rx2, ry2) = restore(x2, y2)
        guard [rx1, ry1, rx2, ry2].allSatisfy(\.isFinite), rx2 > rx1, ry2 > ry1 else { return nil }
        let box = CGRect(x: clamp(rx1, imageWidth), y: clamp(ry1, imageHeight),
                         width: clamp(rx2, imageWidth) - clamp(rx1, imageWidth),
                         height: clamp(ry2, imageHeight) - clamp(ry1, imageHeight))

        let start = layout.firstKeypointChannel
        let kp = Kp.allCases.map { part -> RawKeypoint in
            guard part.rawValue < map.count, let index = map[part.rawValue], index < keypointCount else {
                return RawKeypoint(x: -1, y: -1, confidence: 0)
            }
            let channel = start + index * 3
            let (x, y) = restore(Double(t.value(channel, best)), Double(t.value(channel + 1, best)))
            let score = Double(t.value(channel + 2, best))
            let inFrame = x.isFinite && y.isFinite && x >= 0 && x < imageWidth && y >= 0 && y < imageHeight
            return RawKeypoint(x: inFrame ? x : -1, y: inFrame ? y : -1,
                               confidence: inFrame && score.isFinite ? max(0, min(1, score)) : 0)
        }
        return DecodedPose(score: bestScore, box: box, keypoints: kp)
    }
}

/// Reads the output tensor (Float16 / Float32 / Double, any strides) without boxing an NSNumber per value.
private struct PoseTensor {
    let array: MLMultiArray
    let candidates: Int
    let channels: Int
    private let channelStride: Int
    private let candidateStride: Int
    private let hasBatchDimension: Bool
    private let channelsFirst: Bool

    init(_ array: MLMultiArray, keypointCount: Int) throws {
        let dims = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        let offset = dims.count == 3 && dims[0] == 1 ? 1 : 0
        hasBatchDimension = offset == 1
        guard dims.count - offset == 2, strides.count == dims.count else { throw PoseRunError.modelFailed("shape \(dims)") }
        let valid = Set([5 + 3 * keypointCount, 6 + 3 * keypointCount])
        if valid.contains(dims[offset]) {
            channelsFirst = true
            channels = dims[offset]
            candidates = dims[offset + 1]
            channelStride = strides[offset]
            candidateStride = strides[offset + 1]
        } else if valid.contains(dims[offset + 1]) {
            channelsFirst = false
            channels = dims[offset + 1]
            candidates = dims[offset]
            channelStride = strides[offset + 1]
            candidateStride = strides[offset]
        } else {
            throw PoseRunError.modelFailed("shape \(dims)")
        }
        guard candidates > 0 else { throw PoseRunError.modelFailed("empty tensor") }
        self.array = array
    }

    @inline(__always) func value(_ channel: Int, _ candidate: Int) -> Float {
        let offset = channel * channelStride + candidate * candidateStride
        guard channel >= 0, channel < channels, candidate >= 0, candidate < candidates, offset >= 0 else { return 0 }
        switch array.dataType {
        case .float16:
            return HalfFloat.float(array.dataPointer.assumingMemoryBound(to: UInt16.self)[offset])
        case .float32:
            return array.dataPointer.assumingMemoryBound(to: Float.self)[offset]
        case .double:
            return Float(array.dataPointer.assumingMemoryBound(to: Double.self)[offset])
        default:
            let idx = channelsFirst ? [channel, candidate] : [candidate, channel]
            let full = hasBatchDimension ? [0] + idx : idx
            return array[full.map { NSNumber(value: $0) }].floatValue
        }
    }
}
