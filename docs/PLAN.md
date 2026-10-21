# flickUI — Plan

flickUI is a SwiftUI rebuild of [CariocaMenu](https://github.com/zigzagg16/cariocamenu):
a "zero-tap" menu that opens when the user swipes in from a screen edge. The user
picks an item by sliding up or down and selects it by lifting the finger.

---

## 1. How CariocaMenu works

### Interaction model
1. **Resting state.** A small indicator bubble sits on one edge at a configured
   vertical position (as a %). It shows the icon of the selected item.
2. **Edge pan begins** (`UIScreenEdgePanGestureRecognizer`, left/right only):
   - the delegate gets `willOpenFromEdge`, and the table is reloaded and shown
     full-screen (with optional blur);
   - the indicator animates *across* the screen to the opposite edge
     ("traversing"), with a two-step ease-in/ease-out bounce;
   - the touch's starting Y is stored.
3. **Pan changes.** The menu is placed so that **the selected item sits under the
   finger**, and it moves *opposite* to the finger:
   ```
   menuTop = startY − rowH·selectedIndex − rowH/2 + (startY − fingerY)
   ```
   A finger movement of Δ moves the menu by −Δ, so the two move apart at 2× speed,
   and a short swipe reaches any row. When `isOffscreenAllowed == false` the value
   is clamped to `20…(hostH − menuH)`.
   The highlighted index is `floor((fingerY − menuTop) / rowH)`, clamped to the
   item range. Each index change moves the indicator to that row, swaps its icon,
   and fires selection haptics.
4. **Pan ends.** The highlighted item is selected and sent to the delegate. The
   menu fades out (0.5s) and the indicator is **restored**:
   - `none`: the indicator stays on the current edge at its current Y;
   - `horizontal`: it returns to the original edge;
   - `vertical`: it returns to the original Y, possibly on the other edge;
   - `originalPosition`: it returns to both the original edge and the original Y.
   In boomerang modes it first slides off-screen, jumps, then bounces back in.
5. **Tap on the indicator.** This simulates a pan began/changed at the tap
   location, which opens the menu in place. A row is then picked with a normal
   table tap.

### Source structure (≈900 LOC)
| File | Role |
|---|---|
| `CariocaMenu.swift` | Coordinator: wires the controller, gestures, indicator and table delegate; show/hide, haptics |
| `CariocaGestureManager.swift` | Edge pan recognisers + **pure math** (`topYConstraint`, `matchingIndex`) |
| `CariocaIndicatorView.swift` | Indicator view, Auto Layout constraint animations, safe-area/notch handling, boomerang restore, **pure math** (`positionConstants`) |
| `CariocaIndicatorConfiguration.swift` | Protocol for indicator colour, font, size, border margin, bounce values, `shape(for:frame:)` (default PaintCode bubble), icon margins |
| `CariocaMenuContainerView.swift` | Full-screen container, table pinned by a top constraint, blur |
| `CariocaMenu+Protocols.swift` | `CariocaDataSource` (the consumer subclasses `UITableViewController`), `CariocaDelegate` |
| `CariocaIcon.swift`, `CariocaMenuItem.swift` | Item model: title + `.emoji(String)` / `.icon(UIImage)` / `.none` |
| `CariocaMenu+Enums.swift` | `BoomerangType` |

### Weaknesses not to carry over
- **Imperative and UIKit-bound.** The consumer must subclass `UITableViewController`,
  call `addInHostView()`, call `bringToFront()`, and forward rotation by hand
  (`hostViewDidRotate`).
- **Crash points.** `edges.first!`, `menuItems.first!`, `superview!`. Edges
  outside `.left/.right` are not validated (there is a TODO for this).
- **Stale layout.** `menuHeight` is computed once at init, so changing the item
  count later breaks the layout.
- **Margin bug.** `makeAnchorConstraints` returns `[top, right, left, bottom]`,
  but `applyMarginConstraints` assumes `[top, right, bottom, left]`, so the bottom
  and left icon margins are swapped.
- **Side effects in drawing.** `draw(_:)` changes constraints. The demo's custom
  indicator fills inside `shape()`.
- **Notch hacks.** The magic numbers `44.0`/`35.0` and `UIDevice.orientation`
  guesses stand in for real safe-area handling.
- **Unused/ad-hoc code.** `edgePanGestures` is never filled. Animation-state flags
  guard against overlapping completion chains.
- **Accessibility.** There is no VoiceOver path, RTL support or Reduce Motion
  handling.

---

## 2. flickUI goals

- **Declarative and generic.** It is a single view modifier that works with any
  `Identifiable` data, bound to a selection.
- **Same feel.** It keeps the opposite-motion, release-to-select mechanic and the
  traverse/bounce indicator, and gets them from SwiftUI springs and keyframes
  instead of hand-chained `UIView.animate`.
- **Customisable throughout.** Rows, indicator, background, layout constants,
  animations and haptics can all be changed, using SwiftUI's `*Style` protocol
  pattern.
- **Safe by construction.** No force-unwraps, edges are validated at the type
  level, and the layout recomputes from live geometry. Rotation, safe areas,
  Dynamic Island and iPad multitasking are handled with no extra work from the
  consumer.
- **Accessible.** VoiceOver, RTL, Reduce Motion and a tap-to-open fallback.
- **Testable.** All geometry lives in pure value types with unit tests.

---

## 3. Proposed public API

```swift
struct ContentView: View {
    @State private var tab: Tab = .home

    var body: some View {
        TabContent(tab)
            .flickMenu(Tab.allCases, selection: $tab, edges: [.leading, .trailing]) { tab, row in
                // Custom row. `row` exposes isHighlighted, edge, index…
                Label(tab.title, systemImage: tab.symbol)
                    .frame(maxWidth: .infinity, alignment: row.edge == .leading ? .trailing : .leading)
            } icon: { tab in
                Image(systemName: tab.symbol)      // shown inside the indicator
            }
            .flickMenuBoomerang(.horizontal)
            .flickMenuRowHeight(60)
            .flickMenuIndicatorStyle(.bubble(tint: .blue))   // or a custom FlickIndicatorStyle
            .flickMenuBackground(.ultraThinMaterial)
            .flickMenuRestingPosition(0.5)       // 0…1 of available height
            .flickMenuAllowsOffscreen(true)
            .onFlickMenuOpen { edge in … }
            .onFlickMenuSelect { tab in … }
    }
}
```

Building blocks:
- `FlickEdge`: `.leading`, `.trailing`, mirrored for RTL. The core is written per
  axis, so `.top`/`.bottom` can be added later without a rewrite.
- `FlickBoomerang`: `.none`, `.horizontal`, `.vertical`, `.originalPosition`.
- `FlickIndicatorStyle` (`makeBody(configuration:)`, like `ButtonStyle`). The
  configuration exposes `edge`, `icon`, `phase` (resting, tracking, restoring)
  and `isPressed`. The built-ins are `.bubble` (a port of the PaintCode shape as a
  mirrored SwiftUI `Shape`), `.capsule`, `.circle` and `.polygon`.
- `FlickMenuRowStyle` gives full row control. Without one, the row builder's
  output is wrapped in a default style that handles highlight, edge alignment and
  insets.
- The configuration flows through the `Environment`, so it can be set at any
  level of the view tree, like `.buttonStyle`.

---

## 4. Internal architecture

```
Sources/FlickUI/
  Public/        FlickMenuModifier.swift, FlickEdge.swift, FlickBoomerang.swift,
                 FlickIndicatorStyle.swift, FlickMenuRowStyle.swift, Environment+Flick.swift
  Engine/        FlickGeometry.swift      ← pure math (port of topYConstraint/matchingIndex/positionConstants)
                 FlickStateMachine.swift  ← pure reducer: idle → tracking → committing → restoring → idle
  Gesture/       EdgePanGesture.swift     ← UIGestureRecognizerRepresentable over UIScreenEdgePanGestureRecognizer
  Views/         FlickMenuOverlay.swift, FlickMenuList.swift, FlickIndicator.swift, BubbleShape.swift
Tests/FlickUITests/   FlickGeometryTests.swift, FlickStateMachineTests.swift
Examples/FlickDemo/   SwiftUI demo app (mirrors the Carioca demo screens)
```

### Key design decisions
1. **Gesture: wrap UIKit's edge pan** with `UIGestureRecognizerRepresentable`
   (iOS 18+), not `DragGesture` on an edge strip. This matches the system edge
   feel, does not block touches on content near the edge, and works over
   `ScrollView`, `Map` and `WebView` without Carioca's "gesture helper" views. A
   gesture-recogniser delegate handles coexistence with `NavigationStack`'s
   interactive back swipe; the docs will recommend `.trailing` when a back stack
   exists.
2. **The state machine is a pure reducer.** Events (`began`, `moved`, `ended`,
   `cancelled`, `tapIndicator`, `tapOutside`, `geometryChanged`) map to a new
   state plus effects (haptic, notify, animate). This replaces Carioca's
   `AnimationState` flags and nested completion closures, and makes cancelling
   mid-animation predictable.
3. **The geometry is pure and value-typed.** `FlickGeometry` takes the container
   size, safe-area insets, row height, item count and edge, and returns the menu
   offset, highlighted index and indicator anchor points. Safe-area insets come
   straight from SwiftUI, which removes the notch and orientation heuristics.
   Carioca's existing test vectors (for example 554 / −150 / 700) are ported as
   regression tests so the feel is preserved.
4. **Rendering is an overlay ZStack**, laid out with
   `onGeometryChange`/`GeometryReader`:
   - a background layer (a style-supplied material or colour) that fades in and
     out;
   - the menu list as a `VStack` of fixed-height rows moved with `.offset(y:)`.
     It does not use `List` or `ScrollView`, because the menu must not scroll;
   - the indicator, positioned by `.position`, animated with `.spring` and a
     `keyframeAnimator` for the traverse and bounce.
5. **Uniform row height is required** because the index math depends on it.
   It is scaled with `@ScaledMetric` for Dynamic Type.
6. **Haptics** use `.sensoryFeedback(.selection, trigger: highlightedIndex)` and
   `.sensoryFeedback(.impact, trigger: committedSelection)`, and can be turned off.

### Accessibility and robustness
- The indicator is a real `Button`, labelled "Menu, current: <item>". Activating
  it opens the menu in tap mode, where a tap on a row selects it and a tap
  outside or the Escape gesture dismisses it. It also offers an adjustable
  action and custom actions for each item, so VoiceOver users never need the
  edge swipe.
- With Reduce Motion on, the traverse and bounce animations become crossfades.
- RTL is handled because edges are logical (`.leading`/`.trailing`).
- Size and safe-area changes during interaction cancel tracking cleanly.

---

## 5. Milestones

| # | Milestone | Deliverable |
|---|---|---|
| M0 | **Scaffold** | `Package.swift` (tools 6.0, iOS 18, Swift 6 strict concurrency), folder layout, SwiftLint config, GitHub Actions (`xcodebuild test` on an iOS simulator, macOS runner), README skeleton |
| M1 | **Geometry engine** | `FlickGeometry` plus tests, with Carioca's test vectors ported (top offset, matching index, indicator positions, safe-area cases) |
| M2 | **State machine** | Pure reducer plus tests for open, track, commit, restore for all 4 boomerang modes, cancel paths and tap mode |
| M3 | **Edge gesture bridge** | `EdgePanGesture` representable, coexistence with back swipe and scroll views |
| M4 | **Menu overlay** | Background, list offset tracking, highlight, release-to-select, haptics, open/select callbacks |
| M5 | **Indicator** | Default `BubbleShape`, edge mirroring, traverse/bounce keyframes, boomerang restore, icon swap |
| M6 | **Customisation API** | `FlickIndicatorStyle`, `FlickMenuRowStyle`, environment modifiers, built-in styles |
| M7 | **Accessibility and polish** | VoiceOver path, Reduce Motion, RTL, Dynamic Type, iPad multitasking |
| M8 | **Demo and docs** | `Examples/FlickDemo` app, DocC catalogue, README with GIF, Xcode previews for each style |

Every milestone is a separate PR that builds and passes its tests.

---

## 6. Open questions

1. **Minimum OS.** The plan assumes iOS 18 for `UIGestureRecognizerRepresentable`.
   iOS 17 is possible with a `UIViewRepresentable` gesture host, at the cost of
   more code.
2. **Edges in v1.** Only leading/trailing (like Carioca), or also top/bottom?
3. **Platforms.** iOS/iPadOS only, or also visionOS/macOS? Neither has an edge pan.
4. **Exact feel.** Keep Carioca's 2× opposite-motion constant exactly, or make
   the ratio configurable (`trackingRatio`, default matching Carioca)?
5. **Module name.** `FlickUI` (product) in the `flickUI` repo?

## 7. Verification note
iOS builds and simulator tests need macOS and Xcode. The plan relies on GitHub
Actions macOS runners for CI. The `Engine/` layer imports only Foundation (where `CGFloat`/`CGPoint` are also
available on Linux), so it can also be unit-tested on Linux with SwiftPM for fast local
feedback.
