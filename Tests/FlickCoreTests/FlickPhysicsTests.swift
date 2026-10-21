import Foundation
import Testing
@testable import FlickCore

@Suite("Physics")
struct FlickPhysicsTests {
    @Test func trackingRatioOneKeepsTheMenuStill() {
        let first = FlickTracking.menuOffset(start: 300, current: 300, anchorIndex: 2, itemLength: 60, trackingRatio: 1)
        let moved = FlickTracking.menuOffset(start: 300, current: 500, anchorIndex: 2, itemLength: 60, trackingRatio: 1)
        #expect(first == moved)
    }

    @Test func higherRatiosReachItemsFaster() {
        func index(ratio: CGFloat) -> Int {
            let offset = FlickTracking.menuOffset(start: 300, current: 360, anchorIndex: 0, itemLength: 60, trackingRatio: ratio)
            return FlickTracking.rawItemIndex(at: 360, menuOffset: offset, itemLength: 60)
        }
        #expect(index(ratio: 1) == 1)
        #expect(index(ratio: 2) == 2)
        #expect(index(ratio: 3) == 3)
    }

    @Test func overscrollModes() {
        let range: ClosedRange<CGFloat> = 0...100
        #expect(FlickPhysics(overscroll: .unbounded).constrain(150, to: range, dimension: 800) == 150)
        #expect(FlickPhysics(overscroll: .clamped).constrain(150, to: range, dimension: 800) == 100)
        #expect(FlickPhysics(overscroll: .clamped).constrain(-5, to: range, dimension: 800) == 0)
        #expect(FlickPhysics(overscroll: .rubberBand(stiffness: 0.55)).constrain(50, to: range, dimension: 800) == 50)
    }

    @Test func rubberBandResistsAndStaysMonotonic() {
        let range: ClosedRange<CGFloat> = 0...100
        let near = FlickPhysics.rubberBand(110, in: range, dimension: 100, stiffness: 0.55)
        let far = FlickPhysics.rubberBand(200, in: range, dimension: 100, stiffness: 0.55)
        #expect(isApproximately(near, 105.213, tolerance: 0.01))
        #expect(near > 100 && near < 110)
        #expect(far > near && far < 200)
        let below = FlickPhysics.rubberBand(-10, in: range, dimension: 100, stiffness: 0.55)
        #expect(isApproximately(below, -5.213, tolerance: 0.01))
    }

    @Test func velocityProjection() {
        #expect(isApproximately(FlickPhysics().projectedDistance(forVelocity: 1000), 499))
        #expect(FlickPhysics(decelerationRate: 1).projectedDistance(forVelocity: 1000) == 0)
    }

    @Test func magnificationFallsOffSmoothly() {
        let magnification = FlickMagnification(maximumScale: 1.4, radius: 2)
        #expect(isApproximately(magnification.scale(atDistance: 0), 1.4))
        #expect(isApproximately(magnification.scale(atDistance: 1), 1.2))
        #expect(isApproximately(magnification.scale(atDistance: -1), 1.2))
        #expect(magnification.scale(atDistance: 2) == 1)
        #expect(magnification.scale(atDistance: 5) == 1)
        #expect(FlickMagnification.disabled.scale(atDistance: 0) == 1)
    }

    @Test func absurdOffsetsDoNotTrap() {
        #expect(FlickTracking.rawItemIndex(at: .greatestFiniteMagnitude, menuOffset: 0, itemLength: 1) == Int(Int32.max))
        #expect(FlickTracking.rawItemIndex(at: .nan, menuOffset: 0, itemLength: 60) == 0)
        #expect(FlickTracking.rawItemIndex(at: 100, menuOffset: 0, itemLength: 0) == 0)
    }
}
