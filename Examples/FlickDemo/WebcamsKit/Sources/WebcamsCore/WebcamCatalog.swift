import Foundation

/// Everything the Webcams app shows, as a backend would describe it: the motorways,
/// their cameras, live streams and traffic maps, with every link.
///
/// Nothing here is tied to cita.lu: the backend can point at any source, rename
/// places, add or retire cameras and change refresh rates without an app update.
/// ``CatalogStore`` loads it; `catalog.json`, bundled with the app, is the catalog
/// until there is a backend.
public struct WebcamCatalog: Codable, Hashable, Sendable {
    /// The format's version, so an older app can tell a catalog it doesn't understand.
    public var version: Int
    /// When the backend built this catalog.
    public var updatedAt: Date
    /// Who provides the pictures, shown in the app.
    public var source: Source
    public var motorways: [Motorway]
    /// Settings the backend can tune.
    public var settings: Settings

    public struct Source: Codable, Hashable, Sendable {
        public var name: String
        public var website: URL
        public var attribution: String?
    }

    public struct Motorway: Codable, Hashable, Sendable, Identifiable {
        /// A stable identifier, such as "a13".
        public var id: String
        /// The road number, such as "A13".
        public var code: String
        /// The full name, such as "Autoroute de la Sarre".
        public var name: String
        /// A short name for the menu, such as "A13 Sarre".
        public var shortName: String
        /// An SF Symbol for the menu.
        public var symbol: String?
        /// The position in the menu; lower comes first.
        public var order: Int?
        /// The source's own page, to open in a browser.
        public var website: URL?
        public var liveStream: LiveStream?
        public var trafficMap: TrafficMap?
        public var cameras: [Camera]
    }

    public struct Camera: Codable, Hashable, Sendable, Identifiable {
        /// A stable identifier, unique across motorways, such as "13034".
        public var id: String
        /// Where the camera is, such as "Sanem".
        public var place: String
        /// Where it looks, such as "Pétange".
        public var direction: String?
        /// The still picture, without cache-busting query.
        public var imageURL: URL
        /// How often the source updates the picture, in seconds.
        public var refreshInterval: TimeInterval?
        public var coordinate: Coordinate?
        /// The road's direction of travel on each half of the picture, for the
        /// traffic estimate per carriageway.
        public var carriageways: Carriageways?
        /// `false` to keep a camera listed but hidden, such as during works.
        public var isEnabled: Bool?
    }

    public struct LiveStream: Codable, Hashable, Sendable {
        /// An HLS playlist.
        public var url: URL
        /// Whether to start muted, as the source does.
        public var startsMuted: Bool?
    }

    public struct TrafficMap: Codable, Hashable, Sendable {
        public var imageURL: URL
        public var refreshInterval: TimeInterval?
    }

    public struct Coordinate: Codable, Hashable, Sendable {
        public var latitude: Double
        public var longitude: Double
    }

    public struct Carriageways: Codable, Hashable, Sendable {
        /// Where traffic on the left half of the picture is heading, such as "Schengen".
        public var left: String?
        public var right: String?
    }

    public struct Settings: Codable, Hashable, Sendable {
        /// How long the app may use this catalog before asking for a new one, in seconds.
        public var catalogMaxAge: TimeInterval?
        /// The default picture refresh, for cameras without their own, in seconds.
        public var imageRefreshInterval: TimeInterval?
        /// The vehicle detection model to download, a Core ML `.mlmodel`.
        public var vehicleModelURL: URL?
        /// Incidents and roadworks, a DATEX II v3 situation publication for ``CitaTraffic``.
        public var trafficEventsURL: URL?
        /// Travel times on the overhead signs, a KML file for ``CitaTraffic``.
        public var travelTimesURL: URL?
        /// How often to reload the events and travel times, in seconds.
        public var trafficRefreshInterval: TimeInterval?
    }
}

extension WebcamCatalog {
    /// The decoder for the backend's JSON: ISO 8601 dates, camel-case keys.
    public static func decode(from data: Data) throws -> WebcamCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WebcamCatalog.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The motorways in menu order.
    public var orderedMotorways: [Motorway] {
        motorways.enumerated()
            .sorted { ($0.element.order ?? $0.offset, $0.offset) < ($1.element.order ?? $1.offset, $1.offset) }
            .map(\.element)
    }
}

/// The motorways the app shows come from the catalog.
public typealias Motorway = WebcamCatalog.Motorway

extension WebcamCatalog {
    /// A catalog with nothing in it, for when none can be read.
    public static let empty = WebcamCatalog(
        version: 1,
        updatedAt: .distantPast,
        source: Source(name: "", website: URL(filePath: "/")),
        motorways: [],
        settings: Settings()
    )

    public func motorway(withID id: String) -> Motorway? {
        motorways.first { $0.id == id }
    }

    /// The app's camera model for a catalog camera, with the default refresh applied.
    public func webcam(for camera: Camera) -> Webcam {
        camera.webcam(defaultRefresh: settings.imageRefreshInterval)
    }
}

extension WebcamCatalog.Motorway {
    /// The cameras to show.
    public var enabledCameras: [WebcamCatalog.Camera] {
        cameras.filter { $0.isEnabled ?? true }
    }

    /// "A13 : Autoroute de la Sarre".
    public var title: String {
        "\(code) : \(name)"
    }

    public var menuSymbol: String {
        symbol ?? "road.lanes"
    }
}

extension WebcamCatalog.Camera {
    /// The app's camera model, as the screens and analysis use it.
    public func webcam(defaultRefresh: TimeInterval? = nil) -> Webcam {
        Webcam(
            id: id,
            place: place,
            direction: direction.map { "direction \($0)" } ?? "",
            imageURL: imageURL,
            refreshInterval: refreshInterval ?? defaultRefresh
        )
    }
}
