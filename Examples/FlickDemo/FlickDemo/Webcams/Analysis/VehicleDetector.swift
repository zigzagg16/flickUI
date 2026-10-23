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
    static let minimumConfidence: Float = 0.2

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

    /// A vehicle found in a picture.
    private struct Detection {
        /// Normalised, with the origin at the top left.
        var box: CGRect
        var confidence: Float
    }

    /// The vehicles' boxes, normalised with the origin at the top left.
    ///
    /// The model sees a small square, 416 × 416 for YOLOv3 Tiny, so in a whole camera
    /// picture distant vehicles are a few pixels and go unseen. The picture is also
    /// looked at in overlapping tiles, each scaled up to the model's size, and the
    /// detections are merged.
    func vehicles(in image: CGImage) throws -> [CGRect] {
        let model = try loadedModel()
        var detections: [Detection] = []
        for tile in Self.tiles {
            guard let crop = tile == Self.fullImage ? image : image.cropping(to: Self.pixels(of: tile, in: image)) else { continue }
            detections += try Self.detections(in: crop, model: model).map { detection in
                var detection = detection
                detection.box = CGRect(
                    x: tile.minX + detection.box.minX * tile.width,
                    y: tile.minY + detection.box.minY * tile.height,
                    width: detection.box.width * tile.width,
                    height: detection.box.height * tile.height
                )
                return detection
            }
        }
        return Self.merged(detections).map(\.box)
    }

    private static let fullImage = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// The whole picture, then six overlapping tiles, half as wide and 60 % as tall,
    /// normalised with the origin at the top left.
    static let tiles: [CGRect] = [fullImage] + [0.0, 0.4].flatMap { y in
        [0.0, 0.25, 0.5].map { x in CGRect(x: x, y: y, width: 0.5, height: 0.6) }
    }

    private static func pixels(of tile: CGRect, in image: CGImage) -> CGRect {
        CGRect(
            x: tile.minX * CGFloat(image.width),
            y: tile.minY * CGFloat(image.height),
            width: tile.width * CGFloat(image.width),
            height: tile.height * CGFloat(image.height)
        ).integral
    }

    private static func detections(in image: CGImage, model: VNCoreMLModel) throws -> [Detection] {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        let objects = request.results as? [VNRecognizedObjectObservation] ?? []
        return objects.compactMap { object in
            // Small vehicles are often a close call between car and truck: a vehicle
            // among the two best guesses counts.
            guard let label = object.labels.prefix(2).first(where: { vehicleLabels.contains($0.identifier) }),
                  label.confidence >= minimumConfidence
            else { return nil }
            // Vision's origin is at the bottom left.
            let box = object.boundingBox
            return Detection(box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height), confidence: label.confidence)
        }
    }

    /// Keeps the most confident of the detections that are the same vehicle: seen in
    /// several tiles, or cut in two by a tile's edge.
    private static func merged(_ detections: [Detection]) -> [Detection] {
        var kept: [Detection] = []
        for detection in detections.sorted(by: { $0.confidence > $1.confidence }) {
            let isDuplicate = kept.contains { other in
                let shared = detection.box.intersection(other.box)
                guard !shared.isNull else { return false }
                let sharedArea = shared.width * shared.height
                let smaller = min(detection.box.width * detection.box.height, other.box.width * other.box.height)
                return TrafficEstimator.overlap(detection.box, other.box) >= 0.45 || (smaller > 0 && sharedArea / smaller >= 0.7)
            }
            if !isDuplicate { kept.append(detection) }
        }
        return kept
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
