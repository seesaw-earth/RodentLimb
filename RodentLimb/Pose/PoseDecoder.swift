import Foundation
import CoreML
import CoreGraphics

struct RawKeypoint { var x: Double; var y: Double; var confidence: Double }

struct DecodedPose {
    var score: Double
    var box: CGRect
    var keypoints: [RawKeypoint]
}

// Decodes the raw Ultralytics pose head from user's Oct 2026 export:
// [1,26,8400] = cx,cy,w,h,1 class score, 7*(x,y,confidence).
// Also accepts [1,8400,26] and YOLO26 nms=False [1,300,27].
// Coordinates are in 640x640 model pixels and mapped back using Vision .scaleFit.
final class PoseDecoder {
    private let threshold: Double
    private let imageWidth: Double
    private let imageHeight: Double
    private let inputSize: Double

    init(threshold: Double, imageWidth: Int, imageHeight: Int, inputSize: Int = 640) {
        self.threshold = threshold
        self.imageWidth = Double(imageWidth)
        self.imageHeight = Double(imageHeight)
        self.inputSize = Double(inputSize)
    }

    func decode(_ array: MLMultiArray) throws -> DecodedPose? {
        let t = try PoseTensor(array)
        guard t.channels == 26 || t.channels == 27 else {
            throw PoseError.unsupportedModel("tensor \(array.shape)")
        }

        // 26: raw one-to-many xywh output; 27: end-to-end xyxy+confidence+class+21 pose coords.
        let isEndToEnd = t.channels == 27
        var best = -1
        var bestScore = threshold
        for i in 0..<t.candidates {
            let confidence = Double(t.value(isEndToEnd ? 4 : 4, i))
            if confidence > bestScore && confidence.isFinite {
                bestScore = confidence
                best = i
            }
        }
        guard best >= 0 else { return nil }

        let x1: Double, y1: Double, x2: Double, y2: Double
        if isEndToEnd {
            x1 = Double(t.value(0, best))
            y1 = Double(t.value(1, best))
            x2 = Double(t.value(2, best))
            y2 = Double(t.value(3, best))
        } else {
            let cx = Double(t.value(0, best))
            let cy = Double(t.value(1, best))
            let w  = Double(t.value(2, best))
            let h  = Double(t.value(3, best))
            x1 = cx - w / 2; y1 = cy - h / 2
            x2 = cx + w / 2; y2 = cy + h / 2
        }

        func restore(_ x: Double, _ y: Double) -> (Double, Double) {
            let scale = min(inputSize / imageWidth, inputSize / imageHeight)
            let padX = (inputSize - imageWidth * scale) / 2
            let padY = (inputSize - imageHeight * scale) / 2
            return ((x - padX) / scale, (y - padY) / scale)
        }
        func clamp(_ value: Double, _ maximum: Double) -> Double {
            return min(max(0, value), maximum)
        }
        let (rx1, ry1) = restore(x1, y1)
        let (rx2, ry2) = restore(x2, y2)
        guard [rx1, ry1, rx2, ry2].allSatisfy(\.isFinite), rx2 > rx1, ry2 > ry1 else {
            return nil
        }
        let box = CGRect(x: clamp(rx1, imageWidth), y: clamp(ry1, imageHeight),
                         width: clamp(rx2, imageWidth) - clamp(rx1, imageWidth),
                         height: clamp(ry2, imageHeight) - clamp(ry1, imageHeight))

        let start = isEndToEnd ? 6 : 5
        let kp = Kp.allCases.map { part -> RawKeypoint in
            let channel = start + part.rawValue * 3
            let vx = Double(t.value(channel, best))
            let vy = Double(t.value(channel + 1, best))
            let score = Double(t.value(channel + 2, best))
            let (x, y) = restore(vx, vy)
            let inFrame = x.isFinite && y.isFinite && x >= 0 && x < imageWidth && y >= 0 && y < imageHeight
            return RawKeypoint(x: inFrame ? x : -1, y: inFrame ? y : -1,
                               confidence: inFrame && score.isFinite ? max(0, min(1, score)) : 0)
        }
        return DecodedPose(score: bestScore, box: box, keypoints: kp)
    }
}

// The arrays may be Float16 or Float32 with non-standard strides.
// Read without boxing a NSNumber for every candidate in every frame.
private struct PoseTensor {
    let array: MLMultiArray
    let candidates: Int
    let channels: Int
    private let channelStride: Int
    private let candidateStride: Int
    private let hasBatchDimension: Bool
    private let channelsFirst: Bool

    init(_ array: MLMultiArray) throws {
        let dims = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        let offset = dims.count == 3 && dims[0] == 1 ? 1 : 0
        hasBatchDimension = offset == 1
        guard dims.count - offset == 2 else {
            throw PoseError.unsupportedModel("shape \(dims)")
        }
        if dims[offset] == 26 || dims[offset] == 27 {
            channelsFirst = true
            channels = dims[offset]
            candidates = dims[offset + 1]
            channelStride = strides[offset]
            candidateStride = strides[offset + 1]
        } else if dims[offset + 1] == 26 || dims[offset + 1] == 27 {
            channelsFirst = false
            channels = dims[offset + 1]
            candidates = dims[offset]
            channelStride = strides[offset + 1]
            candidateStride = strides[offset]
        } else {
            throw PoseError.unsupportedModel("shape \(dims)")
        }
        guard candidates > 0 else { throw PoseError.unsupportedModel("empty tensor") }
        self.array = array
    }

    @inline(__always) func value(_ channel: Int, _ candidate: Int) -> Float {
        let offset = channel * channelStride + candidate * candidateStride
        switch array.dataType {
        case .float16:
            let bits = array.dataPointer.assumingMemoryBound(to: UInt16.self)[offset]
            return Float(Float16(bitPattern: bits))
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
