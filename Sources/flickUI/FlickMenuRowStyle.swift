#if canImport(UIKit)
import FlickCore
import SwiftUI

// MARK: - Rows

/// The properties of a menu row, passed to a ``FlickMenuRowStyle``.
public struct FlickMenuRowStyleConfiguration {
    /// The row content provided to `flickMenu`.
    public struct Label: View {
        let item: FlickMenuItemLabel
        let edge: FlickScreenEdge
        let layoutDirection: LayoutDirection

        public var body: some View {
            item
                .labelStyle(FlickRowLabelStyle(edge: edge))
                .environment(\.layoutDirection, layoutDirection)
        }
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
#endif
