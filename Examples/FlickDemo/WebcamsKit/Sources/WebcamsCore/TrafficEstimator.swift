#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Estimates a camera's traffic from the vehicles in its successive pictures.
///
/// A vehicle found at the same place as in the previous picture, a minute or so
/// earlier, is standing still: many still vehicles mean a jam. Vehicles that stay put
/// for many pictures while other traffic moves are parked, or something that only
/// looks like a vehicle, and are left out; in a jam nothing moves, so it stays a jam.
/// Each half of the picture, usually one carriageway, is judged on its own.
/// The thresholds are starting values to tune on real pictures.
public struct TrafficEstimator {
    public struct Estimate: Equatable {
        public var traffic: RoadReport.Traffic
        public var left: RoadReport.Traffic
        public var right: RoadReport.Traffic
        /// The vehicles counted, without parked ones.
        public var vehicles: [CGRect]
    }

    /// A box seen at about the same place picture after picture.
    private struct Track {
        var box: CGRect
        var hits = 1
        var misses = 0
        /// Pictures in which it stood still while other vehicles moved.
        var stillAmongMoving = 0

        var isParked: Bool {
            hits >= TrafficEstimator.parkedAfter && stillAmongMoving >= TrafficEstimator.parkedAfter / 2
        }
    }

    /// Boxes overlapping this much are the same vehicle.
    public static let sameVehicleOverlap: CGFloat = 0.5
    /// Pictures in a row after which a vehicle counts as parked.
    public static let parkedAfter = 10
    /// Pictures a track survives without being seen.
    public static let forgetAfter = 3

    private var previous: [CGRect] = []
    private var tracks: [Track] = []
    /// The most vehicles seen at once, slowly forgotten: the camera's busy level.
    private var busiest: Double = 0

    public init() {}

    public mutating func update(with boxes: [CGRect]) -> Estimate {
        let seen = updateTracks(with: boxes)
        let parked = tracks.filter(\.isParked).map(\.box)
        let vehicles = boxes.filter { box in !parked.contains { Self.overlap(box, $0) >= Self.sameVehicleOverlap } }
        let still = vehicles.filter { box in previous.contains { Self.overlap(box, $0) >= Self.sameVehicleOverlap } }
        if still.count < vehicles.count {
            for index in seen where tracks[index].hits > 1 {
                tracks[index].stillAmongMoving += 1
            }
        }
        tracks.removeAll { $0.misses >= Self.forgetAfter }
        previous = vehicles

        busiest = max(busiest * 0.98, Double(vehicles.count))
        let capacity = max(busiest, 6)
        let left = vehicles.filter { $0.midX < 0.5 }
        let right = vehicles.filter { $0.midX >= 0.5 }
        return Estimate(
            traffic: Self.level(count: vehicles.count, still: still.count, capacity: capacity),
            left: Self.level(count: left.count, still: still.filter { $0.midX < 0.5 }.count, capacity: capacity / 2),
            right: Self.level(count: right.count, still: still.filter { $0.midX >= 0.5 }.count, capacity: capacity / 2),
            vehicles: vehicles
        )
    }

    public static func level(count: Int, still: Int, capacity: Double) -> RoadReport.Traffic {
        guard count > 0 else { return .empty }
        let stillShare = Double(still) / Double(count)
        if count >= 4 && stillShare >= 0.6 { return .jammed }
        if count >= 3 && stillShare >= 0.4 { return .dense }
        if Double(count) >= max(capacity * 0.6, 4) { return .dense }
        return .flowing
    }

    /// Intersection over union of two boxes.
    public static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let shared = sharedArea(lhs, rhs)
        guard shared > 0 else { return 0 }
        let union = lhs.width * lhs.height + rhs.width * rhs.height - shared
        return union > 0 ? shared / union : 0
    }

    /// The area two boxes have in common, 0 when they don't meet.
    ///
    /// Computed by hand: `CGRect.intersection` isn't in Foundation on every platform.
    public static func sharedArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let width = min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
        let height = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
        return width > 0 && height > 0 ? width * height : 0
    }

    /// Matches the boxes to the tracks, and returns the indices of the tracks seen.
    private mutating func updateTracks(with boxes: [CGRect]) -> Set<Int> {
        var seen = Set<Int>()
        for box in boxes {
            let match = tracks.indices.first { index in
                !seen.contains(index) && Self.overlap(tracks[index].box, box) >= Self.sameVehicleOverlap
            }
            if let index = match {
                tracks[index].box = box
                tracks[index].hits += 1
                tracks[index].misses = 0
                seen.insert(index)
            } else {
                tracks.append(Track(box: box))
                seen.insert(tracks.count - 1)
            }
        }
        for index in tracks.indices where !seen.contains(index) {
            tracks[index].misses += 1
        }
        return seen
    }
}
