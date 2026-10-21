#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Where the indicator goes after an item is chosen.
public enum FlickBoomerang: Hashable, Sendable {
    /// It stays on the edge the menu was opened from, next to the chosen item.
    /// (CariocaMenu's `.none`.)
    case stay
    /// It returns to its home edge, keeping its position when the axis allows.
    /// (CariocaMenu's `.horizontal`.)
    case edge
    /// It returns to its home position along the edge the menu was opened from.
    /// (CariocaMenu's `.vertical`.)
    case position
    /// It returns to its home edge and home position. (CariocaMenu's `.originalPosition`.)
    case origin
}

/// The settings of a menu. Behaviour can differ per edge: each value is read for
/// the edge the menu was opened from.
public struct FlickMenuConfiguration: Equatable, Sendable {
    /// The edge the indicator starts on.
    public var homeEdge: FlickScreenEdge
    /// The indicator's starting position along its edge, from 0 (start) to 1 (end).
    public var homeFraction: CGFloat
    public var boomerang: FlickEdgeValues<FlickBoomerang>
    public var physics: FlickEdgeValues<FlickPhysics>
    /// The indicator's size, used to keep it inside the safe area.
    public var indicatorSize: FlickEdgeValues<CGSize>

    public static let defaultIndicatorSize = CGSize(width: 50, height: 40)

    public init(
        homeEdge: FlickScreenEdge = .right,
        homeFraction: CGFloat = 0.5,
        boomerang: FlickEdgeValues<FlickBoomerang> = FlickEdgeValues(.stay),
        physics: FlickEdgeValues<FlickPhysics> = FlickEdgeValues(.fluid),
        indicatorSize: FlickEdgeValues<CGSize> = FlickEdgeValues(FlickMenuConfiguration.defaultIndicatorSize)
    ) {
        self.homeEdge = homeEdge
        self.homeFraction = homeFraction
        self.boomerang = boomerang
        self.physics = physics
        self.indicatorSize = indicatorSize
    }
}

/// Where the indicator rests while the menu is closed.
public struct FlickIndicatorState: Hashable, Sendable {
    public var edge: FlickScreenEdge
    /// The main-axis centre.
    public var position: CGFloat

    public init(edge: FlickScreenEdge, position: CGFloat) {
        self.edge = edge
        self.position = position
    }
}

/// One opening of the menu.
public struct FlickSession: Hashable, Sendable {
    /// How the menu was opened.
    public enum Origin: Hashable, Sendable {
        /// An edge swipe. Lifting the finger chooses the highlighted item.
        case gesture
        /// A tap on the indicator, or a programmatic open. The menu stays open until
        /// an item is tapped or it is dismissed.
        case presentation
    }

    public var origin: Origin
    public var edge: FlickScreenEdge
    /// The selected index when the menu opened. This item starts under the finger.
    public var anchorIndex: Int
    /// The main-axis position where the session began.
    public var start: CGFloat
    /// The current main-axis position of the finger.
    public var current: CGFloat
    /// The finger's main-axis velocity, in points per second.
    public var velocity: CGFloat
    /// The offset of the menu's first item along the main axis.
    public var menuOffset: CGFloat
    public var highlightedIndex: Int
    /// Whether the finger has gone past the first or last item.
    public var isBeyondBounds: Bool
}

/// The menu's phase.
public enum FlickPhase: Hashable, Sendable {
    case closed
    case open(FlickSession)
}

/// Inputs to the menu.
public enum FlickEvent: Equatable, Sendable {
    /// An edge swipe began at a main-axis position.
    case began(edge: FlickScreenEdge, position: CGFloat)
    /// The finger moved.
    case moved(position: CGFloat, velocity: CGFloat)
    /// The finger lifted.
    case ended(velocity: CGFloat)
    /// The system cancelled the gesture.
    case cancelled
    /// The indicator was tapped or activated.
    case tapIndicator
    /// Open from code, on the indicator's edge or the given one.
    case open(edge: FlickScreenEdge?)
    /// An item was tapped while the menu was presented.
    case chooseItem(Int)
    /// A tap outside, the escape gesture, or a call from code.
    case dismiss
    /// The container, safe area or item count changed.
    case geometryChanged(FlickGeometry)
    /// The selection changed outside the menu, for example through a binding.
    case selectionChanged(Int)
}

