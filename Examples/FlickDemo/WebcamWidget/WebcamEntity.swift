import AppIntents
import Foundation
import WebcamsCore

/// A camera, as the widget's configuration offers it.
struct WebcamEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Webcam"
    static let defaultQuery = WebcamQuery()

    /// "a13/13034".
    let id: String
    let motorwayID: String
    /// The road number, such as "A13".
    let motorwayCode: String
    let cameraID: String
    let place: String
    let direction: String
    let imageURL: URL
    let refreshInterval: TimeInterval?
    let coordinate: WebcamCatalog.Coordinate?
    let heading: Double?

    init(_ camera: Webcam, on motorway: Motorway) {
        id = "\(motorway.id)/\(camera.id)"
        motorwayID = motorway.id
        motorwayCode = motorway.code
        cameraID = camera.id
        place = camera.place
        direction = camera.direction
        imageURL = camera.imageURL
        refreshInterval = camera.refreshInterval
        coordinate = camera.coordinate
        heading = camera.heading
    }

    /// Shown until a camera is chosen: the catalog's first camera.
    static var fallback: WebcamEntity? {
        let catalog = CatalogStore.current()
        for motorway in catalog.orderedMotorways {
            if let camera = motorway.enabledCameras.first {
                return WebcamEntity(catalog.webcam(for: camera), on: motorway)
            }
        }
        return nil
    }

    var webcam: Webcam {
        Webcam(
            id: cameraID, place: place, direction: direction, imageURL: imageURL, refreshInterval: refreshInterval,
            coordinate: coordinate, heading: heading
        )
    }

    var link: WebcamLink {
        WebcamLink(motorwayID: motorwayID, cameraID: cameraID)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(place)", subtitle: "\(motorwayCode) · \(direction)")
    }
}

/// Lists the cameras of every motorway in the catalog, reading the source's page for
/// motorways the catalog lists without cameras.
struct WebcamQuery: EntityStringQuery {
    func entities(for identifiers: [WebcamEntity.ID]) async throws -> [WebcamEntity] {
        let wanted = Set(identifiers)
        return await Self.allCameras().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [WebcamEntity] {
        await Self.allCameras().filter { camera in
            camera.place.localizedCaseInsensitiveContains(string)
                || camera.direction.localizedCaseInsensitiveContains(string)
                || camera.motorwayCode.localizedCaseInsensitiveContains(string)
        }
    }

    func suggestedEntities() async throws -> [WebcamEntity] {
        await Self.allCameras()
    }

    func defaultResult() async -> WebcamEntity? {
        .fallback
    }

    private static func allCameras() async -> [WebcamEntity] {
        let catalog = await CatalogStore.refreshed()
        let motorways = catalog.orderedMotorways
        let pages = await Self.pages(for: motorways.filter { $0.enabledCameras.isEmpty })
        return motorways.flatMap { motorway in
            let listed = motorway.enabledCameras.map(catalog.webcam(for:))
            let cameras = listed.isEmpty ? pages[motorway.id]?.cameras ?? [] : listed
            return cameras.map { WebcamEntity($0, on: motorway) }
        }
    }

    /// The pages that load, by motorway; the others are left out.
    private static func pages(for motorways: [Motorway]) async -> [String: WebcamPage] {
        await withTaskGroup(of: (String, WebcamPage?).self) { group in
            for motorway in motorways {
                guard let website = motorway.website else { continue }
                group.addTask { (motorway.id, try? await CitaWebcams.page(at: website)) }
            }
            var pages: [String: WebcamPage] = [:]
            for await (id, page) in group {
                pages[id] = page
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
