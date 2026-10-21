#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Floating-point comparison for geometry expectations.
func isApproximately(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}
