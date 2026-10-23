#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// How the menu reacts to the finger.
public struct FlickPhysics: Hashable, Sendable {
    /// What happens when tracking would push the menu outside the safe area.
    public enum Overscroll: Hashable, Sendable {
        /// The menu follows the finger off-screen (CariocaMenu's default).
        case unbounded
        /// The menu stops at the safe-area bounds.
        case clamped
        /// The menu resists past the bounds, like a scroll view.
        /// `stiffness` matches `UIScrollView`'s constant at `0.55`.
        case rubberBand(stiffness: CGFloat)
    }

    /// How fast the finger moves through items, relative to a static menu.
    ///
    /// - `1`: the menu stays still and the finger slides over it.
    /// - `2`: the menu moves as far as the finger, in the opposite direction
    ///   (CariocaMenu's feel).
    /// - Higher values reach distant items with shorter swipes.
    public var trackingRatio: CGFloat
    public var overscroll: Overscroll
    /// The deceleration rate used to project release velocity, as in `UIScrollView`.
    public var decelerationRate: CGFloat
    /// Whether every item stays reachable wherever the swipe starts. When the finger
    /// starts close to the end of the edge, tracking in that direction speeds up just
    /// enough to reach the last item before the safe area ends. `trackingRatio` is
    /// the minimum and is used as is whenever there is room.
    public var reachesAllItems: Bool

    public init(
        trackingRatio: CGFloat = 2,
        overscroll: Overscroll = .rubberBand(stiffness: 0.55),
        decelerationRate: CGFloat = 0.998,
        reachesAllItems: Bool = true
    ) {
        self.trackingRatio = trackingRatio
        self.overscroll = overscroll
        self.decelerationRate = decelerationRate
        self.reachesAllItems = reachesAllItems
    }

    /// The default: CariocaMenu's tracking with rubber-banded bounds.
    public static let fluid = FlickPhysics()
    /// CariocaMenu's exact behaviour: 2× tracking, an unbounded menu, and items
    /// that can be out of reach near the ends of the edge.
    public static let carioca = FlickPhysics(trackingRatio: 2, overscroll: .unbounded, reachesAllItems: false)
    /// Faster tracking that stops hard at the bounds.
    public static let snappy = FlickPhysics(trackingRatio: 2.5, overscroll: .clamped, decelerationRate: 0.99)
    /// A static menu that the finger slides over.
    public static let direct = FlickPhysics(trackingRatio: 1, overscroll: .clamped)

    /// Applies the overscroll behaviour to a menu offset.
    /// - Parameters:
    ///   - offset: The unconstrained offset.
    ///   - range: The offsets that keep the menu inside the safe area.
    ///   - dimension: The container's length, which scales the rubber band.
    public func constrain(_ offset: CGFloat, to range: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        switch overscroll {
        case .unbounded:
            offset
        case .clamped:
            min(max(offset, range.lowerBound), range.upperBound)
        case let .rubberBand(stiffness):
            Self.rubberBand(offset, in: range, dimension: dimension, stiffness: stiffness)
        }
    }

    /// The distance a release velocity carries, in points.
    /// - Parameter velocity: Points per second.
    public func projectedDistance(forVelocity velocity: CGFloat) -> CGFloat {
        guard decelerationRate > 0, decelerationRate < 1 else { return 0 }
        return velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    /// `UIScrollView`-style rubber banding: values outside `range` are pulled back,
    /// and the further they go, the stronger the pull.
    public static func rubberBand(
        _ value: CGFloat,
        in range: ClosedRange<CGFloat>,
        dimension: CGFloat,
        stiffness: CGFloat
    ) -> CGFloat {
        guard dimension > 0, stiffness > 0 else {
            return min(max(value, range.lowerBound), range.upperBound)
        }
        func band(_ overshoot: CGFloat) -> CGFloat {
            (1 - 1 / (overshoot * stiffness / dimension + 1)) * dimension
        }
        if value < range.lowerBound {
            return range.lowerBound - band(range.lowerBound - value)
        }
        if value > range.upperBound {
            return range.upperBound + band(value - range.upperBound)
        }
        return value
    }
}

/// The core tracking math, generalised from CariocaMenu.
///
/// Coordinates are along the menu's main axis (Y for left/right edges, X for top/bottom).
public enum FlickTracking {
    /// The offset of the menu's first item, such that the item selected when the
    /// gesture began starts under the finger, and the menu moves against the finger
    /// as it travels.
    ///
    /// With `trackingRatio == 2` this is exactly CariocaMenu's `topYConstraint`.
    public static func menuOffset(
        start: CGFloat,
        current: CGFloat,
        anchorIndex: Int,
        itemLength: CGFloat,
        trackingRatio: CGFloat
    ) -> CGFloat {
        start
            - itemLength * CGFloat(anchorIndex)
            - itemLength / 2
            - (trackingRatio - 1) * (current - start)
    }

