import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads the traffic the road operator publishes as open data on data.public.lu:
/// incidents and roadworks, and the travel times on the overhead signs.
///
/// Both change by the minute, so the app reads them live. Everything about traffic is
/// in this `Traffic` folder; the rest of the package doesn't use it, so it can be
/// deleted with the app's own `Traffic` folder.
public enum CitaTraffic {
    /// How often the app reloads the feeds, in seconds.
    public static let refreshInterval: TimeInterval = 120

    /// The DATEX II v3.6 situation records: incidents and roadworks on the motorways.
    public static let eventsURL = URL(string: "https://cita.lu/info_trafic/datex/situationrecord36")!
    /// The travel times on the overhead signs, as KML.
    public static let travelTimesURL = URL(string: "https://www.cita.lu/kml/temps_parcours.kml")!

    public static func events(from url: URL = eventsURL) async throws -> [TrafficEvent] {
        try parseEvents(await load(url))
    }

    public static func travelTimes(from url: URL = travelTimesURL) async throws -> [TravelTimeSign] {
        parseTravelTimes(String(decoding: try await load(url), as: UTF8.self))
    }

    private static func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: Parsing

    /// The events in a DATEX II v3 situation publication.
    public static func parseEvents(_ data: Data) throws -> [TrafficEvent] {
        let parser = XMLParser(data: data)
        let reader = SituationReader()
        parser.delegate = reader
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return reader.events
    }

    /// The signs in the travel times KML.
    ///
    /// Each sign is a placemark whose description lists its lines as
    /// `<span class='time'>LUX-SUD:	19min</span>`.
    public static func parseTravelTimes(_ kml: String) -> [TravelTimeSign] {
        let placemark = #/<Placemark[^>]*>\s*<name>([^<]*)</name>[\s\S]*?<description>([\s\S]*?)</description>[\s\S]*?<coordinates>\s*([-\d.]+),([-\d.]+)/#
        let line = #/<span class='time'>\s*([^:<]+?)\s*:\s*([^<]*?)\s*</span>/#
        return kml.matches(of: placemark).compactMap { match in
            guard let longitude = Double(match.3), let latitude = Double(match.4) else { return nil }
            let destinations = match.2.matches(of: line).map { line in
                TravelTimeSign.Destination(
                    name: CitaWebcams.decode(String(line.1)),
                    minutes: line.2.wholeMatch(of: #/(\d+)\s*min/#).flatMap { Int($0.1) }
                )
            }
            return TravelTimeSign(
                name: CitaWebcams.decode(String(match.1)),
                coordinate: WebcamCatalog.Coordinate(latitude: latitude, longitude: longitude),
                destinations: destinations
            )
        }
    }
}

/// Collects situation records from a DATEX II v3 feed, keeping the parts the app shows.
private final class SituationReader: NSObject, XMLParserDelegate {
    /// The elements holding a record type's own detail, such as `vehicleObstructionType`.
    static let causes: Set = [
        "roadMaintenanceType", "constructionWorkType", "vehicleObstructionType",
        "faultyEquipmentOrSystemType", "obstructionType", "abnormalTrafficType",
        "accidentType", "poorEnvironmentType", "roadOrCarriagewayOrLaneManagementType"
    ]

    var events: [TrafficEvent] = []
    private var event: TrafficEvent?
    /// The local names of the open elements.
    private var path: [String] = []
    private var text = ""
    private var latitude: Double?
    private var longitude: Double?
    private let dateFormatter = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let name = Self.localName(elementName)
        if name == "situationRecord", let id = attributes["id"] {
            event = TrafficEvent(id: id, type: Self.localName(attributes["xsi:type"] ?? ""))
            latitude = nil
            longitude = nil
        }
        path.append(name)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { path.removeLast() }
        guard var event else { return }
        let name = Self.localName(elementName)
        let value = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let parent = path.dropLast().last

        switch name {
        case "situationRecord":
            if let latitude, let longitude {
                event.coordinate = WebcamCatalog.Coordinate(latitude: latitude, longitude: longitude)
            }
            events.append(event)
            self.event = nil
            return
        case "roadName": event.road = event.road ?? value
        case "roadDestination": event.destination = event.destination ?? value
        case "value" where path.contains("locationDescription"): event.place = event.place ?? value
        case "value" where path.contains("generalPublicComment"): event.comment = event.comment ?? value
        case "overallStartTime": event.startTime = date(value)
        case "overallEndTime": event.endTime = date(value)
        case "situationRecordVersionTime": event.updatedAt = date(value)
        case "numberOfLanesRestricted": event.lanesRestricted = Int(value)
        case "numberOfOperationalLanes": event.operationalLanes = Int(value)
        case "lengthAffected": event.length = event.length ?? Double(value)
        case "latitude" where parent == "pointCoordinates": latitude = latitude ?? Double(value)
        case "longitude" where parent == "pointCoordinates": longitude = longitude ?? Double(value)
        case _ where Self.causes.contains(name): event.cause = event.cause ?? value
        default: break
        }
        self.event = event
    }

    /// "sit:situationRecord" becomes "situationRecord".
    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    /// Feed times look like 2026-10-23T19:52:34+02:00, sometimes with fractional seconds.
    private func date(_ value: String) -> Date? {
        dateFormatter.formatOptions = [.withInternetDateTime]
        if let date = dateFormatter.date(from: value) { return date }
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return dateFormatter.date(from: value)
    }
}
