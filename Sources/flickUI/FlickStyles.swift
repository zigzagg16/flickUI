#if canImport(UIKit)
import FlickCore
import SwiftUI

// MARK: - Indicator

/// The properties of an indicator, passed to a ``FlickIndicatorStyle``.
public struct FlickIndicatorStyleConfiguration {
    /// The icon of the selected item, or of the highlighted item while the menu is open.
    public struct Icon: View {
        let content: AnyView
        public var body: some View { content }
    }

    public let icon: Icon
    /// The physical edge the indicator belongs to. While the menu is open, this is the
    /// edge it was opened from, and the indicator sits on the opposite side.
    public let edge: FlickScreenEdge
    public let isOpen: Bool
}

/// The appearance of the indicator.
@MainActor @preconcurrency
public protocol FlickIndicatorStyle {
    associatedtype Body: View
    typealias Configuration = FlickIndicatorStyleConfiguration

    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

struct AnyFlickIndicatorStyle: FlickIndicatorStyle {
    private let make: @MainActor (Configuration) -> AnyView

    init<S: FlickIndicatorStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
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
            icon.glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            icon.background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint?.opacity(0.35) ?? .clear))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
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

/// Liquid Glass where available, CariocaMenu's bubble otherwise.
public struct FlickAutomaticIndicatorStyle: FlickIndicatorStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            FlickGlassIndicatorStyle().makeBody(configuration: configuration)
        } else {
            FlickBubbleIndicatorStyle().makeBody(configuration: configuration)
        }
    }
}

extension FlickIndicatorStyle where Self == FlickAutomaticIndicatorStyle {
    public static var automatic: Self { Self() }
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
    public let isHighlighted: Bool
    public let isSelected: Bool
    /// The signed distance, in items, between this row and the finger
    /// (or the highlighted row when the menu was opened by a tap).
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

struct AnyFlickMenuRowStyle: FlickMenuRowStyle {
    private let make: @MainActor (Configuration) -> AnyView

    init<S: FlickMenuRowStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
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

/// The default label style of menu rows. Compact rows, used along the top and bottom
/// edges, are as narrow as an item, so they stack the icon above a short title.
struct FlickRowLabelStyle: LabelStyle {
    let isCompact: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if isCompact {
            VStack(spacing: 4) {
                configuration.icon
                configuration.title
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .multilineTextAlignment(.center)
        } else {
            Label(configuration)
        }
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
}

struct AnyFlickMenuBackgroundStyle: FlickMenuBackgroundStyle {
    private let make: @MainActor (Configuration) -> AnyView

    init<S: FlickMenuBackgroundStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
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

    public func makeBody(configuration: Configuration) -> some View {
        Rectangle()
            .fill(material)
            .overlay(Color.black.opacity(dimming))
    }
}

/// A plain colour.
public struct FlickColorBackgroundStyle: FlickMenuBackgroundStyle {
    public var color: Color

    public init(_ color: Color) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        Rectangle().fill(color)
    }
}

/// A gradient that fades out away from the indicator, leaving the content visible.
public struct FlickGradientBackgroundStyle: FlickMenuBackgroundStyle {
    public var color: Color

    public init(_ color: Color = .black.opacity(0.55)) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        let toward = configuration.edge.indicatorSideAnchor
        let away = UnitPoint(x: 1 - toward.x, y: 1 - toward.y)
        Rectangle().fill(LinearGradient(colors: [color, color.opacity(0)], startPoint: toward, endPoint: away))
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
