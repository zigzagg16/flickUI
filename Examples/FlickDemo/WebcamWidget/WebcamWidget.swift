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
    var traffic: WidgetTraffic? // Traffic
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
        let data = try? await CitaWebcams.image(of: camera.webcam)
        return WebcamEntry(
            date: .now, camera: camera, imageData: data, report: RoadReportStore.report(forCamera: camera.cameraID),
            traffic: await WidgetTraffic(near: camera), // Traffic
        )
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
            entry.traffic.map { WidgetTrafficLabels(traffic: $0, family: family) } // Traffic
            if let report = entry.report, let condition = report.conditions.first {
                Label(condition, systemImage: report.symbol ?? "eye.fill")
                    .font(.caption2.weight(.semibold))
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
