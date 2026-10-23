import CoreImage
import CoreVideo
import Foundation
import Vision

/// A frame copied from the live stream's video output.
///
/// Each frame is a fresh copy handed to the analyzer and never touched again by the
/// player, so it is safe to send.
struct VideoFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// How much the live stream moves on each half of the picture, usually one
/// carriageway each.
struct MotionReading: Equatable, Sendable {
    /// From 0 (nothing moves) to 1 (the most movement seen so far).
    var left: Double
    var right: Double
    var measuredAt = Date.now

    /// Older than a couple of looks: kept from an earlier visit of the camera.
    var isFromEarlierVisit: Bool {
        Date.now.timeIntervalSince(measuredAt) > 30
    }

    enum Level {
        case still, slow, fast

        var title: String {
            switch self {
            case .still: "Little movement"
            case .slow: "Moving slowly"
            case .fast: "Moving freely"
            }
        }
    }

    static func level(_ value: Double) -> Level {
        switch value {
        case ..<0.15: .still
        case ..<0.5: .slow
        default: .fast
        }
    }
}

/// The camera a live stream shows, read from the picture: streams cycle through
/// several cameras, each with its label and caption burnt in.
struct LiveCamera: Equatable, Sendable {
    /// The identifier in the box in a top corner, such as "A6 WG 00.7".
    var label: String
    /// The caption at the bottom, such as "Croix de Cessange: direction Croix de Gasperich".
    var caption: String?
}

/// What one look at the live stream found.
struct LiveReading: Equatable, Sendable {
    var camera: LiveCamera?
    /// `nil` when the stream just changed camera, or cut between the two frames.
    var motion: MotionReading?
    /// After a switch, the camera's reading from its previous visit, if recent enough
    /// to be a hint. It is never passed off as current.
    var previousVisit: MotionReading?
    /// The stream switched to another camera: the motion analysis starts over.
    var cameraChanged = false
}

/// A frame kept for the dashboard. A `CGImage` never changes once made, so it is safe
/// to share.
struct StillFrame: @unchecked Sendable, Identifiable {
    let id = UUID()
    let image: CGImage
    let date: Date
}

/// What the live stream last showed of one of its cameras, for the dashboard.
struct CameraSnapshot: Sendable, Identifiable {
    var id: String { camera.label }
    var camera: LiveCamera
    /// The last few frames, oldest first.
    var frames: [StillFrame] = []
    var lastSeen: Date
    /// The movement over the camera's last visit, averaged.
    var motion: MotionReading?
}

