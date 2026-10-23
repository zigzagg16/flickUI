import Foundation
import Observation

/// Keeps a report for every camera of a motorway, so the menu can show each
/// camera's situation at a glance.
@MainActor @Observable
final class RoadMonitor {
    private(set) var reports: [String: RoadReport] = [:]

    /// How often every camera is looked at again.
    static let interval: Duration = .seconds(120)

    func report(for camera: Webcam) -> RoadReport? {
        reports[camera.id]
    }

    /// Analyzes a picture the app just loaded.
    func record(_ data: Data, for camera: Webcam) async {
        if let report = await RoadAnalyzer.shared.analyze(data, camera: camera.id) {
            reports[camera.id] = report
        }
    }

    func recordFailure(for camera: Webcam) {
        reports[camera.id] = .unavailable(at: .now)
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
