#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// What the app reads from a camera image, on the device. These are estimates from
/// the picture, never an official traffic state.
public struct RoadReport: Codable, Equatable, Sendable {
    public enum Feed: String, Codable, Sendable {
        case live
        /// The camera keeps sending the same picture.
        case frozen
        /// No picture, or a blank one.
        case unavailable
    }

    public enum Light: String, Codable, Sendable {
        case day, dusk, night
    }

    public enum Visibility: String, Codable, Sendable {
        case good, reduced, poor
    }

    public enum Weather: String, Codable, Sendable, CaseIterable {
        case snow, fog, rain
    }

    public enum Traffic: String, Codable, Sendable, Comparable {
        case empty, flowing, dense, jammed

        public static func < (lhs: Self, rhs: Self) -> Bool {
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

    public var date: Date
    public var feed = Feed.live
    public var light = Light.day
    public var visibility = Visibility.good
    public var weather: Set<Weather> = []
    /// The number of vehicles seen, with vehicle detection on.
    public var vehicles: Int?
    /// The vehicles' boxes, normalised with the origin at the top left.
    public var vehicleBoxes: [CGRect] = []
    public var traffic: Traffic?
    /// The traffic on the left and right halves of the picture, usually one carriageway each.
    public var leftTraffic: Traffic?
    public var rightTraffic: Traffic?
    /// How fast things move in the live stream, from 0 (stopped) to 1, per half of the picture.
    public var leftMotion: Double?
    public var rightMotion: Double?

    public init(
        date: Date,
        feed: Feed = .live,
        light: Light = .day,
        visibility: Visibility = .good,
        weather: Set<Weather> = [],
        vehicles: Int? = nil,
        vehicleBoxes: [CGRect] = [],
        traffic: Traffic? = nil,
        leftTraffic: Traffic? = nil,
        rightTraffic: Traffic? = nil,
        leftMotion: Double? = nil,
        rightMotion: Double? = nil
    ) {
        self.date = date
        self.feed = feed
        self.light = light
        self.visibility = visibility
        self.weather = weather
        self.vehicles = vehicles
        self.vehicleBoxes = vehicleBoxes
        self.traffic = traffic
        self.leftTraffic = leftTraffic
        self.rightTraffic = rightTraffic
        self.leftMotion = leftMotion
        self.rightMotion = rightMotion
    }

    public static func unavailable(at date: Date) -> Self {
        RoadReport(date: date, feed: .unavailable)
    }

    /// The conditions worth a mention, most important first.
    public var conditions: [String] {
        switch feed {
        case .frozen: return ["Image not updating"]
        case .unavailable: return ["Camera unavailable"]
        case .live: break
        }
        var parts: [String] = []
        if let traffic {
            // Name the jammed or dense side when the two carriageways differ.
            if let leftTraffic, let rightTraffic, leftTraffic != rightTraffic {
                parts.append("Left \(leftTraffic.title.lowercased()), right \(rightTraffic.title.lowercased())")
            } else {
                parts.append(traffic.title)
            }
        }
        if let vehicles { parts.append(vehicles == 1 ? "1 vehicle" : "\(vehicles) vehicles") }
        parts += Weather.allCases.filter(weather.contains).map(\.title)
        if visibility != .good { parts.append(visibility.title) }
        if light != .day { parts.append(light.title) }
        return parts
    }

    /// A symbol for what matters most, or `nil` when nothing stands out.
    public var symbol: String? {
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
    public var title: String {
        switch self {
        case .empty: "Empty"
        case .flowing: "Flowing"
        case .dense: "Dense"
        case .jammed: "Jammed"
        }
    }
}

extension RoadReport.Weather {
    public var title: String {
        switch self {
        case .snow: "Snow"
        case .fog: "Fog"
        case .rain: "Rain"
        }
    }
}

extension RoadReport.Visibility {
    public var title: String {
        switch self {
        case .good: "Good visibility"
        case .reduced: "Reduced visibility"
        case .poor: "Poor visibility"
        }
    }
}

extension RoadReport.Light {
    public var title: String {
        switch self {
        case .day: "Day"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }
}
