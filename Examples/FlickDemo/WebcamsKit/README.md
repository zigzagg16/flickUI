# WebcamsKit

The Webcams app's code that isn't UI, in two layers:

| Module | Platforms | What's in it |
|---|---|---|
| `WebcamsCore` | iOS, iPadOS, macOS, Linux, Android | The catalog, cita.lu loading and parsing, traffic events and travel times, road reports, the traffic estimate, favourites, links, live-stream readings. Foundation only. |
| `WebcamsVision` | iOS, iPadOS, macOS | Reading pictures and the live stream with Vision and Core ML: `RoadAnalyzer`, `VehicleDetector`, `MotionAnalyzer`, `RoadMonitor`. Empty elsewhere. |

The SwiftUI app and the widget, in `FlickDemo/` and `WebcamWidget/`, use both.

Another platform reuses `WebcamsCore` and brings its own picture analysis in place of
`WebcamsVision`: it turns a picture into greyscale pixels for `ImageStatistics`, and
vehicle boxes into `TrafficEstimator`, the way `RoadAnalyzer` does with Vision.

```bash
swift test                     # on a Mac
docker run --rm -v "$PWD":/src -w /src swift:6.1 swift test   # on Linux
```
