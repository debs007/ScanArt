// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanArtExport",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ScanArtExport", targets: ["ScanArtExport"])
    ],
    dependencies: [
        .package(path: "../ScanArtAlgorithms"),
        .package(path: "../ScanArtCore")
    ],
    targets: [
        .target(name: "ScanArtExport", dependencies: ["ScanArtAlgorithms", "ScanArtCore"])
    ]
)
