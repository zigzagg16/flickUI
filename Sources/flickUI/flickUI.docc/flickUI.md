# ``flickUI``

A fluid menu that opens with a swipe from any screen edge.

## Overview

Swipe in from an edge and the selected item appears under your finger. Sliding
along the edge moves through the items, and lifting your finger chooses one. It is
a modern rebuild of CariocaMenu, with SF Symbol items, a morphing Liquid Glass
indicator and per-edge customisation.

```swift
import flickUI

struct ContentView: View {
    @State private var tab = Tab.home.id

    var body: some View {
        TabContent(tab)
            .flickMenu(Tab.allCases, selection: $tab, edges: .all, title: \.title, systemImage: \.symbol)
    }
}
```

`flickUI` re-exports its engine, `FlickCore`, so apps only need `import flickUI`.

## Topics

### Essentials

- <doc:CustomizingTheMenu>
- <doc:AccessibilityAndInput>
- ``FlickEdge``
- ``FlickEdgeSet``
- ``FlickMenuEvent``

### Opening the menu from code

- ``FlickMenuAction``

### Indicator

- ``FlickIndicatorStyle``
- ``FlickIndicatorStyleConfiguration``
- ``FlickAutomaticIndicatorStyle``
- ``FlickMorphingIndicatorStyle``
- ``FlickGlassIndicatorStyle``
- ``FlickBubbleIndicatorStyle``
- ``FlickCapsuleIndicatorStyle``
- ``FlickIndicatorMorph``
- ``FlickShapeForm``
- ``FlickMorphingShape``
- ``FlickBubbleShape``

### Rows

- ``FlickMenuRowStyle``
- ``FlickMenuRowStyleConfiguration``
- ``FlickMagnifyingRowStyle``
- ``FlickPlainRowStyle``
- ``FlickMenuItemEmphasis``
- ``FlickSymbolEffect``

### Background

- ``FlickMenuBackgroundStyle``
- ``FlickMenuBackgroundStyleConfiguration``
- ``FlickMaterialBackgroundStyle``
- ``FlickGradientBackgroundStyle``
- ``FlickColorBackgroundStyle``

### Behaviour

- ``FlickMenuFeedback``
- ``FlickMenuHome``
