#if canImport(UIKit)
import FlickCore
import SwiftUI
import UIKit

/// A screen-edge pan, bridged from UIKit so it matches the system's edge feel and
/// works over scroll views, maps and web views.
struct FlickEdgePanGesture: UIGestureRecognizerRepresentable {
    enum Phase {
        /// Location in global coordinates.
        case began(CGPoint)
        /// Location and velocity in global coordinates.
        case changed(CGPoint, CGPoint)
        /// Velocity in global coordinates.
        case ended(CGPoint)
        case cancelled
    }

    let edge: FlickScreenEdge
    let isEnabled: Bool
    let onPhase: @MainActor (Phase) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.edges = edge.rectEdge
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        recognizer.edges = edge.rectEdge
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIScreenEdgePanGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .global)
        let velocity = context.converter.velocity(in: .global) ?? .zero
        switch recognizer.state {
        case .began:
            onPhase(.began(location))
        case .changed:
            onPhase(.changed(location, velocity))
        case .ended:
            onPhase(.ended(velocity))
        case .cancelled, .failed:
            onPhase(.cancelled)
        default:
            break
        }
    }
}

extension FlickScreenEdge {
    var rectEdge: UIRectEdge {
        switch self {
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        }
    }
}
#endif
