#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import FlickCore

@Suite("Menu state machine")
struct FlickMenuMachineTests {
    /// A 400×800 portrait container with five 60pt items, CariocaMenu physics,
    /// and the indicator resting on the right edge at 400.
    private func makeMachine(
        boomerang: FlickBoomerang = .stay,
        itemCount: Int = 5,
        selectedIndex: Int = 0
    ) -> FlickMenuMachine {
        FlickMenuMachine(
            configuration: FlickMenuConfiguration(
                homeEdge: .right,
                homeFraction: 0.5,
                boomerang: FlickEdgeValues(boomerang),
                physics: FlickEdgeValues(.carioca),
                indicatorSize: FlickEdgeValues(CGSize(width: 50, height: 40))
            ),
            geometry: FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: itemCount),
            selectedIndex: selectedIndex
        )
    }

    @Test func startsClosedAtHome() {
        let machine = makeMachine()
        #expect(machine.phase == .closed)
        #expect(machine.indicator == FlickIndicatorState(edge: .right, position: 400))
    }

    @Test func swipeTrackAndRelease() {
        var machine = makeMachine()

        #expect(machine.send(.began(edge: .left, position: 300)) == [.opened(.left), .highlighted(0)])
        #expect(machine.session?.menuOffset == 270)

        #expect(machine.send(.moved(position: 330, velocity: 100)) == [.highlighted(1)])
        #expect(machine.session?.menuOffset == 240)
        #expect(machine.openIndicatorPosition == 330)

        #expect(machine.send(.moved(position: 360, velocity: 100)) == [.highlighted(2)])
        // No change, no effect.
        #expect(machine.send(.moved(position: 361, velocity: 10)).isEmpty)

        #expect(machine.send(.ended(velocity: 0)) == [.chose(2)])
        #expect(machine.selectedIndex == 2)
        #expect(machine.phase == .closed)
        // Boomerang `.stay`: the indicator stays next to the chosen item, on the swiped edge.
        #expect(machine.indicator.edge == .left)
        // Menu offset 209 (after the last move to 361) + 2×60 + 30.
        #expect(isApproximately(machine.indicator.position, 359))
    }

    @Test func trackingPositionFollowsTheFingerWithinTheItems() {
        var machine = makeMachine()
        #expect(machine.trackingPosition == nil)
        machine.send(.began(edge: .left, position: 300))
        #expect(machine.trackingPosition == 300)
        machine.send(.moved(position: 310, velocity: 0))
        #expect(isApproximately(machine.trackingPosition ?? 0, 310))
        // Past the first item, it stays on its centre.
        machine.send(.moved(position: 250, velocity: 0))
        #expect(isApproximately(machine.trackingPosition ?? 0, (machine.session?.menuOffset ?? 0) + 30))
    }

    @Test func selectedItemStartsUnderTheFinger() {
        var machine = makeMachine(selectedIndex: 3)
        #expect(machine.send(.began(edge: .right, position: 500)) == [.opened(.right), .highlighted(3)])
        // 500 - 3×60 - 30
        #expect(machine.session?.menuOffset == 290)
    }

    @Test(arguments: [
        (FlickBoomerang.stay, FlickScreenEdge.left, CGFloat(360)),
        (.edge, .right, 360),
        (.position, .left, 400),
        (.origin, .right, 400)
    ])
    func boomerangs(boomerang: FlickBoomerang, edge: FlickScreenEdge, position: CGFloat) {
        var machine = makeMachine(boomerang: boomerang)
        machine.send(.began(edge: .left, position: 300))
        machine.send(.moved(position: 360, velocity: 0))
        machine.send(.ended(velocity: 0))
        #expect(machine.indicator.edge == edge)
        #expect(isApproximately(machine.indicator.position, position))
    }

    @Test func stayKeepsTheIndicatorOnTheBottomEdge() {
        var machine = makeMachine(boomerang: .stay)
        machine.send(.began(edge: .bottom, position: 100))
        machine.send(.moved(position: 160, velocity: 0))
        #expect(machine.send(.ended(velocity: 0)) == [.chose(2)])
        #expect(machine.indicator.edge == .bottom)
        // Menu offset 10 (100 - 30 - 60) + 2×60 + 30.
        #expect(isApproximately(machine.indicator.position, 160))
    }

    @Test func edgeBoomerangAcrossAxesUsesHomePosition() {
        var machine = makeMachine(boomerang: .edge)
        machine.send(.began(edge: .top, position: 100))
        machine.send(.ended(velocity: 0))
        #expect(machine.indicator == FlickIndicatorState(edge: .right, position: 400))
    }

    @Test func boundaryIsReportedOnce() {
        var machine = makeMachine()
        machine.send(.began(edge: .left, position: 300))
        #expect(machine.send(.moved(position: 250, velocity: -200)) == [.boundaryReached])
        #expect(machine.send(.moved(position: 240, velocity: -200)).isEmpty)
        #expect(machine.session?.isBeyondBounds == true)
        #expect(machine.session?.highlightedIndex == 0)
    }

    @Test func cancelKeepsSelectionAndIndicator() {
        var machine = makeMachine(selectedIndex: 1)
        let indicator = machine.indicator
        machine.send(.began(edge: .left, position: 300))
        machine.send(.moved(position: 400, velocity: 0))
        #expect(machine.send(.cancelled) == [.dismissed])
        #expect(machine.selectedIndex == 1)
        #expect(machine.indicator == indicator)
    }

    @Test func secondSwipeIsIgnoredWhileTracking() {
        var machine = makeMachine()
        machine.send(.began(edge: .left, position: 300))
        #expect(machine.send(.began(edge: .right, position: 100)).isEmpty)
        #expect(machine.session?.edge == .left)
    }

    @Test func tapPresentsAndAnItemTapChooses() {
        var machine = makeMachine()
        #expect(machine.send(.tapIndicator) == [.opened(.right), .highlighted(0)])
        #expect(machine.session?.origin == .presentation)
        #expect(machine.session?.menuOffset == 370)

        // Finger movement belongs to swipes only.
        #expect(machine.send(.moved(position: 600, velocity: 0)).isEmpty)
        #expect(machine.send(.ended(velocity: 0)).isEmpty)

        #expect(machine.send(.chooseItem(3)) == [.chose(3)])
        #expect(machine.indicator == FlickIndicatorState(edge: .right, position: 580))
    }

    @Test func tappingTheIndicatorAgainDismisses() {
        var machine = makeMachine()
        machine.send(.tapIndicator)
        #expect(machine.send(.tapIndicator) == [.dismissed])
        #expect(!machine.isOpen)
    }

    @Test func aSwipeTakesOverAPresentedMenu() {
        var machine = makeMachine()
        machine.send(.tapIndicator)
        #expect(machine.send(.began(edge: .left, position: 300)) == [.opened(.left), .highlighted(0)])
        #expect(machine.session?.origin == .gesture)
    }

    @Test func programmaticOpenOnAnotherAxisUsesHomePosition() {
        var machine = makeMachine()
        #expect(machine.send(.open(edge: .bottom)) == [.opened(.bottom), .highlighted(0)])
        // Bottom edge: main axis is X, home is half of the 400pt width.
        #expect(machine.session?.start == 200)
        #expect(machine.send(.open(edge: nil)).isEmpty)
        #expect(machine.send(.dismiss) == [.dismissed])
        #expect(machine.send(.dismiss).isEmpty)
    }

    @Test func keysMoveTheHighlightAndChoose() {
        var machine = makeMachine(selectedIndex: 1)
        machine.send(.tapIndicator)
        #expect(machine.send(.moveHighlight(by: 1)) == [.highlighted(2)])
        #expect(machine.session?.progress == 2.5)
        #expect(machine.send(.moveHighlight(by: 10)) == [.highlighted(4)])
        #expect(machine.send(.moveHighlight(by: 1)) == [.boundaryReached])
        #expect(machine.send(.moveHighlight(by: -2)) == [.highlighted(2)])
        #expect(machine.send(.chooseHighlighted) == [.chose(2)])
        #expect(machine.selectedIndex == 2)
    }

    @Test func keysDoNothingDuringASwipeOrWhenClosed() {
        var machine = makeMachine()
        #expect(machine.send(.moveHighlight(by: 1)).isEmpty)
        #expect(machine.send(.chooseHighlighted).isEmpty)
        machine.send(.began(edge: .left, position: 300))
        #expect(machine.send(.moveHighlight(by: 1)).isEmpty)
        #expect(machine.session?.highlightedIndex == 0)
    }

    @Test func invalidItemChoicesAreIgnored() {
        var machine = makeMachine()
        #expect(machine.send(.chooseItem(0)).isEmpty)
        machine.send(.tapIndicator)
        #expect(machine.send(.chooseItem(5)).isEmpty)
        #expect(machine.send(.chooseItem(-1)).isEmpty)
        #expect(machine.isOpen)
    }

    @Test func emptyMenusNeverOpen() {
        var machine = makeMachine(itemCount: 0)
        #expect(machine.send(.began(edge: .left, position: 300)).isEmpty)
        #expect(machine.send(.tapIndicator).isEmpty)
        #expect(machine.phase == .closed)
    }

    @Test func rotationKeepsRelativeIndicatorPositionAndCloses() {
        var machine = makeMachine()
        machine.send(.began(edge: .left, position: 300))
        let landscape = FlickGeometry(containerSize: CGSize(width: 800, height: 400), itemLength: 60, itemCount: 5)
        #expect(machine.send(.geometryChanged(landscape)) == [.dismissed])
        #expect(machine.phase == .closed)
        #expect(machine.indicator == FlickIndicatorState(edge: .right, position: 200))
    }

    @Test func shrinkingTheMenuClampsTheSelection() {
        var machine = makeMachine(selectedIndex: 4)
        machine.send(.geometryChanged(FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: 2)))
        #expect(machine.selectedIndex == 1)
    }

    @Test func externalSelectionIsClamped() {
        var machine = makeMachine()
        machine.send(.selectionChanged(10))
        #expect(machine.selectedIndex == 4)
        machine.send(.selectionChanged(-3))
        #expect(machine.selectedIndex == 0)
    }

    @Test func rubberBandKeepsTheMenuNearTheScreen() {
        var machine = FlickMenuMachine(
            configuration: FlickMenuConfiguration(physics: FlickEdgeValues(.fluid)),
            geometry: FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: 5)
        )
        machine.send(.began(edge: .left, position: 100))
        machine.send(.moved(position: 700, velocity: 1000))
        // CariocaMenu physics would push the menu to -530; the rubber band
        // lets it pass the bound (0) but holds it much closer.
        let offset = machine.session?.menuOffset ?? 0
        #expect(offset < 0 && offset > -300)
    }
}

