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
    var boomerang = FlickEdgeSettings(FlickBoomerang.stay)
    var indicatorStyle = FlickEdgeSettings<AnyFlickIndicatorStyle?>(nil)
    var rowStyle = FlickEdgeSettings<AnyFlickMenuRowStyle?>(nil)
    var backgroundStyle = FlickEdgeSettings<AnyFlickMenuBackgroundStyle?>(nil)
    var feedback = FlickMenuFeedback.default
    var defersSystemGestures = true
    var onEvent: (@MainActor (FlickMenuEvent) -> Void)?
}

private struct FlickMenuSettingsKey: EnvironmentKey {
    static var defaultValue: FlickMenuSettings { FlickMenuSettings() }
}

extension EnvironmentValues {
    var flickMenuSettings: FlickMenuSettings {
        get { self[FlickMenuSettingsKey.self] }
        set { self[FlickMenuSettingsKey.self] = newValue }
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

    /// How the menu follows the finger, for all edges or only some.
    public func flickMenuPhysics(_ physics: FlickPhysics, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { $0.physics.set(physics, for: edges) }
    }

    /// Shorthand for the tracking ratio: how fast the finger moves through items.
    /// For specific edges, the edge's current physics are kept and only the ratio changes.
    public func flickMenuTracking(ratio: CGFloat, edges: FlickEdgeSet = .all) -> some View {
        transformEnvironment(\.flickMenuSettings) { settings in
            if edges == .all {
                settings.physics.base.trackingRatio = ratio
            } else {
                for edge in edges.edges {
                    var physics = settings.physics[edge]
                    physics.trackingRatio = ratio
                    settings.physics.overrides[edge] = physics
                }
            }
        }
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

    /// Observes menu events. Several handlers can be attached; all are called.
    public func onFlickMenuEvent(_ handler: @escaping @MainActor (FlickMenuEvent) -> Void) -> some View {
        transformEnvironment(\.flickMenuSettings) { settings in
            let previous = settings.onEvent
            settings.onEvent = { event in
                previous?(event)
                handler(event)
            }
        }
    }
}
#endif
