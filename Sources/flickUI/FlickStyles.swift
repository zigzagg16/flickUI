#if canImport(UIKit)
import FlickCore
import SwiftUI

// MARK: - Indicator

/// The properties of an indicator, passed to a ``FlickIndicatorStyle``.
public struct FlickIndicatorStyleConfiguration {
    /// An indicator's icon.
    public struct Icon: View {
        let content: AnyView
        public var body: some View { content }
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

// MARK: - Rows

/// The properties of a menu row, passed to a ``FlickMenuRowStyle``.
public struct FlickMenuRowStyleConfiguration {
    /// The row content provided to `flickMenu`.
    public struct Label: View {
        let content: AnyView
        public var body: some View { content }
    }

    public let label: Label
    public let index: Int
    public let title: String
    /// The name of the item's SF Symbol.
    public let systemImage: String
    public let isHighlighted: Bool
    public let isSelected: Bool
    /// The signed distance, in items, between this row and the finger's position in
    /// the menu (or the highlighted row when the menu was opened by a tap).
    public let distance: CGFloat
    /// The physical edge the menu was opened from.
    public let edge: FlickScreenEdge
}

/// The appearance of each menu row.
@MainActor @preconcurrency
public protocol FlickMenuRowStyle {
    associatedtype Body: View
    typealias Configuration = FlickMenuRowStyleConfiguration

    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// Stores the style itself rather than a closure; see ``AnyFlickIndicatorStyle``.
struct AnyFlickMenuRowStyle: FlickMenuRowStyle {
    private let base: any FlickMenuRowStyle

    init<S: FlickMenuRowStyle>(_ style: S) {
        base = style
    }

    func makeBody(configuration: Configuration) -> some View {
        AnyView(base.makeBody(configuration: configuration))
    }
}

/// Rows that grow around the finger, like the Dock.
public struct FlickMagnifyingRowStyle: FlickMenuRowStyle {
    public var magnification: FlickMagnification

    public init(_ magnification: FlickMagnification = .subtle) {
        self.magnification = magnification
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(configuration.isHighlighted ? .semibold : .regular))
            .opacity(configuration.isHighlighted ? 1 : 0.75)
            .scaleEffect(
                magnification.scale(atDistance: configuration.distance),
                anchor: configuration.edge.indicatorSideAnchor
            )
            .animation(.snappy(duration: 0.2), value: configuration.isHighlighted)
    }
}

/// Rows without magnification.
public struct FlickPlainRowStyle: FlickMenuRowStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(configuration.isHighlighted ? .semibold : .regular))
            .opacity(configuration.isHighlighted ? 1 : 0.75)
            .animation(.snappy(duration: 0.2), value: configuration.isHighlighted)
    }
}

extension FlickMenuRowStyle where Self == FlickMagnifyingRowStyle {
    public static var magnifying: Self { Self() }
    public static func magnifying(_ magnification: FlickMagnification) -> Self { Self(magnification) }
}

extension FlickMenuRowStyle where Self == FlickPlainRowStyle {
    public static var plain: Self { Self() }
}

