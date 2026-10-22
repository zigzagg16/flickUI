#if canImport(UIKit)
import FlickCore
import SwiftUI

/// Hidden buttons for hardware keyboards. They also list the commands in the
/// keyboard shortcuts overlay on iPad.
struct FlickKeyboardCommands: View {
    enum Command {
        case toggle
        case dismiss
        case move(Int)
        case choose
    }

    let session: FlickSession?
    /// Opens and closes the menu. `nil` for none.
    let shortcut: KeyboardShortcut?
    let perform: (Command) -> Void

    var body: some View {
        let isPresented = session?.origin == .presentation
        let isVertical = session?.edge.mainAxis == .vertical
        ZStack {
            if let shortcut {
                command(Text("Open Menu", bundle: #bundle, comment: "Keyboard command that opens or closes the menu."), .toggle)
                    .keyboardShortcut(shortcut)
            }
            if session != nil {
                command(Text("Close Menu", bundle: #bundle, comment: "Keyboard command that closes the menu."), .dismiss)
                    .keyboardShortcut(.cancelAction)
            }
            if isPresented {
                command(
                    Text("Previous Item", bundle: #bundle, comment: "Keyboard command that highlights the previous menu item."),
                    .move(-1)
                )
                    .keyboardShortcut(isVertical ? .upArrow : .leftArrow, modifiers: [])
                command(Text("Next Item", bundle: #bundle, comment: "Keyboard command that highlights the next menu item."), .move(1))
                    .keyboardShortcut(isVertical ? .downArrow : .rightArrow, modifiers: [])
                command(Text("Choose Item", bundle: #bundle, comment: "Keyboard command that chooses the highlighted menu item."), .choose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func command(_ title: Text, _ command: Command) -> some View {
        Button { perform(command) } label: { title }
    }
}
#endif