/// Outputs of the menu, for the UI to turn into callbacks, haptics and sounds.
public enum FlickEffect: Hashable, Sendable {
    case opened(FlickScreenEdge)
    case highlighted(Int)
    /// The finger went past the first or last item.
    case boundaryReached
    case chose(Int)
    case dismissed
}

/// The menu's behaviour as a pure state machine.
///
/// The UI feeds it events and renders its state; animations are derived from state
/// changes. Every transition is synchronous, so a new gesture can interrupt anything.
public struct FlickMenuMachine: Equatable, Sendable {
    public private(set) var configuration: FlickMenuConfiguration
    public private(set) var geometry: FlickGeometry
    public private(set) var selectedIndex: Int
    public private(set) var phase: FlickPhase = .closed
    public private(set) var indicator: FlickIndicatorState

    public init(configuration: FlickMenuConfiguration, geometry: FlickGeometry, selectedIndex: Int = 0) {
        self.configuration = configuration
        self.geometry = geometry
        self.selectedIndex = Self.clampedIndex(selectedIndex, count: geometry.itemCount)
        self.indicator = FlickIndicatorState(edge: configuration.homeEdge, position: 0)
        self.indicator.position = homePosition(on: configuration.homeEdge)
    }

    /// The open session, if any.
    public var session: FlickSession? {
        if case let .open(session) = phase { return session }
        return nil
    }

    public var isOpen: Bool {
        session != nil
    }

    /// Where the indicator's centre is along the main axis while the menu is open:
    /// next to the highlighted item.
    public var openIndicatorPosition: CGFloat? {
        guard let session else { return nil }
        return geometry.itemCenter(at: session.highlightedIndex, menuOffset: session.menuOffset, edge: session.edge)
    }

    /// Replaces the configuration. An open menu is kept open.
    /// Changing the home edge or position sends the indicator home.
    public mutating func update(configuration: FlickMenuConfiguration) {
        let previous = self.configuration
        self.configuration = configuration
        if configuration.homeEdge != previous.homeEdge || configuration.homeFraction != previous.homeFraction {
            indicator = FlickIndicatorState(edge: configuration.homeEdge, position: homePosition(on: configuration.homeEdge))
        } else {
            indicator.position = restingRange(on: indicator.edge).clamp(indicator.position)
        }
    }

    // MARK: Events

    /// Applies an event and returns the effects it produced.
    @discardableResult
    public mutating func send(_ event: FlickEvent) -> [FlickEffect] {
        switch event {
        case let .began(edge, position):
            // A swipe can take over a presented menu, but not another swipe.
            if let session, session.origin == .gesture { return [] }
            return begin(.gesture, edge: edge, at: position)

        case let .moved(position, velocity):
            guard var session, session.origin == .gesture else { return [] }
            session.current = position
            session.velocity = velocity
            return track(session)

        case let .ended(velocity):
            guard var session, session.origin == .gesture else { return [] }
            session.velocity = velocity
            return choose(session.highlightedIndex, in: session)

        case .cancelled:
            guard let session, session.origin == .gesture else { return [] }
            return close()

        case .tapIndicator:
            if let session, session.origin == .presentation { return close() }
            guard !isOpen else { return [] }
            return begin(.presentation, edge: indicator.edge, at: indicator.position)

        case let .open(requestedEdge):
            guard !isOpen else { return [] }
            let edge = requestedEdge ?? indicator.edge
            let position = edge.mainAxis == indicator.edge.mainAxis ? indicator.position : homePosition(on: edge)
            return begin(.presentation, edge: edge, at: position)

        case let .chooseItem(index):
            guard let session, index >= 0, index < geometry.itemCount else { return [] }
            return choose(index, in: session)

        case .dismiss:
            guard isOpen else { return [] }
            return close()

        case let .geometryChanged(newGeometry):
            return changeGeometry(to: newGeometry)

        case let .selectionChanged(index):
            selectedIndex = Self.clampedIndex(index, count: geometry.itemCount)
            return []
        }
    }

