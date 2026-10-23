import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads camera pictures on the device with Vision, remembering each camera's
/// previous pictures to tell a frozen camera from a live one.
actor RoadAnalyzer {
    static let shared = RoadAnalyzer()

    /// What the analyzer remembers about a camera between pictures.
    private struct CameraMemory {
        var lastImage: Data?
        /// How many pictures in a row were identical to the one before.
        var repeats = 0
    }

    /// Identical pictures in a row before a camera counts as frozen. cita.lu updates
    /// its pictures about every minute, so two repeats is over a minute.
    private static let frozenAfterRepeats = 2

    private var memories: [String: CameraMemory] = [:]
    private let detector = VehicleDetector()

    /// Analyzes a picture of a camera. `nil` if it can't be decoded.
    func analyze(_ data: Data, camera id: String, detectsVehicles: Bool, at date: Date = .now) -> RoadReport? {
        guard let image = Self.image(from: data), let statistics = ImageStatistics(image: image) else { return nil }

        var memory = memories[id] ?? CameraMemory()
        memory.repeats = memory.lastImage == data ? memory.repeats + 1 : 0
        memory.lastImage = data
        memories[id] = memory

        var report = RoadReport(date: date, light: statistics.light, visibility: statistics.visibility)
        if statistics.isBlank {
            report.feed = .unavailable
            return report
        }
        if memory.repeats >= Self.frozenAfterRepeats {
            report.feed = .frozen
        }
        report.weather = Self.weather(in: image)
        if report.weather.contains(.fog), report.visibility == .good {
            report.visibility = .reduced
        }
        if detectsVehicles, VehicleDetector.isInstalled, let boxes = try? detector.vehicles(in: image) {
            report.vehicles = boxes.count
            report.vehicleBoxes = boxes
        }
        return report
    }

    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: Weather

    /// The weather Vision's scene classification sees, from the labels it is confident about.
    static func weather(in image: CGImage) -> Set<RoadReport.Weather> {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }
        var weather: Set<RoadReport.Weather> = []
        for observation in observations where observation.confidence >= minimumConfidence {
            let label = observation.identifier.lowercased()
            for kind in RoadReport.Weather.allCases where kind.labelKeywords.contains(where: { label.contains($0) }) {
                weather.insert(kind)
            }
        }
        return weather
    }

    private static let minimumConfidence: Float = 0.3
}

private extension RoadReport.Weather {
    /// Words in Vision's classification labels that mean this weather.
    var labelKeywords: [String] {
        switch self {
        case .snow: ["snow", "blizzard"]
        case .fog: ["fog", "mist", "haze"]
        case .rain: ["rain", "storm"]
        }
    }
}
