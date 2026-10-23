import CoreVideo
import Foundation
import Vision

/// A frame copied from the live stream's video output.
///
/// Each frame is a fresh copy handed to the analyzer and never touched again by the
/// player, so it is safe to send.
struct VideoFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// How much the live stream moves on each half of the picture, usually one
/// carriageway each.
struct MotionReading: Equatable, Sendable {
    /// From 0 (nothing moves) to 1 (the most movement seen so far).
    var left: Double
    var right: Double

    enum Level {
        case still, slow, fast

        var title: String {
            switch self {
            case .still: "Little movement"
            case .slow: "Moving slowly"
            case .fast: "Moving freely"
            }
        }
    }

    static func level(_ value: Double) -> Level {
        switch value {
        case ..<0.15: .still
        case ..<0.5: .slow
        default: .fast
        }
    }
}

/// Measures movement between two frames of the live stream with Vision's optical flow.
actor MotionAnalyzer {
    /// The fastest movement seen, slowly forgotten, so readings are relative to the
    /// stream's usual traffic.
    private var peak = 0.0

    /// Flow below this, in pixels between the two frames, is noise.
    private static let noise: Float = 0.3
    /// The least peak, so a quiet stream doesn't look fast.
    private static let minimumPeak = 1.5

    func motion(from first: VideoFrame, to second: VideoFrame) -> MotionReading? {
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: second.buffer, options: [:])
        request.computationAccuracy = .low
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        let handler = VNImageRequestHandler(cvPixelBuffer: first.buffer, options: [:])
        guard (try? handler.perform([request])) != nil, let flow = request.results?.first?.pixelBuffer else { return nil }
        guard let movement = Self.meanMovement(in: flow) else { return nil }

        peak = max(peak * 0.99, movement.left, movement.right, Self.minimumPeak)
        return MotionReading(left: min(movement.left / peak, 1), right: min(movement.right / peak, 1))
    }

    /// The mean flow magnitude of each half of the picture, in pixels.
    private static func meanMovement(in flow: CVPixelBuffer) -> (left: Double, right: Double)? {
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(flow) else { return nil }
        let width = CVPixelBufferGetWidth(flow)
        let height = CVPixelBufferGetHeight(flow)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(flow)
        var sums = (left: 0.0, right: 0.0)
        var counts = (left: 0.0, right: 0.0)
        // Every other pixel is plenty.
        for y in stride(from: 0, to: height, by: 2) {
            let row = (base + y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: 0, to: width, by: 2) {
                let dx = row[2 * x]
                let dy = row[2 * x + 1]
                var magnitude = (dx * dx + dy * dy).squareRoot()
                if magnitude < noise { magnitude = 0 }
                if x < width / 2 {
                    sums.left += Double(magnitude)
                    counts.left += 1
                } else {
                    sums.right += Double(magnitude)
                    counts.right += 1
                }
            }
        }
        guard counts.left > 0, counts.right > 0 else { return nil }
        // Scaled up: most of the picture is road side and sky, which doesn't move.
        return (left: sums.left / counts.left * 10, right: sums.right / counts.right * 10)
    }
}
