import Foundation

/// How much the live stream moves on each half of the picture, usually one
/// carriageway each.
public struct MotionReading: Equatable, Sendable {
    /// From 0 (nothing moves) to 1 (the most movement seen so far).
    public var left: Double
    public var right: Double
    public var measuredAt: Date

    public init(left: Double, right: Double, measuredAt: Date = .now) {
        self.left = left
        self.right = right
        self.measuredAt = measuredAt
    }

    /// Older than a couple of looks: kept from an earlier visit of the camera.
    public var isFromEarlierVisit: Bool {
        Date.now.timeIntervalSince(measuredAt) > 30
    }

    public enum Level {
        case still, slow, fast

        public var title: String {
            switch self {
            case .still: "Little movement"
            case .slow: "Moving slowly"
            case .fast: "Moving freely"
            }
        }
    }

    public static func level(_ value: Double) -> Level {
        switch value {
        case ..<0.15: .still
        case ..<0.5: .slow
        default: .fast
        }
    }
}

/// The camera a live stream shows, read from the picture: streams cycle through
/// several cameras, each with its label and caption burnt in.
public struct LiveCamera: Equatable, Sendable {
    /// The identifier in the box in a top corner, such as "A6 WG 00.7".
    public var label: String
    /// The caption at the bottom, such as "Croix de Cessange: direction Croix de Gasperich".
    public var caption: String?

    public init(label: String, caption: String? = nil) {
        self.label = label
        self.caption = caption
    }

    /// The label in a line of text, such as "A6 WG 13.0": a road number, a short code
    /// and a distance, upper-cased with single spaces so it reads the same every time.
    public static func label(in line: String) -> String? {
        let pattern = #/(?i)\b([AB]\s?\d{1,2})\s+([A-Z0-9]{1,4})\s+(\d{1,3}[.,]\d)\b/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        let road = match.1.uppercased().replacingOccurrences(of: " ", with: "")
        return "\(road) \(match.2.uppercased()) \(match.3.replacingOccurrences(of: ",", with: "."))"
    }
}

/// What one look at the live stream found.
public struct LiveReading: Equatable, Sendable {
    public var camera: LiveCamera?
    /// `nil` when the stream just changed camera, or cut between the two frames.
    public var motion: MotionReading?
    /// After a switch, the camera's reading from its previous visit, if recent enough
    /// to be a hint. It is never passed off as current.
    public var previousVisit: MotionReading?
    /// The stream switched to another camera: the motion analysis starts over.
    public var cameraChanged = false

    public init(camera: LiveCamera?, motion: MotionReading?, previousVisit: MotionReading? = nil, cameraChanged: Bool = false) {
        self.camera = camera
        self.motion = motion
        self.previousVisit = previousVisit
        self.cameraChanged = cameraChanged
    }
}
