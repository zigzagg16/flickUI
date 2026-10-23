#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import FlickCore
import Foundation
import Testing

@Suite("Edges and geometry")
struct FlickGeometryTests {
    @Test func logicalEdgesFollowLayoutDirection() {
        #expect(FlickEdge.leading.resolved(isRightToLeft: false) == .left)
        #expect(FlickEdge.leading.resolved(isRightToLeft: true) == .right)
        #expect(FlickEdge.trailing.resolved(isRightToLeft: true) == .left)
        #expect(FlickEdge.top.resolved(isRightToLeft: true) == .top)
    }

    @Test func edgeSets() {
        #expect(FlickEdgeSet.all.edges == [.leading, .trailing, .top, .bottom])
        #expect(FlickEdgeSet.vertical.edges == [.top, .bottom])
        #expect(FlickEdgeSet.horizontal.contains(.trailing))
        #expect(!FlickEdgeSet.horizontal.contains(.bottom))
    }

    @Test func axes() {
        #expect(FlickScreenEdge.left.mainAxis == .vertical)
        #expect(FlickScreenEdge.bottom.mainAxis == .horizontal)
        #expect(FlickScreenEdge.top.crossAxis == .vertical)
        #expect(FlickScreenEdge.bottom.opposite == .top)
    }

    @Test func pointsFromEdgeCoordinates() {
        let size = CGSize(width: 400, height: 800)
        #expect(FlickScreenEdge.right.point(main: 100, distanceFromEdge: 30, in: size) == CGPoint(x: 370, y: 100))
        #expect(FlickScreenEdge.bottom.point(main: 100, distanceFromEdge: 30, in: size) == CGPoint(x: 100, y: 770))
        #expect(FlickScreenEdge.top.distance(toCrossCoordinate: 50, in: size) == 50)
        #expect(FlickScreenEdge.bottom.distance(toCrossCoordinate: 750, in: size) == 50)
    }

    @Test func menuOffsetRangeKeepsMenuInSafeArea() {
        let short = FlickGeometry(
            containerSize: CGSize(width: 375, height: 800),
            safeAreaInsets: FlickInsets(top: 20),
            itemLength: 60,
            itemCount: 5
        )
        #expect(short.menuOffsetRange(for: .left) == 20...500)

        var long = short
        long.itemCount = 20
        // The menu is taller than the screen: it may slide far enough to show both ends.
        #expect(long.menuOffsetRange(for: .left) == -400...20)
    }

    @Test func topEdgeUsesHorizontalMainAxis() {
        let geometry = FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 80, itemCount: 4)
        #expect(geometry.menuOffsetRange(for: .top) == 0...80)
        let size = CGSize(width: 50, height: 40)
        #expect(isApproximately(geometry.restingIndicatorPosition(fraction: 0.5, for: .top, indicatorSize: size), 200))
        #expect(geometry.restingIndicatorRange(for: .top, indicatorSize: size) == 50...350)
    }

    @Test func indicatorPlacementOnTopEdgeRespectsDynamicIsland() {
        let geometry = FlickGeometry(
            containerSize: CGSize(width: 375, height: 667),
            safeAreaInsets: FlickInsets(top: 59),
            itemLength: 60,
            itemCount: 5
        )
        let placement = geometry.indicatorPlacement(for: .top, indicatorSize: CGSize(width: 50, height: 40), margin: 5)
        #expect(placement == FlickIndicatorPlacement(resting: 74, traversed: 642, hidden: 707))
    }

    @Test func itemCentersAndDistances() {
        let geometry = FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: 5)
        #expect(geometry.itemCenter(at: 2, menuOffset: 100, edge: .left) == 250)
        #expect(isApproximately(geometry.distance(ofItem: 2, from: 280, menuOffset: 100, edge: .left), 0.5))
        #expect(isApproximately(geometry.distance(ofItem: 3, from: 280, menuOffset: 100, edge: .left), -0.5))
        #expect(geometry.itemIndex(at: 280, menuOffset: 100, edge: .left) == 3)
    }

    @Test func noItems() {
        let geometry = FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: 0)
        #expect(geometry.itemIndex(at: 100, menuOffset: 0, edge: .left) == nil)
        #expect(geometry.menuLength(for: .left) == 0)
    }

    @Test func tinyContainerStillHasAValidRestingRange() {
        let geometry = FlickGeometry(containerSize: CGSize(width: 30, height: 30), itemLength: 60, itemCount: 1)
        let range = geometry.restingIndicatorRange(for: .left, indicatorSize: CGSize(width: 50, height: 40))
        #expect(range.lowerBound == range.upperBound)
    }
}