@Suite("Reaching every item")
struct FlickReachTests {
    /// A 400×800 container with a 34pt bottom inset and six 60pt items.
    private func makeMachine(physics: FlickPhysics, selectedIndex: Int = 0) -> FlickMenuMachine {
        FlickMenuMachine(
            configuration: FlickMenuConfiguration(physics: FlickEdgeValues(physics)),
            geometry: FlickGeometry(
                containerSize: CGSize(width: 400, height: 800),
                safeAreaInsets: FlickInsets(top: 0, left: 0, bottom: 34, right: 0),
                itemLength: 60,
                itemCount: 6
            ),
            selectedIndex: selectedIndex
        )
    }

    @Test func aSwipeNearTheBottomReachesTheLastItem() {
        var machine = makeMachine(physics: .fluid)
        #expect(machine.send(.began(edge: .right, position: 700)) == [.opened(.right), .highlighted(0)])
        // The safe area ends at 766; the last item's centre is reached half an item before.
        machine.send(.moved(position: 736, velocity: 0))
        #expect(machine.session?.highlightedIndex == 5)
        #expect(machine.session?.isBeyondBounds == false)
    }

    @Test func aSwipeInTheInsetStillReachesTheLastItem() {
        var machine = makeMachine(physics: .fluid)
        machine.send(.began(edge: .right, position: 780))
        machine.send(.moved(position: 790, velocity: 0))
        #expect(machine.session?.highlightedIndex == 5)
    }

