// Vision and Core ML exist only on Apple platforms: elsewhere this module is empty.
#if canImport(Vision)

import Foundation
import Observation
import WebcamsCore

/// Keeps a report for every camera of a motorway, so the menu can show each
/// camera's situation at a glance.
@MainActor @Observable
public final class RoadMonitor {
    public enum DetectorState: Equatable {
        case off
        /// Downloading the model, from 0 to 1.
        case downloading(Double)
        case on
        case failed(String)
    }

    public private(set) var reports: [String: RoadReport] = [:]
    public private(set) var detector = DetectorState.off
    /// The vehicle detection model on the device, if any.
    public private(set) var installedModel: VehicleDetector.InstalledModel?

    /// Where to download the vehicle detection model, from the catalog. A new URL
    /// replaces the model, downloading the new one if detection is on.
    public var vehicleModelURL: URL? {
        didSet {
            guard vehicleModelURL != oldValue else { return }
            installedModel = VehicleDetector.installedModel(for: vehicleModelURL)
            if detector == .on, installedModel == nil {
                detector = .off
                Task { await setDetectsVehicles(true) }
            }
        }
    }

    public var detectsVehicles: Bool {
        detector == .on
    }

    public var isDownloadingModel: Bool {
        if case .downloading = detector { return true }
        return false
    }

    private static let detectsVehiclesKey = "detectsVehicles"

    public init() {
        installedModel = VehicleDetector.installedModel(for: nil)
    }

    /// Turns vehicle detection on, downloading its model the first time, or off.
    /// The choice is remembered.
    public func setDetectsVehicles(_ isOn: Bool) async {
        UserDefaults.standard.set(isOn, forKey: Self.detectsVehiclesKey)
        guard isOn else {
            detector = .off
            return
        }
        guard detector != .on, !isDownloadingModel else { return }
        detector = .downloading(0)
        do {
            try await VehicleDetector.install(from: vehicleModelURL) { fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.isDownloadingModel else { return }
                    self.detector = .downloading(fraction)
                }
            }
            installedModel = VehicleDetector.installedModel(for: vehicleModelURL)
            detector = .on
        } catch {
            detector = .failed(error.localizedDescription)
        }
    }

    /// Deletes the downloaded model to free its space, and turns detection off.
    public func deleteModel() {
        VehicleDetector.removeDownloadedModels()
        UserDefaults.standard.set(false, forKey: Self.detectsVehiclesKey)
        detector = .off
        installedModel = VehicleDetector.installedModel(for: vehicleModelURL)
    }

    /// Restores the remembered choice.
    public func restore() async {
        if UserDefaults.standard.bool(forKey: Self.detectsVehiclesKey) {
            await setDetectsVehicles(true)
        }
    }

    /// How often every camera is looked at again.
    public static let interval: Duration = .seconds(120)

    public func report(for camera: Webcam) -> RoadReport? {
        reports[camera.id]
    }

    /// Analyzes a picture the app just loaded.
    public func record(_ data: Data, for camera: Webcam) async {
        let vehicleModel = detectsVehicles ? VehicleDetector.modelFile(for: vehicleModelURL) : nil
        if let report = await RoadAnalyzer.shared.analyze(data, camera: camera.id, vehicleModel: vehicleModel) {
            store(report, for: camera)
        }
    }

    public func recordFailure(for camera: Webcam) {
        store(.unavailable(at: .now), for: camera)
    }

    /// Keeps the report, and shares it with the widget.
    private func store(_ report: RoadReport, for camera: Webcam) {
        reports[camera.id] = report
        RoadReportStore.save([camera.id: report])
    }

    /// Looks at each camera in turn, then again after `interval`, until cancelled.
    /// Cameras analyzed recently, like the one on screen, are skipped.
    public func watch(_ cameras: [Webcam]) async {
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

#endif
