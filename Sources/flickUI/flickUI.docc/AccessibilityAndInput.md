# Accessibility and input

Use the menu with VoiceOver, large text, a keyboard, a pointer or Apple Pencil.

## Overview

The menu works without a swipe: tapping the indicator opens it in place, and an
item is then chosen with a tap.

### VoiceOver

The indicator is a button labelled "Menu", with the selected item as its value.
Swipe up or down on it to change the selection without opening the menu. Once the
menu is open, VoiceOver stays inside it, and the escape gesture (a two-finger
scrub) closes it.

### Dynamic Type, Reduce Motion and Reduce Transparency

Items grow with the text size, up to a limit that keeps a useful number of them on
screen; beyond it, titles shrink to fit. The indicator keeps its size and shows the
large content viewer on a long press. With Reduce Motion on, springs become short
fades. With Reduce Transparency on, materials and gradients become opaque, and
Liquid Glass adapts itself.

### Opening the menu from code

Read ``FlickMenuAction`` from the environment of the content the menu is attached
to:

```swift
struct MenuButton: View {
    @Environment(\.flickMenu) private var menu

    var body: some View {
        Button("Menu", systemImage: "list.bullet") { menu.open() }
    }
}
```

### Keyboard

`flickMenuKeyboardShortcut(_:)` adds a shortcut that opens and closes the menu.
While a menu opened without a swipe is shown, the arrow keys move through the items,
Return chooses one and Escape closes it. On iPad, the commands appear in the
keyboard shortcuts overlay.

```swift
ContentView()
    .flickMenuKeyboardShortcut(KeyboardShortcut("m", modifiers: .command))
```

### Pointer and Apple Pencil

Rows and the indicator have hover effects with a pointer or a hovering Pencil.
`flickMenuOpensOnPencilSqueeze(_:)` lets a squeeze of Apple Pencil Pro open and close
the menu. It is only used when the person's preferred squeeze action, in Settings,
is to show a contextual palette.
