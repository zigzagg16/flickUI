import CoreGraphics
import Foundation

/// What the app reads from a camera image, on the device. These are estimates from
/// the picture, never an official traffic state.
struct RoadReport: Codable, Hashable, Sendable {
    enum Feed: String, Codable, Sendable {
        case live
        /// The camera keeps sending the same picture.
        case frozen
        /// No picture, or a blank one.
        case unavailable
    }

    enum Light: String, Codable, Sendable {
        case day, dusk, night
    }

    enum Visibility: String, Codable, Sendable {
        case good, reduced, poor
    }

    enum Weather: String, Codable, Sendable, CaseIterable {
        case snow, fog, rain
    }

    enum Traffic: String, Codable, Sendable, Comparable {
        case empty, flowing, dense, jammed

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .empty: 0
            case .flowing: 1
            case .dense: 2
            case .jammed: 3
            }
        }
    }

    var date: Date
    var feed = Feed.live
    var light = Light.day
    var visibility = Visibility.good
    var weather: Set<Weather> = []
    /// The number of vehicles seen, with vehicle detection on.
    var vehicles: Int?
    /// The vehicles' boxes, normalised with the origin at the top left.
    var vehicleBoxes: [CGRect] = []
    var traffic: Traffic?
    /// The traffic on the left and right halves of the picture, usually one carriageway each.
    var leftTraffic: Traffic?
    var rightTraffic: Traffic?
    /// How fast things move in the live stream, from 0 (stopped) to 1, per half of the picture.
    var leftMotion: Double?
    var rightMotion: Double?

    static func unavailable(at date: Date) -> Self {
        RoadReport(date: date, feed: .unavailable)
    }

    /// The conditions worth a mention, most important first.
    var conditions: [String] {
        switch feed {
        case .frozen: return ["Image not updating"]
        case .unavailable: return ["Camera unavailable"]
        case .live: break
        }
        var parts: [String] = []
        if let traffic { parts.append(traffic.title) }
        if let vehicles { parts.append(vehicles == 1 ? "1 vehicle" : "\(vehicles) vehicles") }
        parts += Weather.allCases.filter(weather.contains).map(\.title)
        if visibility != .good { parts.append(visibility.title) }
        if light != .day { parts.append(light.title) }
        return parts
    }

    /// A symbol for what matters most, or `nil` when nothing stands out.
    var symbol: String? {
        switch feed {
        case .frozen: return "pause.circle.fill"
        case .unavailable: return "video.slash.fill"
        case .live: break
        }
        if traffic == .jammed { return "exclamationmark.triangle.fill" }
        if weather.contains(.snow) { return "snowflake" }
        if weather.contains(.fog) || visibility == .poor { return "cloud.fog.fill" }
        if traffic == .dense { return "car.2.fill" }
        if weather.contains(.rain) { return "cloud.rain.fill" }
        return nil
    }
}

extension RoadReport.Traffic {
    var title: String {
        switch self {
        case .empty: "Empty"
        case .flowing: "Flowing"
        case .dense: "Dense"
        case .jammed: "Jammed"
        }
    }
}

extension RoadReport.Weather {
    var title: String {
        switch self {
        case .snow: "Snow"
        case .fog: "Fog"
        case .rain: "Rain"
        }
    }
}

extension RoadReport.Visibility {
    var title: String {
        switch self {
        case .good: "Good visibility"
        case .reduced: "Reduced visibility"
        case .poor: "Poor visibility"
        }
    }
}

extension RoadReport.Light {
    var title: String {
        switch self {
        case .day: "Day"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }
}
