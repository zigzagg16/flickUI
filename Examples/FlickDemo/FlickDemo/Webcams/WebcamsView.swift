import flickUI
import SwiftUI
import UIKit

/// The UserDefaults key of whether detected vehicles are drawn over the picture.
private let showsVehiclesKey = "showsVehicleDetections"

/// What the side menu shows: the motorway's live stream, its traffic map, then its cameras.
enum WebcamFeed: Identifiable, Hashable {
    case live
    case map
    case camera(Webcam)

    static let liveID = "live"
    static let mapID = "map"

    var id: String {
        switch self {
        case .live: Self.liveID
        case .map: Self.mapID
        case let .camera(camera): camera.id
        }
    }

    var title: String {
        switch self {
        case .live: "Live stream"
        case .map: "Traffic map"
        case let .camera(camera): camera.title
        }
    }

    var symbol: String {
        switch self {
        case .live: "play.tv.fill"
        case .map: "map.fill"
        case let .camera(camera): camera.symbol
        }
    }
}

/// Live motorway webcams from cita.lu. Two nested menus, one per side: the right
/// edge switches between the live stream and the cameras, the left edge switches motorways.
struct WebcamsView: View {
    /// A camera to show, from a widget.
    var link: WebcamLink?

    @State private var motorway = Motorway.a13.id
    /// A camera to show once its motorway is selected.
    @State private var requestedFeed: [Motorway: String] = [:]
    @State private var feedID = WebcamFeed.liveID
    @State private var pages: [Motorway: WebcamPage] = [:]
    @State private var loadError: String?
    /// Contained by default, so the camera stays visible around the menu.
    @State private var background = BackgroundChoice.panel
    @State private var monitor = RoadMonitor()

    init(link: WebcamLink? = nil) {
        self.link = link
    }

    private var current: Motorway {
        Motorway(rawValue: motorway) ?? .a13
    }

    private var cameras: [Webcam] {
        pages[current]?.cameras ?? []
    }

    /// The live stream and map are always there, so the menu works before the cameras load.
    private var feeds: [WebcamFeed] {
        [.live, .map] + cameras.map(WebcamFeed.camera)
    }

    private var feed: WebcamFeed {
        feeds.first { $0.id == feedID } ?? .live
    }

    var body: some View {
        WebcamScreen(
            motorway: current,
            title: pages[current]?.title ?? current.title,
            feed: feed,
            position: cameraPosition,
            report: currentReport,
            error: loadError,
            background: $background
        ) {
            Task { await load(current) }
        }
        .environment(monitor)
        .flickMenu(feeds, selection: $feedID, edges: .trailing, title: \.title, systemImage: { symbol(for: $0) })
        .flickMenuHome(.trailing, position: 0.4)
        .flickMenu(Motorway.allCases, selection: $motorway, edges: .leading, title: \.title, systemImage: \.symbol)
        .flickMenuHome(.leading, position: 0.4)
        .flickMenuIndicatorStyle(.morphing(.liquid, tint: .yellow), edges: .leading)
        .flickMenuBackground(DemoBackgroundStyle(choice: background))
        .onChange(of: motorway) {
            if let requested = requestedFeed.removeValue(forKey: current) {
                feedID = requested
            } else if feedID != WebcamFeed.liveID {
                // Stay on the live stream; otherwise start at the new motorway's first camera.
                feedID = pages[current]?.cameras.first?.id ?? WebcamFeed.liveID
            }
        }
        .onChange(of: link, initial: true) { _, link in
            guard let link else { return }
            if link.motorway == current {
                feedID = link.cameraID
            } else {
                requestedFeed[link.motorway] = link.cameraID
                motorway = link.motorway.id
            }
        }
        .task(id: motorway) {
            await load(current)
        }
        .task(id: cameras) {
            await monitor.watch(cameras)
        }
        .task {
            await monitor.restore()
        }
    }

    private var currentReport: RoadReport? {
        guard case let .camera(camera) = feed else { return nil }
        return monitor.report(for: camera)
    }

    /// A camera's symbol in the menu shows its situation when something stands out.
    private func symbol(for feed: WebcamFeed) -> String {
        if case let .camera(camera) = feed, let symbol = monitor.report(for: camera)?.symbol {
            return symbol
        }
        return feed.symbol
    }

    /// The camera's place among the cameras, 1-based, and their number.
    private var cameraPosition: (index: Int, count: Int)? {
        guard case let .camera(camera) = feed, let index = cameras.firstIndex(of: camera) else { return nil }
        return (index: index + 1, count: cameras.count)
    }

    private func load(_ motorway: Motorway) async {
        loadError = nil
        do {
            let page = try await CitaWebcams.page(for: motorway)
            pages[motorway] = page
            if motorway == current, !feeds.contains(where: { $0.id == feedID }) {
                feedID = page.cameras.first?.id ?? WebcamFeed.liveID
            }
        } catch {
            // A cached page stays usable; only a motorway without cameras shows the error.
            if !Task.isCancelled, pages[motorway] == nil {
                loadError = error.localizedDescription
            }
        }
    }
}

