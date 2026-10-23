import MapKit
import SwiftUI
import WebcamsCore

/// The road operator's live traffic: incidents and roadworks, and the travel times on
/// the overhead signs, reloaded while the webcams are on screen.
@Observable
@MainActor
final class TrafficMonitor {
    private(set) var events: [TrafficEvent] = []
    private(set) var signs: [TravelTimeSign] = []
    private(set) var updated: Date?

    /// For catalogs without their own interval.
    private static let defaultRefreshInterval: TimeInterval = 120

    /// Reloads the feeds the catalog names until cancelled. A feed that fails keeps
    /// what it read before.
    func watch(_ settings: WebcamCatalog.Settings) async {
        guard settings.trafficEventsURL != nil || settings.travelTimesURL != nil else { return }
        while !Task.isCancelled {
            async let events = Self.events(from: settings.trafficEventsURL)
            async let signs = Self.signs(from: settings.travelTimesURL)
            let (loadedEvents, loadedSigns) = await (events, signs)
            if let loadedEvents { self.events = loadedEvents }
            if let loadedSigns { self.signs = loadedSigns }
            if loadedEvents != nil || loadedSigns != nil { updated = .now }
            try? await Task.sleep(for: .seconds(settings.trafficRefreshInterval ?? Self.defaultRefreshInterval))
        }
    }

    private nonisolated static func events(from url: URL?) async -> [TrafficEvent]? {
        guard let url else { return nil }
        return try? await CitaTraffic.events(from: url)
    }

    private nonisolated static func signs(from url: URL?) async -> [TravelTimeSign]? {
        guard let url else { return nil }
        return try? await CitaTraffic.travelTimes(from: url)
    }

    /// The events under way on a motorway, most important first.
    func events(on motorway: Motorway) -> [TrafficEvent] {
        Self.sorted(motorway.events(in: events))
    }

    /// The events under way on the camera's motorway near it, most important first.
    func events(near camera: Webcam, on motorway: Motorway) -> [TrafficEvent] {
        guard let coordinate = camera.coordinate else { return [] }
        return Self.sorted(motorway.events(in: events).near(coordinate))
    }

    func sign(near camera: Webcam) -> TravelTimeSign? {
        camera.coordinate.flatMap { signs.nearest(to: $0) }
    }

    private static func sorted(_ events: [TrafficEvent]) -> [TrafficEvent] {
        events.filter { $0.isActive() }.sorted { $0.importance > $1.importance }
    }
}

extension TrafficEvent {
    /// Red for a closure or an accident, orange for what happened on the road, yellow otherwise.
    var tint: Color {
        if closesRoad || kind == .accident { return .red }
        switch kind {
        case .breakdown, .obstruction, .congestion, .roadConditions: return .orange
        default: return .yellow
        }
    }

    /// "Roadworks · Road closed".
    var headline: String {
        [title, lanesSummary].compactMap(\.self).joined(separator: " · ")
    }
}

/// The incidents near a camera, or on a motorway: the most important one, and how
/// many more. Tapping it lists them all.
struct TrafficEventsBadge: View {
    let events: [TrafficEvent]
    /// "nearby", or "on A13".
    let scope: String
    @State private var showsList = false

