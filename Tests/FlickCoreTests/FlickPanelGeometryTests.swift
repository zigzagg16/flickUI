#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import FlickCore
import Foundation
import Testing

@Suite("Contained backgrounds")
struct FlickPanelGeometryTests {
    let size = CGSize(width: 400, height: 800)
    let insets = FlickInsets(top: 50, bottom: 30)

    @Test func cardPadsTheLabels() {
        let labels = CGRect(x: 40, y: 300, width: 180, height: 200)
        let frame = FlickPanelGeometry.frame(around: labels, extent: .card, edge: .right, containerSize: size, padding: 16)
        #expect(frame == CGRect(x: 24, y: 284, width: 212, height: 232))
    }

    @Test func cardStaysInsideTheSafeArea() {
        // A menu longer than the screen.
        let labels = CGRect(x: 40, y: -300, width: 180, height: 1_600)
        let frame = FlickPanelGeometry.frame(
            around: labels, extent: .card, edge: .right, containerSize: size, safeAreaInsets: insets, padding: 16
        )
        let margin = FlickPanelGeometry.screenMargin
        #expect(frame == CGRect(x: 24, y: 50 + margin, width: 212, height: 800 - 50 - 30 - 2 * margin))
    }

    @Test func noCardWithoutVisibleLabels() {
        let offscreen = CGRect(x: 40, y: 900, width: 180, height: 200)
        #expect(FlickPanelGeometry.frame(around: offscreen, extent: .card, edge: .right, containerSize: size, padding: 16) == nil)
        #expect(FlickPanelGeometry.frame(around: .null, extent: .drawer, edge: .right, containerSize: size, padding: 16) == nil)
    }

    @Test func drawerHugsTheSideTheRowsSitOn() {
        let labels = CGRect(x: 40, y: 300, width: 180, height: 200)
        // Opened from the right: the rows, and the drawer, are on the left.
        let fromRight = FlickPanelGeometry.frame(
            around: labels, extent: .drawer, edge: .right, containerSize: size, padding: 16, overhang: 30
        )
        #expect(fromRight == CGRect(x: -30, y: -30, width: 236 + 30, height: 860))

        let right = CGRect(x: 180, y: 300, width: 180, height: 200)
        let fromLeft = FlickPanelGeometry.frame(
            around: right, extent: .drawer, edge: .left, containerSize: size, padding: 16, overhang: 30
        )
        #expect(fromLeft == CGRect(x: 164, y: -30, width: 400 + 30 - 164, height: 860))
    }

    @Test func drawerAlongTheBottom() {
        let labels = CGRect(x: -100, y: 40, width: 600, height: 60)
        let fromBottom = FlickPanelGeometry.frame(around: labels, extent: .drawer, edge: .bottom, containerSize: size, padding: 10)
        #expect(fromBottom == CGRect(x: 0, y: 0, width: 400, height: 110))
    }
}
