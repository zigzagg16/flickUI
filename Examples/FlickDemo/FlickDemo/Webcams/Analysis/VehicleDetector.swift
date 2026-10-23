import CoreGraphics
import CoreML
import Foundation
import Vision

/// Finds vehicles in a picture with a Core ML object detector run through Vision.
///
/// The model is an object detector trained on the COCO classes, which include cars,
/// trucks, buses and motorbikes, such as Apple's YOLOv3 Tiny. It is downloaded from
/// the catalog's `vehicleModelURL` and compiled on the device the first time vehicle
/// detection is turned on, rather than shipped in the repository. A model named
/// `VehicleDetector` added to the app target is used instead when present.
final class VehicleDetector {
    static let vehicleLabels: Set<String> = ["car", "truck", "bus", "motorbike", "motorcycle"]
    static let minimumConfidence: Float = 0.3

    enum InstallError: LocalizedError {
        case noModel
        case download

        var errorDescription: String? {
            switch self {
            case .noModel: "No vehicle detection model is configured."
            case .download: "The vehicle detection model couldn't be downloaded."
            }
        }
    }

    private var model: VNCoreMLModel?

    // MARK: Installing

    /// A model added to the app target, which Xcode compiles.
    private static var bundledURL: URL? {
        Bundle.main.url(forResource: "VehicleDetector", withExtension: "mlmodelc")
    }

    private static var installedURL: URL {
        URL.applicationSupportDirectory.appending(path: "VehicleDetector.mlmodelc")
    }

    static var isInstalled: Bool {
        bundledURL != nil || FileManager.default.fileExists(atPath: installedURL.path(percentEncoded: false))
    }

    /// Downloads and compiles the model, unless it is already there.
    static func install(from modelURL: URL?) async throws {
        guard !isInstalled else { return }
        guard let modelURL else { throw InstallError.noModel }
        let (downloaded, response) = try await URLSession.shared.download(from: modelURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.download
        }
        let fileManager = FileManager.default
        // Core ML compiles a file by its extension.
        let source = fileManager.temporaryDirectory.appending(path: "VehicleDetector.mlmodel")
        try? fileManager.removeItem(at: source)
        try fileManager.moveItem(at: downloaded, to: source)
        let compiled = try await MLModel.compileModel(at: source)
        try fileManager.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: installedURL)
        try fileManager.moveItem(at: compiled, to: installedURL)
        try? fileManager.removeItem(at: source)
    }

    // MARK: Detecting

    /// The vehicles' boxes, normalised with the origin at the top left.
    func vehicles(in image: CGImage) throws -> [CGRect] {
        let request = VNCoreMLRequest(model: try loadedModel())
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        let objects = request.results as? [VNRecognizedObjectObservation] ?? []
        return objects.compactMap { object in
            guard let label = object.labels.first,
                  Self.vehicleLabels.contains(label.identifier),
                  label.confidence >= Self.minimumConfidence
            else { return nil }
            // Vision's origin is at the bottom left.
            let box = object.boundingBox
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    private func loadedModel() throws -> VNCoreMLModel {
        if let model { return model }
        guard let url = Self.bundledURL ?? (Self.isInstalled ? Self.installedURL : nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let loaded = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: MLModelConfiguration()))
        model = loaded
        return loaded
    }
}
