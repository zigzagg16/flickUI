#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import FlickCore

/// CariocaMenu's original test vectors, so `.carioca` physics keep its exact feel.
@Suite("CariocaMenu regression")
struct CariocaRegressionTests {
    @Test func topConstraintCalculation() {
        let offset1 = FlickTracking.menuOffset(start: 342, current: 40, anchorIndex: 1, itemLength: 60, trackingRatio: 2)
        let offset2 = FlickTracking.menuOffset(start: 50, current: 40, anchorIndex: 3, itemLength: 60, trackingRatio: 2)
        let unclamped = FlickTracking.menuOffset(start: 600, current: 40, anchorIndex: 3, itemLength: 60, trackingRatio: 2)
        let offset3 = FlickPhysics(overscroll: .clamped).constrain(unclamped, to: 20...700, dimension: 800)

        #expect(isApproximately(offset1, 554))
        #expect(isApproximately(offset2, -150))
        #expect(isApproximately(offset3, 700))
    }

    @Test func matchingIndexCalculation() {
        #expect(FlickTracking.itemIndex(at: 40, menuOffset: 342, itemLength: 60, itemCount: 10) == 0)
        #expect(FlickTracking.itemIndex(at: 390, menuOffset: 290, itemLength: 60, itemCount: 10) == 1)
    }

    /// CariocaMenu expressed indicator positions relative to the host's centre X.
    private func centerRelative(_ distance: CGFloat, edge: FlickScreenEdge, size: CGSize) -> CGFloat {
        edge.crossCoordinate(atDistance: distance, in: size) - size.width / 2
    }

    @Test(arguments: [
        // edge, inset, resting (start), traversed (end.to), hidden
        (FlickScreenEdge.left, CGFloat(0), CGFloat(-167.5), CGFloat(157.5), CGFloat(237.5)),
        (.right, 0, 167.5, -157.5, -237.5),
        (.left, 44, -123.5, 113.5, 237.5),
        (.right, 44, 123.5, -113.5, -237.5)
    ])
    func indicatorPositions(edge: FlickScreenEdge, inset: CGFloat, start: CGFloat, end: CGFloat, hiding: CGFloat) {
        let size = CGSize(width: 375, height: 667)
        let geometry = FlickGeometry(
            containerSize: size,
            safeAreaInsets: FlickInsets(left: inset, right: inset),
            itemLength: 60,
            itemCount: 5
        )
        let placement = geometry.indicatorPlacement(for: edge, indicatorSize: CGSize(width: 50, height: 40), margin: 5)

        #expect(isApproximately(centerRelative(placement.resting, edge: edge, size: size), start))
        #expect(isApproximately(centerRelative(placement.traversed, edge: edge, size: size), end))
        #expect(isApproximately(centerRelative(placement.hidden, edge: edge, size: size), hiding))
    }

    @Test func restingPositionMatchesPercentages() {
        let geometry = FlickGeometry(containerSize: CGSize(width: 375, height: 800), itemLength: 60, itemCount: 5)
        let size = CGSize(width: 50, height: 40)
        #expect(isApproximately(geometry.restingIndicatorPosition(fraction: 0.5, for: .left, indicatorSize: size), 400))
        #expect(isApproximately(geometry.restingIndicatorPosition(fraction: 0, for: .left, indicatorSize: size), 40))
        #expect(isApproximately(geometry.restingIndicatorPosition(fraction: 1, for: .left, indicatorSize: size), 760))
    }
}
