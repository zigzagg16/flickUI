import flickUI
import SwiftUI
import UIKit

/// The UserDefaults key of whether detected vehicles are drawn over the picture.
private let showsVehiclesKey = "showsVehicleDetections"

/// What the side menu shows: a motorway's live stream, its traffic map and its
/// cameras, or the favourites, which can mix motorways.
enum WebcamFeed: Identifiable, Hashable {
    case live(motorwayID: String)
    case map(motorwayID: String)
    case camera(Webcam, motorwayID: String)

    var id: String {
        switch self {
        case let .live(motorwayID): "live-\(motorwayID)"
        case let .map(motorwayID): "map-\(motorwayID)"
        case let .camera(camera, _): camera.id
        }
    }

    var motorwayID: String {
        switch self {
        case let .live(motorwayID), let .map(motorwayID), let .camera(_, motorwayID): motorwayID
        }
    }

    /// The favourite this feed would be; the traffic map can't be one.
    var favourite: Favourite? {
        switch self {
        case let .live(motorwayID): Favourite(motorwayID: motorwayID, feed: .live)
        case .map: nil
        case let .camera(camera, motorwayID): Favourite(motorwayID: motorwayID, feed: .camera(camera.id))
        }
    }

    var title: String {
        switch self {
        case .live: "Live stream"
        case .map: "Traffic map"
        case let .camera(camera, _): camera.title
        }
    }

    var symbol: String {
        switch self {
        case .live: "play.tv.fill"
        case .map: "map.fill"
        case let .camera(camera, _): camera.symbol
        }
    }
}

/// The motorway menu: the favourites, when there are some, then the motorways.
enum MotorwayMenuItem: Identifiable {
    case favourites
    case motorway(Motorway)

    static let favouritesID = "favourites"

    var id: String {
        switch self {
        case .favourites: Self.favouritesID
        case let .motorway(motorway): motorway.id
        }
    }

    var title: String {
        switch self {
        case .favourites: "Favourites"
        case let .motorway(motorway): motorway.shortName
        }
    }

    var symbol: String {
        switch self {
        case .favourites: "star.fill"
        case let .motorway(motorway): motorway.menuSymbol
        }
    }
}

/// Live motorway webcams. Everything shown comes from the ``WebcamCatalog``. Two
/// nested menus, one per side: the left edge picks a motorway, or the favourites; the
/// right edge switches between the motorway's live stream, traffic map and cameras,
/// or between the favourites.
struct WebcamsView: View {
    /// A camera to show, from a widget.
    var link: WebcamLink?

    @State private var catalog = CatalogStore.current()
    /// The motorway menu's selection: a motorway, or the favourites.
    @AppStorage("webcamsMotorway") private var menuID = ""
    /// A feed to show once its motorway is selected.
    @State private var requestedFeed: [String: String] = [:]
    @State private var feedID = ""
    /// Cameras read from the source's pages, for motorways the catalog lists without cameras.
    @State private var pages: [String: WebcamPage] = [:]
    @State private var loadError: String?
    /// Contained by default, so the camera stays visible around the menu.
    @State private var background = BackgroundChoice.panel
    @State private var monitor = RoadMonitor()
    @State private var favourites = Favourites()
    @State private var showsFavouritesEditor = false

    init(link: WebcamLink? = nil) {
        self.link = link
    }

    private var motorways: [Motorway] {
        catalog.orderedMotorways
    }

    private var menuItems: [MotorwayMenuItem] {
        (favourites.items.isEmpty ? [] : [.favourites]) + motorways.map(MotorwayMenuItem.motorway)
    }

    private var showsFavourites: Bool {
        menuID == MotorwayMenuItem.favouritesID && !favourites.items.isEmpty
    }

    /// The motorway picked in the menu, or the first one.
    private var selectedMotorway: Motorway? {
        catalog.motorway(withID: menuID) ?? motorways.first
    }

