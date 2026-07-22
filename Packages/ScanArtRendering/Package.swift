// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScanArtRendering",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ScanArtRendering", targets: ["ScanArtRendering"])
    ],
    dependencies: [
        .package(path: "../ScanArtAlgorithms")
    ],
    targets: [
        .target(
            name: "ScanArtRendering",
            dependencies: ["ScanArtAlgorithms"],
            resources: [.process("Shaders/MeshHeatmap.metal")]
        )
    ]
)
