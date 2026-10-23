#if canImport(UIKit)
import FlickCore
import SwiftUI

extension View {
    /// Adds a menu that opens with a swipe from a screen edge.
    ///
    /// The selected item appears under the finger. Sliding along the edge moves through
    /// the items, and lifting the finger chooses one. Tapping the indicator opens the
    /// menu without a swipe.
    ///
    /// Every item is an SF Symbol with a title, so the menu can animate its symbols.
    /// Key paths work for both closures:
    ///
    /// ```swift
    /// .flickMenu(Tab.allCases, selection: $tab, title: \.title, systemImage: \.symbol)
    /// ```
    ///
    /// - Parameters:
    ///   - data: The menu items.
    ///   - selection: The selected item's identifier.
    ///   - edges: The edges a swipe can start from.
    ///   - title: The title of an item.
    ///   - systemImage: The name of an item's SF Symbol.
    public func flickMenu<Data>(
        _ data: Data,
        selection: Binding<Data.Element.ID>,
        edges: FlickEdgeSet = .horizontal,
        title: @escaping (Data.Element) -> String,
        systemImage: @escaping (Data.Element) -> String
    ) -> some View
    where Data: RandomAccessCollection, Data.Element: Identifiable {
        modifier(FlickMenuModifier(data: data, selection: selection, edges: edges, title: title, systemImage: systemImage))
    }
}

struct FlickMenuModifier<Data>: ViewModifier
where Data: RandomAccessCollection, Data.Element: Identifiable {
    let data: Data
    @Binding var selection: Data.Element.ID
    let edges: FlickEdgeSet
    let title: (Data.Element) -> String
    let systemImage: (Data.Element) -> String

    @Environment(\.flickMenuSettings) private var settings
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.preferredPencilSqueezeAction) private var preferredSqueezeAction
    /// How much the rows' text has grown with Dynamic Type.
    @ScaledMetric(relativeTo: .title3) private var textScale: CGFloat = 1

    @State private var machine = FlickMenuMachine(
        configuration: FlickMenuConfiguration(),
        geometry: FlickGeometry(containerSize: .zero, itemLength: 60, itemCount: 0)
    )
    /// The overlay's origin in global coordinates, to convert gesture locations.
    @State private var origin: CGPoint = .zero
    @State private var ticks = FeedbackTicks()
    @State private var controller = FlickMenuController()
    @State private var nesting = FlickMenuNesting()
    @Environment(\.flickMenuParent) private var parent

    func body(content: Content) -> some View {
        controller.perform = { command in perform(command) }
        return content
            .environment(\.flickMenuSettings, settings.forNestedMenus)
            .environment(\.flickMenu, FlickMenuAction(controller: controller))
            .environment(\.flickMenuParent, nesting)
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
            .onChange(of: machine.isOpen) { _, isOpen in
                parent?.isNestedMenuOpen = isOpen
            }
            .onDisappear {
                if machine.isOpen { parent?.isNestedMenuOpen = false }
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

    /// Items grow with Dynamic Type so their text fits, up to a limit that keeps a
    /// useful number of them on screen. Titles shrink to fit beyond it.
    private var layouts: FlickEdgeValues<FlickMenuLayout> {
        let scale = min(max(textScale, 1), 1.6)
        return settings.layout.resolved(isRightToLeft: isRightToLeft).map { layout in
            var layout = layout
            layout.itemLength *= scale
            return layout
        }
    }

    private var configuration: FlickMenuConfiguration {
        FlickMenuConfiguration(
            homeEdge: settings.home.edge.resolved(isRightToLeft: isRightToLeft),
            homeFraction: settings.home.position,
            boomerang: settings.boomerang.resolved(isRightToLeft: isRightToLeft),
            physics: physics,
            indicatorSize: layouts.indicatorFrames
        )
    }

    /// Physics per edge, with tracking ratios from `flickMenuTracking` applied on top.
    private var physics: FlickEdgeValues<FlickPhysics> {
        settings.physics.resolved(isRightToLeft: isRightToLeft)
            .applying(trackingRatios: settings.trackingRatio.resolved(isRightToLeft: isRightToLeft))
    }

    private var selectedIndex: Int {
        guard let index = data.firstIndex(where: { $0.id == selection }) else { return 0 }
        return data.distance(from: data.startIndex, to: index)
    }

    private var isHiddenByNestedMenu: Bool {
        nesting.isNestedMenuOpen && !machine.isOpen
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
        settings.indicatorStyle.value(for: edge, isRightToLeft: isRightToLeft)
            ?? AnyFlickIndicatorStyle(FlickAutomaticIndicatorStyle())
    }

    private func backgroundStyle(for edge: FlickScreenEdge) -> AnyFlickMenuBackgroundStyle {
        settings.backgroundStyle.value(for: edge, isRightToLeft: isRightToLeft)
            ?? AnyFlickMenuBackgroundStyle(FlickMaterialBackgroundStyle())
    }

    private func rowAppearance(for edge: FlickScreenEdge) -> RowAppearance {
        RowAppearance(
            style: settings.rowStyle.value(for: edge, isRightToLeft: isRightToLeft)
                ?? AnyFlickMenuRowStyle(FlickMagnifyingRowStyle()),
            highlight: settings.highlight.value(for: edge, isRightToLeft: isRightToLeft),
            selection: settings.selection.value(for: edge, isRightToLeft: isRightToLeft)
        )
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
                settings.send(.opened(edge.logical(isRightToLeft: isRightToLeft)))
            case let .highlighted(index):
                // Opening has its own feedback.
                if !opened { ticks.highlight += 1 }
                settings.send(.highlighted(index))
            case .boundaryReached:
                ticks.boundary += 1
            case let .chose(index):
                ticks.choose += 1
                if index < data.count {
                    selection = element(at: index).id
                }
                settings.send(.chose(index))
            case .dismissed:
                settings.send(.dismissed)
            }
        }
    }

    private func perform(_ command: FlickMenuController.Command) {
        switch command {
        case let .open(edge):
            send(.open(edge: edge?.resolved(isRightToLeft: isRightToLeft)), animation: openAnimation)
        case .dismiss:
            send(.dismiss, animation: closeAnimation)
        case let .toggle(edge):
            perform(machine.isOpen ? .dismiss : .open(edge))
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
        guard next != current else { return }
        selection = element(at: next).id
        // Choosing through VoiceOver is still choosing: handlers hear about it.
        settings.send(.chose(next))
    }

}