    var body: some View {
        if let first = events.first {
            Button {
                showsList = true
            } label: {
                Label {
                    Text(events.count == 1 ? first.headline : "\(first.headline) +\(events.count - 1)")
                } icon: {
                    Image(systemName: first.symbol)
                        .foregroundStyle(first.tint)
                }
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(events.count) traffic events \(scope)"))
            .sheet(isPresented: $showsList) {
                TrafficEventsList(events: events, title: "Traffic \(scope)")
            }
        }
    }
}

/// Every detail the operator gives about some events.
struct TrafficEventsList: View {
    let events: [TrafficEvent]
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(events) { event in
                TrafficEventRow(event: event)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        // Not the white of the screen it's shown over.
        .foregroundStyle(.primary)
        .tint(.accentColor)
        .presentationDetents([.medium, .large])
    }
}

struct TrafficEventRow: View {
    let event: TrafficEvent

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.headline)
                    .font(.headline)
                if let destination = event.destination {
                    Text([event.road, destination].compactMap(\.self).joined(separator: " · "))
                }
                if let comment = event.comment {
                    Text(comment)
                        .italic()
                }
                Group {
                    if let place = event.place {
                        Text(event.length.map { "\(place) · \(Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))" } ?? place)
                    }
                    if let start = event.startTime {
                        if let end = event.endTime {
                            Text("\(start, format: .dateTime.day().month().hour().minute()) – \(end, format: .dateTime.day().month().hour().minute())")
                        } else {
                            Text("Since \(start, format: .relative(presentation: .named))")
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: event.symbol)
                .foregroundStyle(event.tint)
        }
    }
}

/// The overhead sign nearest a camera, with its travel times.
struct TravelTimesCard: View {
    let sign: TravelTimeSign

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label(sign.name, systemImage: "signpost.right.fill")
                .font(.caption2.weight(.semibold))
                .opacity(0.8)
            ForEach(sign.destinations, id: \.name) { destination in
                HStack(spacing: 8) {
                    Text(destination.name)
                    Text(destination.minutes.map { "\($0) min" } ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(.yellow)
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Travel times from \(sign.name)"))
    }
}

/// A motorway on a map: its cameras pointing the way they look, the incidents on it,
/// and the travel time signs. Tapping a camera shows it.
struct TrafficMapView: View {
    let motorway: Motorway
    let cameras: [Webcam]
    let events: [TrafficEvent]
    let signs: [TravelTimeSign]
    let showCamera: (Webcam) -> Void
    @State private var selectedEvent: TrafficEvent?
    @State private var selectedSign: TravelTimeSign?

    /// The signs along the motorway, so the map frames the motorway rather than the country.
    private var nearbySigns: [TravelTimeSign] {
        let coordinates = cameras.compactMap(\.coordinate)
        return signs.filter { sign in coordinates.contains { $0.distance(to: sign.coordinate) < 3000 } }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(cameras.filter { $0.coordinate != nil }) { camera in
                Annotation(camera.title, coordinate: camera.coordinate!.location, anchor: .center) {
                    Button {
                        showCamera(camera)
                    } label: {
                        Image(systemName: "location.north.fill")
                            .font(.caption)
                            .rotationEffect(.degrees(camera.heading ?? 0))
                            .foregroundStyle(.black)
                            .padding(5)
                            .background(.white, in: Circle())
                            .shadow(radius: 1)
                    }
                    .accessibilityLabel(Text("Camera \(camera.title)"))
                }
                .annotationTitles(.hidden)
            }
            ForEach(nearbySigns) { sign in
                Annotation(sign.name, coordinate: sign.coordinate.location) {
                    Button {
                        selectedSign = sign
                    } label: {
                        Image(systemName: "signpost.right.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.blue, in: Circle())
                    }
                    .accessibilityLabel(Text("Travel times from \(sign.name)"))
                }
            }
            // Last, so they are drawn over the cameras.
            ForEach(events.filter { $0.coordinate != nil }) { event in
                Annotation(event.title, coordinate: event.coordinate!.location) {
                    Button {
                        selectedEvent = event
                    } label: {
                        Image(systemName: event.symbol)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(event.tint, in: Circle())
                    }
                    .accessibilityLabel(Text(event.headline))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: true))
        .sheet(item: $selectedEvent) { event in
            TrafficEventsList(events: [event], title: event.road ?? motorway.code)
        }
        .sheet(item: $selectedSign) { sign in
            TravelTimesCard(sign: sign)
                .foregroundStyle(.white)
                .padding()
                .presentationDetents([.height(160)])
                .presentationBackground(.black)
        }
    }
}

extension WebcamCatalog.Coordinate {
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
