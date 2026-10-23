#if canImport(Vision)

import CoreGraphics
import CoreML
import Foundation
import Vision
import WebcamsCore

/// Finds vehicles in a picture with a Core ML object detector run through Vision.
///
/// The model is an object detector trained on the COCO classes, which include cars,
/// trucks, buses and motorbikes, such as Apple's YOLOv3. It is downloaded from
/// the catalog's `vehicleModelURL` and compiled on the device the first time vehicle
/// detection is turned on, rather than shipped in the repository. A model named
/// `VehicleDetector` added to the app target is used instead when present.
public final class VehicleDetector {
    public static let vehicleLabels: Set<String> = ["car", "truck", "bus", "motorbike", "motorcycle"]
    public static let minimumConfidence: Float = 0.2

    public enum InstallError: LocalizedError {
        case noModel
        case download

        public var errorDescription: String? {
            switch self {
            case .noModel: "No vehicle detection model is configured."
            case .download: "The vehicle detection model couldn't be downloaded."
            }
        }
    }

    /// The loaded model, and the file it was loaded from.
    private var model: (url: URL, model: VNCoreMLModel)?

    // MARK: Installing

    /// A model the app can use, and where it comes from.
    public struct InstalledModel: Equatable, Sendable {
        /// The model's name, such as "YOLOv3FP16".
        public var name: String
        /// The size of the compiled model on the device.
        public var bytes: Int64
        /// Added to the app target rather than downloaded.
        public var isBundled: Bool
    }

    /// A model added to the app target, which Xcode compiles.
    private static var bundledURL: URL? {
        Bundle.main.url(forResource: "VehicleDetector", withExtension: "mlmodelc")
    }

    /// Downloaded models, one at a time, named after the file they came from.
    private static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "VehicleModels", directoryHint: .isDirectory)
    }

    /// Where the model downloaded from a URL is kept: a new URL in the catalog means a
    /// new model, rather than keeping the one downloaded before.
    private static func installedURL(for modelURL: URL) -> URL {
        modelsDirectory.appending(path: modelURL.deletingPathExtension().lastPathComponent + ".mlmodelc")
    }

    /// The model in use: the bundled one, or the one downloaded from `modelURL`.
    public static func modelFile(for modelURL: URL?) -> URL? {
        if let bundledURL { return bundledURL }
        guard let modelURL else { return nil }
        let url = installedURL(for: modelURL)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    public static func installedModel(for modelURL: URL?) -> InstalledModel? {
        guard let file = modelFile(for: modelURL) else { return nil }
        return InstalledModel(
            name: file.deletingPathExtension().lastPathComponent,
            bytes: Self.size(of: file),
            isBundled: file == bundledURL
        )
    }

    /// Downloads and compiles the model, unless it is already there, and removes any
    /// other downloaded model. Reports the download's progress, from 0 to 1.
    public static func install(from modelURL: URL?, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard modelFile(for: modelURL) == nil else { return }
        guard let modelURL else { throw InstallError.noModel }
        let observer = DownloadObserver(onProgress: progress)
        let (downloaded, response) = try await URLSession.shared.download(from: modelURL, delegate: observer)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.download
        }
        let fileManager = FileManager.default
        // Core ML compiles a file by its extension.
        let source = fileManager.temporaryDirectory.appending(path: modelURL.lastPathComponent)
        try? fileManager.removeItem(at: source)
        try fileManager.moveItem(at: downloaded, to: source)
        defer { try? fileManager.removeItem(at: source) }
        let compiled = try await MLModel.compileModel(at: source)
        removeDownloadedModels()
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try fileManager.moveItem(at: compiled, to: installedURL(for: modelURL))
    }

    /// Deletes downloaded models, including one kept by an earlier version of the app.
    public static func removeDownloadedModels() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: modelsDirectory)
        try? fileManager.removeItem(at: URL.applicationSupportDirectory.appending(path: "VehicleDetector.mlmodelc"))
    }

    private static func size(of directory: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
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
    /// The model sees a small square, 416 × 416 for YOLOv3, so in a whole camera
    /// picture distant vehicles are a few pixels and go unseen. The picture is also
    /// looked at in overlapping tiles, each scaled up to the model's size, and the
    /// detections are merged.
    public func vehicles(in image: CGImage, modelFile: URL) throws -> [CGRect] {
        let model = try loadedModel(from: modelFile)
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
    public static let tiles: [CGRect] = [fullImage] + [0.0, 0.4].flatMap { y in
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

    private func loadedModel(from file: URL) throws -> VNCoreMLModel {
        if let model, model.url == file { return model.model }
        let loaded = try VNCoreMLModel(for: MLModel(contentsOf: file, configuration: MLModelConfiguration()))
        model = (file, loaded)
        return loaded
    }
}

/// Reports a download's progress, from the task the download creates.
private final class DownloadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    public init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}

#endif
