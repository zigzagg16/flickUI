#if canImport(UIKit)
import FlickCore
import SwiftUI

// MARK: - Contained backgrounds

/// What a contained background is filled with.
public enum FlickPanelFill {
    /// A material. With Reduce Transparency on, the opaque system background instead.
    case material(Material)
    /// A colour.
    case color(Color)
    /// Liquid Glass on iOS 26 and later, optionally tinted; a material before.
    case glass(tint: Color? = nil)
}

/// A background that holds the rows, as a card or a drawer, and leaves the rest of
/// the screen visible.
///
/// It follows the menu as it moves, and stays inside the screen when the menu is
/// longer than it. Tapping outside it still closes the menu.
public struct FlickPanelBackgroundStyle: FlickMenuBackgroundStyle {
    public var fill: FlickPanelFill
    public var extent: FlickPanelExtent
    public var cornerRadius: CGFloat
    /// The space kept around the rows' labels. Leave room for magnified rows.
    public var padding: CGFloat
    /// How much the rest of the screen is darkened, from `0` to `1`.
    public var scrim: Double
    public let contentColorScheme: ColorScheme?

    /// - Parameters:
    ///   - fill: The panel's fill.
    ///   - extent: A card around the rows, or a drawer against their side of the screen.
    ///   - cornerRadius: The panel's corner radius. A drawer only rounds its inner corners.
    ///   - padding: The space kept around the rows' labels.
    ///   - scrim: How much the rest of the screen is darkened, from `0` to `1`.
    ///   - contentColorScheme: The rows' colour scheme. By default it is worked out
    ///     from a colour fill, and left to the app for materials and glass.
    public init(
        _ fill: FlickPanelFill = .material(.regularMaterial),
        extent: FlickPanelExtent = .card,
        cornerRadius: CGFloat = 28,
        padding: CGFloat = 20,
        scrim: Double = 0,
        contentColorScheme: ColorScheme? = nil
    ) {
        self.fill = fill
        self.extent = extent
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.scrim = scrim
        if let contentColorScheme {
            self.contentColorScheme = contentColorScheme
        } else if case let .color(color) = fill {
            self.contentColorScheme = color.flickContentColorScheme
        } else {
            self.contentColorScheme = nil
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        // A drawer reaches past the screen so that only its inner corners show.
        let overhang = extent == .drawer ? cornerRadius : 0
        let frame = configuration.contentFrame.flatMap { content in
            FlickPanelGeometry.frame(
                around: content,
                extent: extent,
                edge: configuration.edge,
                containerSize: configuration.containerSize,
                safeAreaInsets: configuration.safeAreaInsets,
                padding: padding,
                overhang: overhang
            )
        }
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(scrim)
            if let frame {
                FlickPanelFillView(fill: fill, shape: shape)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: configuration.containerSize.width, height: configuration.containerSize.height, alignment: .topLeading)
    }
}

struct FlickPanelFillView<S: InsettableShape>: View {
    let fill: FlickPanelFill
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    var body: some View {
        switch fill {
        case let .material(material):
            shape
                .fill(reducesTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(material))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
        case let .color(color):
            shape
                .fill(reducesTransparency ? color.opacity(1) : color)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
        case let .glass(tint):
            if #available(iOS 26.0, *) {
                // Liquid Glass adapts to Reduce Transparency itself.
                Color.clear.glassEffect(.regular.tint(tint), in: shape)
            } else {
                shape
                    .fill(reducesTransparency ? AnyShapeStyle(.background) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(shape.fill(tint?.opacity(0.25) ?? .clear))
                    .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
            }
        }
    }
}

/// A soft glow behind the rows, with no hard edge.
public struct FlickHaloBackgroundStyle: FlickMenuBackgroundStyle {
    public var color: Color
    /// How far the glow spreads around the rows' labels.
    public var spread: CGFloat
    public let contentColorScheme: ColorScheme?

    /// - Parameters:
    ///   - color: The glow's colour, strongest behind the rows.
    ///   - spread: How far the glow spreads around the rows' labels.
    ///   - contentColorScheme: The rows' colour scheme. By default it is worked out from the colour.
    public init(_ color: Color = .black.opacity(0.6), spread: CGFloat = 36, contentColorScheme: ColorScheme? = nil) {
        self.color = color
        self.spread = spread
        self.contentColorScheme = contentColorScheme ?? color.flickContentColorScheme
    }

    /// With Reduce Transparency on, it is a card in the colour at full opacity instead.
    public func makeBody(configuration: Configuration) -> some View {
        FlickTransparencyReader { reducesTransparency in
            if reducesTransparency {
                FlickPanelBackgroundStyle(.color(color.opacity(1))).makeBody(configuration: configuration)
            } else {
                let frame = configuration.contentFrame.flatMap { content in
                    FlickPanelGeometry.frame(
                        around: content,
                        extent: .card,
                        edge: configuration.edge,
                        containerSize: configuration.containerSize,
                        padding: spread / 2
                    )
                }
                ZStack(alignment: .topLeading) {
                    if let frame {
                        RoundedRectangle(cornerRadius: spread, style: .continuous)
                            .fill(color)
                            .frame(width: frame.width, height: frame.height)
                            .blur(radius: spread)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                .frame(width: configuration.containerSize.width, height: configuration.containerSize.height, alignment: .topLeading)
            }
        }
    }
}

extension FlickMenuBackgroundStyle where Self == FlickPanelBackgroundStyle {
    /// A material card around the rows.
    public static var panel: Self { Self() }

    /// A card around the rows.
    public static func panel(_ fill: FlickPanelFill, cornerRadius: CGFloat = 28, scrim: Double = 0) -> Self {
        Self(fill, cornerRadius: cornerRadius, scrim: scrim)
    }

    /// A Liquid Glass card around the rows; a material before iOS 26.
    public static var glassPanel: Self { Self(.glass()) }

    /// A material drawer against the side the rows sit on, running the edge's whole length.
    public static var drawer: Self { Self(extent: .drawer) }

    /// A drawer against the side the rows sit on, running the edge's whole length.
    public static func drawer(_ fill: FlickPanelFill, cornerRadius: CGFloat = 28, scrim: Double = 0) -> Self {
        Self(fill, extent: .drawer, cornerRadius: cornerRadius, scrim: scrim)
    }
}

extension FlickMenuBackgroundStyle where Self == FlickHaloBackgroundStyle {
    /// A soft dark glow behind the rows.
    public static var halo: Self { Self() }
    public static func halo(_ color: Color, spread: CGFloat = 36) -> Self { Self(color, spread: spread) }
}
#endif