// MARK: - Rendering

extension FlickMenuModifier {

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
            // The indicator is drawn behind the rows: while the menu is open it sits
            // under the highlighted item's symbol instead of repeating it. The background
            // goes behind both, and learns where the rows' labels are.
            ZStack(alignment: .topLeading) {
                if let session = machine.session {
                    menu(for: session)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .backgroundPreferenceValue(FlickHighlightedSymbolKey.self) { anchor in
                GeometryReader { local in
                    indicator(symbolFrame: anchor.map { local[$0] })
                }
            }
            .backgroundPreferenceValue(FlickRowLabelBoundsKey.self) { anchors in
                GeometryReader { local in
                    if let session = machine.session {
                        let frames = anchors.map { local[$0] }
                        background(for: session, contentFrame: frames.isEmpty ? nil : frames.reduce(frames[0]) { $0.union($1) })
                    }
                }
            }
            FlickKeyboardCommands(session: machine.session, shortcut: settings.keyboardShortcut) { command in
                switch command {
                case .toggle: perform(.toggle(nil))
                case .dismiss: send(.dismiss, animation: closeAnimation)
                case let .move(offset): send(.moveHighlight(by: offset), animation: indicatorAnimation)
                case .choose: send(.chooseHighlighted, animation: closeAnimation)
                }
            }
            if settings.opensOnPencilSqueeze {
                // A leaf view, so turning the setting on and off leaves the content alone.
                Color.clear
                    .frame(width: 0, height: 0)
                    .onPencilSqueeze { phase in
                        guard case .ended = phase, preferredSqueezeAction == .showContextualPalette else { return }
                        perform(.toggle(nil))
                    }
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        .onChange(of: geometry, initial: true) { _, newValue in
            send(.geometryChanged(newValue), animation: closeAnimation)
        }
        .onChange(of: globalOrigin, initial: true) { _, newValue in
            origin = newValue
        }
    }

    private func background(for session: FlickSession, contentFrame: CGRect?) -> some View {
        let geometry = machine.geometry
        let configuration = FlickMenuBackgroundStyleConfiguration(
            edge: session.edge,
            contentFrame: contentFrame,
            containerSize: geometry.containerSize,
            safeAreaInsets: geometry.safeAreaInsets
        )
        return backgroundStyle(for: session.edge)
            .makeBody(configuration: configuration)
            .frame(width: geometry.containerSize.width, height: geometry.containerSize.height)
            .contentShape(Rectangle())
            .onTapGesture { send(.dismiss, animation: closeAnimation) }
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func menu(for session: FlickSession) -> some View {
        let geometry = machine.geometry
        let edge = session.edge
        let isVertical = edge.mainAxis == .vertical
        let itemLength = geometry.itemLength[edge]
        let cross = geometry.crossLength(for: edge)
        let menuLength = geometry.menuLength(for: edge)
        // Resolved once per update rather than once per row: this runs on every move.
        let appearance = rowAppearance(for: edge)
        // Rows are identified by their item, so their state and symbol effects follow
        // the item if the data changes.
        let rows = ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
            rowView(for: item, at: index, session: session, appearance: appearance)
                .frame(width: isVertical ? cross : itemLength, height: isVertical ? itemLength : cross)
        }

        return Group {
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
        .environment(\.colorScheme, backgroundStyle(for: edge).contentColorScheme ?? colorScheme)
        // VoiceOver stays in the open menu, and the escape gesture closes it.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { send(.dismiss, animation: closeAnimation) }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func rowView(for item: Data.Element, at index: Int, session: FlickSession, appearance: RowAppearance) -> some View {
        let edge = session.edge
        let isHighlighted = index == session.highlightedIndex
        let isSelected = index == machine.selectedIndex
        let label = FlickMenuItemLabel(
            title: title(item),
            systemImage: systemImage(item),
            isHighlighted: isHighlighted,
            isSelected: isSelected,
            highlight: appearance.highlight,
            selection: appearance.selection
        )
        let configuration = FlickMenuRowStyleConfiguration(
            label: FlickMenuRowStyleConfiguration.Label(item: label, edge: edge, layoutDirection: layoutDirection),
            index: index,
            title: title(item),
            systemImage: systemImage(item),
            isHighlighted: isHighlighted,
            isSelected: isSelected,
            distance: session.progress - (CGFloat(index) + 0.5),
            edge: edge
        )
        return appearance.style
            .makeBody(configuration: configuration)
            .anchorPreference(key: FlickRowLabelBoundsKey.self, value: .bounds) { [$0] }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.indicatorSideAlignment)
            // Keep labels clear of the far side's safe area.
            .padding(edge.indicatorSideEdges, machine.geometry.safeAreaInsets[edge.opposite] + 28)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
            .onTapGesture { send(.chooseItem(index), animation: closeAnimation) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The indicator. While the menu is open it sits under the highlighted item's
    /// symbol, whose frame comes from the rows; otherwise it rests against its edge.
    @ViewBuilder
    private func indicator(symbolFrame: CGRect?) -> some View {
        let geometry = machine.geometry
        if geometry.itemCount > 0, !data.isEmpty, geometry.containerSize != .zero {
            let session = machine.session
            let edge = session?.edge ?? machine.indicator.edge
            let layout = layouts[edge]
            let restingFrame = layout.indicatorFrame(for: edge)
            let index = min(session?.highlightedIndex ?? machine.selectedIndex, data.count - 1)
            let placement = openPlacement(symbolFrame: symbolFrame, itemLength: layout.itemLength)
                ?? restingPlacement(edge: edge, frame: restingFrame, margin: layout.indicatorMargin)
            let configuration = FlickIndicatorStyleConfiguration(
                // Under the menu, the item's own symbol shows on top.
                icon: FlickIndicatorStyleConfiguration.Icon(
                    systemImage: systemImage(element(at: index)),
                    isHidden: session != nil,
                    layoutDirection: layoutDirection
                ),
                systemImage: systemImage(element(at: index)),
                edge: edge,
                isOpen: session != nil,
                velocity: session?.velocity ?? 0
            )

            indicatorStyle(for: edge)
                .makeBody(configuration: configuration)
                .frame(width: placement.size.width, height: placement.size.height)
                .contentShape(Rectangle())
                .hoverEffect()
                .onTapGesture { send(.tapIndicator, animation: openAnimation) }
                .position(placement.center)
                // Out of the way of a nested menu's rows while that menu is open.
                .opacity(isHiddenByNestedMenu ? 0 : 1)
                .allowsHitTesting(!isHiddenByNestedMenu)
                .accessibilityHidden(isHiddenByNestedMenu)
                .animation(.easeInOut(duration: 0.2), value: isHiddenByNestedMenu)
                // Opening, closing and choosing animate through `send`; while the finger
                // moves the indicator follows it without animation.
                .animation(indicatorAnimation, value: machine.indicator)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Menu", bundle: #bundle, comment: "Accessibility label of the button that opens the menu."))
                // The indicator keeps its size at large text sizes; a long press shows it enlarged.
                .accessibilityShowsLargeContentViewer {
                    Label(title(element(at: index)), systemImage: systemImage(element(at: index)))
                }
                .accessibilityValue(Text(title(element(at: index))))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { send(.tapIndicator, animation: openAnimation) }
                .accessibilityAdjustableAction { direction in adjustSelection(direction) }
        }
    }

    /// A bead on the line of symbols, under the finger: it slides continuously from
    /// symbol to symbol as the finger moves.
    private func openPlacement(symbolFrame: CGRect?, itemLength: CGFloat) -> IndicatorPlacement? {
        guard let session = machine.session, let main = machine.trackingPosition,
              let symbolFrame, !symbolFrame.isEmpty else { return nil }
        let side = min(itemLength * 0.8, 48)
        let center = switch session.edge.mainAxis {
        case .vertical: CGPoint(x: symbolFrame.midX, y: main)
        case .horizontal: CGPoint(x: main, y: symbolFrame.midY)
        }
        return IndicatorPlacement(center: center, size: CGSize(width: side, height: side))
    }

    /// Against the edge, or across the screen if the rows report no symbol.
    private func restingPlacement(edge: FlickScreenEdge, frame: CGSize, margin: CGFloat) -> IndicatorPlacement {
        let geometry = machine.geometry
        let placement = geometry.indicatorPlacement(for: edge, indicatorSize: frame, margin: margin)
        let main = machine.openIndicatorPosition ?? machine.indicator.position
        let distance = machine.isOpen ? placement.traversed : placement.resting
        return IndicatorPlacement(
            center: edge.point(main: main, distanceFromEdge: distance, in: geometry.containerSize),
            size: frame
        )
    }
}

/// The styling of a menu's rows on one edge.
private struct RowAppearance {
    let style: AnyFlickMenuRowStyle
    let highlight: FlickMenuItemEmphasis
    let selection: FlickMenuItemEmphasis
}

private struct IndicatorPlacement: Equatable {
    var center: CGPoint
    var size: CGSize
}

/// Counters that trigger haptic feedback when they change.
private struct FeedbackTicks {
    var open = 0
    var highlight = 0
    var boundary = 0
    var choose = 0
}
#endif
