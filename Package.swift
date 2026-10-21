// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "flickUI",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "flickUI", targets: ["flickUI"])
    ],
    targets: [
        // Platform-independent engine: geometry, physics and the menu state machine.
        // Imports only Foundation so it can be tested on Linux.
        .target(name: "FlickCore"),
        // SwiftUI / UIKit layer.
        .target(name: "flickUI", dependencies: ["FlickCore"]),
        .testTarget(name: "FlickCoreTests", dependencies: ["FlickCore"])
    ],
    swiftLanguageModes: [.v6]
)