struct WebcamScreen: View {
    let motorway: Motorway
    let title: String
    let feed: WebcamFeed
    let position: (index: Int, count: Int)?
    let report: RoadReport?
    let error: String?
    @Binding var background: BackgroundChoice
    let retry: () -> Void
    @Environment(RoadMonitor.self) private var monitor
    @AppStorage(showsVehiclesKey) private var showsVehicles = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch feed {
            case .live:
                LiveStreamView(motorway: motorway)
            case .map:
                // Not a camera: shown as is, without analysis.
                WebcamImage(
                    camera: Webcam(id: "map-\(motorway.rawValue)", place: "Traffic map", direction: "", imageURL: motorway.trafficMapURL),
                    analyzes: false
                )
            case let .camera(camera):
                WebcamImage(camera: camera)
            }
        }
        .overlay(alignment: .top) {
            header
        }
        .foregroundStyle(.white)
        .tint(.white)
    }

    private var detectsVehicles: Binding<Bool> {
        Binding {
            monitor.detectsVehicles || monitor.detector == .downloading
        } set: { isOn in
            Task { await monitor.setDetectsVehicles(isOn) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            AppSwitcher()
                .labelStyle(.iconOnly)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                switch feed {
                case .live:
                    Text("Live stream")
                        .font(.title2.bold())
                case .map:
                    Text("Traffic map")
                        .font(.title2.bold())
                    Text("cita.lu")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                case let .camera(camera):
                    Text(camera.place)
                        .font(.title2.bold())
                    Text(camera.direction)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    if let report, !report.conditions.isEmpty {
                        RoadReportBadge(report: report)
                            .padding(.top, 4)
                    }
                }
                if let error {
                    Button("Cameras unavailable. Retry", systemImage: "arrow.clockwise", action: retry)
                        .font(.footnote)
                        .accessibilityHint(error)
                }
                switch monitor.detector {
                case .downloading:
                    Label("Downloading the vehicle model…", systemImage: "arrow.down.circle")
                        .font(.footnote)
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                case .off, .on:
                    EmptyView()
                }
            }
            Spacer()
            Menu {
                Section("Analysis") {
                    Toggle("Detect Vehicles", systemImage: "car.fill", isOn: detectsVehicles)
                    Toggle("Show Detections", systemImage: "rectangle.dashed", isOn: $showsVehicles)
                        .disabled(!monitor.detectsVehicles)
                }
                Picker("Menu Background", systemImage: "paintbrush.fill", selection: $background) {
                    ForEach(BackgroundChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } label: {
                Label("Options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
            if feed == .live {
                Text("LIVE")
                    .font(.footnote.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.red, in: Capsule())
            } else if let position {
                Text("\(position.index)/\(position.count)")
                    .font(.footnote.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding()
        .background {
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .animation(.smooth, value: feed)
    }
}

/// A camera's still image, reloaded every 30 seconds while it is shown.
struct WebcamImage: View {
    let camera: Webcam
    /// Whether the road monitor reads the picture.
    var analyzes = true

    @State private var image: UIImage?
    /// The camera `image` belongs to; the previous camera's image stays, dimmed, until the next one loads.
    @State private var imageCameraID: String?
    @State private var updated: Date?
    @State private var failed = false
    @Environment(RoadMonitor.self) private var monitor
    @AppStorage(showsVehiclesKey) private var showsVehicles = true

    private static let refreshInterval = Duration.seconds(30)

    private var isCurrent: Bool {
        imageCameraID == camera.id
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        if isCurrent, analyzes, showsVehicles, let report = monitor.report(for: camera) {
                            VehicleBoxes(boxes: report.vehicleBoxes)
                        }
                    }
                    .opacity(isCurrent ? 1 : 0.4)
            }
            if !isCurrent && !failed {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            status
        }
        .task(id: camera) {
            await refresh()
        }
    }

    @ViewBuilder
    private var status: some View {
        if failed {
            Label("Image unavailable", systemImage: "exclamationmark.triangle.fill")
                .statusCapsule()
        } else if isCurrent, let updated {
            Label {
                Text(updated, format: .dateTime.hour().minute().second())
            } icon: {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
            .statusCapsule()
        }
    }

    private func refresh() async {
        failed = false
        while !Task.isCancelled {
            do {
                let data = try await CitaWebcams.image(of: camera)
                if let loaded = UIImage(data: data) {
                    withAnimation(.smooth) {
                        image = loaded
                        imageCameraID = camera.id
                    }
                    updated = .now
                    failed = false
                    if analyzes { await monitor.record(data, for: camera) }
                } else {
                    failed = !isCurrent
                }
            } catch {
                if !Task.isCancelled {
                    failed = !isCurrent
                    if analyzes { monitor.recordFailure(for: camera) }
                }
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}

/// The detected vehicles, drawn over the picture.
struct VehicleBoxes: View {
    let boxes: [CGRect]

    var body: some View {
        GeometryReader { proxy in
            ForEach(boxes.indices, id: \.self) { index in
                let box = boxes[index]
                Rectangle()
                    .strokeBorder(.yellow, lineWidth: 1.5)
                    .frame(width: box.width * proxy.size.width, height: box.height * proxy.size.height)
                    .offset(x: box.minX * proxy.size.width, y: box.minY * proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The conditions read from a camera's picture.
struct RoadReportBadge: View {
    let report: RoadReport

    var body: some View {
        Label {
            Text(report.conditions.joined(separator: " · "))
        } icon: {
            Image(systemName: report.symbol ?? "eye.fill")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel(Text("Estimated from the picture: \(report.conditions.joined(separator: ", "))"))
    }
}

private extension View {
    func statusCapsule() -> some View {
        font(.footnote.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding()
    }
}

#Preview {
    WebcamsView()
}
