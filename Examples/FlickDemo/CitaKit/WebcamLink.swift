import Foundation

/// A link to a camera in the app, such as `flickdemo://webcams/a13/13034`.
/// Widgets open the app with it.
struct WebcamLink: Hashable, Sendable {
    static let scheme = "flickdemo"

    /// The motorway's catalog identifier.
    let motorwayID: String
    /// A camera number, or `WebcamLink.live` for the motorway's live stream.
    let cameraID: String
    /// Makes every opening of a link a change, even of the same camera.
    var token = UUID()

    static let live = "live"

    init(motorwayID: String, cameraID: String) {
        self.motorwayID = motorwayID
        self.cameraID = cameraID
    }

    init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.scheme == Self.scheme, url.host() == "webcams",
              let motorwayID = parts.first
        else { return nil }
        self.init(motorwayID: motorwayID, cameraID: parts.count > 1 ? parts[1] : Self.live)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "webcams"
        components.path = "/\(motorwayID)/\(cameraID)"
        return components.url ?? URL(filePath: "/")
    }
}
