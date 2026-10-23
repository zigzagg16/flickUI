#if canImport(UIKit)
import FlickCore
import SwiftUI

/// The outline of a ``FlickMorphingShape``. Every property animates, so any two
/// forms morph smoothly into each other.
public struct FlickShapeForm: Hashable, Sendable {
    /// The roundness of the side facing the edge: `0.55` is elliptical, `1` square.
    public var edgeRoundness: CGFloat
    /// The roundness of the side away from the edge.
    public var farRoundness: CGFloat
    /// How far the side facing the edge is drawn out into a point, as a fraction of
    /// the shape's extent away from the edge. `0` for none.
    public var tail: CGFloat
    /// Stretch along the edge, with the extent away from the edge shrinking to
    /// match. `0` for none.
    public var stretch: CGFloat

    public init(edgeRoundness: CGFloat, farRoundness: CGFloat, tail: CGFloat = 0, stretch: CGFloat = 0) {
        self.edgeRoundness = edgeRoundness
        self.farRoundness = farRoundness
        self.tail = tail
        self.stretch = stretch
    }

    /// An ellipse, or a circle in a square frame.
    public static let round = Self(edgeRoundness: 0.56, farRoundness: 0.56)
    /// A superellipse, like an app icon.
    public static let squircle = Self(edgeRoundness: 0.86, farRoundness: 0.86)
    /// A drop pointing at the edge, close to CariocaMenu's bubble.
    public static let drop = Self(edgeRoundness: 0.6, farRoundness: 0.9, tail: 0.18)

    /// The same form, stretched further.
    public func stretched(by amount: CGFloat) -> Self {
        var form = self
        form.stretch += amount
        return form
    }
}

/// A shape oriented to a screen edge that morphs between ``FlickShapeForm``s.
public struct FlickMorphingShape: Shape {
    public var edge: FlickScreenEdge
    public var form: FlickShapeForm

    public init(edge: FlickScreenEdge, form: FlickShapeForm) {
        self.edge = edge
        self.form = form
    }

    public nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(form.edgeRoundness, form.farRoundness),
                AnimatablePair(form.tail, form.stretch)
            )
        }
        set {
            form.edgeRoundness = newValue.first.first
            form.farRoundness = newValue.first.second
            form.tail = newValue.second.first
            form.stretch = newValue.second.second
        }
    }

    public nonisolated func path(in rect: CGRect) -> Path {
        let vertical = edge.mainAxis == .vertical
        // Cross: away from the edge. Main: along the edge.
        let cross = vertical ? rect.width : rect.height
        let main = vertical ? rect.height : rect.width
        let edge = self.edge
        let tail = min(max(form.tail, 0), 0.9)
        let stretch = max(1 + form.stretch, 0.1)
        let edgeK = form.edgeRoundness
        let farK = form.farRoundness

        // Points are built in unit coordinates, `c` from the edge and `m` along it,
        // then stretched about the centre and mapped to the edge.
        func point(_ c: CGFloat, _ m: CGFloat) -> CGPoint {
            let c = cross / 2 + (c - 0.5) * cross / stretch
            let m = main / 2 + (m - 0.5) * main * stretch
            switch edge {
            case .left: return CGPoint(x: rect.minX + c, y: rect.minY + m)
            case .right: return CGPoint(x: rect.maxX - c, y: rect.minY + m)
            case .top: return CGPoint(x: rect.minX + m, y: rect.minY + c)
            case .bottom: return CGPoint(x: rect.minX + m, y: rect.maxY - c)
            }
        }

        // The body spans from `tail` to 1; the tail point sits on the edge side at 0.
        let bodyHalf = (1 - tail) / 2
        let center = 1 - bodyHalf
        // A longer tail has shorter tangents at its tip, so it reads as a point.
        let tip = edgeK * 0.5 / (1 + 3 * tail)

        var path = Path()
        path.move(to: point(1, 0.5))
        path.addCurve(
            to: point(center, 0),
            control1: point(1, 0.5 - 0.5 * farK),
            control2: point(center + bodyHalf * farK, 0)
        )
        path.addCurve(
            to: point(0, 0.5),
            control1: point(center - bodyHalf * edgeK, 0),
            control2: point(0, 0.5 - tip)
        )
        path.addCurve(
            to: point(center, 1),
            control1: point(0, 0.5 + tip),
            control2: point(center - bodyHalf * edgeK, 1)
        )
        path.addCurve(
            to: point(1, 0.5),
            control1: point(center + bodyHalf * farK, 1),
            control2: point(1, 0.5 + 0.5 * farK)
        )
        path.closeSubpath()
        return path
    }
}

/// The forms of a morphing indicator: one at rest against the edge, one while the
/// menu is open, and how much it stretches as the finger moves.
public struct FlickIndicatorMorph: Hashable, Sendable {
    public var resting: FlickShapeForm
    public var open: FlickShapeForm
    /// The stretch at full speed. `0` turns it off.
    public var maximumStretch: CGFloat
    /// How springy the morphs are, from `0` (none) to `1`.
    public var bounce: CGFloat

    public init(resting: FlickShapeForm, open: FlickShapeForm, maximumStretch: CGFloat = 0.3, bounce: CGFloat = 0.45) {
        self.resting = resting
        self.open = open
        self.maximumStretch = maximumStretch
        self.bounce = bounce
    }

    /// A drop against the edge that rounds into a bead when the menu opens.
    public static let drop = Self(resting: .drop, open: .round, maximumStretch: 0.3)
    /// A superellipse that softens into a bead.
    public static let squircle = Self(resting: .squircle, open: .round, maximumStretch: 0.2, bounce: 0.35)
    /// A round, liquid bead that stretches strongly with speed.
    public static let liquid = Self(resting: .round, open: .round, maximumStretch: 0.5, bounce: 0.6)
    /// No morphing: the same drop throughout.
    public static let still = Self(resting: .drop, open: .drop, maximumStretch: 0, bounce: 0)

    /// The form for an indicator state.
    /// - Parameters:
    ///   - isOpen: Whether the menu is open.
    ///   - velocity: The finger's velocity along the edge, in points per second.
    public func form(isOpen: Bool, velocity: CGFloat) -> FlickShapeForm {
        let speed = min(abs(velocity) / 2000, 1)
        return (isOpen ? open : resting).stretched(by: maximumStretch * speed)
    }
}
#endif