    // MARK: Transitions

    private mutating func begin(_ origin: FlickSession.Origin, edge: FlickScreenEdge, at position: CGFloat) -> [FlickEffect] {
        guard geometry.itemCount > 0 else { return [] }
        let anchor = Self.clampedIndex(selectedIndex, count: geometry.itemCount)
        let session = FlickSession(
            origin: origin,
            edge: edge,
            anchorIndex: anchor,
            start: position,
            current: position,
            velocity: 0,
            menuOffset: 0,
            highlightedIndex: anchor,
            isBeyondBounds: false
        )
        phase = .open(session)
        return [.opened(edge)] + track(session, forceHighlight: true)
    }

    private mutating func track(_ session: FlickSession, forceHighlight: Bool = false) -> [FlickEffect] {
        var session = session
        let previousIndex = session.highlightedIndex
        let wasBeyond = session.isBeyondBounds
        session.menuOffset = geometry.menuOffset(
            for: session.edge,
            start: session.start,
            current: session.current,
            anchorIndex: session.anchorIndex,
            physics: configuration.physics[session.edge]
        )
        let raw = FlickTracking.rawItemIndex(
            at: session.current,
            menuOffset: session.menuOffset,
            itemLength: geometry.itemLength[session.edge]
        )
        session.isBeyondBounds = raw < 0 || raw >= geometry.itemCount
        session.highlightedIndex = Self.clampedIndex(raw, count: geometry.itemCount)
        phase = .open(session)

        var effects: [FlickEffect] = []
        if forceHighlight || session.highlightedIndex != previousIndex {
            effects.append(.highlighted(session.highlightedIndex))
        }
        if session.isBeyondBounds && !wasBeyond {
            effects.append(.boundaryReached)
        }
        return effects
    }

    private mutating func choose(_ index: Int, in session: FlickSession) -> [FlickEffect] {
        selectedIndex = index
        let released = geometry.itemCenter(at: index, menuOffset: session.menuOffset, edge: session.edge)
        indicator = restingIndicator(afterChoosingAt: released, from: session.edge)
        phase = .closed
        return [.chose(index)]
    }

    private mutating func close() -> [FlickEffect] {
        phase = .closed
        return [.dismissed]
    }

    private mutating func changeGeometry(to newGeometry: FlickGeometry) -> [FlickEffect] {
        let oldLength = geometry.mainLength(for: indicator.edge)
        geometry = newGeometry
        selectedIndex = Self.clampedIndex(selectedIndex, count: newGeometry.itemCount)

        // Keep the indicator at the same relative position, e.g. across a rotation or a fold.
        let fraction = oldLength > 0 ? indicator.position / oldLength : configuration.homeFraction
        let newLength = newGeometry.mainLength(for: indicator.edge)
        indicator.position = restingRange(on: indicator.edge).clamp(fraction * newLength)

        guard isOpen else { return [] }
        return close()
    }

    // MARK: Indicator placement

    private func restingIndicator(afterChoosingAt released: CGFloat, from edge: FlickScreenEdge) -> FlickIndicatorState {
        let home = configuration.homeEdge
        switch configuration.boomerang[edge] {
        case .stay:
            return FlickIndicatorState(edge: edge, position: restingRange(on: edge).clamp(released))
        case .edge:
            let position = home.mainAxis == edge.mainAxis
                ? restingRange(on: home).clamp(released)
                : homePosition(on: home)
            return FlickIndicatorState(edge: home, position: position)
        case .position:
            return FlickIndicatorState(edge: edge, position: homePosition(on: edge))
        case .origin:
            return FlickIndicatorState(edge: home, position: homePosition(on: home))
        }
    }

    private func restingRange(on edge: FlickScreenEdge) -> ClosedRange<CGFloat> {
        geometry.restingIndicatorRange(for: edge, indicatorSize: configuration.indicatorSize[edge])
    }

    private func homePosition(on edge: FlickScreenEdge) -> CGFloat {
        geometry.restingIndicatorPosition(
            fraction: configuration.homeFraction,
            for: edge,
            indicatorSize: configuration.indicatorSize[edge]
        )
    }

    private static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