    /// The catalog's cameras, or those read from the motorway's page when it lists none.
    private func cameras(of motorway: Motorway?) -> [Webcam] {
        guard let motorway else { return [] }
        let listed = motorway.enabledCameras.map(catalog.webcam(for:))
        return listed.isEmpty ? pages[motorway.id]?.cameras ?? [] : listed
    }

    private func feeds(of motorway: Motorway) -> [WebcamFeed] {
        var feeds: [WebcamFeed] = []
        if motorway.liveStream != nil { feeds.append(.live(motorwayID: motorway.id)) }
        if motorway.trafficMap != nil { feeds.append(.map(motorwayID: motorway.id)) }
        return feeds + cameras(of: motorway).map { .camera($0, motorwayID: motorway.id) }
    }

    /// A favourite's feed, once its motorway's cameras are known.
    private func feed(for favourite: Favourite) -> WebcamFeed? {
        guard let motorway = catalog.motorway(withID: favourite.motorwayID) else { return nil }
        switch favourite.feed {
        case .live:
            return motorway.liveStream == nil ? nil : .live(motorwayID: motorway.id)
        case let .camera(cameraID):
            return cameras(of: motorway).first { $0.id == cameraID }.map { .camera($0, motorwayID: motorway.id) }
        }
    }

    private var feeds: [WebcamFeed] {
        if showsFavourites {
            return favourites.items.compactMap(feed(for:))
        }
        return selectedMotorway.map(feeds(of:)) ?? []
    }

    private var feed: WebcamFeed? {
        feeds.first { $0.id == feedID } ?? feeds.first
    }

    /// The motorway of the feed on screen.
    private var current: Motorway? {
        feed.flatMap { catalog.motorway(withID: $0.motorwayID) } ?? selectedMotorway
    }

    /// The cameras the menu lists, which the road monitor watches.
    private var cameras: [Webcam] {
        feeds.compactMap { feed in
            if case let .camera(camera, _) = feed { return camera }
            return nil
        }
    }

    /// The motorways whose page must be read: the selected one, or the favourites'.
    private var motorwaysToLoad: [Motorway] {
        if showsFavourites {
            let ids = Set(favourites.items.map(\.motorwayID))
            return motorways.filter { ids.contains($0.id) }
        }
        return selectedMotorway.map { [$0] } ?? []
    }

    var body: some View {
        Group {
            if let current, let feed {
                WebcamScreen(
                    motorway: current,
                    title: showsFavourites ? "★ \(current.title)" : pages[current.id]?.title ?? current.title,
                    source: catalog.source.name,
                    feed: feed,
                    position: position,
                    report: currentReport,
                    error: loadError,
                    background: $background,
                    manageFavourites: { showsFavouritesEditor = true }
                ) {
                    Task { await load(current) }
                }
            } else {
                ContentUnavailableView("No Webcams", systemImage: "web.camera", description: Text(loadError ?? "The catalog lists no cameras."))
                    .overlay(alignment: .topLeading) {
                        AppSwitcher()
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .padding()
                    }
            }
        }
        .environment(monitor)
        .environment(favourites)
        .flickMenu(feeds, selection: $feedID, edges: .trailing, title: { menuTitle(for: $0) }, systemImage: { symbol(for: $0) })
        .flickMenuHome(.trailing, position: 0.4)
        .flickMenu(menuItems, selection: menuSelection, edges: .leading, title: \.title, systemImage: \.symbol)
        .flickMenuHome(.leading, position: 0.4)
        .flickMenuIndicatorStyle(.morphing(.liquid, tint: .yellow), edges: .leading)
        .flickMenuBackground(DemoBackgroundStyle(choice: background))
        .sheet(isPresented: $showsFavouritesEditor) {
            FavouritesEditor(motorways: motorways, name: name(of:), cameras: loadCameras(of:))
                .environment(favourites)
        }
        .onChange(of: menuID) {
            if showsFavourites {
                feedID = feeds.first?.id ?? ""
            } else if let requested = requestedFeed.removeValue(forKey: menuID) {
                feedID = requested
            } else if let motorway = selectedMotorway {
                // Stay on the live stream; otherwise start at the motorway's first camera.
                let motorwayFeeds = feeds(of: motorway)
                if feedID.hasPrefix("live-"), motorway.liveStream != nil {
                    feedID = WebcamFeed.live(motorwayID: motorway.id).id
                } else {
                    let firstCamera = motorwayFeeds.first { feed in
                        if case .camera = feed { return true }
                        return false
                    }
                    feedID = (firstCamera ?? motorwayFeeds.first)?.id ?? ""
                }
            }
        }
        .onChange(of: link, initial: true) { _, link in
            guard let link else { return }
            let id = link.cameraID == WebcamLink.live ? WebcamFeed.live(motorwayID: link.motorwayID).id : link.cameraID
            if showsFavourites, feeds.contains(where: { $0.id == id }) {
                feedID = id
            } else if menuID == link.motorwayID {
                feedID = id
            } else {
                requestedFeed[link.motorwayID] = id
                menuID = link.motorwayID
            }
        }
        .onChange(of: catalog.settings.vehicleModelURL, initial: true) { _, url in
            monitor.vehicleModelURL = url
        }
        .task {
            catalog = await CatalogStore.refreshed()
        }
        .task(id: motorwaysToLoad.map(\.id)) {
            for motorway in motorwaysToLoad {
                await load(motorway)
            }
        }
        .task(id: cameras) {
            await monitor.watch(cameras)
        }
        .task {
            await monitor.restore()
        }
    }

