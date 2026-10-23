import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One camera on a motorway.
public struct Webcam: Identifiable, Hashable, Sendable {
    /// The camera number, as in `cccam_13034.jpg`.
    public let id: String
    public let place: String
    /// Where the camera looks, for example "direction Pétange".
    public let direction: String
    /// The still image, without a cache-busting query.
    public let imageURL: URL
    /// How often the picture is reloaded, in seconds; `nil` for the app's default.
    public var refreshInterval: TimeInterval?

    public init(id: String, place: String, direction: String, imageURL: URL, refreshInterval: TimeInterval? = nil) {
        self.id = id
        self.place = place
        self.direction = direction
        self.imageURL = imageURL
        self.refreshInterval = refreshInterval
    }

    /// "Sanem → Pétange".
    public var title: String {
        let target = direction.replacingOccurrences(of: "direction ", with: "")
        return target.isEmpty ? place : "\(place) → \(target)"
    }

    public var symbol: String {
        place.localizedCaseInsensitiveContains("tunnel") ? "mountain.2.fill" : "web.camera.fill"
    }

    /// The image URL with a timestamp, the way cita.lu refreshes its images.
    public func imageURL(at date: Date) -> URL {
        imageURL.appending(queryItems: [URLQueryItem(name: "t", value: String(Int(date.timeIntervalSince1970)))])
    }
}

/// The cameras of one motorway, as listed on its cita.lu webcam page.
public struct WebcamPage: Sendable {
    /// "A13 : Autoroute de la Sarre".
    public var title: String?
    public var cameras: [Webcam]

    public init(title: String? = nil, cameras: [Webcam]) {
        self.title = title
        self.cameras = cameras
    }
}

/// Loads camera pictures, and reads cameras from a cita.lu webcam page for
/// motorways whose cameras the catalog doesn't list.
///
/// cita.lu has no API for its webcams: each motorway page is server-rendered HTML
/// listing `<figure id="cam-…">` items, each with the JPEG the site reloads with a
/// timestamp query. Which pages to read comes from the ``WebcamCatalog``.
public enum CitaWebcams {
    public enum LoadError: LocalizedError {
        case noCameras

        public var errorDescription: String? {
            "No cameras found on the page."
        }
    }

    /// The cameras listed on a webcam page.
    public static func page(at url: URL) async throws -> WebcamPage {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let html = String(decoding: data, as: UTF8.self)
        let page = parse(html, baseURL: url)
        guard !page.cameras.isEmpty else { throw LoadError.noCameras }
        return page
    }

    public static func image(of camera: Webcam, at date: Date = .now) async throws -> Data {
        var request = URLRequest(url: camera.imageURL(at: date))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Parsing

    public static func parse(_ html: String, baseURL: URL) -> WebcamPage {
        let title = html.firstMatch(of: #/<h2>\s*(A\d+\s*:[^<]+)</h2>/#).map { decode(String($0.1)) }

        let figure = #/<figure id="cam-([^"]+)"[\s\S]*?data-origin="([^"]+)"[\s\S]*?<figcaption>([\s\S]*?)</figcaption>/#
        var seen = Set<String>()
        let cameras = html.matches(of: figure).compactMap { match -> Webcam? in
            let id = String(match.1)
            guard seen.insert(id).inserted,
                  let imageURL = URL(string: decode(String(match.2)), relativeTo: baseURL)?.absoluteURL
            else { return nil }
            // "Sanem: <span>direction Pétange</span>"
            let caption = decode(String(match.3).replacing(#/<[^>]+>/#, with: ""))
            let parts = caption.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Webcam(
                id: id,
                place: parts.first ?? "Camera \(id)",
                direction: parts.count > 1 ? parts[1] : "",
                imageURL: imageURL
            )
        }
        return WebcamPage(title: title, cameras: cameras)
    }

    /// Decodes the few HTML entities the pages use.
    public static func decode(_ text: String) -> String {
        let named = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let numeric = named.replacing(#/&#(\d+);/#) { match in
            UInt32(match.1).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? String(match.0)
        }
        return numeric
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
