// ImageIO exists only on Apple platforms: elsewhere each app decodes pictures its own way.
#if canImport(ImageIO)

import CoreGraphics
import Foundation
import ImageIO

/// Decodes a camera picture, for SwiftUI's `Image(decorative:scale:)` and for analysis.
public enum Picture {
    /// The first image in JPEG or other image data, `nil` if it can't be decoded.
    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

#endif