    /// The selection of the motorway menu, which always has an item selected.
    private var menuSelection: Binding<String> {
        Binding {
            showsFavourites ? MotorwayMenuItem.favouritesID : selectedMotorway?.id ?? menuID
        } set: { id in
            menuID = id
        }
    }

    /// Among favourites, a live stream is named after its motorway.
    private func menuTitle(for feed: WebcamFeed) -> String {
        guard showsFavourites, case let .live(motorwayID) = feed else { return feed.title }
        return "\(catalog.motorway(withID: motorwayID)?.code ?? motorwayID) live"
    }

    /// A favourite's name, such as "A13 · Sanem → Pétange".
    private func name(of favourite: Favourite) -> String {
        let motorway = catalog.motorway(withID: favourite.motorwayID)
        let code = motorway?.code ?? favourite.motorwayID
        switch favourite.feed {
        case .live:
            return "\(code) · Live stream"
        case let .camera(cameraID):
            let camera = cameras(of: motorway).first { $0.id == cameraID }
            return "\(code) · \(camera?.title ?? "Camera \(cameraID)")"
        }
    }

    /// A motorway's cameras, reading its page first if needed.
    private func loadCameras(of motorway: Motorway) async -> [Webcam] {
        if cameras(of: motorway).isEmpty {
            await load(motorway)
        }
        return cameras(of: motorway)
    }

    private var currentReport: RoadReport? {
        guard case let .camera(camera, _) = feed else { return nil }
        return monitor.report(for: camera)
    }

    /// A camera's symbol in the menu shows its situation when something stands out.
    private func symbol(for feed: WebcamFeed) -> String {
        if case let .camera(camera, _) = feed, let symbol = monitor.report(for: camera)?.symbol {
            return symbol
        }
        return feed.symbol
    }

    /// The feed's place in the menu, 1-based, and the number of cameras, or of favourites.
    private var position: (index: Int, count: Int)? {
        guard let feed else { return nil }
        if showsFavourites {
            guard let index = feeds.firstIndex(of: feed) else { return nil }
            return (index: index + 1, count: feeds.count)
        }
        guard case let .camera(camera, _) = feed, let index = cameras.firstIndex(of: camera) else { return nil }
        return (index: index + 1, count: cameras.count)
    }

