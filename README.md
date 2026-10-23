# flickUI

A fluid, edge-triggered menu component for SwiftUI. It is a modern rebuild of
[CariocaMenu](https://github.com/zigzagg16/cariocamenu).

Swipe in from any screen edge. The selected item appears under your finger,
sliding moves through the items, and lifting your finger chooses one. It takes
no taps.

> **Status:** early development. The engine (geometry, physics, state machine) and
> a first SwiftUI layer are in place. See [`docs/PLAN.md`](docs/PLAN.md) for the roadmap.

## Usage

```swift
import flickUI

struct ContentView: View {
    @State private var tab: Tab.ID = Tab.home.id

    var body: some View {
        TabContent(tab)
            .flickMenu(Tab.allCases, selection: $tab, edges: .all, title: \.title, systemImage: \.symbol)
    }
}
```

Every item is an SF Symbol with a title. While the menu is open, the indicator
leaves the edge and morphs into a bead under the highlighted item's symbol, so
the symbol is never shown twice.

### Customising, globally or per edge

Every setting has a default for all edges. Pass `edges:` to override it for some
edges only; edge-specific settings always win, whatever the modifier order.

```swift
ContentView()
    .flickMenuIndicatorStyle(.morphing(.liquid))           // all edges
    .flickMenuIndicatorStyle(.bubble(tint: .pink), edges: .vertical)
    .flickMenuHighlight(FlickMenuItemEmphasis(tint: .yellow, symbolVariant: .fill, symbolEffect: .wiggle))
    .flickMenuSelection(FlickMenuItemEmphasis(symbolEffect: .breathe.repeating))
    .flickMenuPhysics(.fluid)
    .flickMenuTracking(ratio: 3, edges: .bottom)           // shorter swipes on the bottom edge
    .flickMenuRowStyle(.magnifying(.dock), edges: .horizontal)
    .flickMenuBackground(.gradient, edges: .top)
    .flickMenuBoomerang(.origin)
    .flickMenuLayout(FlickMenuLayout(itemLength: 72), edges: .vertical)
    .flickMenuHome(.trailing, position: 0.6)
    .flickMenuFeedback(.subtle)
    .onFlickMenuEvent { event in print(event) }
```

| Setting | Per edge | Built-ins |
|---|---|---|
| `flickMenuIndicatorStyle` | ✓ | `.automatic` (a morphing drop, in Liquid Glass on iOS 26+), `.morphing(.drop / .squircle / .liquid / .still, tint:)`, `.glass`, `.bubble`, `.capsule`, or your own `FlickIndicatorStyle` |
| `flickMenuHighlight` / `flickMenuSelection` | ✓ | `FlickMenuItemEmphasis`: tint, symbol variant and SF Symbols effect (`.bounce`, `.pulse`, `.wiggle`, `.breathe`, `.rotate`, `.scale`, `.variableColor`, once or `.repeating`) |
| `flickMenuRowStyle` | ✓ | `.magnifying` (default), `.plain`, or your own `FlickMenuRowStyle` |
| `flickMenuBackground` | ✓ | Full screen: `.material` (default), `.gradient`, `.color`, `.clear`. Contained, holding only the rows: `.panel`, `.glassPanel`, `.drawer`, `.halo`, with `.panel(_:)` / `.drawer(_:)` taking a material, colour or Liquid Glass fill. Or your own `FlickMenuBackgroundStyle`. Rows switch to light text on dark backgrounds (`contentColorScheme`) |
| `flickMenuPhysics` / `flickMenuTracking` | ✓ | `.fluid` (default), `.carioca`, `.snappy`, `.direct`. Every item stays reachable wherever a swipe starts (`reachesAllItems`), except with `.carioca` |
| `flickMenuBoomerang` | ✓ | `.stay` (default), `.edge`, `.position`, `.origin` |
| `flickMenuLayout` | ✓ | item length, indicator size and margin |
| `flickMenuHome`, `flickMenuFeedback`, `flickMenuDefersSystemGestures`, `onFlickMenuEvent` | — | |
| `flickMenuKeyboardShortcut`, `flickMenuOpensOnPencilSqueeze` | — | A shortcut to open the menu; Apple Pencil Pro squeeze (off by default) |

### Opening from code, keyboard and accessibility

`@Environment(\.flickMenu)` opens, dismisses and toggles the menu from inside its
content:

```swift
@Environment(\.flickMenu) private var menu

Button("Menu", systemImage: "list.bullet") { menu.open() }
```

While a menu opened without a swipe is shown, the arrow keys move through items,
Return chooses and Escape closes. For VoiceOver the indicator is an adjustable
"Menu" button, and the open menu is modal and closes with the escape gesture. Items
grow with Dynamic Type, and backgrounds become opaque with Reduce Transparency.

### Morphing indicator

`FlickMorphingIndicatorStyle` draws a `FlickMorphingShape`, whose `FlickShapeForm`
(roundness on each side, a tail pointing at the edge, stretch) animates between
any two values. A `FlickIndicatorMorph` picks the form at rest, the form while
open, how far it stretches with the finger's speed and how springy it is:

```swift
let morph = FlickIndicatorMorph(
    resting: FlickShapeForm(edgeRoundness: 0.6, farRoundness: 1, tail: 0.3),
    open: .squircle,
    maximumStretch: 0.4,
    bounce: 0.5
)
ContentView().flickMenuIndicatorStyle(.morphing(morph, tint: .orange))
```

## Highlights

- Opens from all four edges
- Configurable tracking speed and rubber-banding, with a `.carioca` preset that
  reproduces the original feel exactly
- Customisable indicator, rows, background and haptics, per edge
- Liquid Glass on iOS 26 and later, with a morphing indicator
- VoiceOver, Reduce Motion, Reduce Transparency, right-to-left languages, Dynamic
  Type, keyboard, pointer and Apple Pencil Pro support

Planned: the fold on iPhone Duo (fold-aware layout and a hinge edge) and custom
transitions. See [`docs/PLAN.md`](docs/PLAN.md).

## Demo app

`Examples/FlickDemo` is a showcase app with a full-screen page per menu item and a
**Customize** sheet to change every setting live, including different settings for
the left/right and top/bottom edges.

The grid button switches to a second app, **Webcams**, which shows the live motorway
cameras from [cita.lu](https://www.cita.lu/fr/webcam/a13.html) with two nested
menus, one per side: the right edge switches between the motorway's live stream and
its cameras, and the left edge switches motorways. Their rows sit on a contained
panel so the camera stays visible; the brush button tries the other backgrounds.

The grid menu also sets which app opens at launch, stored in UserDefaults under
`launchApp` (`showcase`, `webcams`, or unset to reopen the last one). The
**Webcams** scheme passes `-launchApp webcams`, so it runs like a separate app.
What the Webcams app shows comes from a catalog, `WebcamCatalog`: the motorways,
their cameras, live streams and traffic maps, and every link. It is decoded from
`CitaKit/catalog.json`, bundled with the app, until a backend serves it at the
`WebcamCatalogURL` Info.plist key; the last downloaded catalog is cached for the app
and the widget. For a motorway listed without cameras, the app reads them from its
webcam page. The cita.lu code lives in `Examples/FlickDemo/CitaKit`, shared with a **Webcams
widget** (small, medium and large): pick a camera in the widget's settings, and it
shows that camera's image, refreshed by WidgetKit about every 15 minutes. Tapping
it opens the camera in the app. Widgets can't play video, so there's no live stream.

The Webcams app also reads the road from the pictures, on the device: frozen or
missing cameras, day or night, visibility and weather (Vision), vehicles (a Core ML
YOLOv3 Tiny model, downloaded on first use), the traffic level per carriageway from
successive pictures, and the live stream's movement (Vision optical flow). Each
camera's situation shows as its symbol in the side menu, in the header and on the
widget, which shares the app's reports through the `group.dev.flickui.FlickDemo`
App Group. These are estimates from the pictures, not an official traffic state; the
**Traffic map** item shows cita.lu's own. cita.lu has no webcam API, so the app
reads the camera list from each motorway's page and reloads each camera's JPEG every
30 seconds. The live stream is the HLS playlist linked from the motorway's
live-stream page, played muted until you unmute it.

To run it on a device:

1. Open `Examples/FlickDemo/FlickDemo.xcodeproj` in Xcode 26 or later.
2. Select the **FlickDemo** target → *Signing & Capabilities* → choose your
   **Team**. If the bundle identifier is taken, change `dev.flickui.FlickDemo` to
   something unique.
3. Pick your iPhone or iPad as the run destination and press **Run** (⌘R).

The project references the package from the repository root, so library changes
are picked up immediately.

## Requirements

- iOS / iPadOS 18 or later. Newer features turn on automatically on iOS 26 and 27.1.
- Xcode 26 or later, Swift 6

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/zigzagg16/flickUI", branch: "main")
```

## Project layout

| Path | Contents |
|---|---|
| `Sources/FlickCore` | Platform-independent engine: edges, geometry, physics, state machine |
| `Sources/flickUI` | SwiftUI layer: the `flickMenu` modifier, edge gesture, styles and settings (re-exports `FlickCore`) |
| `Sources/flickUI/flickUI.docc` | Documentation catalog: overview, customisation, accessibility and input |
| `Tests/FlickCoreTests` | Engine tests, including CariocaMenu's original test values as regression tests |
| `Tests/flickUITests` | Tests for the SwiftUI layer's logic (iOS only) |

Run the engine tests on macOS or Linux with:

```sh
swift test
```

Run every test on an iOS Simulator with `xcodebuild test -scheme flickUI -destination 'platform=iOS Simulator,name=<iPhone>'`.
Build the documentation with **Product › Build Documentation** in Xcode.

## License

MIT. See [LICENSE](LICENSE).
