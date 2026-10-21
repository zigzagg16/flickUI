# flickUI

A fluid, edge-triggered menu component for SwiftUI. It is a modern rebuild of
[CariocaMenu](https://github.com/zigzagg16/cariocamenu).

Swipe in from any screen edge. The selected item appears under your finger,
sliding moves through the items, and lifting your finger chooses one. It takes
no taps.

> **Status:** early development. The engine (geometry, physics and state machine)
> is in place. The SwiftUI layer is next. See [`docs/PLAN.md`](docs/PLAN.md)
> for the roadmap.

## Highlights (planned)

- Opens from all four edges, plus the fold on iPhone Duo
- Configurable tracking speed and rubber-banding, with a `.carioca` preset that
  reproduces the original feel exactly
- Fully customisable indicator, rows, background, haptics and transitions
- Liquid Glass on iOS 26 and later, with the indicator morphing into the menu
- Fold-aware layout and hinge-driven effects on iPhone Duo
- VoiceOver, Reduce Motion, right-to-left languages, Dynamic Type, keyboard and
  Apple Pencil Pro support

## Requirements

- iOS / iPadOS 18 or later. Newer features turn on automatically on iOS 26 and 27.1.
- Swift 6

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/zigzagg16/flickUI", branch: "main")
```

## Project layout

| Path | Contents |
|---|---|
| `Sources/FlickCore` | Platform-independent engine: edges, geometry, physics, state machine |
| `Sources/flickUI` | SwiftUI / UIKit layer (re-exports `FlickCore`) |
| `Tests/FlickCoreTests` | Engine tests, including CariocaMenu's original test values as regression tests |

Run the engine tests on macOS or Linux with:

```sh
swift test
```

## License

MIT. See [LICENSE](LICENSE).
