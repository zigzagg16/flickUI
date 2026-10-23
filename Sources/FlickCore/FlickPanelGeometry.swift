#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// How a contained menu background sits around the rows.
public enum FlickPanelExtent: Hashable, Sendable {
    /// A card around the rows, inside the safe area.
    case card
    /// A drawer against the side the rows sit on, running the edge's whole length.
    case drawer
}

/// The frame of a contained menu background.
public enum FlickPanelGeometry {
    /// The gap a card keeps from the safe area.
    public static let screenMargin: CGFloat = 8

    /// The background's frame around the rows' labels.
    ///
    /// - Parameters:
    ///   - content: The area the labels take up. It can extend past the container when
    ///     the menu is longer than the screen.
    ///   - extent: A card or a drawer.
    ///   - edge: The edge the menu was opened from. The rows sit against the opposite side.
    ///   - containerSize: The menu's container.
    ///   - safeAreaInsets: The container's safe-area insets.
    ///   - padding: The space kept around the labels.
    ///   - overhang: How far a drawer reaches past the container on its three outer
    ///     sides, so that only its inner corners show.
    /// - Returns: `nil` when no label is on screen.
    public static func frame(
        around content: CGRect,
        extent: FlickPanelExtent,
        edge: FlickScreenEdge,
        containerSize: CGSize,
        safeAreaInsets: FlickInsets = .zero,
        padding: CGFloat,
        overhang: CGFloat = 0
    ) -> CGRect? {
        guard !content.isNull, !content.isEmpty else { return nil }
        let padded = content.insetBy(dx: -padding, dy: -padding)
        switch extent {
        case .card:
            let visible = CGRect(origin: .zero, size: containerSize).inset(by: safeAreaInsets, margin: screenMargin)
            let frame = padded.intersection(visible)
            return frame.isNull || frame.isEmpty ? nil : frame
        case .drawer:
            let width = containerSize.width
            let height = containerSize.height
            let fullHeight = height + 2 * overhang
            let fullWidth = width + 2 * overhang
            return switch edge {
            // Opened from the right, the rows are on the left: the drawer runs from the
            // screen's left edge to just past the labels.
            case .right: CGRect(x: -overhang, y: -overhang, width: max(padded.maxX + overhang, 0), height: fullHeight)
            case .left: CGRect(x: padded.minX, y: -overhang, width: max(width + overhang - padded.minX, 0), height: fullHeight)
            case .bottom: CGRect(x: -overhang, y: -overhang, width: fullWidth, height: max(padded.maxY + overhang, 0))
            case .top: CGRect(x: -overhang, y: padded.minY, width: fullWidth, height: max(height + overhang - padded.minY, 0))
            }
        }
    }
}

extension CGRect {
    func inset(by insets: FlickInsets, margin: CGFloat) -> CGRect {
        CGRect(
            x: minX + insets.left + margin,
            y: minY + insets.top + margin,
            width: max(width - insets.left - insets.right - 2 * margin, 0),
            height: max(height - insets.top - insets.bottom - 2 * margin, 0)
        )
    }
}
