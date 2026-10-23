import SwiftUI
import WebcamsCore
import WidgetKit

@main
struct WebcamWidgetBundle: WidgetBundle {
    var body: some Widget {
        WebcamWidget()
    }
}

/// A cita.lu camera on the Home Screen. Widgets can't play video, so it shows the
/// camera's still image, which WidgetKit refreshes about every 15 minutes.
struct WebcamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WebcamWidget", intent: SelectWebcamIntent.self, provider: WebcamProvider()) { entry in
            WebcamWidgetView(entry: entry)
        }
        .configurationDisplayName("Motorway webcam")
        .description("A cita.lu camera, refreshed about every 15 minutes.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct WebcamEntry: TimelineEntry {
    let date: Date
    /// `nil` when the catalog has no camera to show.
    let camera: WebcamEntity?
    /// The JPEG, or `nil` if it couldn't be loaded.
    let imageData: Data?
    /// What the app last read from this camera, if recent.
    var report: RoadReport?
    /// The incidents near the camera on its motorway, most important first.
    var events: [TrafficEvent] = []
    /// The travel time sign nearest the camera.
    var sign: TravelTimeSign?
}

struct WebcamProvider: AppIntentTimelineProvider {
    /// WidgetKit decides when to refresh; this asks for no sooner than that.
    private static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> WebcamEntry {
        WebcamEntry(date: .now, camera: .fallback, imageData: nil)
    }

    func snapshot(for configuration: SelectWebcamIntent, in context: Context) async -> WebcamEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectWebcamIntent, in context: Context) async -> Timeline<WebcamEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(Self.refreshInterval)))
    }

    private func entry(for configuration: SelectWebcamIntent) async -> WebcamEntry {
        guard let camera = configuration.camera ?? .fallback else {
            return WebcamEntry(date: .now, camera: nil, imageData: nil)
        }
        let catalog = CatalogStore.current()
        async let data = try? await CitaWebcams.image(of: camera.webcam)
        async let events = Self.events(from: catalog.settings.trafficEventsURL)
        async let signs = Self.signs(from: catalog.settings.travelTimesURL)
        var entry = WebcamEntry(date: .now, camera: camera, imageData: await data, report: RoadReportStore.report(forCamera: camera.cameraID))
        if let coordinate = camera.coordinate {
            if let events = await events, let motorway = catalog.motorway(withID: camera.motorwayID) {
                entry.events = motorway.events(in: events).near(coordinate)
                    .filter { $0.isActive() }
                    .sorted { $0.importance > $1.importance }
            }
            entry.sign = await signs?.nearest(to: coordinate)
        }
        return entry
    }

    private static func events(from url: URL?) async -> [TrafficEvent]? {
        guard let url else { return nil }
        return try? await CitaTraffic.events(from: url)
    }

    private static func signs(from url: URL?) async -> [TravelTimeSign]? {
        guard let url else { return nil }
        return try? await CitaTraffic.travelTimes(from: url)
    }
}

struct WebcamWidgetView: View {
    let entry: WebcamEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let camera = entry.camera {
                content(camera)
                    .widgetURL(camera.link.url)
            } else {
                Text("No webcams")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) {
            background
        }
    }

    private func content(_ camera: WebcamEntity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(camera.motorwayCode)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.yellow, in: Capsule())
                    .foregroundStyle(.black)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2.monospacedDigit())
            }
            Spacer()
            if let event = entry.events.first {
                Label(entry.events.count == 1 ? event.title : "\(event.title) +\(entry.events.count - 1)", systemImage: event.symbol)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            if let report = entry.report, let condition = report.conditions.first {
                Label(condition, systemImage: report.symbol ?? "eye.fill")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            if family != .systemSmall, let sign = entry.sign {
                let times = sign.destinations.prefix(family == .systemLarge ? 3 : 2)
                    .map { "\($0.name) \($0.minutes.map { "\($0)′" } ?? "–")" }
                Label(times.joined(separator: " · "), systemImage: "signpost.right.fill")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            Text(camera.place)
                .font(family == .systemSmall ? .subheadline.bold() : .headline)
                .lineLimit(1)
            if family != .systemSmall {
                Text(camera.direction)
                    .font(.caption)
                    .lineLimit(1)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 3)
        .padding(12)
    }

    private var background: some View {
        ZStack {
            Color.black
            if let data = entry.imageData, let image = Picture.image(from: data) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "web.camera")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.4))
            }
            LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
    }
}

#Preview(as: .systemMedium) {
    WebcamWidget()
} timeline: {
    WebcamEntry(date: .now, camera: .fallback, imageData: nil)
}
