import Foundation

/// The geometry the menu is laid out in. Everything is computed from live values,
/// so rotation, window resizing and safe-area changes need no special handling.
public struct FlickGeometry: Equatable, Sendable {
    /// The size of the container the menu covers.
    public var containerSize: CGSize
    /// The container's safe-area insets.
    public var safeAreaInsets: FlickInsets
    /// The length of one item along the main axis, per edge. All items of a menu
    /// share it, because the index math depends on it.
    public var itemLength: FlickEdgeValues<CGFloat>
    /// The number of items.
    public var itemCount: Int

    public init(
        containerSize: CGSize,
        safeAreaInsets: FlickInsets = .zero,
        itemLength: FlickEdgeValues<CGFloat>,
        itemCount: Int
    ) {
        self.containerSize = containerSize
        self.safeAreaInsets = safeAreaInsets
        self.itemLength = itemLength
        self.itemCount = itemCount
    }

    /// The total length of the menu opened from an edge.
    public func menuLength(for edge: FlickScreenEdge) -> CGFloat {
        itemLength[edge] * CGFloat(max(itemCount, 0))
    }

    /// The container's length along the edge's main axis.
    public func mainLength(for edge: FlickScreenEdge) -> CGFloat {
        edge.mainAxis.length(of: containerSize)
    }

    /// The container's length along the edge's cross axis.
    public func crossLength(for edge: FlickScreenEdge) -> CGFloat {
        edge.crossAxis.length(of: containerSize)
    }

    // MARK: Menu

    /// The menu offsets that keep the whole menu inside the safe area.
    /// When the menu is longer than the safe area, the range lets it slide
    /// far enough to reach both ends.
    public func menuOffsetRange(for edge: FlickScreenEdge) -> ClosedRange<CGFloat> {
        let insets = safeAreaInsets.along(edge.mainAxis)
        let lower = insets.start
        let upper = mainLength(for: edge) - insets.end - menuLength(for: edge)
        return upper >= lower ? lower...upper : upper...lower
    }

    /// The menu offset while tracking, with the physics' overscroll behaviour applied.
    public func menuOffset(
        for edge: FlickScreenEdge,
        start: CGFloat,
        current: CGFloat,
        anchorIndex: Int,
        physics: FlickPhysics
    ) -> CGFloat {
        let raw = FlickTracking.menuOffset(
            start: start,
            current: current,
            anchorIndex: anchorIndex,
            itemLength: itemLength[edge],
            trackingRatio: physics.trackingRatio
        )
        return physics.constrain(raw, to: menuOffsetRange(for: edge), dimension: mainLength(for: edge))
    }

    /// The item under a main-axis position, or `nil` when there are no items.
    public func itemIndex(at position: CGFloat, menuOffset: CGFloat, edge: FlickScreenEdge) -> Int? {
        FlickTracking.itemIndex(at: position, menuOffset: menuOffset, itemLength: itemLength[edge], itemCount: itemCount)
    }

    /// The main-axis centre of an item.
    public func itemCenter(at index: Int, menuOffset: CGFloat, edge: FlickScreenEdge) -> CGFloat {
        let length = itemLength[edge]
        return menuOffset + length * CGFloat(index) + length / 2
    }

    /// The signed distance, in items, between an item's centre and a position.
    /// Negative when the position is before the item. Drives per-item effects such as magnification.
    public func distance(ofItem index: Int, from position: CGFloat, menuOffset: CGFloat, edge: FlickScreenEdge) -> CGFloat {
        let length = itemLength[edge]
        guard length > 0 else { return 0 }
        return (position - itemCenter(at: index, menuOffset: menuOffset, edge: edge)) / length
    }

    // MARK: Indicator

    /// The indicator's cross-axis placements, as distances from `edge` to its centre.
    ///
    /// - Parameters:
    ///   - indicatorSize: The indicator's size.
    ///   - margin: How far the resting indicator tucks past the edge,
    ///     and the gap it keeps from the far edge once it has traversed the screen.
    public func indicatorPlacement(
        for edge: FlickScreenEdge,
        indicatorSize: CGSize,
        margin: CGFloat
    ) -> FlickIndicatorPlacement {
        let size = edge.crossAxis.length(of: indicatorSize)
        let half = size / 2
        let crossExtent = crossLength(for: edge)
        return FlickIndicatorPlacement(
            resting: safeAreaInsets[edge] + half - margin,
            traversed: crossExtent - safeAreaInsets[edge.opposite] - half - margin,
            hidden: crossExtent + size
        )
    }

    /// The main-axis positions the resting indicator's centre may take.
    /// - Parameter spacing: The gap kept from the safe area. Defaults to half the
    ///   indicator's length, as in CariocaMenu.
    public func restingIndicatorRange(
        for edge: FlickScreenEdge,
        indicatorSize: CGSize,
        spacing: CGFloat? = nil
    ) -> ClosedRange<CGFloat> {
        let length = edge.mainAxis.length(of: indicatorSize)
        let gap = spacing ?? length / 2
        let insets = safeAreaInsets.along(edge.mainAxis)
        let lower = insets.start + length / 2 + gap
        let upper = mainLength(for: edge) - insets.end - length / 2 - gap
        guard upper >= lower else {
            let middle = (lower + upper) / 2
            return middle...middle
        }
        return lower...upper
    }

    /// The resting indicator's main-axis centre for a fraction of the container (0 = start, 1 = end).
    public func restingIndicatorPosition(
        fraction: CGFloat,
        for edge: FlickScreenEdge,
        indicatorSize: CGSize,
        spacing: CGFloat? = nil
    ) -> CGFloat {
        let range = restingIndicatorRange(for: edge, indicatorSize: indicatorSize, spacing: spacing)
        return range.clamp(mainLength(for: edge) * fraction)
    }
}

/// The indicator's cross-axis placements, as distances from the opening edge to its centre.
public struct FlickIndicatorPlacement: Hashable, Sendable {
    /// At rest, tucked against the edge.
    public var resting: CGFloat
    /// While the menu is open, against the opposite edge.
    public var traversed: CGFloat
    /// Fully off-screen, past the opposite edge. Used by boomerang restores.
    public var hidden: CGFloat

    public init(resting: CGFloat, traversed: CGFloat, hidden: CGFloat) {
        self.resting = resting
        self.traversed = traversed
        self.hidden = hidden
    }
}

extension ClosedRange where Bound == CGFloat {
    /// The value, limited to the range.
    public func clamp(_ value: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