    @Test func aSwipeNearTheTopReachesTheFirstItem() {
        var machine = makeMachine(physics: .snappy, selectedIndex: 5)
        machine.send(.began(edge: .left, position: 60))
        machine.send(.moved(position: 30, velocity: 0))
        #expect(machine.session?.highlightedIndex == 0)
    }

    @Test func theRatioIsKeptWhenThereIsRoom() {
        var machine = makeMachine(physics: .fluid)
        machine.send(.began(edge: .right, position: 100))
        machine.send(.moved(position: 130, velocity: 0))
        // 2× tracking: 30pt moves through one item.
        #expect(machine.session?.highlightedIndex == 1)
        #expect(machine.session?.menuOffset == 40)
    }

    @Test func overscrollDoesNotChangeTheHighlight() {
        // The menu would start below the screen, so the rubber band pulls it up,
        // but the selected item stays highlighted.
        var machine = makeMachine(physics: .fluid, selectedIndex: 0)
        #expect(machine.send(.began(edge: .right, position: 760)) == [.opened(.right), .highlighted(0)])
    }

    @Test func cariocaKeepsItsOriginalReach() {
        var machine = makeMachine(physics: .carioca)
        machine.send(.began(edge: .right, position: 700))
        machine.send(.moved(position: 736, velocity: 0))
        // 2× tracking only: 36pt moves through one item.
        #expect(machine.session?.highlightedIndex == 1)
    }
}

