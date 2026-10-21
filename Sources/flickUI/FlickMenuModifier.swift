#if canImport(UIKit)
import FlickCore
import SwiftUI

/// Information about a row, passed to the row builder of `flickMenu`.
public struct FlickMenuRowContext: Sendable {
    public let index: Int
    public let isHighlighted: Bool
    public let isSelected: Bool
    /// The physical edge the menu was opened from. The indicator sits on the opposite side.
    public let edge: FlickScreenEdge
}

extension View {
    /// Adds a menu that opens with a swipe from a screen edge.
    ///
    /// The selected item appears under the finger. Sliding along the edge moves through
    /// the items, and lifting the finger chooses one. Tapping the indicator opens the
    /// menu without a swipe.
    ///
    /// - Parameters:
    ///   - data: The menu items.
    ///   - selection: The selected item's identifier.
    ///   - edges: The edges a swipe can start from.
    ///   - row: The content of each row.
    ///   - icon: The content of the indicator for an item.
    public func flickMenu<Data, Row, Icon>(
        _ data: Data,
        selection: Binding<Data.Element.ID>,
        edges: FlickEdgeSet = .horizontal,
        @ViewBuilder row: @escaping (Data.Element, FlickMenuRowContext) -> Row,
        @ViewBuilder icon: @escaping (Data.Element) -> Icon
    ) -> some View
    where Data: RandomAccessCollection, Data.Element: Identifiable, Row: View, Icon: View {
        modifier(FlickMenuModifier(data: data, selection: selection, edges: edges, row: row, icon: icon))
    }
}

