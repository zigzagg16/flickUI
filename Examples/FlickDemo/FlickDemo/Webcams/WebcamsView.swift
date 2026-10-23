import flickUI
import SwiftUI
import UIKit

/// Live motorway webcams from cita.lu. Two nested menus: the side edges switch
/// cameras, the top and bottom edges switch motorways.
struct WebcamsView: View {
    @State private var motorway = Motorway.a13.id
    @State private var cameraID = ""
    @State private var pages: [Motorway: WebcamPage] = [:]
    @State private var loadError: String?

    private var current: Motorway {
        Motorway(rawValue: motorway) ?? .a13
    }

    private var cameras: [Webcam] {
        pages[current]?.cameras ?? []
    }

    private var camera: Webcam? {
        cameras.first { $0.id == cameraID } ?? cameras.first
    }

    var body: some View {
        WebcamScreen(
            title: pages[current]?.title ?? current.title,
            camera: camera,
            position: camera.flatMap { camera in cameras.firstIndex(of: camera) }.map { (index: $0 + 1, count: cameras.count) },
            error: loadError
        ) {
            Task { await load(current) }
        }
        .flickMenu(cameras, selection: $cameraID, edges: .horizontal, title: \.title, systemImage: \.symbol)
        .flickMenuHome(.trailing, position: 0.4)
        .flickMenu(Motorway.allCases, selection: $motorway, edges: .vertical, title: \.title, systemImage: \.symbol)
        .flickMenuHome(.bottom)
        .flickMenuIndicatorStyle(.morphing(.liquid, tint: .yellow), edges: .vertical)
        .flickMenuRowStyle(.magnifying(.dock), edges: .vertical)
        .flickMenuBackground(.gradient, edges: .vertical)
        .onChange(of: motorway) {
            cameraID = pages[current]?.cameras.first?.id ?? ""
        }
        .task(id: motorway) {
            await load(current)
        }
    }

    private func load(_ motorway: Motorway) async {
        loadError = nil
        do {
            let page = try await CitaWebcams.page(for: motorway)
            pages[motorway] = page
            if motorway == current, !page.cameras.contains(where: { $0.id == cameraID }) {
                cameraID = page.cameras.first?.id ?? ""
            }
        } catch {
            // A cached page stays usable; only an empty screen shows the error.
            if !Task.isCancelled, pages[motorway] == nil {
                loadError = error.localizedDescription
            }
        }
    }
}

struct WebcamScreen: View {
    let title: String
    let camera: Webcam?
    /// The camera's place in the list, 1-based, and the number of cameras.
    let position: (index: Int, count: Int)?
    let error: String?
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let camera {
                WebcamImage(camera: camera)
            } else if let error {
                ContentUnavailableView {
                    Label("Webcams unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again", action: retry)
                }
            } else {
                ProgressView()
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
                if let camera {
                    Text(camera.place)
                        .font(.title2.bold())
                    Text(camera.direction)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer()
            if let position {
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
        .animation(.smooth, value: camera)
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
