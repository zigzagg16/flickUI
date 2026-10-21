#if canImport(UIKit)
import FlickCore
import SwiftUI

/// CariocaMenu's indicator bubble, ported from its PaintCode path and generalised
/// to all four edges. The rounder side faces the edge.
public struct FlickBubbleShape: Shape {
    public let edge: FlickScreenEdge

    public init(edge: FlickScreenEdge) {
        self.edge = edge
    }

    public nonisolated func path(in rect: CGRect) -> Path {
        let vertical = edge.mainAxis == .vertical
        // Cross: away from the edge. Main: along the edge.
        let cross = vertical ? rect.width : rect.height
        let main = vertical ? rect.height : rect.width
        // The original constants were drawn for a 50pt-wide indicator.
        let k = cross / 50
        let edge = self.edge

        func point(_ c: CGFloat, _ m: CGFloat) -> CGPoint {
            switch edge {
            case .left: CGPoint(x: rect.minX + c, y: rect.minY + m)
            case .right: CGPoint(x: rect.maxX - c, y: rect.minY + m)
            case .top: CGPoint(x: rect.minX + m, y: rect.minY + c)
            case .bottom: CGPoint(x: rect.minX + m, y: rect.maxY - c)
            }
        }

        var path = Path()
        path.move(to: point(cross, 0.5 * main))
        path.addCurve(
            to: point(cross - 20 * k, 0),
            control1: point(cross, 0.22 * main),
            control2: point(cross - 9 * k, 0)
        )
        path.addCurve(
            to: point(0, 0.5 * main),
            control1: point(cross - 31 * k, 0),
            control2: point(0, 0.3 * main)
        )
        path.addCurve(
            to: point(cross - 20 * k, main),
            control1: point(0, 0.7 * main),
            control2: point(cross - 31 * k, main)
        )
        path.addCurve(
            to: point(cross, 0.5 * main),
            control1: point(cross - 9 * k, main),
            control2: point(cross, 0.78 * main)
        )
        path.closeSubpath()
        return path
    }
}
#endif
