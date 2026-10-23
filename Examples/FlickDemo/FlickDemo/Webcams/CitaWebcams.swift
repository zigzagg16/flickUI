import Foundation

/// A Luxembourg motorway with webcams on cita.lu.
enum Motorway: String, CaseIterable, Identifiable {
    case a1, a3, a4, a6, a7, a13

    var id: String { rawValue }

    var code: String { rawValue.uppercased() }

    /// A short name for the menu. The page's own title replaces it once loaded.
    var title: String {
        switch self {
        case .a1: "A1 Trèves"
        case .a3: "A3 Dudelange"
        case .a4: "A4 Esch"
        case .a6: "A6 Arlon"
        case .a7: "A7 Nord"
        case .a13: "A13 Sarre"
        }
    }

    var symbol: String {
        "\(rawValue.dropFirst()).circle.fill"
    }

    var pageURL: URL {
        CitaWebcams.baseURL.appending(path: "fr/webcam/\(rawValue).html")
    }

    var liveStreamPageURL: URL {
        CitaWebcams.baseURL.appending(path: "fr/live-stream/\(rawValue).html")
    }

    /// The HLS stream the live-stream page plays, following the pattern the pages use.
    var defaultLiveStreamURL: URL {
        URL(string: "https://live-edge.rtl.lu/cita/cita_\(rawValue)/playlist.m3u8")!
    }
}

/// One camera on a motorway.
struct Webcam: Identifiable, Hashable, Sendable {
    /// The camera number, as in `cccam_13034.jpg`.
    let id: String
    let place: String
    /// Where the camera looks, for example "direction Pétange".
    let direction: String
    /// The still image, without a cache-busting query.
    let imageURL: URL

    /// "Sanem → Pétange".
    var title: String {
        let target = direction.replacingOccurrences(of: "direction ", with: "")
        return target.isEmpty ? place : "\(place) → \(target)"
    }

    var symbol: String {
        place.localizedCaseInsensitiveContains("tunnel") ? "mountain.2.fill" : "web.camera.fill"
    }

    /// The image URL with a timestamp, the way cita.lu refreshes its images.
    func imageURL(at date: Date) -> URL {
        imageURL.appending(queryItems: [URLQueryItem(name: "t", value: String(Int(date.timeIntervalSince1970)))])
    }
}

/// The cameras of one motorway, as listed on its cita.lu webcam page.
struct WebcamPage: Sendable {
    /// "A13 : Autoroute de la Sarre".
    var title: String?
    var cameras: [Webcam]
}

/// Reads the cameras from cita.lu.
///
/// cita.lu has no API for its webcams: each motorway page is server-rendered HTML
/// listing `<figure id="cam-…">` items, and every camera is a JPEG at
/// `/info_trafic/cameras/images/cccam_<id>.jpg` that the site reloads with a
/// timestamp query. So the page is fetched once to learn the cameras, and the
/// images are then fetched directly. Each motorway also has one HLS live stream,
/// linked from its live-stream page.
enum CitaWebcams {
    static let baseURL = URL(string: "https://www.cita.lu")!

    enum LoadError: LocalizedError {
        case noCameras

        var errorDescription: String? {
            "No cameras found on the page."
        }
    }

    static func page(for motorway: Motorway) async throws -> WebcamPage {
        var request = URLRequest(url: motorway.pageURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let html = String(decoding: data, as: UTF8.self)
        let page = parse(html, baseURL: motorway.pageURL)
        guard !page.cameras.isEmpty else { throw LoadError.noCameras }
        return page
    }

    /// The motorway's HLS live stream, as linked from its live-stream page.
    /// Falls back to the usual URL pattern if the page can't be read.
    static func liveStream(for motorway: Motorway) async -> URL {
        guard let data = try? await URLSession.shared.data(from: motorway.liveStreamPageURL).0,
              let match = String(decoding: data, as: UTF8.self).firstMatch(of: #/https://[^'"\s]+\.m3u8/#),
              let url = URL(string: String(match.0))
        else { return motorway.defaultLiveStreamURL }
        return url
    }

    static func image(of camera: Webcam, at date: Date = .now) async throws -> Data {
        var request = URLRequest(url: camera.imageURL(at: date))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Parsing

    static func parse(_ html: String, baseURL: URL) -> WebcamPage {
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
    static func decode(_ text: String) -> String {
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
