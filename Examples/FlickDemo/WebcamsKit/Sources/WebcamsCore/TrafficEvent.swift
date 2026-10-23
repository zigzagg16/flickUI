import Foundation

/// An incident or roadworks on a motorway, as the road operator publishes it.
///
/// One event is one DATEX II situation record: works on both carriageways are two
/// events, one per direction. ``CitaTraffic`` reads them; `fetch_cita.py` writes the
/// same keys, so its snapshot decodes into this too.
public struct TrafficEvent: Codable, Hashable, Sendable, Identifiable {
    /// The record's identifier, such as "238034-1".
    public var id: String
    /// The DATEX II record type, such as "MaintenanceWorks" or "VehicleObstruction".
    public var type: String
    /// The record's own detail, such as "brokenDownVehicle".
    public var cause: String?
    /// The road number, such as "A13".
    public var road: String?
    /// Which carriageway, such as "Collectrice du Sud, vers Schengen".
    public var destination: String?
    /// Where on the road, such as "Section courante" or "Echangeur".
    public var place: String?
    /// The operator's note, such as the name of the works, often in Luxembourgish.
    public var comment: String?
    public var startTime: Date?
    /// When it should end; `nil` until the operator knows.
    public var endTime: Date?
    /// When the operator last changed the record.
    public var updatedAt: Date?
    public var lanesRestricted: Int?
    /// The lanes still open; 0 means the carriageway is closed.
    public var operationalLanes: Int?
    /// The length of road affected, in metres.
    public var length: Double?
    public var coordinate: WebcamCatalog.Coordinate?

    public init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}

extension TrafficEvent {
    public enum Kind: String, Sendable, CaseIterable {
        case accident, breakdown, obstruction, roadworks, equipmentFault, roadConditions, congestion, other
    }

    public var kind: Kind {
        switch type {
        case "Accident": .accident
        case "VehicleObstruction": cause == "brokenDownVehicle" ? .breakdown : .obstruction
        case "GeneralObstruction", "AnimalPresenceObstruction", "EnvironmentalObstruction", "InfrastructureDamageObstruction": .obstruction
        case "MaintenanceWorks", "ConstructionWorks", "RoadOrCarriagewayOrLaneManagement": .roadworks
        case "EquipmentOrSystemFault": .equipmentFault
        case "PoorEnvironmentConditions", "WeatherRelatedRoadConditions", "NonWeatherRelatedRoadConditions": .roadConditions
        case "AbnormalTraffic": .congestion
        default: .other
        }
    }

    /// An SF Symbol for the kind of event.
    public var symbol: String {
        switch kind {
        case .accident: "car.side.rear.and.collision.and.car.side.front"
        case .breakdown: "car.fill"
        case .obstruction: "exclamationmark.triangle.fill"
        case .roadworks: "cone.fill"
        case .equipmentFault: "wrench.adjustable.fill"
        case .roadConditions: "cloud.snow.fill"
        case .congestion: "car.2.fill"
        case .other: "info.circle.fill"
        }
    }

    /// Whether the carriageway is closed.
    public var closesRoad: Bool {
        operationalLanes == 0
    }

    /// Whether the event is under way at a date, rather than planned or over.
    public func isActive(at date: Date = .now) -> Bool {
        (startTime ?? .distantPast) <= date && date < (endTime ?? .distantFuture)
    }
}

extension WebcamCatalog.Motorway {
    /// The events on this motorway.
    public func events(in events: [TrafficEvent]) -> [TrafficEvent] {
        events.filter { $0.road?.caseInsensitiveCompare(code) == .orderedSame }
    }
}

extension WebcamCatalog.Camera {
    /// The events near this camera, nearest first; none when it has no coordinate.
    public func nearbyEvents(in events: [TrafficEvent], within distance: Double = 2000) -> [TrafficEvent] {
        guard let coordinate else { return [] }
        return events
            .compactMap { event in event.coordinate.map { (event, $0.distance(to: coordinate)) } }
            .filter { $0.1 <= distance }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}

extension WebcamCatalog.Coordinate {
    /// The distance to another coordinate along the Earth's surface, in metres.
    public func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let dLatitude = (other.latitude - latitude) * radians
        let dLongitude = (other.longitude - longitude) * radians
        let a = sin(dLatitude / 2) * sin(dLatitude / 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * sin(dLongitude / 2) * sin(dLongitude / 2)
        return 6_371_000 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}