struct FlickMenuModifier<Data, Row, Icon>: ViewModifier
where Data: RandomAccessCollection, Data.Element: Identifiable, Row: View, Icon: View {
    let data: Data
    @Binding var selection: Data.Element.ID
    let edges: FlickEdgeSet
    let row: (Data.Element, FlickMenuRowContext) -> Row
    let icon: (Data.Element) -> Icon

    @Environment(\.flickMenuSettings) private var settings
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var machine = FlickMenuMachine(
        configuration: FlickMenuConfiguration(),
        geometry: FlickGeometry(containerSize: .zero, itemLength: 60, itemCount: 0)
    )
    /// The overlay's origin in global coordinates, to convert gesture locations.
    @State private var origin: CGPoint = .zero
    @State private var ticks = FeedbackTicks()

    func body(content: Content) -> some View {
        content
            .gesture(edgeGesture(.left))
            .gesture(edgeGesture(.right))
            .gesture(edgeGesture(.top))
            .gesture(edgeGesture(.bottom))
            .defersSystemGestures(on: deferredEdges)
            .overlay {
                GeometryReader { proxy in
                    overlayContent(in: proxy)
                }
                .ignoresSafeArea()
                // The engine works in physical coordinates; row and icon content get
                // the app's layout direction back.
                .environment(\.layoutDirection, .leftToRight)
            }
            .onChange(of: configuration, initial: true) { _, newValue in
                machine.update(configuration: newValue)
            }
            .onChange(of: selectedIndex, initial: true) { _, newValue in
                machine.send(.selectionChanged(newValue))
            }
            .sensoryFeedback(trigger: ticks.open) { _, _ in settings.feedback.open }
            .sensoryFeedback(trigger: ticks.highlight) { _, _ in settings.feedback.highlight }
            .sensoryFeedback(trigger: ticks.boundary) { _, _ in settings.feedback.boundary }
            .sensoryFeedback(trigger: ticks.choose) { _, _ in settings.feedback.choose }
    }

    // MARK: Derived state

    private var isRightToLeft: Bool {
        layoutDirection == .rightToLeft
    }

    private var layouts: FlickEdgeValues<FlickMenuLayout> {
        settings.layout.resolved(isRightToLeft: isRightToLeft)
    }

    private var configuration: FlickMenuConfiguration {
        FlickMenuConfiguration(
            homeEdge: settings.home.edge.resolved(isRightToLeft: isRightToLeft),
            homeFraction: settings.home.position,
            boomerang: settings.boomerang.resolved(isRightToLeft: isRightToLeft),
            physics: settings.physics.resolved(isRightToLeft: isRightToLeft),
            indicatorSize: layouts.indicatorFrames
        )
    }

    private var selectedIndex: Int {
        guard let index = data.firstIndex(where: { $0.id == selection }) else { return 0 }
        return data.distance(from: data.startIndex, to: index)
    }

    private var deferredEdges: Edge.Set {
        guard settings.defersSystemGestures else { return [] }
        var deferred: Edge.Set = []
        if edges.contains(.top) { deferred.insert(.top) }
        if edges.contains(.bottom) { deferred.insert(.bottom) }
        return deferred
    }

    private var openAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.4, extraBounce: 0.05)
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)
    }

    private var indicatorAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .bouncy(duration: 0.35, extraBounce: 0.1)
    }

    private func element(at offset: Int) -> Data.Element {
        data[data.index(data.startIndex, offsetBy: offset)]
    }

    private func indicatorStyle(for edge: FlickScreenEdge) -> AnyFlickIndicatorStyle {
        settings.indicatorStyle.resolved(isRightToLeft: isRightToLeft)[edge]
            ?? AnyFlickIndicatorStyle(FlickAutomaticIndicatorStyle())
    }

    private func rowStyle(for edge: FlickScreenEdge) -> AnyFlickMenuRowStyle {
        settings.rowStyle.resolved(isRightToLeft: isRightToLeft)[edge]
            ?? AnyFlickMenuRowStyle(FlickMagnifyingRowStyle())
    }

    private func backgroundStyle(for edge: FlickScreenEdge) -> AnyFlickMenuBackgroundStyle {
        settings.backgroundStyle.resolved(isRightToLeft: isRightToLeft)[edge]
            ?? AnyFlickMenuBackgroundStyle(FlickMaterialBackgroundStyle())
    }

    // MARK: Events

    private func edgeGesture(_ edge: FlickScreenEdge) -> FlickEdgePanGesture {
        let logical = edge.logical(isRightToLeft: isRightToLeft)
        let isEnabled = edges.contains(FlickEdgeSet(logical)) && !data.isEmpty
        return FlickEdgePanGesture(edge: edge, isEnabled: isEnabled) { phase in
            handle(phase, from: edge)
        }
    }

    private func handle(_ phase: FlickEdgePanGesture.Phase, from edge: FlickScreenEdge) {
        let axis = edge.mainAxis
        switch phase {
        case let .began(location):
            send(.began(edge: edge, position: axis.value(of: local(location))), animation: openAnimation)
        case let .changed(location, velocity):
            send(.moved(position: axis.value(of: local(location)), velocity: axis.value(of: velocity)), animation: nil)
        case let .ended(velocity):
            send(.ended(velocity: axis.value(of: velocity)), animation: closeAnimation)
        case .cancelled:
            send(.cancelled, animation: closeAnimation)
        }
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func send(_ event: FlickEvent, animation: Animation?) {
        let effects = withAnimation(animation) { machine.send(event) }
        apply(effects)
    }

    private func apply(_ effects: [FlickEffect]) {
        let opened = effects.contains { effect in
            if case .opened = effect { return true }
            return false
        }
        for effect in effects {
            switch effect {
            case let .opened(edge):
                ticks.open += 1
                settings.onEvent?(.opened(edge.logical(isRightToLeft: isRightToLeft)))
            case let .highlighted(index):
                // Opening has its own feedback.
                if !opened { ticks.highlight += 1 }
                settings.onEvent?(.highlighted(index))
            case .boundaryReached:
                ticks.boundary += 1
            case let .chose(index):
                ticks.choose += 1
                if index < data.count {
                    selection = element(at: index).id
                }
                settings.onEvent?(.chose(index))
            case .dismissed:
                settings.onEvent?(.dismissed)
            }
        }
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !data.isEmpty else { return }
        let current = selectedIndex
        let next: Int
        switch direction {
        case .increment: next = min(current + 1, data.count - 1)
        case .decrement: next = max(current - 1, 0)
        @unknown default: return
        }
        selection = element(at: next).id
    }

    // MARK: Rendering

    @ViewBuilder
    private func overlayContent(in proxy: GeometryProxy) -> some View {
        let insets = proxy.safeAreaInsets
        let geometry = FlickGeometry(
            containerSize: proxy.size,
            safeAreaInsets: FlickInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing),
            itemLength: layouts.map { $0.itemLength },
            itemCount: data.count
        )
        let globalOrigin = proxy.frame(in: .global).origin

        ZStack(alignment: .topLeading) {
            if let session = machine.session {
                menu(for: session)
            }
            indicator
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .onChange(of: geometry, initial: true) { _, newValue in
            send(.geometryChanged(newValue), animation: closeAnimation)
        }
        .onChange(of: globalOrigin, initial: true) { _, newValue in
            origin = newValue
        }
    }

    @ViewBuilder
    private func menu(for session: FlickSession) -> some View {
        let geometry = machine.geometry
        let edge = session.edge
        let isVertical = edge.mainAxis == .vertical
        let itemLength = geometry.itemLength[edge]
        let cross = geometry.crossLength(for: edge)
        let menuLength = geometry.menuLength(for: edge)
        let rows = ForEach(0..<data.count, id: \.self) { index in
            rowView(at: index, session: session)
                .frame(width: isVertical ? cross : itemLength, height: isVertical ? itemLength : cross)
        }

        backgroundStyle(for: edge)
            .makeBody(configuration: FlickMenuBackgroundStyleConfiguration(edge: edge))
            .frame(width: geometry.containerSize.width, height: geometry.containerSize.height)
            .contentShape(Rectangle())
            .onTapGesture { send(.dismiss, animation: closeAnimation) }
            .transition(.opacity)
            .accessibilityHidden(true)

        Group {
            if isVertical {
                VStack(spacing: 0) { rows }
            } else {
                HStack(spacing: 0) { rows }
            }
        }
        .frame(width: isVertical ? cross : menuLength, height: isVertical ? menuLength : cross)
        .position(
            x: isVertical ? cross / 2 : session.menuOffset + menuLength / 2,
            y: isVertical ? session.menuOffset + menuLength / 2 : cross / 2
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func rowView(at index: Int, session: FlickSession) -> some View {
        let edge = session.edge
        let layout = layouts[edge]
        let context = FlickMenuRowContext(
            index: index,
            isHighlighted: index == session.highlightedIndex,
            isSelected: index == machine.selectedIndex,
            edge: edge
        )
        let label = row(element(at: index), context).environment(\.layoutDirection, layoutDirection)
        let configuration = FlickMenuRowStyleConfiguration(
            label: FlickMenuRowStyleConfiguration.Label(content: AnyView(label)),
            index: index,
            isHighlighted: context.isHighlighted,
            isSelected: context.isSelected,
            distance: machine.geometry.distance(
                ofItem: index,
                from: session.current,
                menuOffset: session.menuOffset,
                edge: edge
            ),
            edge: edge
        )
        return rowStyle(for: edge)
            .makeBody(configuration: configuration)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.indicatorSideAlignment)
            // Keep labels clear of the indicator, which sits on this side while open.
            .padding(edge.indicatorSideEdges, layout.indicatorSize.width + layout.indicatorMargin + 12)
            .contentShape(Rectangle())
            .onTapGesture { send(.chooseItem(index), animation: closeAnimation) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(context.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var indicator: some View {
        let geometry = machine.geometry
        if geometry.itemCount > 0, !data.isEmpty, geometry.containerSize != .zero {
            let session = machine.session
            let edge = session?.edge ?? machine.indicator.edge
            let layout = layouts[edge]
            let frame = layout.indicatorFrame(for: edge)
            let placement = geometry.indicatorPlacement(for: edge, indicatorSize: frame, margin: layout.indicatorMargin)
            let main = machine.openIndicatorPosition ?? machine.indicator.position
            let distance = session == nil ? placement.resting : placement.traversed
            let point = edge.point(main: main, distanceFromEdge: distance, in: geometry.containerSize)
            let index = min(session?.highlightedIndex ?? machine.selectedIndex, data.count - 1)
            let iconView = icon(element(at: index)).environment(\.layoutDirection, layoutDirection)
            let configuration = FlickIndicatorStyleConfiguration(
                icon: FlickIndicatorStyleConfiguration.Icon(content: AnyView(iconView)),
                edge: edge,
                isOpen: session != nil
            )

            indicatorStyle(for: edge)
                .makeBody(configuration: configuration)
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .onTapGesture { send(.tapIndicator, animation: openAnimation) }
                .position(point)
                .animation(indicatorAnimation, value: point)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Menu"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { send(.tapIndicator, animation: openAnimation) }
                .accessibilityAdjustableAction { direction in adjustSelection(direction) }
        }
    }
}

/// Counters that trigger haptic feedback when they change.
private struct FeedbackTicks {
    var open = 0
    var highlight = 0
    var boundary = 0
    var choose = 0
}
#endif
