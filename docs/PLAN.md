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

## 2. Decisions

| Topic | Decision |
|---|---|
| Minimum OS | **iOS/iPadOS 18**. Newer APIs are adopted in tiers (see §5) |
| Edges | **All four**: `.leading`, `.trailing`, `.top`, `.bottom`, plus a **hinge** edge on foldables |
| Platforms | iOS and iPadOS in v1. The engine has no UIKit dependency so other touch OSes can follow (see §8) |
| Tracking speed | Configurable `trackingRatio`. The default `2.0` reproduces CariocaMenu's feel |
| Module / product | `flickUI` |
| Branching | All work goes to a dev branch and is squash-merged into `main` |

## 3. Goals

- **Declarative and generic.** It is a single view modifier that works with any
  `Identifiable` data, bound to a selection.
- **Top-notch interaction.** The opposite-motion, release-to-select mechanic is
  kept and then improved:
  - motion is driven by interruptible springs, never fixed durations;
  - lifting with velocity keeps the menu's momentum;
  - magnification and resistance make positions feel physical.
- **Everything customisable.** Rows, indicator, background, layout, physics,
  haptics, sounds, transitions and accessibility labels can all be changed,
  using SwiftUI's `*Style` protocol pattern and environment values. Each one has
  a polished default.
- **First-class on new hardware.** The menu adapts to iPhone Duo's fold, the
  Dynamic Island, iPad multitasking and Stage Manager windows.
- **Safe by construction.** No force-unwraps, the layout always comes from live
  geometry, and Swift 6 strict concurrency is on.
- **Accessible.** VoiceOver, RTL, Reduce Motion, Reduce Transparency, Dynamic
  Type, and a tap or keyboard path to every item.
- **Testable.** All geometry and the state machine are pure value types with
  unit tests.

---

## 4. Proposed public API

```swift
struct ContentView: View {
    @State private var tab: Tab = .home

    var body: some View {
        TabContent(tab)
            .flickMenu(Tab.allCases, selection: $tab) { tab, row in
                // row: index, isHighlighted, distance (finger → row, for effects), edge, phase
                Label(tab.title, systemImage: tab.symbol)
            } icon: { tab in
                Image(systemName: tab.symbol)      // shown inside the indicator
            }
            .flickMenuEdges(.all)                         // [.leading, .trailing, .top, .bottom, .hinge]
            .flickMenuTracking(ratio: 2.0, rubberBand: .soft)
            .flickMenuBoomerang(.origin)              // .stay, .edge, .position, .origin
            .flickMenuIndicatorStyle(.glass)              // .glass, .bubble, .capsule, .orb, custom
            .flickMenuRowStyle(.magnifying)               // .plain, .magnifying, .carousel, custom
            .flickMenuBackground(.glass(.regular))         // .glass / material / color / custom view
            .flickMenuHaptics(.default)                   // per event: highlight, edgeHit, commit, cancel
            .flickMenuFoldBehavior(.avoidHinge)           // iPhone Duo (see §6)
            .onFlickMenuOpen { edge in … }
            .onFlickMenuSelect { tab in … }
    }
}

// Programmatic control: open from a button, a shortcut or Pencil squeeze.
@Environment(\.flickMenu) private var menu
menu.open(from: .trailing)
```

