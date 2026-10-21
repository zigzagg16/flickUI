#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The metrics of a menu, which can differ per edge.
public struct FlickMenuLayout: Equatable, Sendable {
    /// The length of each item along the edge.
    public var itemLength: CGFloat
    /// The indicator's size, oriented to its edge: `width` is its extent away from
    /// the edge and `height` its extent along it. It is rotated for the top and bottom edges.
    public var indicatorSize: CGSize
    /// How far the resting indicator tucks past the edge, and the gap it keeps
    /// from the far edge while the menu is open.
    public var indicatorMargin: CGFloat

    public init(itemLength: CGFloat = 60, indicatorSize: CGSize = CGSize(width: 50, height: 40), indicatorMargin: CGFloat = 5) {
        self.itemLength = itemLength
        self.indicatorSize = indicatorSize
        self.indicatorMargin = indicatorMargin
    }

    /// The indicator's physical size on an edge.
    public func indicatorFrame(for edge: FlickScreenEdge) -> CGSize {
        switch edge.mainAxis {
        case .vertical: indicatorSize
        case .horizontal: CGSize(width: indicatorSize.height, height: indicatorSize.width)
        }
    }
}

extension FlickEdgeValues where Value == FlickMenuLayout {
    /// The physical indicator size for each edge.
    public var indicatorFrames: FlickEdgeValues<CGSize> {
        var frames = FlickEdgeValues<CGSize>(base.indicatorFrame(for: .left))
        for edge in FlickScreenEdge.allCases where edge.mainAxis == .horizontal || overrides[edge] != nil {
            frames[edge] = self[edge].indicatorFrame(for: edge)
        }
        return frames
    }
}
