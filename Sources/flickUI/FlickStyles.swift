#if canImport(UIKit)
import FlickCore
import SwiftUI

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
