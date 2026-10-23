import Foundation
import Observation

/// Keeps a report for every camera of a motorway, so the menu can show each
/// camera's situation at a glance.
@MainActor @Observable
final class RoadMonitor {
    enum DetectorState: Equatable {
        case off
        case downloading
        case on
        case failed(String)
    }

    private(set) var reports: [String: RoadReport] = [:]
    private(set) var detector = DetectorState.off
    /// Where to download the vehicle detection model, from the catalog.
    var vehicleModelURL: URL?

    var detectsVehicles: Bool {
        detector == .on
    }

    private static let detectsVehiclesKey = "detectsVehicles"

    /// Turns vehicle detection on, downloading its model the first time, or off.
    /// The choice is remembered.
    func setDetectsVehicles(_ isOn: Bool) async {
        UserDefaults.standard.set(isOn, forKey: Self.detectsVehiclesKey)
        guard isOn else {
            detector = .off
            return
        }
        guard detector != .on, detector != .downloading else { return }
        detector = .downloading
        do {
            try await VehicleDetector.install(from: vehicleModelURL)
            detector = .on
        } catch {
            detector = .failed(error.localizedDescription)
        }
    }

    /// Restores the remembered choice.
    func restore() async {
        if UserDefaults.standard.bool(forKey: Self.detectsVehiclesKey) {
            await setDetectsVehicles(true)
        }
    }

    /// How often every camera is looked at again.
    static let interval: Duration = .seconds(120)

    func report(for camera: Webcam) -> RoadReport? {
        reports[camera.id]
    }

    /// Analyzes a picture the app just loaded.
    func record(_ data: Data, for camera: Webcam) async {
        if let report = await RoadAnalyzer.shared.analyze(data, camera: camera.id, detectsVehicles: detectsVehicles) {
            store(report, for: camera)
        }
    }

    func recordFailure(for camera: Webcam) {
        store(.unavailable(at: .now), for: camera)
    }

    /// Keeps the report, and shares it with the widget.
    private func store(_ report: RoadReport, for camera: Webcam) {
        reports[camera.id] = report
        RoadReportStore.save([camera.id: report])
    }

    /// Looks at each camera in turn, then again after `interval`, until cancelled.
    /// Cameras analyzed recently, like the one on screen, are skipped.
    func watch(_ cameras: [Webcam]) async {
        while !Task.isCancelled {
            for camera in cameras {
                guard !Task.isCancelled else { return }
                if let report = reports[camera.id], Date.now.timeIntervalSince(report.date) < 60 { continue }
                do {
                    let data = try await CitaWebcams.image(of: camera)
                    await record(data, for: camera)
                } catch {
                    if !Task.isCancelled { recordFailure(for: camera) }
                }
            }
            try? await Task.sleep(for: Self.interval)
        }
    }
}
