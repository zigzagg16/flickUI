// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebcamsKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "WebcamsCore", targets: ["WebcamsCore"]),
        .library(name: "WebcamsVision", targets: ["WebcamsVision"])
    ],
    targets: [
        // Platform-independent: the catalog, cita.lu, road reports and the traffic
        // estimate. Imports only Foundation, so it builds on Linux and Android too.
        .target(name: "WebcamsCore", resources: [.copy("Resources/catalog.json")]),
        // Apple platforms: reads pictures and the live stream with Vision and Core ML.
        .target(name: "WebcamsVision", dependencies: ["WebcamsCore"]),
        .testTarget(name: "WebcamsCoreTests", dependencies: ["WebcamsCore"])
    ],
    swiftLanguageModes: [.v6]
)
