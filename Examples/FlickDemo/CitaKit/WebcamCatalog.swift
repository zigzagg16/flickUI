import Foundation

/// Everything the Webcams app shows, as a backend would describe it: the motorways,
/// their cameras, live streams and traffic maps, with every link.
///
/// Nothing here is tied to cita.lu: the backend can point at any source, rename
/// places, add or retire cameras and change refresh rates without an app update.
/// ``CatalogStore`` loads it; `catalog.json`, bundled with the app, is the catalog
/// until there is a backend.
struct WebcamCatalog: Codable, Hashable, Sendable {
    /// The format's version, so an older app can tell a catalog it doesn't understand.
    var version: Int
    /// When the backend built this catalog.
    var updatedAt: Date
    /// Who provides the pictures, shown in the app.
    var source: Source
    var motorways: [Motorway]
    /// Settings the backend can tune.
    var settings: Settings

    struct Source: Codable, Hashable, Sendable {
        var name: String
        var website: URL
        var attribution: String?
    }

    struct Motorway: Codable, Hashable, Sendable, Identifiable {
        /// A stable identifier, such as "a13".
        var id: String
        /// The road number, such as "A13".
        var code: String
        /// The full name, such as "Autoroute de la Sarre".
        var name: String
        /// A short name for the menu, such as "A13 Sarre".
        var shortName: String
        /// An SF Symbol for the menu.
        var symbol: String?
        /// The position in the menu; lower comes first.
        var order: Int?
        /// The source's own page, to open in a browser.
        var website: URL?
        var liveStream: LiveStream?
        var trafficMap: TrafficMap?
        var cameras: [Camera]
    }

    struct Camera: Codable, Hashable, Sendable, Identifiable {
        /// A stable identifier, unique across motorways, such as "13034".
        var id: String
        /// Where the camera is, such as "Sanem".
        var place: String
        /// Where it looks, such as "Pétange".
        var direction: String?
        /// The still picture, without cache-busting query.
        var imageURL: URL
        /// How often the source updates the picture, in seconds.
        var refreshInterval: TimeInterval?
        var coordinate: Coordinate?
        /// The road's direction of travel on each half of the picture, for the
        /// traffic estimate per carriageway.
        var carriageways: Carriageways?
        /// `false` to keep a camera listed but hidden, such as during works.
        var isEnabled: Bool?
    }

    struct LiveStream: Codable, Hashable, Sendable {
        /// An HLS playlist.
        var url: URL
        /// Whether to start muted, as the source does.
        var startsMuted: Bool?
    }

    struct TrafficMap: Codable, Hashable, Sendable {
        var imageURL: URL
        var refreshInterval: TimeInterval?
    }

    struct Coordinate: Codable, Hashable, Sendable {
        var latitude: Double
        var longitude: Double
    }

    struct Carriageways: Codable, Hashable, Sendable {
        /// Where traffic on the left half of the picture is heading, such as "Schengen".
        var left: String?
        var right: String?
    }

    struct Settings: Codable, Hashable, Sendable {
        /// How long the app may use this catalog before asking for a new one, in seconds.
        var catalogMaxAge: TimeInterval?
        /// The default picture refresh, for cameras without their own, in seconds.
        var imageRefreshInterval: TimeInterval?
        /// The vehicle detection model to download, a Core ML `.mlmodel`.
        var vehicleModelURL: URL?
    }
}

extension WebcamCatalog {
    /// The decoder for the backend's JSON: ISO 8601 dates, camel-case keys.
    static func decode(from data: Data) throws -> WebcamCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WebcamCatalog.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The motorways in menu order.
    var orderedMotorways: [Motorway] {
        motorways.enumerated()
            .sorted { ($0.element.order ?? $0.offset, $0.offset) < ($1.element.order ?? $1.offset, $1.offset) }
            .map(\.element)
    }
}

/// The motorways the app shows come from the catalog.
typealias Motorway = WebcamCatalog.Motorway

extension WebcamCatalog {
    /// A catalog with nothing in it, for when none can be read.
    static let empty = WebcamCatalog(
        version: 1,
        updatedAt: .distantPast,
        source: Source(name: "", website: URL(filePath: "/")),
        motorways: [],
        settings: Settings()
    )

    func motorway(withID id: String) -> Motorway? {
        motorways.first { $0.id == id }
    }

    /// The app's camera model for a catalog camera, with the default refresh applied.
    func webcam(for camera: Camera) -> Webcam {
        camera.webcam(defaultRefresh: settings.imageRefreshInterval)
    }
}

extension WebcamCatalog.Motorway {
    /// The cameras to show.
    var enabledCameras: [WebcamCatalog.Camera] {
        cameras.filter { $0.isEnabled ?? true }
    }

    /// "A13 : Autoroute de la Sarre".
    var title: String {
        "\(code) : \(name)"
    }

    var menuSymbol: String {
        symbol ?? "road.lanes"
    }
}

extension WebcamCatalog.Camera {
    /// The app's camera model, as the screens and analysis use it.
    func webcam(defaultRefresh: TimeInterval? = nil) -> Webcam {
        Webcam(
            id: id,
            place: place,
            direction: direction.map { "direction \($0)" } ?? "",
            imageURL: imageURL,
            refreshInterval: refreshInterval ?? defaultRefresh
        )
    }
}
