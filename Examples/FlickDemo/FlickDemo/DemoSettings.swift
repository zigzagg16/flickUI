import flickUI
import SwiftUI

enum IndicatorChoice: String, CaseIterable, Identifiable {
    case automatic, glass, bubble, capsule
    var id: Self { self }
}

enum RowChoice: String, CaseIterable, Identifiable {
    case magnifying, dock, plain
    var id: Self { self }
}

enum BackgroundChoice: String, CaseIterable, Identifiable {
    case material, gradient, dim, clear
    var id: Self { self }
}

enum PhysicsChoice: String, CaseIterable, Identifiable {
    case fluid, carioca, snappy, direct
    var id: Self { self }

    var physics: FlickPhysics {
        switch self {
        case .fluid: .fluid
        case .carioca: .carioca
        case .snappy: .snappy
        case .direct: .direct
        }
    }
}

enum BoomerangChoice: String, CaseIterable, Identifiable {
    case stay, edge, position, origin
    var id: Self { self }

    var boomerang: FlickBoomerang {
        switch self {
        case .stay: .stay
        case .edge: .edge
        case .position: .position
        case .origin: .origin
        }
    }
}

enum FeedbackChoice: String, CaseIterable, Identifiable {
    case `default`, subtle, silent
    var id: Self { self }

    var feedback: FlickMenuFeedback {
        switch self {
        case .default: .default
        case .subtle: .subtle
        case .silent: .silent
        }
    }
}

/// The appearance and behaviour of a group of edges.
struct EdgeAppearance: Equatable {
    var indicator = IndicatorChoice.automatic
    var tint = Color.blue
    var row = RowChoice.magnifying
    var background = BackgroundChoice.material
    var physics = PhysicsChoice.fluid
    var trackingRatio = 2.0
    var boomerang = BoomerangChoice.stay
}

struct DemoSettings: Equatable {
    var edges: FlickEdgeSet = .all
    var home = FlickEdge.trailing
    var homePosition = 0.5
    /// Left and right edges.
    var sides = EdgeAppearance()
    /// When on, the top and bottom edges use `ends` instead of `sides`.
    var customizesEnds = true
    var ends = EdgeAppearance(
        indicator: .bubble,
        tint: .pink,
        row: .dock,
        background: .gradient,
        trackingRatio: 3,
        boomerang: .origin
    )
    var feedback = FeedbackChoice.default

    var effectiveEnds: EdgeAppearance {
        customizesEnds ? ends : sides
    }
}

// MARK: - Styles driven by the settings

struct DemoIndicatorStyle: FlickIndicatorStyle {
    let choice: IndicatorChoice
    let tint: Color

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch choice {
        case .automatic: FlickAutomaticIndicatorStyle().makeBody(configuration: configuration)
        case .glass: FlickGlassIndicatorStyle(tint: tint.opacity(0.4)).makeBody(configuration: configuration)
        case .bubble: FlickBubbleIndicatorStyle(tint: tint).makeBody(configuration: configuration)
        case .capsule: FlickCapsuleIndicatorStyle(tint: tint).makeBody(configuration: configuration)
        }
    }
}

struct DemoRowStyle: FlickMenuRowStyle {
    let choice: RowChoice

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch choice {
        case .magnifying: FlickMagnifyingRowStyle(.subtle).makeBody(configuration: configuration)
        case .dock: FlickMagnifyingRowStyle(.dock).makeBody(configuration: configuration)
        case .plain: FlickPlainRowStyle().makeBody(configuration: configuration)
        }
    }
}

struct DemoBackgroundStyle: FlickMenuBackgroundStyle {
    let choice: BackgroundChoice

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch choice {
        case .material: FlickMaterialBackgroundStyle().makeBody(configuration: configuration)
        case .gradient: FlickGradientBackgroundStyle().makeBody(configuration: configuration)
        case .dim: FlickColorBackgroundStyle(.black.opacity(0.45)).makeBody(configuration: configuration)
        case .clear: FlickColorBackgroundStyle(.clear).makeBody(configuration: configuration)
        }
    }
}

/// Applies an `EdgeAppearance` to some edges.
struct EdgeAppearanceModifier: ViewModifier {
    let appearance: EdgeAppearance
    let edges: FlickEdgeSet

    func body(content: Content) -> some View {
        content
            .flickMenuIndicatorStyle(DemoIndicatorStyle(choice: appearance.indicator, tint: appearance.tint), edges: edges)
            .flickMenuRowStyle(DemoRowStyle(choice: appearance.row), edges: edges)
            .flickMenuBackground(DemoBackgroundStyle(choice: appearance.background), edges: edges)
            .flickMenuPhysics(appearance.physics.physics, edges: edges)
            .flickMenuTracking(ratio: appearance.trackingRatio, edges: edges)
            .flickMenuBoomerang(appearance.boomerang.boomerang, edges: edges)
    }
}
