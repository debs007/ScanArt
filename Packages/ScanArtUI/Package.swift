// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanArtUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ScanArtUI", targets: ["ScanArtUI"])
    ],
    dependencies: [
        .package(path: "../ScanArtAlgorithms")
    ],
    targets: [
        .target(name: "ScanArtUI", dependencies: ["ScanArtAlgorithms"])
    ]
)