@Suite("Per-edge values")
struct FlickEdgeValuesTests {
    @Test func overridesWinOverTheBase() {
        var values = FlickEdgeValues<CGFloat>(60)
        values[.top] = 80
        #expect(values[.left] == 60)
        #expect(values[.top] == 80)
    }

    @Test func settingAllKeepsEdgeOverridesWhateverTheOrder() {
        var settings = FlickEdgeSettings(FlickPhysics.fluid)
        settings.set(.snappy, for: .vertical)
        settings.set(.carioca, for: .all)
        #expect(settings[.leading] == .carioca)
        #expect(settings[.top] == .snappy)
        #expect(settings[.bottom] == .snappy)
    }

    @Test func logicalSettingsResolveForRightToLeft() {
        var settings = FlickEdgeSettings<CGFloat>(60)
        settings.set(44, for: .leading)
        #expect(settings.resolved(isRightToLeft: false)[.left] == 44)
        #expect(settings.resolved(isRightToLeft: true)[.right] == 44)
        #expect(settings.resolved(isRightToLeft: true)[.left] == 60)
    }

    @Test func geometryUsesTheOpeningEdgesItemLength() {
        var itemLength: FlickEdgeValues<CGFloat> = 60
        itemLength[.top] = 100
        let geometry = FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: itemLength, itemCount: 3)
        #expect(geometry.menuLength(for: .left) == 180)
        #expect(geometry.menuLength(for: .top) == 300)
        #expect(geometry.itemCenter(at: 1, menuOffset: 0, edge: .top) == 150)
    }
}

@Suite("Layout")
struct FlickMenuLayoutTests {
    @Test func indicatorIsRotatedForTopAndBottomEdges() {
        let layout = FlickMenuLayout(indicatorSize: CGSize(width: 50, height: 40))
        #expect(layout.indicatorFrame(for: .left) == CGSize(width: 50, height: 40))
        #expect(layout.indicatorFrame(for: .bottom) == CGSize(width: 40, height: 50))
    }

    @Test func indicatorFramesHonourOverrides() {
        var layouts = FlickEdgeValues(FlickMenuLayout())
        layouts[.right] = FlickMenuLayout(indicatorSize: CGSize(width: 60, height: 60))
        let frames = layouts.indicatorFrames
        #expect(frames[.left] == CGSize(width: 50, height: 40))
        #expect(frames[.right] == CGSize(width: 60, height: 60))
        #expect(frames[.top] == CGSize(width: 40, height: 50))
    }

    @Test func physicalEdgesMapBackToLogicalOnes() {
        for edge in FlickEdge.allCases {
            for rtl in [false, true] {
                #expect(edge.resolved(isRightToLeft: rtl).logical(isRightToLeft: rtl) == edge)
            }
        }
    }

    @Test func directLookupMatchesResolvedSettings() {
        var settings = FlickEdgeSettings(1)
        settings.set(2, for: .leading)
        settings.set(3, for: .top)
        for rtl in [false, true] {
            let resolved = settings.resolved(isRightToLeft: rtl)
            for edge in FlickScreenEdge.allCases {
                #expect(settings.value(for: edge, isRightToLeft: rtl) == resolved[edge])
            }
        }
    }

    @Test func defaultConfigurationRotatesTheIndicatorForTopAndBottom() {
        let sizes = FlickMenuConfiguration().indicatorSize
        #expect(sizes[.right] == FlickMenuLayout().indicatorSize)
        #expect(sizes[.top] == FlickMenuLayout().indicatorFrame(for: .top))
    }

    @Test func mapTransformsBaseAndOverrides() {
        var values = FlickEdgeValues<CGFloat>(10)
        values[.top] = 20
        let doubled = values.map { $0 * 2 }
        #expect(doubled[.left] == 20)
        #expect(doubled[.top] == 40)
    }
}