/// Analyzes the live stream: which camera it shows, from the text burnt into the
/// picture, and how much it moves, with Vision's optical flow.
///
/// Live streams switch cameras within the same feed. A cut between pictures, or a new
/// camera label, starts the analysis over, so movement is never measured across two
/// cameras and each camera keeps its own calibration.
actor MotionAnalyzer {
    /// The fastest movement seen per camera label, slowly forgotten, so readings are
    /// relative to each camera's usual traffic. Kept between launches.
    private var peaks: [String: Double]
    /// Each camera's last reading, shown again when the stream comes back to it.
    private var lastReadings: [String: MotionReading] = [:]
    private var readingsSinceSave = 0
    private var camera: LiveCamera?
    /// A new label read once: it takes over when read again, so one misread doesn't
    /// count as a switch.
    private var candidateLabel: String?
    /// A cut was seen since the last confirmed camera: the next new label takes over at once.
    private var sawCut = false
    /// A small greyscale copy of the last frame looked at, to spot cuts between looks.
    private var lastThumbnail: [Float]?
    /// When the label was last read: reading it is the slow part, so it is read after
    /// a cut, and otherwise every couple of seconds.
    private var lastLabelRead = Date.distantPast
    /// Each camera the stream showed, by label, for the dashboard.
    private var snapshots: [String: CameraSnapshot] = [:]
    /// The readings of the current visit of the current camera.
    private var visitReadings: [MotionReading] = []
    private var lastFrameKept = Date.distantPast
    private let imageContext = CIContext()

    /// How often the label is read when nothing suggests a switch.
    private static let labelInterval: TimeInterval = 2
    /// How many frames each camera keeps, and how far apart.
    private static let framesKept = 6
    private static let frameInterval: TimeInterval = 0.5

    /// Mean brightness difference, 0–255, above which two frames show different scenes.
    private static let cutThreshold: Float = 28
    /// How long a camera's last reading stays worth showing when it comes back.
    private static let previousVisitLifetime: TimeInterval = 15 * 60
    private static let peaksKey = "liveMotionPeaks"

    init() {
        peaks = UserDefaults.standard.dictionary(forKey: Self.peaksKey) as? [String: Double] ?? [:]
    }

    /// Flow below this, in pixels between the two frames, is noise.
    private static let noise: Float = 0.3
    /// The least peak, so a quiet stream doesn't look fast.
    private static let minimumPeak = 1.5

    func analyze(from first: VideoFrame, to second: VideoFrame) -> LiveReading {
        let firstThumbnail = Self.thumbnail(of: first.buffer)
        let secondThumbnail = Self.thumbnail(of: second.buffer)
        defer { lastThumbnail = secondThumbnail }
        let cutBetweenLooks = Self.isCut(lastThumbnail, firstThumbnail)
        let cutWithinPair = Self.isCut(firstThumbnail, secondThumbnail)
        if cutBetweenLooks || cutWithinPair {
            sawCut = true
        }

        let readsLabel = sawCut || camera == nil || candidateLabel != nil
            || Date.now.timeIntervalSince(lastLabelRead) >= Self.labelInterval
        let read = readsLabel ? Self.readCamera(in: second.buffer) : nil
        if readsLabel { lastLabelRead = .now }
        let changed = updateCamera(with: read, cut: cutBetweenLooks || cutWithinPair)
        // Movement across a cut, or right after a switch, means nothing.
        guard !changed, !cutWithinPair else {
            if changed {
                savePeaks()
                visitReadings = []
            }
            return LiveReading(camera: camera, motion: nil, previousVisit: changed ? previousVisit() : nil, cameraChanged: changed)
        }
        let key = camera?.label ?? ""
        let reading = motion(from: first, to: second, peakKey: key)
        if let reading {
            lastReadings[key] = reading
            visitReadings.append(reading)
            readingsSinceSave += 1
            if readingsSinceSave >= 15 { savePeaks() }
        }
        updateSnapshot(with: second)
        return LiveReading(camera: camera, motion: reading)
    }

    /// Every camera the stream showed since ``resetDashboard()``, by label.
    func dashboard() -> [CameraSnapshot] {
        snapshots.values.sorted { $0.camera.label.localizedStandardCompare($1.camera.label) == .orderedAscending }
    }

    /// Forgets the cameras shown, for another stream. Calibrations are kept.
    func resetDashboard() {
        snapshots = [:]
        visitReadings = []
        camera = nil
        candidateLabel = nil
        lastThumbnail = nil
    }

    /// Keeps a frame of the current camera every so often, and its visit's movement.
    private func updateSnapshot(with frame: VideoFrame) {
        guard let camera else { return }
        var snapshot = snapshots[camera.label] ?? CameraSnapshot(camera: camera, lastSeen: .now)
        snapshot.camera = camera
        snapshot.lastSeen = .now
        if !visitReadings.isEmpty {
            let count = Double(visitReadings.count)
            snapshot.motion = MotionReading(
                left: visitReadings.map(\.left).reduce(0, +) / count,
                right: visitReadings.map(\.right).reduce(0, +) / count
            )
        }
        if Date.now.timeIntervalSince(lastFrameKept) >= Self.frameInterval, let image = still(of: frame) {
            snapshot.frames.append(StillFrame(image: image, date: .now))
            snapshot.frames = Array(snapshot.frames.suffix(Self.framesKept))
            lastFrameKept = .now
        }
        snapshots[camera.label] = snapshot
    }

    /// A half-size copy of a frame.
    private func still(of frame: VideoFrame) -> CGImage? {
        let image = CIImage(cvPixelBuffer: frame.buffer).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        return imageContext.createCGImage(image, from: image.extent)
    }

    /// The current camera's reading from its previous visit, if recent enough.
    private func previousVisit() -> MotionReading? {
        guard let label = camera?.label, let reading = lastReadings[label],
              Date.now.timeIntervalSince(reading.measuredAt) < Self.previousVisitLifetime
        else { return nil }
        return reading
    }

    private func savePeaks() {
        UserDefaults.standard.set(peaks, forKey: Self.peaksKey)
        readingsSinceSave = 0
    }

    /// Takes in the camera read from the picture. Returns whether the stream switched camera.
    private func updateCamera(with read: LiveCamera?, cut: Bool) -> Bool {
        guard let read else {
            // No readable label: a cut is the only sign of a switch.
            return cut
        }
        if read.label == camera?.label {
            camera?.caption = read.caption ?? camera?.caption
            candidateLabel = nil
            sawCut = false
            return false
        }
        guard camera == nil || sawCut || candidateLabel == read.label else {
            candidateLabel = read.label
            return false
        }
        let switched = camera != nil
        camera = read
        candidateLabel = nil
        sawCut = false
        return switched
    }

    private func motion(from first: VideoFrame, to second: VideoFrame, peakKey: String) -> MotionReading? {
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: second.buffer, options: [:])
        request.computationAccuracy = .low
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        let handler = VNImageRequestHandler(cvPixelBuffer: first.buffer, options: [:])
        guard (try? handler.perform([request])) != nil, let flow = request.results?.first?.pixelBuffer else { return nil }
        guard let movement = Self.meanMovement(in: flow) else { return nil }

        let peak = max((peaks[peakKey] ?? 0) * 0.99, movement.left, movement.right, Self.minimumPeak)
        peaks[peakKey] = peak
        return MotionReading(left: min(movement.left / peak, 1), right: min(movement.right / peak, 1))
    }

    /// The mean flow magnitude of each half of the picture, in pixels.
    private static func meanMovement(in flow: CVPixelBuffer) -> (left: Double, right: Double)? {
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(flow) else { return nil }
        let width = CVPixelBufferGetWidth(flow)
        let height = CVPixelBufferGetHeight(flow)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(flow)
        var sums = (left: 0.0, right: 0.0)
        var counts = (left: 0.0, right: 0.0)
        // Every other pixel is plenty.
        for y in stride(from: 0, to: height, by: 2) {
            let row = (base + y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in stride(from: 0, to: width, by: 2) {
                let dx = row[2 * x]
                let dy = row[2 * x + 1]
                var magnitude = (dx * dx + dy * dy).squareRoot()
                if magnitude < noise { magnitude = 0 }
                if x < width / 2 {
                    sums.left += Double(magnitude)
                    counts.left += 1
                } else {
                    sums.right += Double(magnitude)
                    counts.right += 1
                }
            }
        }
        guard counts.left > 0, counts.right > 0 else { return nil }
        // Scaled up: most of the picture is road side and sky, which doesn't move.
        return (left: sums.left / counts.left * 10, right: sums.right / counts.right * 10)
    }

    // MARK: Cuts

    /// The brightness of a 32 × 18 grid of points of a BGRA frame.
    private static func thumbnail(of buffer: CVPixelBuffer, columns: Int = 32, rows: Int = 18) -> [Float]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var values: [Float] = []
        values.reserveCapacity(columns * rows)
        for row in 0..<rows {
            let y = (2 * row + 1) * height / (2 * rows)
            let line = (base + y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<columns {
                let x = (2 * column + 1) * width / (2 * columns)
                let blue = Float(line[4 * x])
                let green = Float(line[4 * x + 1])
                let red = Float(line[4 * x + 2])
                values.append(0.299 * red + 0.587 * green + 0.114 * blue)
            }
        }
        return values
    }

    private static func isCut(_ lhs: [Float]?, _ rhs: [Float]?) -> Bool {
        guard let lhs, let rhs, lhs.count == rhs.count, !lhs.isEmpty else { return false }
        let difference = zip(lhs, rhs).reduce(Float(0)) { $0 + abs($1.0 - $1.1) } / Float(lhs.count)
        return difference > cutThreshold
    }

    // MARK: Camera label

    /// The camera label and the caption, read with Vision.
    ///
    /// The label sits in a corner of the top strip, left or right depending on the
    /// camera, among other text such as gantry signs: only text shaped like a label is
    /// taken. The caption is the bottom line that reads "Place: direction …".
    private static func readCamera(in buffer: CVPixelBuffer) -> LiveCamera? {
        let top = textRequest(in: CGRect(x: 0, y: 0.82, width: 1, height: 0.18))
        let bottom = textRequest(in: CGRect(x: 0, y: 0, width: 1, height: 0.16))
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        guard (try? handler.perform([top, bottom])) != nil,
              let label = lines(of: top).lazy.compactMap { cameraLabel(in: $0) }.first
        else { return nil }
        let caption = lines(of: bottom).first { $0.contains(":") || $0.localizedCaseInsensitiveContains("direction") }
        return LiveCamera(label: label, caption: caption)
    }

    /// The label in a line of text, such as "A6 WG 13.0": a road number, a short code
    /// and a distance, upper-cased with single spaces so it reads the same every time.
    static func cameraLabel(in line: String) -> String? {
        let pattern = #/(?i)\b([AB]\s?\d{1,2})\s+([A-Z0-9]{1,4})\s+(\d{1,3}[.,]\d)\b/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let road = match.1.uppercased().replacingOccurrences(of: " ", with: "")
        return "\(road) \(match.2.uppercased()) \(match.3.replacingOccurrences(of: ",", with: "."))"
    }

    /// Reads text in a region, in Vision's coordinates (origin at the bottom left).
    private static func textRequest(in region: CGRect) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = region
        return request
    }

    private static func lines(of request: VNRecognizeTextRequest) -> [String] {
        (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
