import AppIntents
import Foundation

/// A camera, as the widget's configuration offers it.
struct WebcamEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Webcam"
    static let defaultQuery = WebcamQuery()

    /// "a13/13034".
    let id: String
    let motorway: Motorway
    let cameraID: String
    let place: String
    let direction: String
    let imageURL: URL

    /// Shown until a camera is chosen: the first camera of the A13.
    static let fallback = WebcamEntity(motorway: .a13, cameraID: "13034", place: "Sanem", direction: "direction Pétange")

    init(motorway: Motorway, cameraID: String, place: String, direction: String, imageURL: URL? = nil) {
        id = "\(motorway.rawValue)/\(cameraID)"
        self.motorway = motorway
        self.cameraID = cameraID
        self.place = place
        self.direction = direction
        self.imageURL = imageURL ?? Webcam.defaultImageURL(forCamera: cameraID)
    }

    init(_ camera: Webcam, on motorway: Motorway) {
        self.init(motorway: motorway, cameraID: camera.id, place: camera.place, direction: camera.direction, imageURL: camera.imageURL)
    }

    var webcam: Webcam {
        Webcam(id: cameraID, place: place, direction: direction, imageURL: imageURL)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(place)", subtitle: "\(motorway.code) · \(direction)")
    }
}

/// Lists the cameras of every motorway from cita.lu.
struct WebcamQuery: EntityStringQuery {
    func entities(for identifiers: [WebcamEntity.ID]) async throws -> [WebcamEntity] {
        let wanted = identifiers.compactMap(Self.parse)
        let pages = await Self.pages(for: Set(wanted.map(\.motorway)))
        return wanted.map { motorway, cameraID in
            if let camera = pages[motorway]?.cameras.first(where: { $0.id == cameraID }) {
                return WebcamEntity(camera, on: motorway)
            }
            return WebcamEntity(motorway: motorway, cameraID: cameraID, place: "Camera \(cameraID)", direction: motorway.title)
        }
    }

    func entities(matching string: String) async throws -> [WebcamEntity] {
        try await suggestedEntities().filter { camera in
            camera.place.localizedCaseInsensitiveContains(string)
                || camera.direction.localizedCaseInsensitiveContains(string)
                || camera.motorway.code.localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [WebcamEntity] {
        let pages = await Self.pages(for: Set(Motorway.allCases))
        return Motorway.allCases.flatMap { motorway in
            (pages[motorway]?.cameras ?? []).map { WebcamEntity($0, on: motorway) }
        }
    }

    func defaultResult() async -> WebcamEntity? {
        .fallback
    }

    private static func parse(_ id: String) -> (motorway: Motorway, cameraID: String)? {
        let parts = id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let motorway = Motorway(rawValue: parts[0]) else { return nil }
        return (motorway, parts[1])
    }

    /// The pages that load; the others are left out.
    private static func pages(for motorways: Set<Motorway>) async -> [Motorway: WebcamPage] {
        await withTaskGroup(of: (Motorway, WebcamPage?).self) { group in
            for motorway in motorways {
                group.addTask { (motorway, try? await CitaWebcams.page(for: motorway)) }
            }
            var pages: [Motorway: WebcamPage] = [:]
            for await (motorway, page) in group {
                pages[motorway] = page
            }
            return pages
        }
    }
}

struct SelectWebcamIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Webcam"
    static let description = IntentDescription("Choose a motorway camera from cita.lu.")

    @Parameter(title: "Camera")
    var camera: WebcamEntity?
}