    /// The finger's position in the menu, in items, before overscroll is applied:
    /// `k + 0.5` is the centre of item `k`. The anchor item starts under the finger.
    public static func progress(
        start: CGFloat,
        current: CGFloat,
        anchorIndex: Int,
        itemLength: CGFloat,
        trackingRatio: CGFloat
    ) -> CGFloat {
        guard itemLength > 0 else { return CGFloat(anchorIndex) + 0.5 }
        return CGFloat(anchorIndex) + 0.5 + trackingRatio * (current - start) / itemLength
    }

    /// The unclamped index under `position`. It can be negative or past the last item.
    public static func rawItemIndex(at position: CGFloat, menuOffset: CGFloat, itemLength: CGFloat) -> Int {
        guard itemLength > 0 else { return 0 }
        return flooredIndex((position - menuOffset) / itemLength)
    }

    /// The index containing a position measured in items, such as a progress.
    /// It can be negative or past the last item.
    static func flooredIndex(_ items: CGFloat) -> Int {
        let value = items.rounded(.down)
        guard value.isFinite else { return 0 }
        // Keep the conversion to Int safe for absurd offsets.
        return Int(max(min(value, CGFloat(Int32.max)), CGFloat(Int32.min)))
    }

    /// The item under `position`, clamped to the menu's items. `nil` when there are no items.
    ///
    /// This is CariocaMenu's `matchingIndex`.
    public static func itemIndex(
        at position: CGFloat,
        menuOffset: CGFloat,
        itemLength: CGFloat,
        itemCount: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }
        let raw = rawItemIndex(at: position, menuOffset: menuOffset, itemLength: itemLength)
        return min(max(raw, 0), itemCount - 1)
    }
}

/// Dock-style magnification of the items around the finger.
public struct FlickMagnification: Hashable, Sendable {
    /// The scale of the item directly under the finger.
    public var maximumScale: CGFloat
    /// How many items away from the finger the effect fades out.
    public var radius: CGFloat

    public init(maximumScale: CGFloat, radius: CGFloat) {
        self.maximumScale = maximumScale
        self.radius = radius
    }

    public static let disabled = FlickMagnification(maximumScale: 1, radius: 1)
    public static let subtle = FlickMagnification(maximumScale: 1.12, radius: 1.5)
    public static let dock = FlickMagnification(maximumScale: 1.35, radius: 2.5)

    /// The scale for an item at `distance` items from the finger.
    /// It falls off smoothly (raised cosine) to `1` at `radius`.
    public func scale(atDistance distance: CGFloat) -> CGFloat {
        guard radius > 0, maximumScale != 1 else { return 1 }
        let normalized = abs(distance) / radius
        guard normalized < 1 else { return 1 }
        let falloff = (1 + cos(Double.pi * Double(normalized))) / 2
        return 1 + (maximumScale - 1) * CGFloat(falloff)
    }
}

extension FlickEdgeValues where Value == FlickPhysics {
    /// The physics with tracking ratios applied on top: each edge's ratio, or the base
    /// ratio, replaces the physics' own. `nil` keeps it.
    public func applying(trackingRatios ratios: FlickEdgeValues<CGFloat?>) -> Self {
        var result = self
        if let ratio = ratios.base {
            result.base.trackingRatio = ratio
        }
        for edge in FlickScreenEdge.allCases {
            var value = self[edge]
            if let ratio = ratios[edge] {
                value.trackingRatio = ratio
            }
            result[edge] = value
        }
        return result
    }
}
