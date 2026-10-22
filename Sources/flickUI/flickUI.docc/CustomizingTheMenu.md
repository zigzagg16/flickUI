# Customizing the menu

Change how the menu looks and behaves, for all edges or only some.

## Overview

Every setting is a view modifier. Settings flow through the environment, so you
can apply them anywhere above the view that has the menu, in any order.

```swift
ContentView()
    .flickMenuIndicatorStyle(.morphing(.liquid))
    .flickMenuIndicatorStyle(.bubble(tint: .pink), edges: .vertical)
    .flickMenuRowStyle(.magnifying(.dock), edges: .horizontal)
    .flickMenuBackground(.gradient, edges: .top)
    .flickMenuPhysics(.fluid)
    .flickMenuTracking(ratio: 3, edges: .bottom)
    .flickMenuBoomerang(.origin)
    .flickMenuHome(.trailing, position: 0.6)
    .flickMenuFeedback(.subtle)
```

### Per-edge settings

Most settings take an `edges` parameter. Without it, the setting is the default for
every edge. With it, the setting applies to those edges only, and always takes
precedence over the default, whatever the modifier order. Edges are logical:
`.leading` and `.trailing` follow the layout direction.

### Your own styles

Indicator, row and background styles follow SwiftUI's style pattern. Conform to
``FlickIndicatorStyle``, ``FlickMenuRowStyle`` or ``FlickMenuBackgroundStyle`` and
build a view from the configuration:

```swift
struct OutlinedIndicatorStyle: FlickIndicatorStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().stroke(.tint, lineWidth: 2))
    }
}
```

### Emphasis

``FlickMenuItemEmphasis`` sets how the highlighted and selected items look: a tint,
a symbol variant and an SF Symbols effect, played once or repeating.

```swift
ContentView()
    .flickMenuHighlight(FlickMenuItemEmphasis(tint: .yellow, symbolVariant: .fill, symbolEffect: .wiggle))
    .flickMenuSelection(FlickMenuItemEmphasis(symbolEffect: .breathe.repeating))
```

### Events

`onFlickMenuEvent(_:)` reports when the menu opens, an item is highlighted or
chosen, and when it is dismissed. Several handlers can be attached; all are called,
outermost first.
