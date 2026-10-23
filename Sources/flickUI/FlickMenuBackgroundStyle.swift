#if canImport(UIKit)
import FlickCore
import SwiftUI

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

    /// - Parameters:
    ///   - color: The background's colour.
    ///   - contentColorScheme: The rows' colour scheme. By default it is worked out
    ///     from the colour: dark text on light colours, light text on dark ones.
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

    /// - Parameters:
    ///   - color: The colour behind the rows, fading to clear away from them.
    ///   - contentColorScheme: The rows' colour scheme. By default it is worked out
    ///     from the colour, which is strongest behind the rows.
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
#endif