    /// Reads the motorway's page when the catalog lists no cameras for it.
    private func load(_ motorway: Motorway) async {
        loadError = nil
        guard motorway.enabledCameras.isEmpty, let website = motorway.website else { return }
        do {
            let page = try await CitaWebcams.page(at: website)
            pages[motorway.id] = page
            if !feeds.contains(where: { $0.id == feedID }) {
                feedID = feeds.first?.id ?? ""
            }
        } catch {
            // A page read before stays usable; only a motorway without cameras shows the error.
            if !Task.isCancelled, pages[motorway.id] == nil {
                loadError = error.localizedDescription
            }
        }
    }
}

struct WebcamScreen: View {
    let motorway: Motorway
    let title: String
    /// Who provides the pictures.
    let source: String
    let feed: WebcamFeed
    let position: (index: Int, count: Int)?
    let report: RoadReport?
    let error: String?
    @Binding var background: BackgroundChoice
    let manageFavourites: () -> Void
    let retry: () -> Void
    @Environment(RoadMonitor.self) private var monitor
    @Environment(Favourites.self) private var favourites
    @AppStorage(showsVehiclesKey) private var showsVehicles = true
    @AppStorage("analyzesLiveMotion") private var analyzesLiveMotion = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch feed {
            case .live:
                LiveStreamView(motorway: motorway)
            case .map:
                if let map = motorway.trafficMap {
                    // Not a camera: shown as is, without analysis.
                    WebcamImage(
                        camera: Webcam(
                            id: "map-\(motorway.id)",
                            place: "Traffic map",
                            direction: "",
                            imageURL: map.imageURL,
                            refreshInterval: map.refreshInterval
                        ),
                        analyzes: false
                    )
                }
            case let .camera(camera, _):
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
            monitor.detectsVehicles || monitor.isDownloadingModel
        } set: { isOn in
            Task { await monitor.setDetectsVehicles(isOn) }
        }
    }

    /// The vehicle model's state: its name and size once on the device.
    private var modelStatus: String {
        switch monitor.detector {
        case let .downloading(fraction):
            return "Downloading… \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case let .failed(message):
            return message
        case .off, .on:
            guard let model = monitor.installedModel else { return "Not downloaded" }
            let size = model.bytes.formatted(.byteCount(style: .file))
            return "\(model.name) · \(size) · \(model.isBundled ? "In the app" : "Downloaded")"
        }
    }

    private var modelStatusSymbol: String {
        switch monitor.detector {
        case .downloading: "arrow.down.circle"
        case .failed: "exclamationmark.triangle"
        case .off, .on: monitor.installedModel == nil ? "icloud.and.arrow.down" : "checkmark.circle"
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
                    Text(source)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                case let .camera(camera, _):
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
                case let .downloading(fraction):
                    Label {
                        Text("Downloading the vehicle model… \(fraction, format: .percent.precision(.fractionLength(0)))")
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .font(.footnote)
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                case .off, .on:
                    EmptyView()
                }
            }
            Spacer()
            if let favourite = feed.favourite {
                Button {
                    favourites.toggle(favourite)
                } label: {
                    Image(systemName: favourites.contains(favourite) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(favourites.contains(favourite) ? "Remove from Favourites" : "Add to Favourites")
            }
            Menu {
                Button("Favourites…", systemImage: "star", action: manageFavourites)
                Section("Analysis") {
                    Toggle("Detect Vehicles", systemImage: "car.fill", isOn: detectsVehicles)
                    Toggle("Show Detections", systemImage: "rectangle.dashed", isOn: $showsVehicles)
                        .disabled(!monitor.detectsVehicles)
                    Toggle("Live Stream Motion", systemImage: "wind", isOn: $analyzesLiveMotion)
                }
                Section("Vehicle Model") {
                    Label(modelStatus, systemImage: modelStatusSymbol)
                    if let model = monitor.installedModel, !model.isBundled {
                        Button("Delete Model", systemImage: "trash", role: .destructive) {
                            monitor.deleteModel()
                        }
                    }
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
            if case .live = feed {
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

    /// For cameras whose catalog entry gives no refresh interval.
    private static let defaultRefreshInterval: TimeInterval = 30

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
            try? await Task.sleep(for: .seconds(camera.refreshInterval ?? Self.defaultRefreshInterval))
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
