import SwiftUI
import WebcamsCore
import WidgetKit

// The widget's part of the live traffic. Like the app's `Traffic` folder, it is used in
// a few lines marked `// Traffic`, and goes with them.

/// The traffic around a camera when the widget refreshed.
struct WidgetTraffic {
    /// The incidents near the camera on its motorway, most important first.
    var events: [TrafficEvent]
    /// The travel time sign nearest the camera.
    var sign: TravelTimeSign?

    /// `nil` when the camera has no position or nothing could be read.
    init?(near camera: WebcamEntity) async {
        guard let coordinate = camera.coordinate else { return nil }
        async let events = try? CitaTraffic.events()
        async let signs = try? CitaTraffic.travelTimes()
        let motorway = CatalogStore.current().motorway(withID: camera.motorwayID)
        let (loadedEvents, loadedSigns) = await (events, signs)
        guard loadedEvents != nil || loadedSigns != nil else { return nil }
        self.events = motorway.map { $0.events(in: loadedEvents ?? []).near(coordinate) } ?? []
        self.events = self.events.filter { $0.isActive() }.sorted { $0.importance > $1.importance }
        sign = loadedSigns?.nearest(to: coordinate)
    }
}

/// The most important incident and, when there is room, the nearest sign's times.
struct WidgetTrafficLabels: View {
    let traffic: WidgetTraffic
    let family: WidgetFamily

    var body: some View {
        if let event = traffic.events.first {
            label(traffic.events.count == 1 ? event.title : "\(event.title) +\(traffic.events.count - 1)", systemImage: event.symbol)
        }
        if family != .systemSmall, let sign = traffic.sign {
            let times = sign.destinations.prefix(family == .systemLarge ? 3 : 2)
                .map { "\($0.name) \($0.minutes.map { "\($0)′" } ?? "–")" }
            label(times.joined(separator: " · "), systemImage: "signpost.right.fill")
                .monospacedDigit()
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.45), in: Capsule())
    }
}
