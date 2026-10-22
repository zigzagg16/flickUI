#if canImport(UIKit)
import FlickCore
import SwiftUI

/// What happened in a menu, delivered to `onFlickMenuEvent(_:)`.
public enum FlickMenuEvent: Equatable, Sendable {
    case opened(FlickEdge)
    case highlighted(Int)
    case chose(Int)
    case dismissed
}

/// The haptic feedback for each menu event. `nil` turns an event's feedback off.
public struct FlickMenuFeedback {
    public var open: SensoryFeedback?
    public var highlight: SensoryFeedback?
    public var boundary: SensoryFeedback?
    public var choose: SensoryFeedback?

    public init(
        open: SensoryFeedback? = nil,
        highlight: SensoryFeedback? = nil,
        boundary: SensoryFeedback? = nil,
        choose: SensoryFeedback? = nil
    ) {
        self.open = open
        self.highlight = highlight
        self.boundary = boundary
        self.choose = choose
    }

    public static var `default`: Self {
        Self(
            open: .impact(flexibility: .soft, intensity: 0.6),
            highlight: .selection,
            boundary: .impact(flexibility: .rigid, intensity: 0.8),
            choose: .impact(weight: .medium)
        )
    }

    public static var subtle: Self {
        Self(highlight: .selection, choose: .impact(weight: .light))
    }

    public static var silent: Self { Self() }
}

/// Where the indicator rests before the menu is first used.
public struct FlickMenuHome: Equatable, Sendable {
    public var edge: FlickEdge
    /// From 0 (start of the edge) to 1 (end of the edge).
    public var position: CGFloat

    public init(edge: FlickEdge = .trailing, position: CGFloat = 0.5) {
        self.edge = edge
        self.position = position
    }
}

/// Everything configurable, stored in the environment. Values that can differ per
/// edge use ``FlickEdgeSettings``: a default for all edges plus edge-specific overrides.
struct FlickMenuSettings {
    var home = FlickMenuHome()
    var layout = FlickEdgeSettings(FlickMenuLayout())
    var physics = FlickEdgeSettings(FlickPhysics.fluid)
    /// Tracking ratios set with `flickMenuTracking`. They apply on top of `physics`,
    /// so the two modifiers can be combined in any order.
    var trackingRatio = FlickEdgeSettings<CGFloat?>(nil)
    var boomerang = FlickEdgeSettings(FlickBoomerang.stay)
    var indicatorStyle = FlickEdgeSettings<AnyFlickIndicatorStyle?>(nil)
    var rowStyle = FlickEdgeSettings<AnyFlickMenuRowStyle?>(nil)
    var backgroundStyle = FlickEdgeSettings<AnyFlickMenuBackgroundStyle?>(nil)
    var highlight = FlickEdgeSettings(FlickMenuItemEmphasis.highlighted)
    var selection = FlickEdgeSettings(FlickMenuItemEmphasis.selected)
    var feedback = FlickMenuFeedback.default
    var defersSystemGestures = true
    var keyboardShortcut: KeyboardShortcut?
    var opensOnPencilSqueeze = false
    /// Handlers from `onFlickMenuEvent`, outermost first. They are references, not
    /// closures, so the environment can compare them.
    var eventHandlers: [FlickMenuEventHandler] = []

    @MainActor func send(_ event: FlickMenuEvent) {
        for handler in eventHandlers {
            handler.handle(event)
        }
    }
}

extension EnvironmentValues {
    @Entry var flickMenuSettings = FlickMenuSettings()
}

/// Holds an `onFlickMenuEvent` handler. Each modifier keeps one instance for its
/// lifetime and updates its closure, so the environment sees the same reference.
@MainActor
final class FlickMenuEventHandler {
    var handle: @MainActor (FlickMenuEvent) -> Void = { _ in }
}

private struct FlickMenuEventModifier: ViewModifier {
    let handler: @MainActor (FlickMenuEvent) -> Void
    @State private var reference = FlickMenuEventHandler()

    func body(content: Content) -> some View {
        reference.handle = handler
        return content.transformEnvironment(\.flickMenuSettings) { [reference] settings in
            settings.eventHandlers.append(reference)
        }
    }
}

// MARK: - Modifiers

