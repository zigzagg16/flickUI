import Foundation

/// An overhead sign showing travel times, such as Schengen: "LUX-SUD 19 min".
public struct TravelTimeSign: Codable, Hashable, Sendable, Identifiable {
    /// A stable identifier made from the name, such as "schengen".
    public var id: String
    /// Where the sign is, such as "Schengen".
    public var name: String
    public var coordinate: WebcamCatalog.Coordinate
    /// The lines on the sign, top first.
    public var destinations: [Destination]

    public struct Destination: Codable, Hashable, Sendable {
        /// As the sign shows it, such as "LUX-SUD" or "BELGIQUE".
        public var name: String
        /// `nil` when the sign shows no time.
        public var minutes: Int?

        public init(name: String, minutes: Int?) {
            self.name = name
            self.minutes = minutes
        }
    }

    public init(name: String, coordinate: WebcamCatalog.Coordinate, destinations: [Destination]) {
        self.id = Self.identifier(for: name)
        self.name = name
        self.coordinate = coordinate
        self.destinations = destinations
    }

    /// "Lux-Sud" becomes "lux-sud".
    static func identifier(for name: String) -> String {
        name.lowercased()
            .replacing(#/[^a-z0-9]+/#, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension Array where Element == TravelTimeSign {
    /// The sign nearest a coordinate, within a distance in metres.
    public func nearest(to coordinate: WebcamCatalog.Coordinate, within distance: Double = 3000) -> TravelTimeSign? {
        map { ($0, $0.coordinate.distance(to: coordinate)) }
            .filter { $0.1 <= distance }
            .min { $0.1 < $1.1 }?.0
    }
}

extension WebcamCatalog.Camera {
    /// The travel time sign nearest this camera, within a distance in metres.
    public func nearestSign(in signs: [TravelTimeSign], within distance: Double = 3000) -> TravelTimeSign? {
        coordinate.flatMap { signs.nearest(to: $0, within: distance) }
    }
}