/// The label style of menu rows. The symbol always faces the side the rows sit on,
/// opposite the edge, so it leads the row: symbol then title from the right edge,
/// title then symbol from the left edge. Along the top and bottom edges rows are as
/// narrow as an item, so the symbol is stacked with a short title.
struct FlickRowLabelStyle: LabelStyle {
    let edge: FlickScreenEdge

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        switch edge {
        case .right:
            HStack(spacing: 10) {
                configuration.icon
                sideTitle(configuration)
            }
            // Physical order, whatever the layout direction.
            .environment(\.layoutDirection, .leftToRight)
        case .left:
            HStack(spacing: 10) {
                sideTitle(configuration)
                configuration.icon
            }
            .environment(\.layoutDirection, .leftToRight)
        case .bottom:
            VStack(spacing: 4) {
                configuration.icon
                compactTitle(configuration)
            }
        case .top:
            VStack(spacing: 4) {
                compactTitle(configuration)
                configuration.icon
            }
        }
    }

    /// At the largest text sizes, titles shrink rather than wrap out of their row.
    private func sideTitle(_ configuration: Configuration) -> some View {
        configuration.title
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func compactTitle(_ configuration: Configuration) -> some View {
        configuration.title
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Background

/// The properties of the menu background, passed to a ``FlickMenuBackgroundStyle``.
public struct FlickMenuBackgroundStyleConfiguration {
    /// The physical edge the menu was opened from.
    public let edge: FlickScreenEdge
}

/// The appearance of the layer behind the menu rows.
@MainActor @preconcurrency
public protocol FlickMenuBackgroundStyle {
    associatedtype Body: View
    typealias Configuration = FlickMenuBackgroundStyleConfiguration

    @ViewBuilder func makeBody(configuration: Configuration) -> Body

    /// The colour scheme of the rows drawn on this background, so they stay legible:
    /// `.dark` for light text on a dark background. `nil`, the default, keeps the app's.
    var contentColorScheme: ColorScheme? { get }
}

extension FlickMenuBackgroundStyle {
    public var contentColorScheme: ColorScheme? { nil }
}

/// Stores the style itself rather than a closure; see ``AnyFlickIndicatorStyle``.
struct AnyFlickMenuBackgroundStyle: FlickMenuBackgroundStyle {
    private let base: any FlickMenuBackgroundStyle

    init<S: FlickMenuBackgroundStyle>(_ style: S) {
        base = style
    }

    var contentColorScheme: ColorScheme? {
        base.contentColorScheme
    }

    func makeBody(configuration: Configuration) -> some View {
        AnyView(base.makeBody(configuration: configuration))
    }
}

/// A material, optionally darkened.
public struct FlickMaterialBackgroundStyle: FlickMenuBackgroundStyle {
    public var material: Material
    public var dimming: Double

    public init(_ material: Material = .ultraThinMaterial, dimming: Double = 0.12) {
        self.material = material
        self.dimming = dimming
    }

    /// With Reduce Transparency on, it is the opaque system background instead.
    public func makeBody(configuration: Configuration) -> some View {
        FlickTransparencyReader { reducesTransparency in
            if reducesTransparency {
                Rectangle().fill(.background)
            } else {
                Rectangle()
                    .fill(material)
                    .overlay(Color.black.opacity(dimming))
            }
        }
    }
}

/// A plain colour.
public struct FlickColorBackgroundStyle: FlickMenuBackgroundStyle {
    public var color: Color
    public let contentColorScheme: ColorScheme?

    /// - Parameter contentColorScheme: The rows' colour scheme. By default it is
    ///   worked out from the colour: dark text on light colours, light text on dark ones.
    public init(_ color: Color, contentColorScheme: ColorScheme? = nil) {
        self.color = color
        self.contentColorScheme = contentColorScheme ?? color.flickContentColorScheme
    }

    public func makeBody(configuration: Configuration) -> some View {
        Rectangle().fill(color)
    }
}

/// A gradient that fades out away from the rows, leaving the content visible.
public struct FlickGradientBackgroundStyle: FlickMenuBackgroundStyle {
    public var color: Color
    public let contentColorScheme: ColorScheme?

    /// - Parameter contentColorScheme: The rows' colour scheme. By default it is
    ///   worked out from the colour, which is strongest behind the rows.
    public init(_ color: Color = .black.opacity(0.55), contentColorScheme: ColorScheme? = nil) {
        self.color = color
        self.contentColorScheme = contentColorScheme ?? color.flickContentColorScheme
    }

    /// With Reduce Transparency on, it is the colour at full opacity instead.
    public func makeBody(configuration: Configuration) -> some View {
        let toward = configuration.edge.indicatorSideAnchor
        let away = UnitPoint(x: 1 - toward.x, y: 1 - toward.y)
        FlickTransparencyReader { reducesTransparency in
            if reducesTransparency {
                Rectangle().fill(color.opacity(1))
            } else {
                Rectangle().fill(LinearGradient(colors: [color, color.opacity(0)], startPoint: toward, endPoint: away))
            }
        }
    }
}

extension FlickMenuBackgroundStyle where Self == FlickMaterialBackgroundStyle {
    public static var material: Self { Self() }
    public static func material(_ material: Material, dimming: Double = 0.12) -> Self { Self(material, dimming: dimming) }
}

extension FlickMenuBackgroundStyle where Self == FlickColorBackgroundStyle {
    public static func color(_ color: Color) -> Self { Self(color) }
    /// No visible background.
    public static var clear: Self { Self(.clear) }
}

extension FlickMenuBackgroundStyle where Self == FlickGradientBackgroundStyle {
    public static var gradient: Self { Self() }
    public static func gradient(_ color: Color) -> Self { Self(color) }
}

// MARK: - Helpers

/// Reads Reduce Transparency for styles, whose `makeBody` can't read the environment itself.
struct FlickTransparencyReader<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(reducesTransparency)
    }
}

extension Color {
    /// The colour scheme that keeps text legible on this colour: `.dark` on dark
    /// colours, `.light` on light ones, and `nil` when it is too transparent to matter.
    var flickContentColorScheme: ColorScheme? {
        let resolved = resolve(in: EnvironmentValues())
        guard resolved.opacity >= 0.3 else { return nil }
        // Relative luminance from linear sRGB components.
        let luminance = 0.2126 * resolved.linearRed + 0.7152 * resolved.linearGreen + 0.0722 * resolved.linearBlue
        // Against unknown content, a translucent colour reads as darker or lighter
        // than it is only as much as it covers: blend towards mid grey.
        let blended = Double(luminance) * Double(resolved.opacity) + 0.18 * (1 - Double(resolved.opacity))
        return blended < 0.18 ? .dark : .light
    }
}

extension FlickScreenEdge {
    /// The side of the screen where the indicator sits while a menu opened from this
    /// edge is shown: the opposite side.
    var indicatorSideAnchor: UnitPoint {
        switch self {
        case .left: .trailing
        case .right: .leading
        case .top: .bottom
        case .bottom: .top
        }
    }

    var indicatorSideAlignment: Alignment {
        switch self {
        case .left: .trailing
        case .right: .leading
        case .top: .bottom
        case .bottom: .top
        }
    }

    var indicatorSideEdges: Edge.Set {
        switch self {
        case .left: .trailing
        case .right: .leading
        case .top: .bottom
        case .bottom: .top
        }
    }
}
#endif
