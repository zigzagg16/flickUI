import flickUI
import SwiftUI
import UIKit

/// What the side menu shows: the motorway's live stream, then its cameras.
enum WebcamFeed: Identifiable, Hashable {
    case live
    case camera(Webcam)

    static let liveID = "live"

    var id: String {
        switch self {
        case .live: Self.liveID
        case let .camera(camera): camera.id
        }
    }

    var title: String {
        switch self {
        case .live: "Live stream"
        case let .camera(camera): camera.title
        }
    }

    var symbol: String {
        switch self {
        case .live: "play.tv.fill"
        case let .camera(camera): camera.symbol
        }
    }
}

/// Live motorway webcams from cita.lu. Two nested menus, one per side: the right
/// edge switches between the live stream and the cameras, the left edge switches motorways.
struct WebcamsView: View {
    @State private var motorway = Motorway.a13.id
    @State private var feedID = WebcamFeed.liveID
    @State private var pages: [Motorway: WebcamPage] = [:]
    @State private var loadError: String?
    /// Contained by default, so the camera stays visible around the menu.
    @State private var background = BackgroundChoice.panel

    private var current: Motorway {
        Motorway(rawValue: motorway) ?? .a13
    }

    private var cameras: [Webcam] {
        pages[current]?.cameras ?? []
    }

    /// The live stream is always there, so the menu works before the cameras load.
    private var feeds: [WebcamFeed] {
        [.live] + cameras.map(WebcamFeed.camera)
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
            error: loadError,
            background: $background
        ) {
            Task { await load(current) }
        }
        .flickMenu(feeds, selection: $feedID, edges: .trailing, title: \.title, systemImage: \.symbol)
        .flickMenuHome(.trailing, position: 0.4)
        .flickMenu(Motorway.allCases, selection: $motorway, edges: .leading, title: \.title, systemImage: \.symbol)
        .flickMenuHome(.leading, position: 0.4)
        .flickMenuIndicatorStyle(.morphing(.liquid, tint: .yellow), edges: .leading)
        .flickMenuBackground(DemoBackgroundStyle(choice: background))
        .onChange(of: motorway) {
            // Stay on the live stream; otherwise start at the new motorway's first camera.
            if feedID != WebcamFeed.liveID {
                feedID = pages[current]?.cameras.first?.id ?? WebcamFeed.liveID
            }
        }
        .task(id: motorway) {
            await load(current)
        }
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
    let error: String?
    @Binding var background: BackgroundChoice
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch feed {
            case .live:
                LiveStreamView(motorway: motorway)
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
                case let .camera(camera):
                    Text(camera.place)
                        .font(.title2.bold())
                    Text(camera.direction)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                if let error {
                    Button("Cameras unavailable. Retry", systemImage: "arrow.clockwise", action: retry)
                        .font(.footnote)
                        .accessibilityHint(error)
                }
            }
            Spacer()
            Menu {
                Picker("Menu background", selection: $background) {
                    ForEach(BackgroundChoice.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Menu background", systemImage: "paintbrush.fill")
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

    @State private var image: UIImage?
    /// The camera `image` belongs to; the previous camera's image stays, dimmed, until the next one loads.
    @State private var imageCameraID: String?
    @State private var updated: Date?
    @State private var failed = false

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
                } else {
                    failed = !isCurrent
                }
            } catch {
                if !Task.isCancelled { failed = !isCurrent }
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
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
