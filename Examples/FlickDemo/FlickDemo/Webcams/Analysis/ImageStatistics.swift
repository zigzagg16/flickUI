import CoreGraphics
import Foundation

/// Brightness, contrast and sharpness of a picture, from a small greyscale copy.
///
/// The thresholds are starting values for cita.lu's cameras, to tune on real pictures.
struct ImageStatistics: Sendable {
    /// Mean brightness, 0–255.
    let brightness: Double
    /// Standard deviation of brightness, 0–255. Fog and blank pictures have little.
    let contrast: Double
    /// Mean difference between neighbouring pixels. Fog and blur flatten edges.
    let sharpness: Double

    init?(image: CGImage, width: Int = 64, height: Int = 48) {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(pixels: pixels, width: width)
    }

    init(pixels: [UInt8], width: Int) {
        let count = Double(max(pixels.count, 1))
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / count
        let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / count
        var edges = 0.0
        var pairs = 0.0
        for index in pixels.indices where (index + 1) % width != 0 && index + 1 < pixels.count {
            edges += abs(Double(pixels[index + 1]) - Double(pixels[index]))
            pairs += 1
        }
        brightness = mean
        contrast = variance.squareRoot()
        sharpness = pairs > 0 ? edges / pairs : 0
    }

    /// A single grey, as cameras send when they have no picture.
    var isBlank: Bool {
        contrast < 3
    }

    var light: RoadReport.Light {
        switch brightness {
        case ..<45: .night
        case ..<85: .dusk
        default: .day
        }
    }

    /// Only judged by day: at night, headlights make the picture contrasted anyway.
    var visibility: RoadReport.Visibility {
        guard light == .day else { return .good }
        if contrast < 20 || sharpness < 3 { return .poor }
        if contrast < 32 || sharpness < 5 { return .reduced }
        return .good
    }
}
