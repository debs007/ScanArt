// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanArtAR",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ScanArtAR", targets: ["ScanArtAR"])
    ],
    dependencies: [
        .package(path: "../ScanArtAlgorithms"),
        .package(path: "../ScanArtCore")
    ],
    targets: [
        .target(name: "ScanArtAR", dependencies: ["ScanArtAlgorithms", "ScanArtCore"])
    ]
)
