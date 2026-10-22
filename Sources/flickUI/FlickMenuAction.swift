#if canImport(UIKit)
import FlickCore
import SwiftUI

/// Opens and closes a menu from code: a button, a keyboard shortcut or a gesture of
/// your own. Read it from the environment of the content `flickMenu` is attached to.
///
/// ```swift
/// @Environment(\.flickMenu) private var menu
///
/// Button("Menu") { menu.open() }
/// ```
///
/// Outside a menu's content it does nothing.
public struct FlickMenuAction {
    let controller: FlickMenuController?

    init(controller: FlickMenuController? = nil) {
        self.controller = controller
    }

    /// Opens the menu without a swipe. It stays open until an item is chosen or it is
    /// dismissed.
    /// - Parameter edge: The edge to open from. `nil` opens it on the indicator's edge.
    @MainActor public func open(from edge: FlickEdge? = nil) {
        controller?.perform(.open(edge))
    }

    /// Closes the menu without choosing an item.
    @MainActor public func dismiss() {
        controller?.perform(.dismiss)
    }

    /// Opens the menu if it is closed, and closes it if it is open.
    @MainActor public func toggle(from edge: FlickEdge? = nil) {
        controller?.perform(.toggle(edge))
    }
}

extension EnvironmentValues {
    /// Opens and closes the enclosing `flickMenu`.
    @Entry public var flickMenu = FlickMenuAction()
}

/// Connects ``FlickMenuAction`` to a menu. Each menu keeps one instance for its
/// lifetime, so the environment sees the same reference on every update.
@MainActor
final class FlickMenuController {
    enum Command {
        case open(FlickEdge?)
        case dismiss
        case toggle(FlickEdge?)
    }

    var perform: @MainActor (Command) -> Void = { _ in }
}
#endif
