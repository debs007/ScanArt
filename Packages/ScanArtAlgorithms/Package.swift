// swift-tools-version: 5.10
import PackageDescription

// ScanArtAlgorithms is deliberately dependency-free (Foundation + simd only).
// It contains ZERO UIKit/ARKit/SwiftData imports so that:
//   1. It can be unit tested with a plain `swift test` on macOS, no simulator needed.
//   2. The hard math (ICP alignment, thickness, volume, statistics) is trivially
//      testable with synthetic data and ground-truth transforms.
let package = Package(
    name: "ScanArtAlgorithms",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScanArtAlgorithms", targets: ["ScanArtAlgorithms"])
    ],
    targets: [
        .target(name: "ScanArtAlgorithms", dependencies: []),
        .testTarget(name: "ScanArtAlgorithmsTests", dependencies: ["ScanArtAlgorithms"])
    ]
)
