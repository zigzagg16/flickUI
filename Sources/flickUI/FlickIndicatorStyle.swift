#if canImport(UIKit)
import FlickCore
import SwiftUI

// MARK: - Indicator

/// The properties of an indicator, passed to a ``FlickIndicatorStyle``.
public struct FlickIndicatorStyleConfiguration {
    /// An indicator's icon.
    public struct Icon: View {
        let systemImage: String
        let isHidden: Bool
        let layoutDirection: LayoutDirection

        public var body: some View {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .opacity(isHidden ? 0 : 1)
                .environment(\.layoutDirection, layoutDirection)
        }
    }

    /// The icon of the selected item. It is hidden while the menu is open, when the
    /// indicator sits under the highlighted item's own symbol.
    public let icon: Icon
    /// The SF Symbol of the selected item, or of the highlighted item while the menu is open.
    public let systemImage: String
    /// The physical edge the indicator belongs to. While the menu is open, this is the
    /// edge it was opened from.
    public let edge: FlickScreenEdge
    public let isOpen: Bool
    /// The finger's velocity along the edge, in points per second. `0` when closed.
    public let velocity: CGFloat
}

/// The appearance of the indicator.
@MainActor @preconcurrency
public protocol FlickIndicatorStyle {
    associatedtype Body: View
    typealias Configuration = FlickIndicatorStyleConfiguration

    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// Stores the style itself rather than a closure, so the environment can compare it
/// and the menu only updates when the style really changes.
struct AnyFlickIndicatorStyle: FlickIndicatorStyle {
    private let base: any FlickIndicatorStyle

    init<S: FlickIndicatorStyle>(_ style: S) {
        base = style
    }

    func makeBody(configuration: Configuration) -> some View {
        AnyView(base.makeBody(configuration: configuration))
    }
}

/// CariocaMenu's bubble, filled with a tint.
public struct FlickBubbleIndicatorStyle: FlickIndicatorStyle {
    public var tint: Color

    public init(tint: Color = Color(red: 0.23, green: 0.60, blue: 0.85)) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FlickBubbleShape(edge: configuration.edge).fill(tint))
    }
}

/// A Liquid Glass capsule on iOS 26 and later, and a material capsule before.
public struct FlickGlassIndicatorStyle: FlickIndicatorStyle {
    public var tint: Color?

    public init(tint: Color? = nil) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        let icon = configuration.icon
            .font(.system(size: 18, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        if #available(iOS 26.0, *) {
            // Liquid Glass adapts to Reduce Transparency itself.
            icon.glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            icon.background {
                FlickTransparencyReader { reducesTransparency in
                    Capsule()
                        .fill(reducesTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
                        .overlay(Capsule().fill(tint?.opacity(0.35) ?? .clear))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                }
            }
        }
    }
}

/// A solid capsule.
public struct FlickCapsuleIndicatorStyle: FlickIndicatorStyle {
    public var tint: Color

    public init(tint: Color = .accentColor) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(tint))
    }
}

/// A shape that morphs as the menu opens and stretches as the finger moves: a drop
/// against the edge that becomes a bead under the highlighted item.
///
/// It is Liquid Glass on iOS 26 and later, optionally tinted, and filled with the
/// tint before.
public struct FlickMorphingIndicatorStyle: FlickIndicatorStyle {
    public var morph: FlickIndicatorMorph
    public var tint: Color?

    public init(_ morph: FlickIndicatorMorph = .drop, tint: Color? = nil) {
        self.morph = morph
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        let form = morph.form(isOpen: configuration.isOpen, velocity: configuration.velocity)
        let shape = FlickMorphingShape(edge: configuration.edge, form: form)
        // Only the change between resting and open springs. The stretch follows the
        // finger's speed directly, so the shape never wobbles on its own.
        let state = configuration.isOpen ? morph.open : morph.resting
        let icon = configuration.icon
            .font(.system(size: 18, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        Group {
            if #available(iOS 26.0, *) {
                icon.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                icon
                    .foregroundStyle(.white)
                    .background(shape.fill(tint ?? Color(red: 0.23, green: 0.60, blue: 0.85)))
            }
        }
        .animation(.spring(duration: 0.45, bounce: morph.bounce), value: state)
    }
}

/// The default: a morphing drop, in Liquid Glass where available.
public struct FlickAutomaticIndicatorStyle: FlickIndicatorStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        FlickMorphingIndicatorStyle().makeBody(configuration: configuration)
    }
}

extension FlickIndicatorStyle where Self == FlickAutomaticIndicatorStyle {
    public static var automatic: Self { Self() }
}

extension FlickIndicatorStyle where Self == FlickMorphingIndicatorStyle {
    public static var morphing: Self { Self() }
    public static func morphing(_ morph: FlickIndicatorMorph, tint: Color? = nil) -> Self { Self(morph, tint: tint) }
}

extension FlickIndicatorStyle where Self == FlickBubbleIndicatorStyle {
    public static var bubble: Self { Self() }
    public static func bubble(tint: Color) -> Self { Self(tint: tint) }
}

extension FlickIndicatorStyle where Self == FlickGlassIndicatorStyle {
    public static var glass: Self { Self() }
    public static func glass(tint: Color?) -> Self { Self(tint: tint) }
}

extension FlickIndicatorStyle where Self == FlickCapsuleIndicatorStyle {
    public static var capsule: Self { Self() }
    public static func capsule(tint: Color) -> Self { Self(tint: tint) }
}
#endif