extension View {
    /// The indicator's appearance. Pass `edges` to style only some edges;
    /// edge-specific styles always take precedence over the default.
    public func flickMenuIndicatorStyle<S: FlickIndicatorStyle>(_ style: S, edges: FlickEdgeSet = .all) -> some View {
        let erased = AnyFlickIndicatorStyle(style)
        return transformEnvironment(\.flickMenuSettings) { $0.indicatorStyle.set(erased, for: edges) }
    }

    /// The rows' appearance, for all edges or only some.
    public func flickMenuRowStyle<S: FlickMenuRowStyle>(_ style: S, edges: FlickEdgeSet = .all) -> some View {
        let erased = AnyFlickMenuRowStyle(style)
        return transformEnvironment(\.flickMenuSettings) { $0.rowStyle.set(erased, for: edges) }
    }

    /// The layer behind the rows, for all edges or only some.
    public func flickMenuBackground<S: FlickMenuBackgroundStyle>(_ style: S, edges: FlickEdgeSet = .all) -> some View {
        let erased = AnyFlickMenuBackgroundStyle(style)
        return transformEnvironment(\.flickMenuSettings) { $0.backgroundStyle.set(erased, for: edges) }
    }

    /// How the highlighted item looks, for all edges or only some. By default its
    /// symbol is filled and bounces once.
    ///
    /// ```swift
    /// .flickMenuHighlight(FlickMenuItemEmphasis(tint: .yellow, symbolEffect: .wiggle))
    /// ```
    public func flickMenuHighlight(_ emphasis: FlickMenuItemEmphasis, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.highlight.set(emphasis, for: edges) }
    }

    /// How the selected item looks while the menu is open, for all edges or only some.
    /// The highlight takes precedence when the selected item is also highlighted.
    public func flickMenuSelection(_ emphasis: FlickMenuItemEmphasis, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.selection.set(emphasis, for: edges) }
    }

    /// How the menu follows the finger, for all edges or only some.
    public func flickMenuPhysics(_ physics: FlickPhysics, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.physics.set(physics, for: edges) }
    }

    /// How fast the finger moves through items, for all edges or only some.
    /// It applies on top of `flickMenuPhysics`, whatever the modifier order.
    public func flickMenuTracking(ratio: CGFloat, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.trackingRatio.set(ratio, for: edges) }
    }

    /// Where the indicator goes after an item is chosen, for all edges or only some.
    public func flickMenuBoomerang(_ boomerang: FlickBoomerang, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.boomerang.set(boomerang, for: edges) }
    }

    /// Item and indicator metrics, for all edges or only some.
    public func flickMenuLayout(_ layout: FlickMenuLayout, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.layout.set(layout, for: edges) }
    }

    /// Where the indicator rests initially, and returns to with boomerangs.
    public func flickMenuHome(_ edge: FlickEdge, position: CGFloat = 0.5) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.home = FlickMenuHome(edge: edge, position: position) }
    }

    /// Haptic feedback for menu events.
    public func flickMenuFeedback(_ feedback: FlickMenuFeedback) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.feedback = feedback }
    }

    /// Whether the top and bottom edges take priority over Notification Center,
    /// Control Center and the home indicator when the menu uses them. On by default.
    public func flickMenuDefersSystemGestures(_ defers: Bool) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.defersSystemGestures = defers }
    }

    /// A keyboard shortcut that opens and closes the menu. None by default.
    ///
    /// Whatever this is set to, while a menu opened without a swipe is shown the arrow
    /// keys move through the items, Return chooses one and Escape closes it.
    public func flickMenuKeyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.keyboardShortcut = shortcut }
    }

    /// Whether squeezing Apple Pencil Pro opens and closes the menu. Off by default.
    ///
    /// The squeeze is only used when the person's preferred squeeze action, in
    /// Settings, is to show a contextual palette.
    public func flickMenuOpensOnPencilSqueeze(_ opens: Bool = true) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.opensOnPencilSqueeze = opens }
    }

    /// Observes menu events. Several handlers can be attached; all are called.
    public func onFlickMenuEvent(_ handler: @escaping @MainActor (FlickMenuEvent) -> Void) -> some View {
        modifier(FlickMenuEventModifier(handler: handler))
    }
}
#endif