### Customisation surface
| Area | API | Built-ins |
|---|---|---|
| Indicator | `FlickIndicatorStyle` (`makeBody(configuration:)`): edge, icon, phase, highlight progress, hinge state | `.glass` (Liquid Glass, morphs into the menu), `.bubble` (CariocaMenu's shape, ported as a `Shape`), `.capsule`, `.orb`, `.minimal` |
| Rows | `FlickMenuRowStyle`: index, highlight, signed distance to the finger, edge, phase | `.plain`, `.magnifying` (Dock-style fisheye), `.carousel` (3-D roll), `.compact` |
| Background | `FlickMenuBackgroundStyle` | `.glass`, `.material`, `.dim`, `.blurredContent`, `.none` |
| Layout | `FlickMenuLayout`: row size, spacing, insets, menu alignment on the cross axis, maximum extent | — |
| Physics | `FlickMenuPhysics`: `trackingRatio`, `rubberBand`, `velocityProjection`, spring presets | `.carioca` (exact original), `.snappy`, `.fluid` |
| Feedback | `FlickMenuFeedback`: `SensoryFeedback` per event, optional sounds | `.default`, `.subtle`, `.none` |
| Transitions | Open/close transitions and indicator traverse | `.morph`, `.slide`, `.fade` (used automatically with Reduce Motion) |
| Accessibility | Labels, hints, custom actions | Generated from the item titles |

The configuration flows through the `Environment`, so it can be set at any level
of the view tree.

---

## 5. Platform API tiers

Each tier is gated with `if #available` / `@available`. A device on a lower tier
gets a polished fallback, never a broken one.

| Tier | APIs used | What it adds |
|---|---|---|
| **iOS 18 (base)** | `UIGestureRecognizerRepresentable`, `onGeometryChange`, `keyframeAnimator`, `PhaseAnimator`, `visualEffect`, `sensoryFeedback`, `symbolEffect`/`contentTransition(.symbolEffect(.replace))`, `@Entry` environment values, Metal shader effects (`layerEffect`/`distortionEffect`), `onPencilSqueeze` | The full interaction: edge gesture, springs, magnification, haptics, symbol morphs, a ripple shader when an item is chosen |
| **iOS 26** | Liquid Glass: `glassEffect`, `GlassEffectContainer`, `glassEffectID` + `@Namespace`, `.interactive()` | The glass indicator **morphs** into the menu panel and back. The materials match the system look |
| **iOS 27.1** | Foldable APIs (hinge state and angle, arrangement and reserved regions)¹ | The iPhone Duo features in §6 |

¹ See §6.

---

## 6. Device-specific features

The aim is maximum support: every feature below is detected at runtime
(`if #available`, hardware capability checks, size and region data, never device
model strings). Devices without a feature get the iOS 18 base experience.

| Device / hardware | Feature | API (minimum OS) |
|---|---|---|
| **iPhone Duo** (foldable) | Rows never straddle the fold. The indicator never rests on the crease. | Reserved regions (27.1)¹ |
| | Half-folded (book or tabletop) posture: the menu opens on the half under the finger | Hinge state (27.1)¹ |
| | Opt-in **hinge edge**: a swipe from the fold opens the menu along it, with items fanning out to both halves | Hinge geometry (27.1)¹ |
| | Glass and parallax react to the hinge angle | Hinge angle (27.1)¹ |
| | Selection and indicator position carry over between the outer and inner displays | Scene geometry (18) |
| **Liquid Glass devices** | The glass indicator **morphs** into the menu. The material follows the system glass setting | `glassEffect`, `GlassEffectContainer`, `glassEffectID` (26) |
| **Dynamic Island / notch** | The top edge and resting positions avoid the sensor housing | Safe area (18) |
| **ProMotion (120 Hz)** | Tracking follows the gesture recogniser at display rate. Springs are tuned for 120 Hz | `UIGestureRecognizerRepresentable` (18) |
| **Taptic Engine** | Detent haptics per item, a stronger "edge hit" at the ends, and a commit thump | `sensoryFeedback` (18); Core Haptics patterns where supported |
| **iPad + Apple Pencil Pro** | Squeeze opens the menu at the Pencil's position. Barrel roll moves through items | `onPencilSqueeze`, hover pose (17.5+) |
| **iPad pointer / trackpad** | Hovering near an edge makes the indicator peek out. Rows have hover and lift effects | `onContinuousHover`, `hoverEffect` (18) |
| **iPad hardware keyboard** | A shortcut opens the menu, arrow keys move, Return chooses, Esc closes | `keyboardShortcut`, `onKeyPress` (18) |
| **Stage Manager / Split View** | The menu lays out from the live window size and adapts as the window resizes | `onGeometryChange` (18) |
| **Action button / Control Center** | An App Intent and Control widget open the menu from outside the app | `AppIntent`, `ControlWidget` (18) |

Not used: **Camera Control**. Apple reserves it for camera experiences, so a
navigation menu should not use it.

¹ These names come from early, secondhand reports. They will be checked against
the iOS 27.1 SDK headers before implementation, and the code will be isolated in
one file so a renamed symbol doesn't affect the rest.

---

## 7. Internal architecture

```
Sources/flickUI/
  Public/        FlickMenuModifier, FlickEdge, FlickBoomerang, styles (Indicator/Row/Background),
                 FlickMenuPhysics, FlickMenuFeedback, FlickMenuController (programmatic), Environment+Flick
  Engine/        FlickGeometry       ← pure math for 2 axes (port of topYConstraint/matchingIndex/positionConstants)
                 FlickPhysics        ← rubber-banding, velocity projection, magnification curve
                 FlickStateMachine   ← pure reducer: idle → peeking → tracking → committing → restoring
                 FlickFoldModel      ← hinge/region geometry → safe layout bands (pure, testable without a device)
  Platform/      EdgePanGesture (UIGestureRecognizerRepresentable), HingeObserver (27.1), HoverPeek
  Views/         FlickMenuOverlay, FlickMenuStack, FlickIndicator, Shapes/, Shaders/flick.metal
Tests/flickUITests/   Geometry, physics, state machine, fold model, and the CariocaMenu regression vectors
Examples/FlickDemo/   Showcase app: every style, edge, physics preset and Duo posture
```

### Key design decisions
1. **Axis-generic geometry.** All the math works in terms of a "main axis"
   (along the edge) and a "cross axis" (away from the edge). Left/right use Y as
   the main axis and top/bottom use X. The hinge is an internal edge with two
   sides. Carioca's 554 / −150 / 700 test values are kept as regression tests for
   `.carioca` physics.
2. **Gesture: UIKit's edge pan** wrapped with `UIGestureRecognizerRepresentable`.
   It needs one recogniser per edge. A delegate handles the conflicts: the
   leading back swipe in a navigation stack, the top edge and Notification
   Center, and the bottom edge and the home indicator. The top and bottom edges
   use `preferredScreenEdgesDeferringSystemGestures`, so the system gesture runs
   first unless the app opts in to taking priority.
3. **Pure state machine.** Events (`began`, `moved(velocity)`, `ended(velocity)`,
   `cancelled`, `tapIndicator`, `tapOutside`, `hover`, `geometryChanged`,
   `hingeChanged`) map to a new state plus effects (haptic, notify, animate). It
   replaces Carioca's flags and completion closures, and every transition can be
   interrupted.
4. **Rendering.** The overlay is a `GlassEffectContainer` on iOS 26 and a
   `ZStack` on 18. Rows are laid out by hand in a stack, with no scrolling
   container. Per-row effects use `visualEffect`, so the magnification is driven
   by the finger position without invalidating the layout. The overlay renders
   only during interaction. Otherwise only the indicator is in the hierarchy.
5. **Performance.** No `AnyView` on hot paths, generic style type erasure only
   at the edges, and 120 Hz tracking checked with Instruments in the demo.

### Accessibility and robustness
- The indicator is a real `Button`, labelled "Menu, current: <item>". It has an
  adjustable action and custom actions for each item. Keyboard shortcuts are
  supported on iPad.
- With Reduce Motion on, morphs and bounces become crossfades. With Reduce
  Transparency on, glass becomes a solid material.
- RTL mirrors the leading and trailing edges. Dynamic Type scales rows with
  `@ScaledMetric`.
- Size, fold or display changes during interaction cancel tracking cleanly.

---

## 8. Milestones

Each milestone is a set of commits on the dev branch, squash-merged into `main`.
🟡 = written, waiting for its first CI run (no Swift toolchain is available in the authoring environment).

| # | Milestone | Deliverable |
|---|---|---|
| M0 🟡 | **Scaffold** | `Package.swift` (tools 6.0, `.iOS(.v18)`, Swift 6 mode), layout, SwiftLint config, GitHub Actions (engine tests on Linux and macOS, plus an iOS Simulator build), README |
| M1 🟡 | **Engine** | `FlickGeometry` (two axes, four edges), `FlickPhysics`, Carioca regression tests |
| M2 🟡 | **State machine** | Reducer plus tests for every boomerang, cancel, tap, programmatic-open and geometry-change path (hover and hinge events arrive with M7–M8) |
| M3 | **Gesture bridge** | Edge recognisers for all edges, system-gesture coexistence, programmatic open |
| M4 | **Menu overlay** | Tracking, highlight, release with velocity, haptics, callbacks |
| M5 | **Indicator** | `.bubble` and `.glass` with the iOS 26 morph, traverse keyframes, boomerang, symbol transitions |
| M6 | **Styles** | Row, indicator and background styles, physics presets, feedback, shader ripple |
| M7 | **iPhone Duo** | `FlickFoldModel` (tests first), hinge observer, posture placement, hinge edge, display continuity |
| M8 | **Accessibility and device extras** | VoiceOver, Reduce Motion and Reduce Transparency, RTL, Dynamic Type, hover peek, keyboard, Pencil Pro, App Intent and Control widget |
| M9 | **Demo and docs** | Showcase app, DocC catalogue with tutorials, README with recordings |

## 9. Open items

- Check the iOS 27.1 foldable API names against the SDK (§5, note 1).
- **Other touch OSes.** watchOS has no edge-pan recogniser, so it would need a
  `DragGesture`-based gesture and a Digital Crown variant. The engine already
  allows this, so it is planned after v1. Other platforms (visionOS, Mac
  Catalyst) can use the tap and keyboard path.

## 10. Verification
iOS builds, simulator tests and iPhone Duo behaviour need macOS and Xcode 27.1,
so CI runs on GitHub Actions macOS runners. The `Engine/` layer imports only
Foundation (where `CGFloat`/`CGPoint` are also available on Linux), so it can
also be tested on Linux with SwiftPM for fast local feedback. Behaviour on the
fold has to be checked in the iPhone Duo simulator or on a device.
