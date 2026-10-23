import Foundation

/// A link to a camera in the app, such as `flickdemo://webcams/a13/13034`.
/// Widgets open the app with it.
public struct WebcamLink: Hashable, Sendable {
    public static let scheme = "flickdemo"

    /// The motorway's catalog identifier.
    public let motorwayID: String
    /// A camera number, or `WebcamLink.live` for the motorway's live stream.
    public let cameraID: String
    /// Makes every opening of a link a change, even of the same camera.
    public var token = UUID()

    public static let live = "live"

    public init(motorwayID: String, cameraID: String) {
        self.motorwayID = motorwayID
        self.cameraID = cameraID
    }

    public init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard url.scheme == Self.scheme, url.host() == "webcams",
              let motorwayID = parts.first
        else { return nil }
        self.init(motorwayID: motorwayID, cameraID: parts.count > 1 ? parts[1] : Self.live)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "webcams"
        components.path = "/\(motorwayID)/\(cameraID)"
        return components.url ?? URL(filePath: "/")
    }
}
