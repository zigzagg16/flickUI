import Foundation

/// A logical screen edge the menu can be opened from.
///
/// `leading` and `trailing` follow the layout direction, so the menu mirrors
/// correctly in right-to-left languages.
public enum FlickEdge: Hashable, Sendable, CaseIterable {
    case leading
    case trailing
    case top
    case bottom

    /// The physical edge for a layout direction.
    public func resolved(isRightToLeft: Bool) -> FlickScreenEdge {
        switch self {
        case .leading: isRightToLeft ? .right : .left
        case .trailing: isRightToLeft ? .left : .right
        case .top: .top
        case .bottom: .bottom
        }
    }
}

/// A set of logical edges, following the shape of SwiftUI's `Edge.Set`.
public struct FlickEdgeSet: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(_ edge: FlickEdge) {
        switch edge {
        case .leading: self = .leading
        case .trailing: self = .trailing
        case .top: self = .top
        case .bottom: self = .bottom
        }
    }

    public static let leading = FlickEdgeSet(rawValue: 1 << 0)
    public static let trailing = FlickEdgeSet(rawValue: 1 << 1)
    public static let top = FlickEdgeSet(rawValue: 1 << 2)
    public static let bottom = FlickEdgeSet(rawValue: 1 << 3)

    /// Leading and trailing.
    public static let horizontal: FlickEdgeSet = [.leading, .trailing]
    /// Top and bottom.
    public static let vertical: FlickEdgeSet = [.top, .bottom]
    /// Every edge.
    public static let all: FlickEdgeSet = [.horizontal, .vertical]

    /// The edges in the set, in declaration order.
    public var edges: [FlickEdge] {
        FlickEdge.allCases.filter { contains(FlickEdgeSet($0)) }
    }
}

/// A physical screen edge. The engine works only with physical edges;
/// logical edges are resolved once, at the UI layer.
public enum FlickScreenEdge: Hashable, Sendable, CaseIterable {
    case left
    case right
    case top
    case bottom

    /// The edge on the other side of the screen.
    public var opposite: FlickScreenEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    /// The axis menu items are laid out along when the menu opens from this edge.
    /// A swipe from the left or right edge lays items out vertically.
    public var mainAxis: FlickAxis {
        switch self {
        case .left, .right: .vertical
        case .top, .bottom: .horizontal
        }
    }

    /// The axis pointing away from this edge, into the screen.
    public var crossAxis: FlickAxis {
        mainAxis.perpendicular
    }

    /// Converts a distance from this edge into an absolute cross-axis coordinate.
    public func crossCoordinate(atDistance distance: CGFloat, in size: CGSize) -> CGFloat {
        switch self {
        case .left, .top: distance
        case .right: size.width - distance
        case .bottom: size.height - distance
        }
    }

    /// The distance between this edge and an absolute cross-axis coordinate.
    public func distance(toCrossCoordinate coordinate: CGFloat, in size: CGSize) -> CGFloat {
        // The conversion is its own inverse.
        crossCoordinate(atDistance: coordinate, in: size)
    }

    /// Builds a point from a main-axis coordinate and a distance from this edge.
    public func point(main: CGFloat, distanceFromEdge distance: CGFloat, in size: CGSize) -> CGPoint {
        let cross = crossCoordinate(atDistance: distance, in: size)
        switch mainAxis {
        case .vertical: return CGPoint(x: cross, y: main)
        case .horizontal: return CGPoint(x: main, y: cross)
        }
    }
}

/// A layout axis.
public enum FlickAxis: Hashable, Sendable {
    case horizontal
    case vertical

    public var perpendicular: FlickAxis {
        self == .horizontal ? .vertical : .horizontal
    }

    /// The point's coordinate along this axis.
    public func value(of point: CGPoint) -> CGFloat {
        self == .horizontal ? point.x : point.y
    }

    /// The size's length along this axis.
    public func length(of size: CGSize) -> CGFloat {
        self == .horizontal ? size.width : size.height
    }
}

/// Physical insets, such as safe-area insets.
public struct FlickInsets: Hashable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = FlickInsets()

    public subscript(edge: FlickScreenEdge) -> CGFloat {
        switch edge {
        case .left: left
        case .right: right
        case .top: top
        case .bottom: bottom
        }
    }

    /// The insets at the start (top/left) and end (bottom/right) of an axis.
    public func along(_ axis: FlickAxis) -> (start: CGFloat, end: CGFloat) {
        switch axis {
        case .horizontal: (start: left, end: right)
        case .vertical: (start: top, end: bottom)
        }
    }
}