@Suite("Per-edge behaviour")
struct FlickPerEdgeMachineTests {
    @Test func boomerangAndPhysicsFollowTheOpeningEdge() {
        var boomerang = FlickEdgeValues(FlickBoomerang.stay)
        boomerang[.top] = .origin
        var physics = FlickEdgeValues(FlickPhysics.carioca)
        physics[.left] = .direct
        var machine = FlickMenuMachine(
            configuration: FlickMenuConfiguration(homeEdge: .right, boomerang: boomerang, physics: physics),
            geometry: FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: 5)
        )

        // `.direct` physics on the left edge: the menu does not move with the finger.
        machine.send(.began(edge: .left, position: 300))
        machine.send(.moved(position: 420, velocity: 0))
        #expect(machine.session?.menuOffset == 270)
        machine.send(.ended(velocity: 0))
        #expect(machine.indicator.edge == .left)

        // `.origin` boomerang on the top edge: back home.
        machine.send(.began(edge: .top, position: 200))
        machine.send(.ended(velocity: 0))
        #expect(machine.indicator == FlickIndicatorState(edge: .right, position: 400))
    }
}

@Suite("Configuration updates")
struct FlickConfigurationUpdateTests {
    @Test func changingTheHomeEdgeSendsTheIndicatorHome() {
        var machine = FlickMenuMachine(
            configuration: FlickMenuConfiguration(homeEdge: .right),
            geometry: FlickGeometry(containerSize: CGSize(width: 400, height: 800), itemLength: 60, itemCount: 5)
        )
        machine.update(configuration: FlickMenuConfiguration(homeEdge: .bottom, homeFraction: 0.25))
        #expect(machine.indicator == FlickIndicatorState(edge: .bottom, position: 100))
    }
}
